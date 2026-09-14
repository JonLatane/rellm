module Pages.About exposing (Model, Msg, fromShared, page)

{-| `/about` -- the main server's own info (`Components.Pages.ServerInformationPage`,
same as `Pages.Server.ServerIdentifier_` shows for an arbitrary server, just
always pointed at `mainFrontendHost`), followed by this app's own "About
Rellm" blurb. Thin wrapper, mirrors `Pages.User.UserId_`'s direct-alias
shape around `Components.Pages.UserProfilePage` -- there's no route segment
of its own to parse (and thus nothing that can be invalid), so unlike
`Pages.Server.ServerIdentifier_` there's no extra `Invalid`/`Info` split
needed here.
-}

import Components.Pages.ServerInformationPage as ServerInformationPage
import Effect exposing (Effect)
import Gen.Params.About exposing (Params)
import Html exposing (a, div, h2, p, pre, text)
import Html.Attributes exposing (class, href, target)
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
        , update = ServerInformationPage.update shared
        , view = view shared req
        , subscriptions = ServerInformationPage.subscriptions
        }


type alias Model =
    ServerInformationPage.Model


type alias Msg =
    ServerInformationPage.Msg


init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared req =
    ServerInformationPage.init shared (RellmServers.isSecure req) shared.accounts.mainFrontendHost req.key req.url.path req.query


view : Shared.Model -> Request.With Params -> Model -> View Msg
view shared req model =
    { title = UI.pageTitle shared [ "About" ]
    , body =
        UI.layout shared
            req.route
            fromShared
            [ ServerInformationPage.view shared model
            , aboutRellmView
            ]
    }


aboutRellmView : Html.Html Msg
aboutRellmView =
    div [ class "about-rellm" ]
        [ h2 [] [ text "About Rellm" ]
        , p [] [ a [ href "https://rellm.org" ] [ text "Rellm" ], text " is a federated, decentralized social media platform created by Jon Latané." ]
        , p [] [ text "Privacy-focused and marketing-hostile, it's AGPLv3 code, with a Rust BE and Elm FE (in the past, alternative ", a [ href "/tamagui/about", target "_self" ] [ text "React/Tamagui" ], text " and ", a [ href "/flutter", target "_self" ] [ text "Flutter" ], text " FEs), ", a [ href "https://github.com/JonLatane/rellm" ] [ text "available on GitHub" ], text ", and easy to deploy yourself." ]
        , p [] [ text "A single-dev process leverages LLMs the \"right\" way, against two of the most slop-resistant languages invented, with tests, to make industrial-grade, delightful, self-hostable software accessible to all. In fact, \"Rellm\" is short for \"Rust, Elm, LLMs\"." ]
        , p [] [ text "Rellm's client is natively interoperable with Mastodon and Bluesky accounts and servers. It also integrates with Facebook, X (Twitter), RSS, Atom, iCal, and much more, in many configurations (sending data to/from all these platforms)." ]
        , p [] [ text "Its only external requirements are PostgreSQL and MinIO/S3. If you have ", pre [] [ text "docker" ], text " and Postgres's ", pre [] [ text "createdb" ], text " it takes about ", a [ href "https://github.com/JonLatane/rellm#2-minute-startup-with-homebrew" ] [ text "2 minutes to set up Rellm on macOS with Homebrew" ], text " or ", a [ href "https://github.com/JonLatane/rellm#3-minute-startup-on-linux" ] [ text "3 minutes to set up Rellm on Linux" ], text "." ]
        , p [] [ text "Feel free to ", a [ href "mailto:jonlatane@gmail.com" ] [ text "email me" ], text " if you have any questions or want to contribute." ]
        ]


{-| See `Components.Pages.ServerInformationPage.fromShared` -- lets `Main`
notify this page of `Shared.Msg`s it didn't itself originate (e.g. the main
server reconnecting at startup), same as `Pages.Post.PostId_.fromShared`.
-}
fromShared : Shared.Msg -> Msg
fromShared =
    ServerInformationPage.fromShared
