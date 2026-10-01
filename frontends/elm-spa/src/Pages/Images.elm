module Pages.Images exposing (Model, Msg, fromShared, page)

{-| `/images` -- a photo-gallery feed of the server's images. Thin wrapper around `Components.Pages.MediaPage` (mode `ImagesOnly`), which
does all the actual work -- see its module doc.
-}

import Components.Pages.MediaPage as MediaPage
import Effect exposing (Effect)
import Gen.Params.Images exposing (Params)
import Page
import Request
import Shared
import UI
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
    MediaPage.init shared MediaPage.ImagesOnly req.key req.url.path req.query


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    MediaPage.update shared msg model


view : Shared.Model -> Request.With Params -> Model -> View Msg
view shared req model =
    { title = UI.pageTitle shared [ "Images" ]
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
