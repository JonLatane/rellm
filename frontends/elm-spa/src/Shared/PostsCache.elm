module Shared.PostsCache exposing
    ( CachedFeed
    , Model
    , Msg(..)
    , Settings
    , Snapshot
    , ageLabel
    , empty
    , evictHost
    , evictPost
    , expired
    , expiryMs
    , reconcile
    , restorable
    , setRestoring
    , update
    )

{-| The posts feeds `Components.Pages.PostsPage` shows, kept in memory so that going _back_ to one (the
browser's back button, after opening a post from it) shows the very same posts, scrolled to the very same
card, instead of fetching and animating them in again.

It lives in `Shared` because a page's own model is discarded the moment another route is entered (`Main`
re-runs the new page's `init` on every path change). It is never persisted: a page reload starts from nothing,
which is what makes a reload always refresh the feeds.

What makes a snapshot usable:

  - **Only on back-navigation.** `Main` marks the navigation (`setRestoring`) when -- and only when -- it was the
    browser's own back button; a link click or typed URL always starts fresh. `restorable` also needs the
    snapshot's `Settings` (search, context, sort, cutoff) to be what the page is starting with, so a changed
    URL never shows another list's posts.
  - **Not expired.** A feed older than `expiryMs` (4 hours, counted from when its posts were _fetched_, not
    from when the snapshot was saved) is not used (`expired`).
  - **Not outlived by its account.** `reconcile` runs whenever the signed-in accounts change (signing out,
    switching account, disabling a server): a feed fetched as an account that is no longer the acting one on
    its server is dropped on the spot, and a "Following" snapshot -- everyone the accounts follow -- goes
    entirely.
  - **Not outlived by its posts.** Deleting a post (`evictPost`), or creating one on a server (`evictHost`),
    drops the snapshots that would now show something out of date.

A bounded number of snapshots (`maxSnapshots`) are kept, most recently stored first.

-}

import Components.Pages.PostsPage.Paging as Paging
import Dict exposing (Dict)
import Proto.Rellm exposing (Post)
import Proto.Rellm.PostContext exposing (PostContext)
import Time


type alias Model =
    { -- Keyed by the page's path (`PostsPage.Model.path`), most recently stored first.
      snapshots : List ( String, Snapshot )

    -- Whether the page being initialised is one the reader just went _back_ to -- see `setRestoring`.
    , restoring : Bool
    }


empty : Model
empty =
    { snapshots = [], restoring = False }


{-| What a feed was showing: each source's loaded posts and where its next page starts, and which slice of
them was rendered.
-}
type alias Snapshot =
    { feeds : Dict String CachedFeed
    , window : Paging.Window
    , settings : Settings
    }


{-| What `PostsPage` was told to show, as plain values: a snapshot only fits a page that starts with the same.
`sort` is `PostsPage`'s own URL form of its sort; `publishedBefore` is the cutoff in milliseconds, only while
the "Posts Before" tab is the one in use.
-}
type alias Settings =
    { searchText : String
    , context : PostContext
    , sort : String
    , publishedBefore : Maybe Int
    }


{-| One source's loaded posts -- `PostsPage.ServerFeed`, less what only matters while a request is in flight.
`accountId` is the acting account the posts were fetched as; `fetchedAt` when the first page of them
arrived (`Nothing` if that wasn't known).
-}
type alias CachedFeed =
    { posts : List Post
    , accountId : Maybe String
    , host : String
    , excludedAuthorIds : List String
    , next : Maybe String
    , rankBase : Int
    , fetchedAt : Maybe Time.Posix
    }


type Msg
    = Store String Snapshot
      -- Forgets one page's snapshot (it was found expired).
    | Evict String
      -- The page being initialised has had its chance to restore a snapshot: later `PostsPage.init`s (a
      -- profile re-initialising its embedded feed) start fresh.
    | ConsumeRestore


update : Msg -> Model -> Model
update msg model =
    case msg of
        Store key snapshot ->
            { model | snapshots = ( key, snapshot ) :: List.filter (\( k, _ ) -> k /= key) model.snapshots |> List.take maxSnapshots }

        Evict key ->
            { model | snapshots = List.filter (\( k, _ ) -> k /= key) model.snapshots }

        ConsumeRestore ->
            { model | restoring = False }


{-| How many pages' snapshots are kept.
-}
maxSnapshots : Int
maxSnapshots =
    8


{-| Four hours. After this a feed is not shown from the cache any more.
-}
expiryMs : Int
expiryMs =
    4 * 60 * 60 * 1000


{-| `Main` calls this on every URL change: `True` if it was the browser's back button.
-}
setRestoring : Bool -> Model -> Model
setRestoring restoring model =
    { model | restoring = restoring }


{-| The snapshot a page starting at `key` with `settings` should show, if this is a back-navigation and one
fits. (Whether it has expired needs the current time, which the page learns only after it starts -- see
`expired`.)
-}
restorable : String -> Settings -> Model -> Maybe Snapshot
restorable key settings model =
    if model.restoring then
        model.snapshots
            |> List.filter (\( k, snapshot ) -> k == key && snapshot.settings == settings)
            |> List.head
            |> Maybe.map Tuple.second

    else
        Nothing


{-| Whether `fetchedAt` is more than `expiryMs` before `now`. Posts of unknown age count as expired.
-}
expired : Time.Posix -> Maybe Time.Posix -> Bool
expired now fetchedAt =
    case fetchedAt of
        Just at ->
            Time.posixToMillis now - Time.posixToMillis at > expiryMs

        Nothing ->
            True


{-| Brings the cache in line with the accounts now signed in. `accountIdFor` is the acting account's id on a
source's host (`Nothing` when there is none -- and for every Mastodon/Bluesky source, whose feeds never depend
on one); `accountsChanged` is whether the set of accounts differs from before. A feed fetched as someone else
is dropped, so signing out of a server forgets that server's posts at once, not when the reader next comes
back; snapshots left with no feeds go too.

"Following" is everyone _any_ signed-in account follows -- Rellm, Mastodon or Bluesky -- so those snapshots
are all dropped whenever the accounts change at all.
-}
reconcile : (String -> Maybe String) -> Bool -> Model -> Model
reconcile accountIdFor accountsChanged model =
    let
        keepFeed : CachedFeed -> Bool
        keepFeed feed =
            feed.accountId == accountIdFor feed.host

        reconciled : Snapshot -> Maybe Snapshot
        reconciled snapshot =
            if accountsChanged && snapshot.settings.sort == "following" then
                Nothing

            else
                let
                    feeds : Dict String CachedFeed
                    feeds =
                        Dict.filter (\_ feed -> keepFeed feed) snapshot.feeds
                in
                if Dict.isEmpty feeds then
                    Nothing

                else
                    Just { snapshot | feeds = feeds }
    in
    { model | snapshots = List.filterMap (\( key, snapshot ) -> reconciled snapshot |> Maybe.map (Tuple.pair key)) model.snapshots }


{-| Drops every snapshot showing post `postId` of `host` (it was deleted).
-}
evictPost : String -> String -> Model -> Model
evictPost host postId model =
    { model
        | snapshots =
            List.filter
                (\( _, snapshot ) ->
                    snapshot.feeds
                        |> Dict.values
                        |> List.any (\feed -> feed.host == host && List.any (\post -> post.id == postId) feed.posts)
                        |> not
                )
                model.snapshots
    }


{-| Drops every snapshot with posts from `host` (something was just created there that they lack).
-}
evictHost : String -> Model -> Model
evictHost host model =
    { model
        | snapshots = List.filter (\( _, snapshot ) -> snapshot.feeds |> Dict.values |> List.all (\feed -> feed.host /= host)) model.snapshots
    }


{-| "7 minutes", "1 hour", "3 hours" for how old the cached posts are (milliseconds) -- `Nothing` while they
are no more than five minutes old, when nothing needs saying.
-}
ageLabel : Int -> Maybe String
ageLabel ageMs =
    if ageMs <= 5 * 60000 then
        Nothing

    else if ageMs < 60 * 60000 then
        Just (String.fromInt (ageMs // 60000) ++ " minutes")

    else
        let
            hours : Int
            hours =
                ageMs // (60 * 60000)
        in
        Just
            (String.fromInt hours
                ++ (if hours == 1 then
                        " hour"

                    else
                        " hours"
                   )
            )
