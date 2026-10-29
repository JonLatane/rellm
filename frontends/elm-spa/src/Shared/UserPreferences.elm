module Shared.UserPreferences exposing (Model, Msg(..), embedDisabled, init, update)

{-| Small, app-wide user preferences that aren't tied to any one page's own
URL/local state -- `prefersCalendar`, `postsBefore`, `eventsAfter`,
`pinnedPostsCollapsedToHidePostIds`, `disable<Network>Embeds` (see each field's own doc), all one JSON
object persisted to its own localStorage key (`Ports.persistUserPreferences`).

Mirrors `Shared.StarredPanel`'s persist-to-localStorage half exactly, minus
the `BroadcastChannel` live cross-tab push -- see `Ports.persistUserPreferences`'s
own doc for why these are only ever picked up by other tabs on their next
load, not pushed into ones already open.

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Proto.Rellm.DefaultPostsSort exposing (DefaultPostsSort(..))
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

    -- Per-network opt-outs for `SocialMediaEmbed` (`Components.QuotedLink.socialEmbedView`): a link to a
    -- post on that network is left as a plain link instead of embedded. Set from the Accounts Panel's
    -- "Preferences" tab (see `UI.userPreferencesTab`); off (embeds shown) by default. Looked up by network
    -- name via `embedDisabled`.
    , disableFacebookEmbeds : Bool
    , disableInstagramEmbeds : Bool
    , disableLinkedInEmbeds : Bool
    , disablePinterestEmbeds : Bool
    , disableTikTokEmbeds : Bool
    , disableXEmbeds : Bool
    , disableYouTubeEmbeds : Bool

    -- The user's own choice of which feed `Components.Pages.PostsPage` starts on (its Recent/Popular/
    -- Following dropdown), set from the Accounts Panel's "Preferences" tab. `Nothing` (never chosen)
    -- follows the main server's `post_settings.default_sort`, which is also what that tab shows
    -- selected until a choice is made -- see `RellmServers.serverDefaultPostsSort`.
    , postsSort : Maybe DefaultPostsSort
    }


type Msg
    = SetPrefersCalendar Bool
    | SetPostsBefore (Maybe Time.Posix)
    | SetEventsAfter (Maybe Time.Posix)
    | SetPinnedPostsCollapsedToHidePostIds (List String)
    | SetDisableFacebookEmbeds Bool
    | SetDisableInstagramEmbeds Bool
    | SetDisableLinkedInEmbeds Bool
    | SetDisablePinterestEmbeds Bool
    | SetDisableTikTokEmbeds Bool
    | SetDisableXEmbeds Bool
    | SetDisableYouTubeEmbeds Bool
    | SetPostsSort (Maybe DefaultPostsSort)


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
    , disableFacebookEmbeds = decodeBoolField "disableFacebookEmbeds" flags
    , disableInstagramEmbeds = decodeBoolField "disableInstagramEmbeds" flags
    , disableLinkedInEmbeds = decodeBoolField "disableLinkedInEmbeds" flags
    , disablePinterestEmbeds = decodeBoolField "disablePinterestEmbeds" flags
    , disableTikTokEmbeds = decodeBoolField "disableTikTokEmbeds" flags
    , disableXEmbeds = decodeBoolField "disableXEmbeds" flags
    , disableYouTubeEmbeds = decodeBoolField "disableYouTubeEmbeds" flags
    , postsSort =
        Decode.decodeValue (Decode.field "postsSort" Decode.int) flags
            |> Result.toMaybe
            |> Maybe.andThen postsSortFromInt
    }


postsSortFromInt : Int -> Maybe DefaultPostsSort
postsSortFromInt n =
    case n of
        0 ->
            Just DEFAULTPOSTSSORTRECENT

        1 ->
            Just DEFAULTPOSTSSORTPOPULAR

        2 ->
            Just DEFAULTPOSTSSORTFOLLOWING

        _ ->
            Nothing


