module Shared.UserPreferences exposing (Model, Msg(..), init, update)

{-| Small, app-wide user preferences that aren't tied to any one page's own
URL/local state -- `prefersCalendar`, `postsBefore`, `eventsAfter`,
`pinnedPostsCollapsedToHidePostIds` (see each field's own doc), all one JSON
object persisted to its own localStorage key (`Ports.persistUserPreferences`).

Mirrors `Shared.StarredPanel`'s persist-to-localStorage half exactly, minus
the `BroadcastChannel` live cross-tab push -- see `Ports.persistUserPreferences`'s
own doc for why these are only ever picked up by other tabs on their next
load, not pushed into ones already open.

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Ports
import Time


type alias Model =
    -- Whether `Components.Pages.EventsPage` should default to `Calendar`
    -- mode rather than its ordinary Row/List default -- set (from
    -- `Pages.Home_`/`Pages.Events` only, see `EventsPage.Model.syncsCalendarPreference`)
    -- whenever the user switches that page's own copy into or out of
    -- `Calendar` mode, then read back by *every* `EventsPage` copy (including
    -- `Components.Pages.UserProfilePage`'s and `Pages.UsernameOrCustomTab_.Events`/
    -- `Pages.User.UserId_.Events`'s, which never write it) to decide their
    -- own initial mode -- see `EventsPage.defaultMode`.
    { prefersCalendar : Bool

    -- The last cutoff the user actually typed into `Components.Pages.PostsPage`'s
    -- own "Posts Before..." tab (`Model.publishedBefore`) -- set only by
    -- `PostsPage.PublishedBeforeDebounceElapsed`, never by a `?published_before=`
    -- query param on load (that's a one-off view into someone else's/an old
    -- link's cutoff, not something that should silently overwrite this).
    -- Read back by `PostsPage.init` as `publishedBefore`'s own default absent
    -- such a query param, so a fresh `/`/`/posts` starts wherever the user
    -- last left it instead of `Nothing` (itself seeded to "now" via `GotNow`).
    , postsBefore : Maybe Time.Posix

    -- Same idea as `postsBefore`, for `Components.Pages.EventsPage`'s
    -- "Events After..." tab (`Model.endsAfter`) -- set only by
    -- `EventsPage.EndsAfterDebounceElapsed`. Read back by `EventsPage`'s own
    -- `TabChanged EventsAfterDate` handler (not `init`: unlike `postsBefore`,
    -- `endsAfter` is kept live at "now" while `UpcomingEvents` is active, so
    -- there's nothing meaningful to seed until the user actually switches to
    -- `EventsAfterDate`) as that switch's starting cutoff instead of
    -- wherever `UpcomingEvents`' live clock last left `endsAfter`.
    , eventsAfter : Maybe Time.Posix

    -- Mirrors `Components.PinnedPosts.Model.postIds` as of the moment the viewer last collapsed
    -- that section via its own header toggle -- `[]` means "currently expanded" (either never
    -- collapsed, or last re-opened). `Components.PinnedPosts` compares this against its own live
    -- `postIds` on every render (see `Components.PinnedPosts.isSectionCollapsed`): an exact match
    -- means nothing pinned has changed since the viewer closed it, so it loads pre-collapsed;
    -- anything else (including a freshly-pinned post the viewer hasn't seen yet) reopens it
    -- automatically, without `Components.PinnedPosts` needing any collapse state of its own to
    -- reconcile in `syncIds`.
    , pinnedPostsCollapsedToHidePostIds : List String
    }


type Msg
    = SetPrefersCalendar Bool
    | SetPostsBefore (Maybe Time.Posix)
    | SetEventsAfter (Maybe Time.Posix)
    | SetPinnedPostsCollapsedToHidePostIds (List String)


{-| `flags` is the raw, persisted JSON object (see `Ports.persistUserPreferences`)
handed down from `Shared.init`, un-decoded -- same convention as
`Shared.StarredPanel.init`'s flags.
-}
init : Decode.Value -> Model
init flags =
    { prefersCalendar =
        Decode.decodeValue (Decode.field "prefersCalendar" Decode.bool) flags
            |> Result.withDefault True
    , postsBefore = decodePosixField "postsBefore" flags
    , eventsAfter = decodePosixField "eventsAfter" flags
    , pinnedPostsCollapsedToHidePostIds =
        Decode.decodeValue (Decode.field "pinnedPostsCollapsedToHidePostIds" (Decode.list Decode.string)) flags
            |> Result.withDefault []
    }


decodePosixField : String -> Decode.Value -> Maybe Time.Posix
decodePosixField field flags =
    Decode.decodeValue (Decode.field field Decode.int) flags
        |> Result.map Time.millisToPosix
        |> Result.toMaybe


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SetPrefersCalendar prefersCalendar ->
            let
                newModel : Model
                newModel =
                    { model | prefersCalendar = prefersCalendar }
            in
            ( newModel, persistCmd newModel )

        SetPostsBefore postsBefore ->
            let
                newModel : Model
                newModel =
                    { model | postsBefore = postsBefore }
            in
            ( newModel, persistCmd newModel )

        SetEventsAfter eventsAfter ->
            let
                newModel : Model
                newModel =
                    { model | eventsAfter = eventsAfter }
            in
            ( newModel, persistCmd newModel )

        SetPinnedPostsCollapsedToHidePostIds pinnedPostsCollapsedToHidePostIds ->
            let
                newModel : Model
                newModel =
                    { model | pinnedPostsCollapsedToHidePostIds = pinnedPostsCollapsedToHidePostIds }
            in
            ( newModel, persistCmd newModel )


persistCmd : Model -> Cmd Msg
persistCmd model =
    Ports.persistUserPreferences (encode model)


encode : Model -> Encode.Value
encode model =
    Encode.object
        [ ( "prefersCalendar", Encode.bool model.prefersCalendar )
        , ( "postsBefore", encodePosixField model.postsBefore )
        , ( "eventsAfter", encodePosixField model.eventsAfter )
        , ( "pinnedPostsCollapsedToHidePostIds", Encode.list Encode.string model.pinnedPostsCollapsedToHidePostIds )
        ]


encodePosixField : Maybe Time.Posix -> Encode.Value
encodePosixField maybePosix =
    case maybePosix of
        Just posix ->
            Encode.int (Time.posixToMillis posix)

        Nothing ->
            Encode.null
