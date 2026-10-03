module Pages.Media exposing (Model, Msg, fromShared, page)

{-| `/media` -- the server's video and audio (plus the signed-in user's own media) in tabs. Thin wrapper around `Components.Pages.MediaPage` (mode `Tabbed`), which
does all the actual work -- see its module doc.
-}

import Components.Pages.MediaPage as MediaPage
import Effect exposing (Effect)
import Gen.Params.Media exposing (Params)
import Page
import Request
import Shared
import UI
import Proto.Rellm.NavigationTab exposing (NavigationTab(..))
import UI.CustomNav as CustomNav
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared req =
    Page.advanced
        { init = init shared req
        , update = update shared
        , view = view shared req
        , subscriptions = MediaPage.subscriptions
        }


type alias Model =
    MediaPage.Model


type alias Msg =
    MediaPage.Msg


init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared req =
    MediaPage.init shared MediaPage.Tabbed req.key req.url.path req.query


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    MediaPage.update shared msg model


view : Shared.Model -> Request.With Params -> Model -> View Msg
view shared req model =
    { title = UI.pageTitle shared [ CustomNav.tabTitle shared MEDIATAB ]
    , body =
        UI.layout shared
            req.route
            fromShared
            [ MediaPage.view shared model
            ]
    }


{-| Lets `Main` forward a `Shared.Msg` that didn't originate from this page -- see
`Components.Pages.MediaPage.fromShared`.
-}
fromShared : Shared.Msg -> Msg
fromShared =
    MediaPage.fromShared