postsSortToInt : DefaultPostsSort -> Int
postsSortToInt sort =
    case sort of
        DEFAULTPOSTSSORTRECENT ->
            0

        DEFAULTPOSTSSORTPOPULAR ->
            1

        DEFAULTPOSTSSORTFOLLOWING ->
            2

        DefaultPostsSortUnrecognized_ _ ->
            0


decodeBoolField : String -> Decode.Value -> Bool
decodeBoolField field flags =
    Decode.decodeValue (Decode.field field Decode.bool) flags
        |> Result.withDefault False


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

        SetDisableFacebookEmbeds disableFacebookEmbeds ->
            let
                newModel : Model
                newModel =
                    { model | disableFacebookEmbeds = disableFacebookEmbeds }
            in
            ( newModel, persistCmd newModel )

        SetDisableInstagramEmbeds disableInstagramEmbeds ->
            let
                newModel : Model
                newModel =
                    { model | disableInstagramEmbeds = disableInstagramEmbeds }
            in
            ( newModel, persistCmd newModel )

        SetDisableLinkedInEmbeds disableLinkedInEmbeds ->
            let
                newModel : Model
                newModel =
                    { model | disableLinkedInEmbeds = disableLinkedInEmbeds }
            in
            ( newModel, persistCmd newModel )

        SetDisablePinterestEmbeds disablePinterestEmbeds ->
            let
                newModel : Model
                newModel =
                    { model | disablePinterestEmbeds = disablePinterestEmbeds }
            in
            ( newModel, persistCmd newModel )

        SetDisableTikTokEmbeds disableTikTokEmbeds ->
            let
                newModel : Model
                newModel =
                    { model | disableTikTokEmbeds = disableTikTokEmbeds }
            in
            ( newModel, persistCmd newModel )

        SetDisableXEmbeds disableXEmbeds ->
            let
                newModel : Model
                newModel =
                    { model | disableXEmbeds = disableXEmbeds }
            in
            ( newModel, persistCmd newModel )

        SetDisableYouTubeEmbeds disableYouTubeEmbeds ->
            let
                newModel : Model
                newModel =
                    { model | disableYouTubeEmbeds = disableYouTubeEmbeds }
            in
            ( newModel, persistCmd newModel )

        SetPostsSort postsSort ->
            let
                newModel : Model
                newModel =
                    { model | postsSort = postsSort }
            in
            ( newModel, persistCmd newModel )


{-| Whether the user turned off embeds for `network` (a `SocialMediaEmbed.network` name). -}
embedDisabled : String -> Model -> Bool
embedDisabled network model =
    case network of
        "facebook" ->
            model.disableFacebookEmbeds

        "instagram" ->
            model.disableInstagramEmbeds

        "linkedin" ->
            model.disableLinkedInEmbeds

        "pinterest" ->
            model.disablePinterestEmbeds

        "tiktok" ->
            model.disableTikTokEmbeds

        "x" ->
            model.disableXEmbeds

        "youtube" ->
            model.disableYouTubeEmbeds

        _ ->
            False


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
        , ( "disableFacebookEmbeds", Encode.bool model.disableFacebookEmbeds )
        , ( "disableInstagramEmbeds", Encode.bool model.disableInstagramEmbeds )
        , ( "disableLinkedInEmbeds", Encode.bool model.disableLinkedInEmbeds )
        , ( "disablePinterestEmbeds", Encode.bool model.disablePinterestEmbeds )
        , ( "disableTikTokEmbeds", Encode.bool model.disableTikTokEmbeds )
        , ( "disableXEmbeds", Encode.bool model.disableXEmbeds )
        , ( "disableYouTubeEmbeds", Encode.bool model.disableYouTubeEmbeds )
        , ( "postsSort", model.postsSort |> Maybe.map (postsSortToInt >> Encode.int) |> Maybe.withDefault Encode.null )
        ]


encodePosixField : Maybe Time.Posix -> Encode.Value
encodePosixField maybePosix =
    case maybePosix of
        Just posix ->
            Encode.int (Time.posixToMillis posix)

        Nothing ->
            Encode.null
