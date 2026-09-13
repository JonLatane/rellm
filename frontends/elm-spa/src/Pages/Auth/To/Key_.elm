module Pages.Auth.To.Key_ exposing (Model, Msg, page)

{-| `/auth/to/:key`, where `:key` is `PUBLIC_KEY_URLSTRING@requestingHost` --
the sending side of the cross-server SSO hand-off (see
`Shared.FederatedAuth`): shows whoever's currently signed in on this app's own
`browsingHost` (`Shared.AccountsPanel.Model.browsingHost`), or -- if nobody
is -- lets them type in (or pick, via `usernameField`'s quick-fill buttons)
the username to sign in as. Either way, asks for their password (a fresh
Login RPC, not reusing any already-stored tokens, since only a freshly issued
token pair is transferred), then encrypts the resulting `RellmAccountAuthTokens`
(just this server's hostname plus that fresh token pair -- everything else an
`RellmAccount` needs is hydrated on the other end, via `GetCurrentUser`) to
`requestingHost`'s public key and redirects back to
`https://requestingHost/elm/auth/from/...`. The receiving side is
`Pages.Auth.From.EncryptedAccountAuthTokens_`.

Optionally (`alsoSignInHere`), that same username/password is also used for a
_second_, independent Login RPC (see `GotLoginResult`/`GotLocalSignInResult`)
whose fresh token pair is fed into this browser's own `Shared.AccountsPanel`
instead of being sent anywhere -- so the transfer to `requestingHost` and
this browser's own sign-in on `browsingHost` never share a token pair.

-}

import Browser.Navigation as Nav
import Dict
import Effect exposing (Effect)
import Gen.Params.Auth.To.Key_ exposing (Params)
import Grpc
import Html exposing (Html, button, div, form, h2, input, label, p, span, text)
import Html.Attributes exposing (attribute, checked, class, disabled, name, placeholder, spellcheck, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)
import Json.Encode as Encode
import Page
import Ports
import Proto.Rellm exposing (ExpirableToken, RefreshTokenResponse)
import Proto.Rellm.Rellm as Rellm
import Request
import Shared
import Shared.AccountsPanel as AccountsPanel exposing (FormStatus(..))
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount, RellmAccountAuthTokens, Token)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Shared.Conversions exposing (int64ToInt, timestampToPosix)
import Shared.FederatedAuth as FederatedAuth
import Task exposing (Task)
import UI
import UI.Classes exposing (classes, hostnameToCSSClass)
import Url
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared req =
    Page.advanced
        { init = init shared req
        , update = update shared
        , view = view shared req
        , subscriptions = subscriptions
        }



-- MODEL


type alias Model =
    { requestingHost : String
    , publicKey : Maybe FederatedAuth.PublicKey

    -- Only used/shown when nobody's currently signed in to `browsingHost` --
    -- see `usernameField`. Otherwise the signed-in account's own username is
    -- used instead (see `effectiveUsername`).
    , username : String
    , password : String

    -- Whether to also feed this page's own fresh Login RPC into this
    -- browser's `Shared.AccountsPanel`, signing (or re-signing) in locally on
    -- `browsingHost` -- see `GotLoginResult`/`GotLocalSignInResult`.
    , alsoSignInHere : Bool

    -- The transfer `RellmAccountAuthTokens` (bound for `requestingHost`) and its public key,
    -- held here between `GotLoginResult` and `GotLocalSignInResult` while
    -- `alsoSignInHere`'s second Login RPC is still in flight. `Nothing` the
    -- rest of the time -- including once that second RPC settles, at which
    -- point it's consumed to actually kick off the encrypt/redirect.
    , pendingTransferAccount : Maybe ( RellmAccountAuthTokens, FederatedAuth.PublicKey )
    , status : FormStatus

    -- The path (app-relative, no `basePath`) the user was on when they
    -- clicked "Sign in from <server>" (see `UI.signInFromButton`) -- passed
    -- through unchanged into the redirect back to `requestingHost` (see
    -- `GotEncryptResult`) so `Pages.Auth.From.EncryptedAccountAuthTokens_` can send them
    -- back where they started instead of just the home page.
    , startPath : Maybe String
    }


