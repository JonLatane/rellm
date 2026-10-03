module Pages.People exposing (Model, Msg, fromShared, page)

{-| `/people` -- every user visible on each enabled server
(`UserListingType.EVERYONE`). Thin wrapper around `Components.Pages.UsersPage`,
which does all the actual work -- mirrors `Pages.Home_`'s own use of
`Components.Pages.PostsPage`, except this passes `target = Nothing` to browse
every user rather than filtering by one user's own relationships.
-}

import Components.Pages.UsersPage as UsersPage
import Effect exposing (Effect)
import Gen.Params.People exposing (Params)
import Html exposing (h2, text)
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
        , update = UsersPage.update shared
        , view = view shared req
        , subscriptions = UsersPage.subscriptions
        }


type alias Model =
    UsersPage.Model


type alias Msg =
    UsersPage.Msg


init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared req =
    UsersPage.init shared Nothing Nothing req.key req.url.path req.query


view : Shared.Model -> Request.With Params -> Model -> View Msg
view shared req model =
    { title = UI.pageTitle shared [ CustomNav.tabTitle shared PEOPLETAB ]
    , body =
        UI.layout shared
            req.route
            fromShared
            [ h2 [] [ text "People" ]
            , UsersPage.view shared model
            ]
    }


{-| Lets `Main` forward a `Shared.Msg` that didn't originate from this page --
see `Components.Pages.UsersPage.fromShared`.
-}
fromShared : Shared.Msg -> Msg
fromShared =
    UsersPage.fromShared
