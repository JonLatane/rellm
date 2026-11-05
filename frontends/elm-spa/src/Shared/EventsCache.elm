module Shared.EventsCache exposing
    ( CachedFeed
    , Model
    , Msg(..)
    , Settings
    , Snapshot
    , empty
    , evictEvent
    , evictHost
    , isCacheable
    , reconcile
    , restorable
    , setRestoring
    , update
    )

{-| The events feeds `Components.Pages.EventsPage` shows, kept in memory so that going _back_ to one (the
browser's back button, after opening an event from it) shows the very same events, scrolled to the very same
card, instead of fetching and animating them in again. `Shared.PostsCache` is its sibling for `PostsPage`, and
works the same way -- see its module doc; its expiry (`PostsCache.expiryMs`, 4 hours) and age wording
(`PostsCache.ageLabel`) are shared.

It lives in `Shared` because a page's own model is discarded the moment another route is entered. It is never
persisted: a page reload starts from nothing, which is what makes a reload always refresh the feeds.

What makes a snapshot usable:

  - **Only on back-navigation.** `Main` marks the navigation (`setRestoring`) when -- and only when -- it was the
    browser's own back button. `restorable` also needs the snapshot's `Settings` (search text, tab and the
    "Events After" cutoff) to be what the page is starting with.
  - **Not expired.** A feed older than `PostsCache.expiryMs`, counted from when its events were _fetched_, is
    not used -- `EventsPage` checks as soon as it learns the time.
  - **Not outlived by its account.** `reconcile` runs whenever the signed-in accounts change: a feed fetched as
    an account that is no longer the acting one on its server is dropped on the spot.
  - **Not outlived by its events.** Deleting an event (`evictEvent`), or creating, editing or RSVPing to one
    (`evictHost`, `EvictAll`), drops the snapshots that would now show something out of date.

A bounded number of snapshots (`maxSnapshots`) are kept, most recently stored first.

-}

import Dict exposing (Dict)
import Proto.Rellm exposing (Event, Occasion)
import Time


type alias Model =
    { -- Keyed by the page's path (`EventsPage.Model.path`), most recently stored first.
      snapshots : List ( String, Snapshot )

    -- Whether the page being initialised is one the reader just went _back_ to -- see `setRestoring`.
    , restoring : Bool
    }


empty : Model
empty =
    { snapshots = [], restoring = False }


{-| What a feed was showing: each source's loaded events, and the settings they were fetched under.
-}
type alias Snapshot =
    { feeds : Dict String CachedFeed
    , settings : Settings

    -- The cutoff `feeds` were last fetched with (`EventsPage.Model.endsAfter`): on the "Upcoming Events" tab that is
    -- the clock at the time, which is what tells the events that had ended by then from those still to come.
    , endsAfter : Maybe Time.Posix
    }


{-| What `EventsPage` was told to show, as plain values: a snapshot only fits a page that starts with the same.
`upcoming` is whether the "Upcoming Events" tab was the one in use; `endsAfter` is the "Events After" cutoff in
milliseconds, only while that tab is (the "Upcoming" cutoff is the live clock, which is never the same twice).
-}
type alias Settings =
    { searchText : String
    , upcoming : Bool
    , endsAfter : Maybe Int
    }


{-| One source's loaded events -- `EventsPage.ServerFeed`, less what only matters while a request is in flight.
`accountId` is the acting account the events were fetched as; `fetchedAt` when they arrived (`Nothing` if that
wasn't known).
-}
type alias CachedFeed =
    { events : List ( Event, Occasion )
    , accountId : Maybe String
    , host : String
    , excludedAuthorIds : List String
    , fetchedAt : Maybe Time.Posix
    }


type Msg
    = Store String Snapshot
      -- Forgets one page's snapshot (it was found expired).
    | Evict String
      -- Forgets every snapshot: something an event shows (an RSVP, a detail the event's own page edits) may have
      -- changed where the cache can't tell which feeds it touches.
    | EvictAll
      -- The page being initialised has had its chance to restore a snapshot: later `EventsPage.init`s start fresh.
    | ConsumeRestore


update : Msg -> Model -> Model
update msg model =
    case msg of
        Store key snapshot ->
            { model | snapshots = ( key, snapshot ) :: List.filter (\( k, _ ) -> k /= key) model.snapshots |> List.take maxSnapshots }

        Evict key ->
            { model | snapshots = List.filter (\( k, _ ) -> k /= key) model.snapshots }

        EvictAll ->
            { model | snapshots = [] }

        ConsumeRestore ->
            { model | restoring = False }


{-| How many pages' snapshots are kept.
-}
maxSnapshots : Int
maxSnapshots =
    8


{-| `Main` calls this on every URL change: `True` if it was the browser's back button.
-}
setRestoring : Bool -> Model -> Model
setRestoring restoring model =
    { model | restoring = restoring }


{-| The snapshot a page starting at `key` with `settings` should show, if this is a back-navigation and one
fits. (Whether it has expired needs the current time, which the page learns only after it starts --
`PostsCache.expired`.)
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


{-| Whether a source's feed (`key` is its `eventsByServer` key) belongs in a snapshot. Not one awaiting a
replacement -- after a search or cutoff change its old events stay up until the new ones land, and saving them
as finished would bring them back under the new settings. Not a linked profile's (`FederatedAuthor`: its key
differs from its host), which only the profile page that lists it can say still belongs.
-}
isCacheable : String -> { a | host : String, refreshing : Bool } -> Bool
isCacheable key feed =
    key == feed.host && not feed.refreshing


{-| Brings the cache in line with the accounts now signed in. `accountIdFor` is the acting account's id on a
source's host (`Nothing` when there is none). A feed fetched as someone else is dropped, so signing out of a
server forgets that server's events at once, not when the reader next comes back; snapshots left with no feeds
go too.
-}
reconcile : (String -> Maybe String) -> Model -> Model
reconcile accountIdFor model =
    let
        reconciled : Snapshot -> Maybe Snapshot
        reconciled snapshot =
            let
                feeds : Dict String CachedFeed
                feeds =
                    Dict.filter (\_ feed -> feed.accountId == accountIdFor feed.host) snapshot.feeds
            in
            if Dict.isEmpty feeds then
                Nothing

            else
                Just { snapshot | feeds = feeds }
    in
    { model | snapshots = List.filterMap (\( key, snapshot ) -> reconciled snapshot |> Maybe.map (Tuple.pair key)) model.snapshots }


{-| Drops every snapshot showing event `eventId` (its post id) of `host` (it was deleted).
-}
evictEvent : String -> String -> Model -> Model
evictEvent host eventId model =
    { model
        | snapshots =
            List.filter
                (\( _, snapshot ) ->
                    snapshot.feeds
                        |> Dict.values
                        |> List.any
                            (\feed ->
                                feed.host
                                    == host
                                    && List.any (\( event, _ ) -> Maybe.map .id event.post == Just eventId) feed.events
                            )
                        |> not
                )
                model.snapshots
    }


{-| Drops every snapshot with events from `host` (something was just created or changed there that they lack).
-}
evictHost : String -> Model -> Model
evictHost host model =
    { model
        | snapshots = List.filter (\( _, snapshot ) -> snapshot.feeds |> Dict.values |> List.all (\feed -> feed.host /= host)) model.snapshots
    }