type Msg
    = UsernameChanged String
    | PasswordChanged String
    | UsernameButtonClicked String
    | AlsoSignInHereToggled
    | SignInClicked
    | GotLoginResult (Result Grpc.Error ( Maybe RellmAccountAuthTokens, FederatedAuth.PublicKey ))
    | GotLocalSignInResult (Result Grpc.Error (Maybe RellmAccount))
    | GotEncryptResult Encode.Value
    | SharedMsg Shared.Msg


{-| `rawKey` is `PUBLIC_KEY_URLSTRING@requestingHost` -- always both parts,
unlike `Components.PostCard.parsePostRouteId`'s `id[@host]`, since this route
has no "current server" to fall back to.
-}
init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared req =
    let
        ( keyString, requestingHost ) =
            case String.split "@" req.params.key of
                [ key, host ] ->
                    ( Just key, host )

                _ ->
                    ( Nothing, "" )

        browsingHost : String
        browsingHost =
            shared.accounts.browsingHost

        -- Pre-filled only when there's exactly one candidate to guess --
        -- see `usernameField`'s quick-fill buttons for the ambiguous case.
        defaultUsername : String
        defaultUsername =
            case RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts browsingHost of
                Just _ ->
                    ""

                Nothing ->
                    case List.filter (\a -> a.server == browsingHost) shared.accounts.accounts of
                        [ onlyAccount ] ->
                            onlyAccount.username

                        _ ->
                            ""
    in
    ( { requestingHost = requestingHost
      , publicKey = keyString |> Maybe.andThen FederatedAuth.urlStringToPublicKey
      , username = defaultUsername
      , password = ""
      , alsoSignInHere = True
      , pendingTransferAccount = Nothing
      , status = Idle
      , startPath = Dict.get "start_path" req.query
      }
    , Effect.none
    )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Ports.federatedAuthEncrypted GotEncryptResult



-- UPDATE


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    case msg of
        UsernameChanged username ->
            ( { model | username = username }, Effect.none )

        PasswordChanged password ->
            ( { model | password = password }, Effect.none )

        UsernameButtonClicked username ->
            ( { model | username = username }, Effect.none )

        AlsoSignInHereToggled ->
            ( { model | alsoSignInHere = not model.alsoSignInHere }, Effect.none )

        SignInClicked ->
            let
                browsingHost : String
                browsingHost =
                    shared.accounts.browsingHost
            in
            case ( RellmServers.rellmServerForHost shared.accounts.servers browsingHost |> Maybe.andThen ifConnected, model.publicKey ) of
                ( Just server, Just publicKey ) ->
                    ( { model | status = Submitting }
                    , loginTask server (effectiveUsername shared model) model.password
                        |> Task.map (\resp -> ( accountAuthTokensFromLogin browsingHost resp, publicKey ))
                        |> Task.attempt GotLoginResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( { model | status = Errored ("You need to be signed in on " ++ browsingHost ++ " to do that.") }
                    , Effect.none
                    )

        GotLoginResult (Ok ( Just account, publicKey )) ->
            if model.alsoSignInHere then
                let
                    browsingHost : String
                    browsingHost =
                        shared.accounts.browsingHost
                in
                case RellmServers.rellmServerForHost shared.accounts.servers browsingHost |> Maybe.andThen ifConnected of
                    Just server ->
                        ( { model | pendingTransferAccount = Just ( account, publicKey ) }
                        , loginTask server (effectiveUsername shared model) model.password
                            |> Task.map (accountFromLogin browsingHost)
                            |> Task.attempt GotLocalSignInResult
                            |> Effect.fromCmd
                        )

                    Nothing ->
                        ( model, encryptAndSendEffect publicKey account )

            else
                ( model, encryptAndSendEffect publicKey account )

        GotLoginResult (Ok ( Nothing, _ )) ->
            ( { model | status = Errored "Server response was missing user/token data." }, Effect.none )

        GotLoginResult (Err err) ->
            ( { model | status = Errored (AccountsPanel.grpcErrorToString err) }, Effect.none )

        GotLocalSignInResult (Ok (Just localAccount)) ->
            case model.pendingTransferAccount of
                Just ( account, publicKey ) ->
                    -- Writes `localAccount`'s tokens into `Shared.AccountsPanel` (and
                    -- has it kick off `persist`, via `FederatedAccountReceived`) before
                    -- the batched `encryptAndSendEffect` below ever navigates away --
                    -- `Main.elm`'s `Effect.partitionShared` applies a page's forwarded
                    -- `Shared.Msg`s synchronously, in this very update cycle.
                    ( { model | pendingTransferAccount = Nothing }
                    , Effect.batch
                        [ Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.FederatedAccountReceived localAccount))
                        , encryptAndSendEffect publicKey account
                        ]
                    )

                Nothing ->
                    ( model, Effect.none )

        GotLocalSignInResult (Ok Nothing) ->
            ( { model | status = Errored "Server response was missing user/token data.", pendingTransferAccount = Nothing }
            , Effect.none
            )

        GotLocalSignInResult (Err err) ->
            ( { model | status = Errored (AccountsPanel.grpcErrorToString err), pendingTransferAccount = Nothing }
            , Effect.none
            )

        GotEncryptResult value ->
            case FederatedAuth.encryptResult value of
                Ok ciphertext ->
                    ( model
                    , Nav.load
                        ("https://"
                            ++ model.requestingHost
                            ++ "/elm/auth/from/"
                            ++ ciphertext
                            ++ (case model.startPath of
                                    Just startPath ->
                                        "?start_path=" ++ Url.percentEncode startPath

                                    Nothing ->
                                        ""
                               )
                        )
                        |> Effect.fromCmd
                    )

                Err err ->
                    ( { model | status = Errored err }, Effect.none )

        SharedMsg subMsg ->
            ( model, Effect.fromShared subMsg )


