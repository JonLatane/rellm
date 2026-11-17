module Shared.AccountsPanel.ContactAuthView exposing
    ( codeStep
    , contactField
    , createContactFields
    , loginConsentCheckbox
    , loginMethodChooser
    )

{-| The SMS/email widgets of the Accounts Panel's login and create-account forms, laid out by
`UI.elm`'s `rellmAddAccountServerForm`: the "Sign in with" chooser, the phone/email field, the
"We sent a code to ..." step, and the create-account form's optional phone/email + consent. All the
state and rules are in `ContactAuth`; these only draw them and wrap their messages with `toMsg`
(`Shared.AccountsPanelMsg`) so this module needn't know about `Shared`.
-}

import Html exposing (Html, button, div, input, label, p, span, text)
import Html.Attributes exposing (attribute, checked, class, classList, disabled, id, name, placeholder, spellcheck, type_, value)
import Html.Events exposing (onClick, onInput, preventDefaultOn)
import Json.Decode as Decode
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.ContactAuth as ContactAuth exposing (Challenge, LoginMethod(..))
import Time


{-| Enter, without the form's native submit (the callers' own submit buttons handle that) -- same
as `UI.onEnter`, which this module can't import.
-}
onEnterKey : msg -> Html.Attribute msg
onEnterKey msg =
    preventDefaultOn "keydown"
        (Decode.field "key" Decode.string
            |> Decode.andThen
                (\key ->
                    if key == "Enter" then
                        Decode.succeed ( msg, True )

                    else
                        Decode.fail "Not the Enter key"
                )
        )


field : (AccountsPanel.Msg -> msg) -> AccountsPanel.Msg -> List (Html.Attribute msg) -> Html msg
field toMsg enterMsg attrs =
    div [ class "account-form-field" ]
        [ input
            (attrs
                ++ [ attribute "autocapitalize" "none"
                   , attribute "autocorrect" "off"
                   , spellcheck False
                   , onEnterKey (toMsg enterMsg)
                   ]
            )
            []
        ]


{-| "Sign in with: [Password] [Text message] [Email]" -- one button per method the server offers
(`ContactAuth.loginMethods`).
-}
loginMethodChooser : (AccountsPanel.Msg -> msg) -> List LoginMethod -> LoginMethod -> Bool -> Html msg
loginMethodChooser toMsg methods selected isDisabled =
    div [ class "login-method-chooser" ]
        [ span [ class "login-method-label" ] [ text "Sign in with" ]
        , div [ class "login-method-buttons" ]
            (methods
                |> List.map
                    (\method ->
                        button
                            [ type_ "button"
                            , classList [ ( "login-method-button", True ), ( "selected", method == selected ) ]
                            , attribute "aria-pressed"
                                (if method == selected then
                                    "true"

                                 else
                                    "false"
                                )
                            , disabled isDisabled
                            , onClick (toMsg (AccountsPanel.ContactAuthMsg (ContactAuth.MethodSelected method)))
                            ]
                            [ text (ContactAuth.loginMethodLabel method) ]
                        )
            )
        ]


{-| The phone/email field of an SMS/email login's first step. `enterMsg` is what Enter does.
-}
contactField : (AccountsPanel.Msg -> msg) -> LoginMethod -> String -> Bool -> AccountsPanel.Msg -> Html msg
contactField toMsg method current isDisabled enterMsg =
    let
        change : String -> msg
        change =
            ContactAuth.ContactChanged >> AccountsPanel.ContactAuthMsg >> toMsg
    in
    case method of
        EmailMethod ->
            field toMsg
                enterMsg
                [ id "account-form-contact"
                , type_ "email"
                , name "email"
                , attribute "inputmode" "email"
                , attribute "autocomplete" "email"
                , placeholder "Email address"
                , value current
                , onInput change
                , disabled isDisabled
                ]

        _ ->
            div []
                [ field toMsg
                    enterMsg
                    [ id "account-form-contact"
                    , type_ "tel"
                    , name "tel"
                    , attribute "inputmode" "tel"
                    , attribute "autocomplete" "tel"
                    , placeholder "Phone, e.g. +19195551234"
                    , value current
                    , onInput change
                    , disabled isDisabled
                    ]
                , p [ class "contact-auth-hint" ] [ text "Include your country code, like +19195551234." ]
                ]


{-| The sign-in form's consent checkbox, under the phone/email field. Checking it is what lets the
server message a contact method whose stored consent was revoked, and it is recorded once the code is
redeemed -- see `SMSLoginRequest.consent_to_contact`. Required before the first phase
(`ContactAuth.loginContactInvalid`).
-}
loginConsentCheckbox : (AccountsPanel.Msg -> msg) -> LoginMethod -> Bool -> Bool -> Html msg
loginConsentCheckbox toMsg method isChecked isDisabled =
    label [ class "create-contact-consent login-contact-consent" ]
        [ input
            [ type_ "checkbox"
            , checked isChecked
            , disabled isDisabled
            , onClick (toMsg (AccountsPanel.ContactAuthMsg (ContactAuth.LoginConsentToggled (not isChecked))))
            ]
            []
        , text
            (" "
                ++ (case method of
                        EmailMethod ->
                            "I agree to receive sign-in codes by email, including this one."

                        _ ->
                            "I agree to receive sign-in codes by text message, including this one. " ++ smsRatesNote
                   )
            )
        ]


smsRatesNote : String
smsRatesNote =
    "Message and data rates may apply. Reply STOP to opt out."


