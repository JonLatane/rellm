module Components.Pages.PostOrEventPage exposing
    ( Model
    , Msg
    , fromShared
    , init
    , subscriptions
    , titleFor
    , update
    , view
    )

{-| A short Post/Event URL's own page: given a raw id (with no way to know up front whether it's a
plain `Post`'s own id or an `Event`/`Occasion`'s), resolves which one it is, then embeds the
same `Components.Pages.PostPage`/`Components.Pages.EventPage` either `Pages.Post.PostId_`/
`Pages.Event.PostId_` themselves mount -- so `/{postId}` (see `Pages.UsernameOrCustomTab_`'s own
doc for when this gets used instead of a plain username/custom-tab lookup) renders exactly the
same content as `/post/:id`/`/event/:id`, in place, without ever redirecting the address bar away
from the short URL.

Resolution is a `GetEvents{post_id}` fetch (`Components.Events.fetchEvent`, which already looks up
either an Event's own post or one of its Occasions' posts): on success, it's an Event; on
failure (e.g. `"event_not_found"` -- the id doesn't belong to any Event/Occasion at all), it's
tried as a plain Post instead. This means resolving an Event id takes two round trips total (one
here, one more inside `Components.Pages.EventPage.init` itself) -- a known, accepted inefficiency,
not a bug: `EventPage`/`PostPage`'s own `init` aren't designed to accept already-fetched data, and
teaching them to would be a much bigger change for a rarely-hit path (most links are either
`/post/:id` or `/event/:id` directly; this short form is a convenience alias).

-}

import Browser.Navigation
import Components.Events as Events
import Components.Pages.EventPage as EventPage
import Components.Pages.PostPage as PostPage
import Effect exposing (Effect)
import Grpc
import Html exposing (Html, text)
import Proto.Rellm exposing (GetEventsResponse)
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts
import Shared.AccountsPanel.RellmServers as RellmServers
import Task


type Model
    = Resolving ResolvingModel
    | Post PostPage.Model
    | Event EventPage.Model


{-| Mirrors `Components.Pages.PostPage.Model`'s own `targetHost`/`pageIsSecure`/`navKey` capture --
same reasoning, just held here only until resolution hands off to whichever of `PostPage`/
`EventPage`'s own `Model` takes over for real.
-}
type alias ResolvingModel =
    { targetHost : String
    , rawId : String
    , pageIsSecure : Bool
    , navKey : Browser.Navigation.Key
    , fetchStarted : Bool
    }


type Msg
    = GotResolveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, GetEventsResponse ))
    | PostMsg PostPage.Msg
    | EventMsg EventPage.Msg
    | SharedMsg Shared.Msg


{-| `rawSegment` is the short-URL route segment, still carrying its reserved leading character
(e.g. `:4rAfoSKAuJo`) -- that character only exists to tell `Pages.UsernameOrCustomTab_` apart from
a username/custom tab, and isn't part of the id itself (unlike base58, it's not even a valid
id character at all), so it's stripped here, once, before the actual id is used for anything --
every fetch/sub-page from this point on gets the real id, same as if `/post/:id`/`/event/:id` had
been visited directly.
-}
init : Shared.Model -> Bool -> String -> Browser.Navigation.Key -> ( Model, Effect Msg )
init shared pageIsSecure rawSegment navKey =
    let
        rawId : String
        rawId =
            String.dropLeft 1 rawSegment

        ( _, targetHost ) =
            Events.parseEventRouteId shared.accounts.mainFrontendHost rawId

        ( fetchedResolving, fetchEffect ) =
            fetchIfReady shared
                { targetHost = targetHost
                , rawId = rawId
                , pageIsSecure = pageIsSecure
                , navKey = navKey
                , fetchStarted = False
                }
    in
    ( Resolving fetchedResolving, fetchEffect )


{-| Mirrors `Components.Pages.EventPage.fetchIfReady`/`Components.Pages.PostPage.fetchIfReady`
exactly -- kicks off the disambiguating `GetEvents` fetch the first time `targetHost` is a known,
connected server, and no-ops (rather than erroring or blocking) until then; `update`'s `SharedMsg`
branch retries this on every incoming `Shared.Msg` while still `Resolving`, same as those two
pages' own `SharedMsg` handling does for their real fetch.
-}
fetchIfReady : Shared.Model -> ResolvingModel -> ( ResolvingModel, Effect Msg )
fetchIfReady shared resolving =
    if resolving.fetchStarted then
        ( resolving, Effect.none )

    else
        case RellmServers.knownConnectedRellmServer shared.accounts.servers resolving.targetHost of
            Just _ ->
                ( { resolving | fetchStarted = True }
                , Events.fetchEvent shared.accounts (maybeAccountServerFor shared resolving) resolving.rawId
                    |> Task.attempt GotResolveResult
                    |> Effect.fromCmd
                )

            Nothing ->
                ( resolving, Effect.none )


