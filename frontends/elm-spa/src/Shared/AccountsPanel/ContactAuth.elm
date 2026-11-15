module Shared.AccountsPanel.ContactAuth exposing
    ( Challenge
    , LoginMethod(..)
    , Msg(..)
    , State
    , challengeFromProto
    , codeIsComplete
    , createCodesComplete
    , createEmailEnabled
    , createFormProblem
    , createPhoneEnabled
    , createWantsEmailCode
    , createWantsPhoneCode
    , emailLooksValid
    , emailValue
    , expiryNote
    , formatCountdown
    , friendlyMessage
    , initial
    , loginContactInvalid
    , loginMethodLabel
    , loginMethods
    , methodAvailable
    , normalizePhone
    , phoneLooksValid
    , resendSecondsLeft
    , sanitizeCode
    , sentToLabel
    , update
    )

{-| Everything pure about the SMS/email halves of the Accounts Panel's login and create-account
forms (`Shared.AccountsPanel`, `UI.elm`'s `rellmAddAccountServerForm`, `ContactAuthView`): which
methods a server offers (from its `ServerConfiguration`), the form's own field state, the
two-phase "we sent a code" challenge and its resend countdown, validation, and the friendly
wording for the backend's error strings. No `Cmd`s and no `Grpc` here -- `AccountsPanel` sends the
requests -- so all of it is unit-tested in `tests/ContactAuthTests.elm`.

Both flows are two-phase (see `protos/authentication.proto`'s `LoginRequest`/`CreateAccountRequest`):
the first request, sent without a code, makes the server text/email one and answers with a
`RefreshTokenResponse` carrying only a `VerificationChallenge`; the same request is then repeated
with the code(s) filled in.

-}

import Proto.Rellm exposing (ServerConfiguration, VerificationChallenge)
import Proto.Rellm.AuthenticationFeature exposing (AuthenticationFeature(..))
import Proto.Rellm.ContactProtocol exposing (ContactProtocol(..))
import Shared.Conversions as Conversions
import Time



-- METHODS


{-| How the user signs in. `PasswordMethod` is the classic username + password form.
-}
type LoginMethod
    = PasswordMethod
    | SmsMethod
    | EmailMethod


loginMethodLabel : LoginMethod -> String
loginMethodLabel method =
    case method of
        PasswordMethod ->
            "Password"

        SmsMethod ->
            "Text message"

        EmailMethod ->
            "Email"


{-| Whether `config` offers SMS login: the feature is listed *and* the server can actually send
`tel:` messages (`supported_contact_protocols`) -- an admin can list the feature before wiring up a
provider.
-}
smsLoginEnabled : ServerConfiguration -> Bool
smsLoginEnabled config =
    List.member LOGINWITHSMS config.authenticationFeatures
        && List.member CONTACTPROTOCOLTEL config.supportedContactProtocols


emailLoginEnabled : ServerConfiguration -> Bool
emailLoginEnabled config =
    List.member LOGINWITHEMAIL config.authenticationFeatures
        && List.member CONTACTPROTOCOLMAILTO config.supportedContactProtocols


{-| Whether `CreateAccountRequest.phone` must be verified on `config` (see its doc) -- which is also
what makes the create-account form offer a phone field at all: without it the server would just
save the number unverified, as it always has.
-}
createPhoneEnabled : ServerConfiguration -> Bool
createPhoneEnabled config =
    List.member CREATEACCOUNTWITHSMS config.authenticationFeatures
        && List.member CONTACTPROTOCOLTEL config.supportedContactProtocols


createEmailEnabled : ServerConfiguration -> Bool
createEmailEnabled config =
    List.member CREATEACCOUNTWITHEMAIL config.authenticationFeatures
        && List.member CONTACTPROTOCOLMAILTO config.supportedContactProtocols


{-| The login methods `config` offers, in display order. Password login is always offered (the
proto treats `LOGIN_WITH_PASSWORD` as implied for now), so a server with no SMS/email features
yields just `[ PasswordMethod ]` -- and the chooser is only shown when there's something to choose
between.
-}
loginMethods : ServerConfiguration -> List LoginMethod
loginMethods config =
    List.concat
        [ [ PasswordMethod ]
        , if smsLoginEnabled config then
            [ SmsMethod ]

          else
            []
        , if emailLoginEnabled config then
            [ EmailMethod ]

          else
            []
        ]


methodAvailable : ServerConfiguration -> LoginMethod -> Bool
methodAvailable config method =
    List.member method (loginMethods config)



-- STATE


{-| A pending verification: a code's been sent and the client should prompt for it.
-}
type alias Challenge =
    { sentTo : List String
    , expiresAt : Maybe Time.Posix
    , resendAvailableAt : Maybe Time.Posix
    }


challengeFromProto : VerificationChallenge -> Challenge
challengeFromProto challenge =
    { sentTo = challenge.sentTo
    , expiresAt = Maybe.map Conversions.timestampToPosix challenge.expiresAt
    , resendAvailableAt = Maybe.map Conversions.timestampToPosix challenge.resendAvailableAt
    }


{-| The form's SMS/email state, beyond the username/password `AccountForm` already holds. The
login fields (`method`, `contact`, `code`, `loginChallenge`) and the create-account ones
(`create*`) are independent: you can't be in both flows at once, but keeping them apart means
backing out of one never clobbers the other.
-}
type alias State =
    { method : LoginMethod

    -- The phone number or email typed for an SMS/email login, per `method`.
    , contact : String
    , code : String
    , loginChallenge : Maybe Challenge

    -- Create account: optional contact methods to verify (only offered when the server enables
    -- `CREATE_ACCOUNT_WITH_SMS`/`_EMAIL`), the consent the backend requires before it may message
    -- them, and the codes for the second phase.
    , createPhone : String
    , createEmail : String
    , createConsent : Bool
    , createPhoneCode : String
    , createEmailCode : String
    , createChallenge : Maybe Challenge

    -- The last clock tick, for the countdowns. `Nothing` until the first one.
    , now : Maybe Time.Posix
    }


initial : State
initial =
    { method = PasswordMethod
    , contact = ""
    , code = ""
    , loginChallenge = Nothing
    , createPhone = ""
    , createEmail = ""
    , createConsent = False
    , createPhoneCode = ""
    , createEmailCode = ""
    , createChallenge = Nothing
    , now = Nothing
    }


{-| Field-level messages. The ones that send a request (`SendLoginCodeClicked`, ...) live on
`AccountsPanel.Msg`.
-}
type Msg
    = MethodSelected LoginMethod
    | ContactChanged String
    | CodeChanged String
    | CreatePhoneChanged String
    | CreateEmailChanged String
    | CreateConsentToggled Bool
    | CreatePhoneCodeChanged String
    | CreateEmailCodeChanged String
    | Tick Time.Posix
    | LoginChallengeDismissed
    | CreateChallengeDismissed


update : Msg -> State -> State
update msg state =
    case msg of
        MethodSelected method ->
            -- Each method has its own kind of contact value, so a half-typed one never carries over.
            if method == state.method then
                state

            else
                { state | method = method, contact = "", code = "", loginChallenge = Nothing }

        ContactChanged contact ->
            { state | contact = contact }

        CodeChanged code ->
            { state | code = sanitizeCode code }

        CreatePhoneChanged phone ->
            { state | createPhone = phone }

        CreateEmailChanged email ->
            { state | createEmail = email }

        CreateConsentToggled consent ->
            { state | createConsent = consent }

        CreatePhoneCodeChanged code ->
            { state | createPhoneCode = sanitizeCode code }

        CreateEmailCodeChanged code ->
            { state | createEmailCode = sanitizeCode code }

        Tick now ->
            { state | now = Just now }

        LoginChallengeDismissed ->
            { state | code = "", loginChallenge = Nothing }

        CreateChallengeDismissed ->
            { state | createPhoneCode = "", createEmailCode = "", createChallenge = Nothing }



-- VALIDATION


{-| Codes are 6 digits; keep only digits (pasting "123 456" works) and cap the length.
-}
sanitizeCode : String -> String
sanitizeCode raw =
    raw
        |> String.filter Char.isDigit
        |> String.left 6


codeIsComplete : String -> Bool
codeIsComplete code =
    String.length code == 6 && String.all Char.isDigit code


{-| The phone number as the API wants it: E.164, i.e. a `+`, then digits only. Spaces, dashes,
dots and parentheses (and a leading `tel:`) are dropped.
-}
normalizePhone : String -> String
normalizePhone raw =
    let
        trimmed : String
        trimmed =
            String.trim raw

        withoutScheme : String
        withoutScheme =
            if String.startsWith "tel:" (String.toLower trimmed) then
                String.dropLeft 4 trimmed

            else
                trimmed
    in
    String.filter (\c -> not (List.member c [ ' ', '-', '.', '(', ')', '\u{00A0}' ])) withoutScheme


{-| E.164: `+`, then 8 to 15 digits, not starting with 0.
-}
phoneLooksValid : String -> Bool
phoneLooksValid raw =
    case String.uncons (normalizePhone raw) of
        Just ( '+', digits ) ->
            String.length digits
                >= 8
                && String.length digits
                <= 15
                && String.all Char.isDigit digits
                && not (String.startsWith "0" digits)

        _ ->
            False


emailValue : String -> String
emailValue raw =
    let
        trimmed : String
        trimmed =
            String.trim raw
    in
    if String.startsWith "mailto:" (String.toLower trimmed) then
        String.dropLeft 7 trimmed

    else
        trimmed


{-| Deliberately loose (the server is the judge): one `@`, something on each side, a dot in the
domain, no spaces.
-}
emailLooksValid : String -> Bool
emailLooksValid raw =
    case String.split "@" (emailValue raw) of
        [ local, domain ] ->
            not (String.isEmpty local)
                && String.contains "." domain
                && not (String.startsWith "." domain)
                && not (String.endsWith "." domain)
                && not (String.contains " " (emailValue raw))

        _ ->
            False


{-| Whether the login form's phone/email field (per `state.method`) can't be submitted yet.
-}
loginContactInvalid : State -> Bool
loginContactInvalid state =
    case state.method of
        SmsMethod ->
            not (phoneLooksValid state.contact)

        EmailMethod ->
            not (emailLooksValid state.contact)

        PasswordMethod ->
            True


{-| Why the create-account form can't be submitted yet (`Nothing` when it can), given the password
typed and which contact methods the server verifies. Password rules are the long-standing ones
(8+ characters) -- except that with a phone/email given, it may be left empty entirely for a
passwordless account. A contact method may only be messaged with consent, and a malformed one is
caught here rather than by a round trip.

Only the *first* problem is returned; the form shows it as a hint, and keeps its submit button
disabled -- same "disable rather than error" convention as the Password step's own length check.

-}
createFormProblem : { phoneEnabled : Bool, emailEnabled : Bool } -> String -> State -> Maybe String
createFormProblem { phoneEnabled, emailEnabled } password state =
    if password /= "" && String.length password < 8 then
        Just "Passwords must be at least 8 characters."

    else if password == "" && typedContact phoneEnabled state.createPhone == "" && typedContact emailEnabled state.createEmail == "" then
        Just
            (if phoneEnabled || emailEnabled then
                "Enter a password, or a phone number or email to sign in with a code."

             else
                "Enter a password."
            )

    else if typedContact phoneEnabled state.createPhone /= "" && not (phoneLooksValid state.createPhone) then
        Just "Phone numbers need a country code, like +19195551234."

    else if typedContact emailEnabled state.createEmail /= "" && not (emailLooksValid state.createEmail) then
        Just "That email address doesn't look right."

    else if (typedContact phoneEnabled state.createPhone /= "" || typedContact emailEnabled state.createEmail /= "") && not state.createConsent then
        Just "Check the box to receive a verification code."

    else
        Nothing


{-| What was typed into a sign-up contact field, or "" when the server doesn't offer that field.
-}
typedContact : Bool -> String -> String
typedContact enabled raw =
    if enabled then
        String.trim raw

    else
        ""


{-| Whether the second phase of create-account has every code it needs: one per contact method the
server said it messaged (`VerificationChallenge.sent_to`).
-}
createCodesComplete : Challenge -> State -> Bool
createCodesComplete challenge state =
    (not (createWantsPhoneCode challenge) || codeIsComplete state.createPhoneCode)
        && (not (createWantsEmailCode challenge) || codeIsComplete state.createEmailCode)
        && (createWantsPhoneCode challenge || createWantsEmailCode challenge)


createWantsPhoneCode : Challenge -> Bool
createWantsPhoneCode challenge =
    List.any (String.startsWith "tel:") challenge.sentTo


createWantsEmailCode : Challenge -> Bool
createWantsEmailCode challenge =
    List.any (String.startsWith "mailto:") challenge.sentTo



-- COUNTDOWNS


{-| "We sent a code to ..." -- the `tel:`/`mailto:` values, scheme dropped.
-}
sentToLabel : List String -> String
sentToLabel sentTo =
    sentTo
        |> List.map
            (\value ->
                if String.startsWith "tel:" value then
                    String.dropLeft 4 value

                else if String.startsWith "mailto:" value then
                    String.dropLeft 7 value

                else
                    value
            )
        |> String.join " and "


{-| Whole seconds as `m:ss` (`0:05`, `9:41`, `12:00`). Negative counts as zero.
-}
formatCountdown : Int -> String
formatCountdown totalSeconds =
    let
        seconds : Int
        seconds =
            max 0 totalSeconds

        secondsPart : Int
        secondsPart =
            modBy 60 seconds
    in
    String.fromInt (seconds // 60)
        ++ ":"
        ++ (if secondsPart < 10 then
                "0"

            else
                ""
           )
        ++ String.fromInt secondsPart


{-| Whole seconds (rounded up) until a new code may be requested. `0` once it may -- and before the
first clock tick, or when the server didn't say, since there's nothing to count down to.
-}
resendSecondsLeft : Maybe Time.Posix -> Challenge -> Int
resendSecondsLeft now challenge =
    case ( now, challenge.resendAvailableAt ) of
        ( Just nowPosix, Just availableAt ) ->
            max 0 (ceiling (toFloat (Time.posixToMillis availableAt - Time.posixToMillis nowPosix) / 1000))

        _ ->
            0


{-| The "Code expires in 9:41" note under the code field, or a prompt to ask for a new one once it
has. `Nothing` when there's nothing to say (no expiry given, or no clock tick yet).
-}
expiryNote : Maybe Time.Posix -> Challenge -> Maybe String
expiryNote now challenge =
    case ( now, challenge.expiresAt ) of
        ( Just nowPosix, Just expiresAt ) ->
            let
                secondsLeft : Int
                secondsLeft =
                    ceiling (toFloat (Time.posixToMillis expiresAt - Time.posixToMillis nowPosix) / 1000)
            in
            if secondsLeft <= 0 then
                Just "This code has expired. Send a new one."

            else
                Just ("Code expires in " ++ formatCountdown secondsLeft ++ ".")

        _ ->
            Nothing



-- ERRORS


{-| Friendly wording for the backend's SMS/email error strings (`Grpc.BadStatus`'s `errMessage`).
`Nothing` for anything else, so callers fall back to their usual formatting -- password login's
own messages are untouched.
-}
friendlyMessage : String -> Maybe String
friendlyMessage errMessage =
    case errMessage of
        "incorrect_code" ->
            Just "That code isn't right. Check it and try again."

        "verification_expired" ->
            Just "That code has expired. Send a new one."

        "too_many_attempts" ->
            Just "Too many wrong codes. Send a new code and try again."

        "verification_recently_sent" ->
            Just "A code was just sent. Wait a minute before asking for another."

        "no_verification_in_progress" ->
            Just "No code is waiting for that. Send a new one."

        "login_with_sms_not_enabled" ->
            Just "This server doesn't allow signing in by text message."

        "login_with_email_not_enabled" ->
            Just "This server doesn't allow signing in by email."

        "create_account_with_sms_not_enabled" ->
            Just "This server doesn't allow creating an account with a phone number."

        "create_account_with_email_not_enabled" ->
            Just "This server doesn't allow creating an account with an email address."

        "contact_already_verified" ->
            Just "That phone number or email already belongs to another account. Try signing in instead."

        "contact_consent_not_granted" ->
            Just "Check the box to agree to receive a verification code."

        "email_must_be_a_valid_address" ->
            Just "That email address doesn't look right."

        "invalid_email_address" ->
            Just "That email address doesn't look right."

        "too_many_verification_requests" ->
            Just "Too many codes requested. Wait a while and try again."

        "multiple_accounts_for_contact" ->
            Just "More than one account uses that phone number or email. Sign in with your username and password instead."

        "phone_verification_code_required" ->
            Just "Enter the code sent to your phone."

        "email_verification_code_required" ->
            Just "Enter the code sent to your email."

        "value_must_be_a_tel_or_mailto_url" ->
            Just "That phone number or email address doesn't look right."

        "verification_not_configured" ->
            Just "This server can't send text messages right now."

        "email_verification_not_configured" ->
            Just "This server can't send email right now."

        "sms_email_login_not_implemented_yet" ->
            Just "This server doesn't support signing in this way yet."

        "login_request_required" ->
            Just "Something went wrong with that request. Please try again."

        _ ->
            Nothing