{-| The second step of either flow: "We sent a code to ...", a 6-digit code field per code the
server is waiting on, the expiry note, and "Resend code" -- disabled with a countdown until
`resendAvailableAt`. `fields` are `(DOM id, placeholder, current value, change message)`; every one
is a numeric one-time-code input, and Enter in any submits (`submitMsg`).
-}
codeStep :
    (AccountsPanel.Msg -> msg)
    ->
        { challenge : Challenge
        , now : Maybe Time.Posix
        , fields : List { id : String, placeholder : String, value : String, onChange : String -> ContactAuth.Msg }
        , submitMsg : AccountsPanel.Msg
        , resendMsg : AccountsPanel.Msg
        , disabled : Bool
        }
    -> Html msg
codeStep toMsg config =
    let
        secondsLeft : Int
        secondsLeft =
            ContactAuth.resendSecondsLeft config.now config.challenge
    in
    div [ class "contact-code-step" ]
        [ p [ class "contact-code-sent" ]
            [ text ("We sent a code to " ++ ContactAuth.sentToLabel config.challenge.sentTo ++ ".") ]
        , div [ class "contact-code-fields" ]
            (config.fields
                |> List.map
                    (\f ->
                        field toMsg
                            config.submitMsg
                            [ id f.id
                            , class "contact-code-input"
                            , type_ "text"
                            , name "one-time-code"
                            , attribute "inputmode" "numeric"
                            , attribute "pattern" "[0-9]*"
                            , attribute "autocomplete" "one-time-code"
                            , attribute "maxlength" "6"
                            , placeholder f.placeholder
                            , value f.value
                            , onInput (f.onChange >> AccountsPanel.ContactAuthMsg >> toMsg)
                            , disabled config.disabled
                            ]
                    )
            )
        , case ContactAuth.expiryNote config.now config.challenge of
            Just note ->
                p [ class "contact-auth-hint" ] [ text note ]

            Nothing ->
                text ""
        , button
            [ type_ "button"
            , class "contact-code-resend"
            , disabled (config.disabled || secondsLeft > 0)
            , onClick (toMsg config.resendMsg)
            ]
            [ text
                (if secondsLeft > 0 then
                    "Resend code in " ++ ContactAuth.formatCountdown secondsLeft

                 else
                    "Resend code"
                )
            ]
        ]


{-| The create-account step's optional phone/email (each only when the server verifies it at
sign-up) and the consent checkbox the backend requires before it may message them. `hint` is
`ContactAuth.createFormProblem`'s current complaint, shown muted under the fields.
-}
createContactFields :
    (AccountsPanel.Msg -> msg)
    ->
        { phoneEnabled : Bool
        , emailEnabled : Bool
        , state : ContactAuth.State
        , passwordEmpty : Bool
        , problem : Maybe String
        , disabled : Bool
        , submitMsg : AccountsPanel.Msg
        }
    -> Html msg
createContactFields toMsg config =
    let
        state : ContactAuth.State
        state =
            config.state

        anyTyped : Bool
        anyTyped =
            (config.phoneEnabled && String.trim state.createPhone /= "")
                || (config.emailEnabled && String.trim state.createEmail /= "")

        contactMsg : ContactAuth.Msg -> msg
        contactMsg =
            AccountsPanel.ContactAuthMsg >> toMsg
    in
    div [ class "create-contact-fields" ]
        [ if config.phoneEnabled then
            field toMsg
                config.submitMsg
                [ id "account-form-create-phone"
                , type_ "tel"
                , name "tel"
                , attribute "inputmode" "tel"
                , attribute "autocomplete" "tel"
                , placeholder "Phone number (optional)"
                , value state.createPhone
                , onInput (ContactAuth.CreatePhoneChanged >> contactMsg)
                , disabled config.disabled
                ]

          else
            text ""
        , if config.emailEnabled then
            field toMsg
                config.submitMsg
                [ id "account-form-create-email"
                , type_ "email"
                , name "email"
                , attribute "inputmode" "email"
                , attribute "autocomplete" "email"
                , placeholder "Email address (optional)"
                , value state.createEmail
                , onInput (ContactAuth.CreateEmailChanged >> contactMsg)
                , disabled config.disabled
                ]

          else
            text ""
        , if anyTyped then
            label [ class "create-contact-consent" ]
                [ input
                    [ type_ "checkbox"
                    , checked state.createConsent
                    , disabled config.disabled
                    , onClick (contactMsg (ContactAuth.CreateConsentToggled (not state.createConsent)))
                    ]
                    []
                , text (" " ++ consentText (config.phoneEnabled && String.trim state.createPhone /= "") (config.emailEnabled && String.trim state.createEmail /= ""))
                ]

          else
            text ""
        , case ( anyTyped, config.problem ) of
            ( True, Just problem ) ->
                p [ class "contact-auth-hint" ] [ text problem ]

            ( True, Nothing ) ->
                if config.passwordEmpty then
                    p [ class "contact-auth-hint" ] [ text "No password? You'll sign in with a code sent to you." ]

                else
                    text ""

            _ ->
                p [ class "contact-auth-hint" ]
                    [ text
                        (if config.phoneEnabled then
                            "Optional: add a phone number (with country code, like +19195551234) or email to verify your account and sign in with a code."

                         else
                            "Optional: add an email to verify your account and sign in with a code."
                        )
                    ]
        ]


{-| The consent checkbox's label, naming whichever of a text/email the user actually typed.
-}
consentText : Bool -> Bool -> String
consentText phoneTyped emailTyped =
    -- What's recorded is a general consent to be contacted at that phone/email (the same one the
    -- profile's checkbox edits), and it covers the sign-in codes sent later too -- say so.
    case ( phoneTyped, emailTyped ) of
        ( True, True ) ->
            "I agree to receive verification and sign-in codes by text message and email. " ++ smsRatesNote

        ( True, False ) ->
            "I agree to receive verification and sign-in codes by text message. " ++ smsRatesNote

        _ ->
            "I agree to receive verification and sign-in codes by email."