{-| Mirrors `Components.Pages.EventPage.maybeAccountServerFor`/`Components.Pages.PostPage`'s
identical derivation exactly -- the resolving fetch must be authenticated the same way the real
`PostPage`/`EventPage` fetch that follows it will be, or a signed-in viewer's own `LIMITED`-
visibility Event could resolve as "not found" here and get (wrongly) treated as a Post instead.
-}
maybeAccountServerFor : Shared.Model -> ResolvingModel -> AccountsPanel.MaybeAccountServer
maybeAccountServerFor shared resolving =
    ( RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts resolving.targetHost |> Maybe.map .userId
    , resolving.targetHost
    )


subscriptions : Model -> Sub Msg
subscriptions model =
    case model of
        Resolving _ ->
            Sub.none

        Post subModel ->
            Sub.map PostMsg (PostPage.subscriptions subModel)

        Event subModel ->
            Sub.map EventMsg (EventPage.subscriptions subModel)


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    case ( msg, model ) of
        ( GotResolveResult (Ok ( _, response )), Resolving resolving ) ->
            if List.isEmpty response.events then
                asPost shared resolving

            else
                asEvent shared resolving

        ( GotResolveResult (Err _), Resolving resolving ) ->
            -- Not an Event/Occasion id (e.g. "event_not_found") -- try it as a Post instead.
            asPost shared resolving

        ( PostMsg subMsg, Post subModel ) ->
            PostPage.update shared subMsg subModel
                |> Tuple.mapFirst Post
                |> Tuple.mapSecond (Effect.map PostMsg)

        ( EventMsg subMsg, Event subModel ) ->
            EventPage.update shared subMsg subModel
                |> Tuple.mapFirst Event
                |> Tuple.mapSecond (Effect.map EventMsg)

        ( SharedMsg _, Resolving resolving ) ->
            fetchIfReady shared resolving
                |> Tuple.mapFirst Resolving

        ( SharedMsg subMsg, Post subModel ) ->
            PostPage.update shared (PostPage.fromShared subMsg) subModel
                |> Tuple.mapFirst Post
                |> Tuple.mapSecond (Effect.map PostMsg)

        ( SharedMsg subMsg, Event subModel ) ->
            EventPage.update shared (EventPage.fromShared subMsg) subModel
                |> Tuple.mapFirst Event
                |> Tuple.mapSecond (Effect.map EventMsg)

        _ ->
            ( model, Effect.none )


asPost : Shared.Model -> ResolvingModel -> ( Model, Effect Msg )
asPost shared resolving =
    PostPage.init shared resolving.pageIsSecure resolving.rawId resolving.navKey
        |> Tuple.mapFirst Post
        |> Tuple.mapSecond (Effect.map PostMsg)


asEvent : Shared.Model -> ResolvingModel -> ( Model, Effect Msg )
asEvent shared resolving =
    EventPage.init shared resolving.pageIsSecure resolving.rawId resolving.navKey
        |> Tuple.mapFirst Event
        |> Tuple.mapSecond (Effect.map EventMsg)


view : Shared.Model -> Model -> Html Msg
view shared model =
    case model of
        Resolving _ ->
            text ""

        Post subModel ->
            Html.map PostMsg (PostPage.view shared subModel)

        Event subModel ->
            Html.map EventMsg (EventPage.view shared subModel)


titleFor : Model -> String
titleFor model =
    case model of
        Resolving _ ->
            "Loading…"

        Post subModel ->
            PostPage.titleFor subModel

        Event subModel ->
            EventPage.titleFor subModel


{-| Lets `Main` forward a `Shared.Msg` that didn't originate from this page -- see `Msg`'s own doc
on why this always wraps as `SharedMsg` rather than picking `Post`'s/`Event`'s own wrapper up
front (mirrors `Pages.UsernameOrCustomTab_.fromShared`'s identical reasoning).
-}
fromShared : Shared.Msg -> Msg
fromShared =
    SharedMsg