loginTask : RellmServer -> String -> String -> Task Grpc.Error RefreshTokenResponse
loginTask server username password =
    case RellmServers.connectionOf server of
        -- Both call sites only ever pass a `server` that just passed `ifConnected`
        -- -- unreachable in practice.
        Nothing ->
            Task.fail Grpc.NetworkError

        Just connection ->
            Grpc.new Rellm.login
                { username = username
                , password = password
                , expiresAt = Nothing
                , deviceName = Nothing
                , userId = Nothing
                }
                |> Grpc.setHost (RellmServers.connectionUrl connection)
                |> Grpc.toTask


encryptAndSendEffect : FederatedAuth.PublicKey -> RellmAccountAuthTokens -> Effect Msg
encryptAndSendEffect publicKey tokens =
    FederatedAuth.encrypt publicKey (Encode.encode 0 (RellmAccounts.encodeRellmAccountAuthTokens tokens))
        |> Effect.fromCmd



-- VIEW


view : Shared.Model -> Request.With Params -> Model -> View Msg
view shared req model =
    { title = UI.pageTitle shared [ "Sign in" ]
    , body =
        UI.layout shared
            req.route
            SharedMsg
            [ signInView shared model ]
    }


signInView : Shared.Model -> Model -> Html Msg
signInView shared model =
    case ( model.publicKey, String.isEmpty model.requestingHost ) of
        ( Nothing, _ ) ->
            div [ class "auth-to-page" ] [ p [] [ text "This sign-in link is malformed." ] ]

        ( _, True ) ->
            div [ class "auth-to-page" ] [ p [] [ text "This sign-in link is malformed." ] ]

        ( Just _, False ) ->
            let
                browsingHost : String
                browsingHost =
                    shared.accounts.browsingHost

                signedInAccount : Maybe RellmAccount
                signedInAccount =
                    RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts browsingHost

                accountsOnHost : List RellmAccount
                accountsOnHost =
                    List.filter (\a -> a.server == browsingHost) shared.accounts.accounts

                username : String
                username =
                    effectiveUsername shared model

                accountForUsername : Maybe RellmAccount
                accountForUsername =
                    accountsOnHost |> List.filter (\a -> a.username == username) |> List.head

                submitting : Bool
                submitting =
                    model.status == Submitting
            in
            -- A real `<form>` (rather than `div`), with a real `submit` button
            -- (rather than `onClick` + `type_ "button"`) and matching
            -- `autocomplete`s on the fields below -- so Safari/Chrome/password
            -- managers recognize this as a login form worth offering to
            -- fill/save, and Enter in either field submits it. `onSubmit`
            -- alone (not a button `onClick`) is what fires `SignInClicked`,
            -- so a native submit (Enter key or clicking the button) can never
            -- double-fire it.
            form [ class "auth-to-page", onSubmit SignInClicked ]
                [ h2 [] [ text (model.requestingHost ++ " is asking to sign in") ]
                , case signedInAccount of
                    Just account ->
                        currentAccountBadge shared account

                    Nothing ->
                        usernameField shared model accountsOnHost submitting
                , input
                    [ type_ "password"
                    , name "current-password"

                    -- "current-password", not "new-password": this page never
                    -- creates an account, only signs into one that already
                    -- exists -- see `UI.elm`'s identical choice for its own
                    -- password field.
                    , attribute "autocomplete" "current-password"
                    , placeholder "Password"
                    , value model.password
                    , onInput PasswordChanged
                    , disabled submitting
                    ]
                    []
                , alsoSignInCheckbox model.alsoSignInHere accountForUsername submitting
                , button
                    [ disabled (submitting || String.isEmpty model.password || String.isEmpty username)
                    , classes [ hostnameToCSSClass model.requestingHost, "background-color-primary", "auth-to-signin-button" ]
                    ]
                    [ text ("Sign in on " ++ model.requestingHost) ]
                , case model.status of
                    Errored err ->
                        div [ class "auth-error" ] [ text err ]

                    _ ->
                        text ""
                ]


