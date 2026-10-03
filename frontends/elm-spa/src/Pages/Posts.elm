module Pages.Posts exposing (Model, Msg, fromShared, page)

{-| `/posts` -- recent posts from every enabled server. Thin wrapper around
`Components.Pages.PostsPage`, which does all the actual work -- mirrors
`Pages.Home_`'s own use of that module (deliberately duplicated rather than
shared, so future changes to `Pages.Home_` don't affect this route). Unlike
`Pages.Home_`, this route passes `embeddedPage = False`, so `PostsPage.view`
renders its own "Recent Posts"/"Posts Before <date>" tabs heading directly
(see `Components.Pages.PostsPage.recentPostsTabsView`) rather than this page
supplying a static one -- and passes `authorUserId = Nothing` (an unfiltered
feed, rather than one user's own posts) -- plus, like `Pages.Home_`, keeps
`Shared.Breadcrumbs` pointed at `mainFrontendHost` (see `setBreadcrumbsHost`),
since this feed isn't scoped to any one server for a breadcrumb trail to
identify the way a Post's own reply chain is.
-}

import Components.Pages.PostsPage as PostsPage
import Effect exposing (Effect)
import Gen.Params.Posts exposing (Params)
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
        , subscriptions = PostsPage.subscriptions
        }


type alias Model =
    PostsPage.Model


type alias Msg =
    PostsPage.Msg


init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared req =
    let
        ( model, effect ) =
            PostsPage.init shared Nothing req.key req.url.path req.query False Nothing Nothing
    in
    ( model, Effect.batch [ effect ] )


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    let
        ( newModel, effect ) =
            PostsPage.update shared msg model
    in
    ( newModel, Effect.batch [ effect ] )


view : Shared.Model -> Request.With Params -> Model -> View Msg
view shared req model =
    { title = UI.pageTitle shared [ CustomNav.tabTitle shared POSTSTAB ]
    , body =
        UI.layout shared
            req.route
            fromShared
            [ PostsPage.view shared True True model
            ]
    }


{-| Lets `Main` forward a `Shared.Msg` that didn't originate from this page --
see `Components.Pages.PostsPage.fromShared`.
-}
fromShared : Shared.Msg -> Msg
fromShared =
    PostsPage.fromShared
