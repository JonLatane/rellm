module Pages.Event.PostId_ exposing (Model, Msg, fromShared, occasionUrlChanged, page)

{-| `/event/:postId[@host]` -- a single Event, by its own (or one of its
`Occasion`s') Post id, on `mainFrontendHost` or (with an `@host` suffix)
some other federated server. Thin wrapper around `Components.Pages.EventPage`,
which does all the actual work -- mirrors `Pages.Post.PostId_`'s own
direct-alias shape around `Components.Pages.PostPage`. Also reused,
unmodified, by `Components.Pages.PostOrEventPage` (once a short-URL id
resolves to an Event/Occasion) and, through it, `Pages.UsernameOrCustomTab_`,
so a vanity short URL like `/:4rAfoSKAuJo` renders indistinguishably from
this page itself -- see those modules' own docs.
-}

import Components.Pages.EventPage as EventPage
import Effect exposing (Effect)
import Gen.Params.Event.PostId_ exposing (Params)
import Page
import Request
import Shared
import Shared.AccountsPanel.RellmServers as RellmServers
import UI
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared req =
    Page.advanced
        { init = init shared req
        , update = update shared
        , view = view shared req
        , subscriptions = EventPage.subscriptions
        }


type alias Model =
    EventPage.Model


type alias Msg =
    EventPage.Msg


init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared req =
    EventPage.init shared (RellmServers.isSecure req) req.params.postId req.key


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    EventPage.update shared msg model


view : Shared.Model -> Request.With Params -> Model -> View Msg
view shared req model =
    { title = UI.pageTitle shared [ EventPage.titleFor model ]
    , body =
        UI.layout shared
            req.route
            fromShared
            [ EventPage.view shared model ]
    }


{-| Lets `Main` forward a `Shared.Msg` that didn't originate from this page -- see
`Components.Pages.EventPage.fromShared`.
-}
fromShared : Shared.Msg -> Msg
fromShared =
    EventPage.fromShared


{-| Lets `Main`'s own `ChangedUrl` deliver a same-page "switched to a sibling
Occasion" URL change straight into an already-running instance of this page
instead of a full `init` remount -- see `Components.Pages.EventPage.occasionUrlChanged`.
-}
occasionUrlChanged : String -> Msg
occasionUrlChanged =
    EventPage.occasionUrlChanged
