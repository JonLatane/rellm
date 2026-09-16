module Pages.Auth.From.EncryptedAccountAuthTokens_ exposing (Model, Msg, page)

{-| `/auth/from/:encryptedAccountAuthTokens` -- the receiving side of the
cross-server SSO hand-off (see `Shared.FederatedAuth`): decrypts
`:encryptedAccountAuthTokens` with this origin's own private key into an
`RellmAccountAuthTokens` (just a server hostname plus a fresh
`refreshToken`/`accessToken` pair -- see that type's own doc), calls
`GetCurrentUser` against that server to hydrate everything else, then adds the
resulting account straight to `Shared.AccountsPanel` and navigates on -- no
confirmation step. Decryption succeeding is itself the authenticity check
(the ciphertext is AEAD-encrypted to this origin's own one-time private key,
so a forged/replayed payload just fails to decrypt), so there's nothing left
for a human to usefully confirm; `Shared.AccountsPanel`'s own
`federatedSignInNotice` (see `UI.elm`'s `federatedSignInNoticeView`) is what
tells the user it happened. The sending side is `Pages.Auth.To.Key_`.
-}

import Browser.Navigation as Nav
import Dict
import Effect exposing (Effect)
import Gen.Params.Auth.From.EncryptedAccountAuthTokens_ exposing (Params)
import Grpc
import Html exposing (Html, div, p, text)
import Html.Attributes exposing (class)
import Json.Decode as Decode
import Json.Encode as Encode
import Page
import Ports
import Proto.Rellm exposing (User)
import Request
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount, RellmAccountAuthTokens)
import Shared.AccountsPanel.RellmServers as RellmServers
import Shared.Conversions as Conversions
import Shared.FederatedAuth as FederatedAuth
import Task
import UI
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared req =
    Page.advanced
        { init = init shared req
        , update = update shared req
        , view = view shared req
        , subscriptions = subscriptions
        }


type alias Model =
    { status : Status

    -- `?start_path=` (see `UI.signInFromButton`/`Pages.Auth.To.Key_`) -- the
    -- app-relative path the user was on, on this origin, before the SSO
    -- hand-off started. Defaults to `/` if somehow missing (a hand-typed or
    -- truncated `/auth/from` link), so the flow always lands somewhere real
    -- rather than needing a fallback UI of its own.
    , startPath : String
    }


type Msg
    = GotDecryptResult Encode.Value
    | GotSignInResult RellmAccountAuthTokens (Result Grpc.Error User)
    | SharedMsg Shared.Msg


type Status
    = Decrypting
    | DecryptFailed String
    | SigningIn
    | SignInFailed String
    | Accepted


init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared req =
    let
        startPath : String
        startPath =
            Dict.get "start_path" req.query |> Maybe.withDefault "/"
    in
    case shared.panels.federatedAuth.privateKey of
        Nothing ->
            ( { status = DecryptFailed "No pending sign-in was started from this browser.", startPath = startPath }, Effect.none )

        Just privateKey ->
            ( { status = Decrypting, startPath = startPath }
            , FederatedAuth.decrypt privateKey req.params.encryptedAccountAuthTokens |> Effect.fromCmd
            )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Ports.federatedAuthDecrypted GotDecryptResult


update : Shared.Model -> Request.With Params -> Msg -> Model -> ( Model, Effect Msg )
update shared req msg model =
    case msg of
        GotDecryptResult value ->
            case FederatedAuth.decryptResult value of
                Ok tokensJson ->
                    case Decode.decodeString RellmAccounts.rellmAccountAuthTokensDecoder tokensJson of
                        Ok tokens ->
                            ( { model | status = SigningIn }
                            , RellmAccounts.resolveFederatedRellmAccountTokens (RellmServers.isSecure req) shared.accounts.servers tokens
                                |> Task.attempt (GotSignInResult tokens)
                                |> Effect.fromCmd
                            )

                        Err _ ->
                            ( { model | status = DecryptFailed "The received sign-in data was malformed." }, Effect.none )

                Err err ->
                    ( { model | status = DecryptFailed err }, Effect.none )

        GotSignInResult tokens (Ok user) ->
            let
                account : RellmAccount
                account =
                    { server = tokens.server
                    , userId = user.id
                    , username = user.username
                    , refreshToken = tokens.refreshToken
                    , accessToken = tokens.accessToken
                    , enabled = True
                    , avatarMediaId = Maybe.map .id user.avatar
                    , permissions = user.permissions
                    , realName = user.realName
                    , needsPassword = False

                    -- Reassigned by `AccountsPanel.FederatedAccountReceived` itself (see that
                    -- handler's own comment) -- meaningless here either way.
                    , sortOrder = 0
                    , syncDestinations = user.syncDestinations
                    , syncSources = user.syncSources
                    , aiModels = user.aiModels
                    , marketSubscriptions = user.marketSubscriptions
                    , mediaStorageBytesUsed = Conversions.int64ToInt user.mediaStorageBytesUsed
                    , mediaStorageLimitBytes = Maybe.map Conversions.int64ToInt user.mediaStorageLimitBytes
                    }
            in
            ( { model | status = Accepted }
            , Effect.batch
                [ Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.FederatedAccountReceived account))
                , Effect.fromShared (Shared.FederatedAuthMsg FederatedAuth.Discarded)
                , Nav.replaceUrl req.key (shared.basePath ++ model.startPath) |> Effect.fromCmd
                ]
            )

        GotSignInResult _ (Err err) ->
            ( { model | status = SignInFailed (AccountsPanel.grpcErrorToString err) }, Effect.none )

        SharedMsg subMsg ->
            ( model, Effect.fromShared subMsg )


view : Shared.Model -> Request.With Params -> Model -> View Msg
view shared req model =
    { title = UI.pageTitle shared [ "Sign in" ]
    , body =
        UI.layout shared
            req.route
            SharedMsg
            [ statusView model ]
    }


statusView : Model -> Html Msg
statusView model =
    div [ class "auth-from-page" ]
        [ p []
            [ text
                (case model.status of
                    Decrypting ->
                        "Decrypting sign-in request…"

                    SigningIn ->
                        "Signing in…"

                    DecryptFailed err ->
                        err

                    SignInFailed err ->
                        "Couldn't finish signing in: " ++ err

                    Accepted ->
                        "Signed in! Redirecting…"
                )
            ]
        ]