currentAccountBadge : Shared.Model -> RellmAccount -> Html Msg
currentAccountBadge shared account =
    let
        avatarUrl : Maybe String
        avatarUrl =
            RellmAccounts.rellmAccountAvatarUrl shared.accounts.servers account

        nameAndHost : String
        nameAndHost =
            account.username
                ++ (if String.isEmpty (String.trim account.realName) then
                        ""

                    else
                        " | " ++ account.realName
                   )
                ++ " from "
                ++ account.server
    in
    div [ class "auth-to-account" ]
        [ span [ class "auth-from-greeting" ] [ text "Sign in as" ]
        , UI.imageOrInitial [ "auth-from-avatar" ] account.username avatarUrl
        , span [ class "auth-from-name" ] [ text nameAndHost ]
        , span [ class "auth-from-greeting" ] [ text "?" ]
        ]


{-| Shown in place of `currentAccountBadge` when nobody's currently signed in
to `browsingHost` -- a plain username input, plus one quick-fill button per
account already known for that host (signed out, or needing a password), so
picking a previously-used username doesn't require retyping it. The
single-candidate auto-fill happens once, in `init`.
-}
usernameField : Shared.Model -> Model -> List RellmAccount -> Bool -> Html Msg
usernameField shared model accountsOnHost submitting =
    div [ class "auth-to-username-section" ]
        (input
            [ type_ "text"
            , name "username"
            , attribute "autocomplete" "username"
            , attribute "autocapitalize" "none"
            , attribute "autocorrect" "off"
            , spellcheck False
            , placeholder ("Username on " ++ shared.accounts.browsingHost)
            , value model.username
            , onInput UsernameChanged
            , disabled submitting
            ]
            []
            :: (if List.isEmpty accountsOnHost then
                    []

                else
                    [ div [ class "auth-to-username-buttons" ]
                        (List.map (usernameButton shared submitting) accountsOnHost)
                    ]
               )
        )


usernameButton : Shared.Model -> Bool -> RellmAccount -> Html Msg
usernameButton shared submitting account =
    button
        [ type_ "button"
        , class "auth-to-username-button"
        , onClick (UsernameButtonClicked account.username)
        , disabled submitting
        ]
        [ UI.imageOrInitial [ "auth-to-username-button-avatar" ] account.username (RellmAccounts.rellmAccountAvatarUrl shared.accounts.servers account)
        , span [] [ text account.username ]
        ]


{-| Below the password field -- lets a fresh Login also be written into
`Shared.AccountsPanel` for `browsingHost` (see `GotLoginResult`), rather than
only ever being used for the `requestingHost` transfer. Its label reflects
whether `accountForUsername` (the current username's existing RellmAccount here,
if any) already exists, since checking it either creates a brand new
sign-in or just refreshes/re-enables that existing one.
-}
alsoSignInCheckbox : Bool -> Maybe RellmAccount -> Bool -> Html Msg
alsoSignInCheckbox isChecked accountForUsername submitting =
    label [ class "auth-to-also-sign-in" ]
        [ input
            [ type_ "checkbox"
            , checked isChecked
            , onClick AlsoSignInHereToggled
            , disabled submitting
            ]
            []
        , text
            (case accountForUsername of
                Nothing ->
                    "Also sign in here"

                Just _ ->
                    "Sign back in here"
            )
        ]


{-| The username this page's Login RPC(s) actually authenticate as: the
signed-in account's own, if `browsingHost` has one, otherwise whatever's
typed into `usernameField`. Shared between `signInView` (for the submit
button's disabled state) and `update` (for the RPC(s) themselves) so the two
never disagree.
-}
effectiveUsername : Shared.Model -> Model -> String
effectiveUsername shared model =
    case RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts shared.accounts.browsingHost of
        Just account ->
            account.username

        Nothing ->
            model.username


{-| `Just server` only while actually connected (see `RellmServer.connected`)
-- `loginTask` needs a live connection, so a known-but-disconnected server
(`serverForHost` matches those too) counts the same as not being signed in.
-}
ifConnected : RellmServer -> Maybe RellmServer
ifConnected server =
    if server.connected == Nothing then
        Nothing

    else
        Just server


{-| The transfer payload's own construction from a fresh `Login` response -- just `server` plus the
fresh token pair (see `RellmAccountAuthTokens`'s own doc), unlike `accountFromLogin`'s full `RellmAccount`
below (used only for this same page's own, separate "sign back in here" local login). `Nothing` if
the response is missing token data (an `update` branch above turns that into the same `Errored`
state `GotAuthResult` would).
-}
accountAuthTokensFromLogin : String -> RefreshTokenResponse -> Maybe RellmAccountAuthTokens
accountAuthTokensFromLogin server resp =
    case ( resp.refreshToken, resp.accessToken ) of
        ( Just refreshToken, Just accessToken ) ->
            Just
                { server = server
                , refreshToken = tokenFromExpirable refreshToken
                , accessToken = tokenFromExpirable accessToken
                }

        _ ->
            Nothing


{-| Mirrors `Shared.AccountsPanel.sendUpdate`'s `GotAuthResult` account
construction -- used for this page's own "sign back in here" local login
(`GotLocalSignInResult`), which needs a full `RellmAccount`, unlike the transfer
payload itself (see `accountAuthTokensFromLogin`). `Nothing` if the response
is missing user/token data (an `update` branch above turns that into the same
`Errored` state `GotAuthResult` would).
-}
accountFromLogin : String -> RefreshTokenResponse -> Maybe RellmAccount
accountFromLogin server resp =
    case ( resp.user, resp.refreshToken, resp.accessToken ) of
        ( Just user, Just refreshToken, Just accessToken ) ->
            Just
                { server = server
                , userId = user.id
                , username = user.username
                , refreshToken = tokenFromExpirable refreshToken
                , accessToken = tokenFromExpirable accessToken
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
                , mediaStorageBytesUsed = int64ToInt user.mediaStorageBytesUsed
                , mediaStorageLimitBytes = Maybe.map int64ToInt user.mediaStorageLimitBytes
                }

        _ ->
            Nothing


tokenFromExpirable : ExpirableToken -> Token
tokenFromExpirable expirable =
    { token = expirable.token
    , expiresAt = Maybe.map timestampToPosix expirable.expiresAt
    }
