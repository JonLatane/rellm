module ContactAuthTests exposing (suite)

{-| Tests for `Shared.AccountsPanel.ContactAuth`'s pure logic: which login/sign-up methods a
server's `ServerConfiguration` offers, the phone/email validation, the create-account form's
rules, the resend/expiry countdowns, and the friendly backend error wording.
-}

import Expect
import Proto.Rellm exposing (ServerConfiguration, defaultServerConfiguration)
import Proto.Rellm.AuthenticationFeature exposing (AuthenticationFeature(..))
import Proto.Rellm.ContactProtocol exposing (ContactProtocol(..))
import Shared.AccountsPanel.ContactAuth as ContactAuth exposing (LoginMethod(..))
import Test exposing (Test, describe, test)
import Time


config : List AuthenticationFeature -> List ContactProtocol -> ServerConfiguration
config features protocols =
    { defaultServerConfiguration | authenticationFeatures = features, supportedContactProtocols = protocols }


challenge : { sentTo : List String, expiresAt : Maybe Int, resendAvailableAt : Maybe Int } -> ContactAuth.Challenge
challenge c =
    { sentTo = c.sentTo
    , expiresAt = Maybe.map Time.millisToPosix c.expiresAt
    , resendAvailableAt = Maybe.map Time.millisToPosix c.resendAvailableAt
    }


suite : Test
suite =
    describe "Shared.AccountsPanel.ContactAuth"
        [ methodTests
        , validationTests
        , createFormTests
        , countdownTests
        , errorTests
        , stateTests
        , staleReplyTests
        ]


methodTests : Test
methodTests =
    describe "method availability"
        [ test "a server with no auth features offers only password" <|
            \_ ->
                ContactAuth.loginMethods defaultServerConfiguration
                    |> Expect.equal [ PasswordMethod ]
        , test "SMS login needs the feature and the tel: protocol" <|
            \_ ->
                Expect.equal
                    [ [ PasswordMethod, SmsMethod ]
                    , [ PasswordMethod ]
                    , [ PasswordMethod ]
                    ]
                    [ ContactAuth.loginMethods (config [ LOGINWITHSMS ] [ CONTACTPROTOCOLTEL ])
                    , ContactAuth.loginMethods (config [ LOGINWITHSMS ] [])
                    , ContactAuth.loginMethods (config [] [ CONTACTPROTOCOLTEL ])
                    ]
        , test "email login needs the feature and the mailto: protocol, and a tel: protocol doesn't count" <|
            \_ ->
                Expect.equal
                    [ [ PasswordMethod, EmailMethod ]
                    , [ PasswordMethod ]
                    ]
                    [ ContactAuth.loginMethods (config [ LOGINWITHEMAIL ] [ CONTACTPROTOCOLMAILTO ])
                    , ContactAuth.loginMethods (config [ LOGINWITHEMAIL ] [ CONTACTPROTOCOLTEL ])
                    ]
        , test "all methods, in display order" <|
            \_ ->
                ContactAuth.loginMethods
                    (config [ LOGINWITHEMAIL, LOGINWITHSMS, LOGINWITHPASSWORD ] [ CONTACTPROTOCOLMAILTO, CONTACTPROTOCOLTEL ])
                    |> Expect.equal [ PasswordMethod, SmsMethod, EmailMethod ]
        , test "sign-up options follow the CREATE_ACCOUNT_* features, independent of login" <|
            \_ ->
                let
                    c : ServerConfiguration
                    c =
                        config [ CREATEACCOUNTWITHSMS, LOGINWITHEMAIL ] [ CONTACTPROTOCOLTEL, CONTACTPROTOCOLMAILTO ]
                in
                Expect.equal ( True, False )
                    ( ContactAuth.createPhoneEnabled c, ContactAuth.createEmailEnabled c )
        , test "methodAvailable" <|
            \_ ->
                Expect.equal ( True, False )
                    ( ContactAuth.methodAvailable (config [ LOGINWITHSMS ] [ CONTACTPROTOCOLTEL ]) SmsMethod
                    , ContactAuth.methodAvailable (config [ LOGINWITHSMS ] [ CONTACTPROTOCOLTEL ]) EmailMethod
                    )
        ]


validationTests : Test
validationTests =
    describe "validation"
        [ test "normalizePhone drops punctuation and a tel: scheme" <|
            \_ ->
                Expect.equal [ "+19195551234", "+19195551234", "+442071838750" ]
                    [ ContactAuth.normalizePhone "+1 (919) 555-1234"
                    , ContactAuth.normalizePhone "tel:+19195551234"
                    , ContactAuth.normalizePhone " +44 20.7183.8750 "
                    ]
        , test "phones need + and 8-15 digits" <|
            \_ ->
                Expect.equal [ True, True, False, False, False, False, False ]
                    [ ContactAuth.phoneLooksValid "+19195551234"
                    , ContactAuth.phoneLooksValid "+1 919 555 1234"
                    , ContactAuth.phoneLooksValid "9195551234"
                    , ContactAuth.phoneLooksValid "+1234"
                    , ContactAuth.phoneLooksValid "+1234567890123456"
                    , ContactAuth.phoneLooksValid "+0195551234"
                    , ContactAuth.phoneLooksValid "+1919555abcd"
                    ]
        , test "emails are checked loosely" <|
            \_ ->
                Expect.equal [ True, True, False, False, False, False ]
                    [ ContactAuth.emailLooksValid "jon@example.com"
                    , ContactAuth.emailLooksValid "mailto:jon@example.com"
                    , ContactAuth.emailLooksValid "jon@example"
                    , ContactAuth.emailLooksValid "@example.com"
                    , ContactAuth.emailLooksValid "jon example@x.com"
                    , ContactAuth.emailLooksValid ""
                    ]
        , test "emailValue drops mailto: and whitespace" <|
            \_ ->
                Expect.equal "jon@example.com" (ContactAuth.emailValue "  mailto:jon@example.com ")
        , test "codes keep digits only, capped at 6" <|
            \_ ->
                Expect.equal [ "123456", "123", "" ]
                    [ ContactAuth.sanitizeCode "123 456 789"
                    , ContactAuth.sanitizeCode "1a2b3"
                    , ContactAuth.sanitizeCode "abc"
                    ]
        , test "codeIsComplete wants exactly 6 digits" <|
            \_ ->
                Expect.equal [ True, False, False ]
                    [ ContactAuth.codeIsComplete "123456"
                    , ContactAuth.codeIsComplete "12345"
                    , ContactAuth.codeIsComplete "12345a"
                    ]
        , test "loginContactInvalid follows the picked method" <|
            \_ ->
                Expect.equal [ False, True, False, True ]
                    [ ContactAuth.loginContactInvalid { initial | method = SmsMethod, contact = "+19195551234", loginConsent = True }
                    , ContactAuth.loginContactInvalid { initial | method = SmsMethod, contact = "jon@example.com", loginConsent = True }
                    , ContactAuth.loginContactInvalid { initial | method = EmailMethod, contact = "jon@example.com", loginConsent = True }
                    , ContactAuth.loginContactInvalid { initial | method = EmailMethod, contact = "+19195551234", loginConsent = True }
                    ]
        , test "a valid phone/email still can't be submitted until the sign-in consent box is checked" <|
            \_ ->
                Expect.equal [ True, True, False ]
                    [ ContactAuth.loginContactInvalid { initial | method = SmsMethod, contact = "+19195551234" }
                    , ContactAuth.loginContactInvalid { initial | method = EmailMethod, contact = "jon@example.com", loginConsent = False }
                    , ContactAuth.loginContactInvalid
                        (ContactAuth.update (ContactAuth.LoginConsentToggled True) { initial | method = EmailMethod, contact = "jon@example.com" })
                    ]
        , test "picking another method forgets the sign-in consent" <|
            \_ ->
                ContactAuth.update (ContactAuth.MethodSelected EmailMethod) { initial | method = SmsMethod, loginConsent = True }
                    |> .loginConsent
                    |> Expect.equal False
        , test "keeping the same method keeps the sign-in consent" <|
            \_ ->
                ContactAuth.update (ContactAuth.MethodSelected SmsMethod) { initial | method = SmsMethod, loginConsent = True }
                    |> .loginConsent
                    |> Expect.equal True
        ]


initial : ContactAuth.State
initial =
    ContactAuth.initial


createFormTests : Test
createFormTests =
    let
        both : { phoneEnabled : Bool, emailEnabled : Bool }
        both =
            { phoneEnabled = True, emailEnabled = True }
    in
    describe "createFormProblem"
        [ test "a long enough password alone is fine" <|
            \_ ->
                ContactAuth.createFormProblem both "hunter2hunter2" initial
                    |> Expect.equal Nothing
        , test "a short password is rejected" <|
            \_ ->
                ContactAuth.createFormProblem both "short" initial
                    |> Expect.notEqual Nothing
        , test "no password and no contact is rejected" <|
            \_ ->
                ContactAuth.createFormProblem both "" initial
                    |> Expect.notEqual Nothing
        , test "no password with a verified-contact option needs consent" <|
            \_ ->
                Expect.equal [ True, False ]
                    [ ContactAuth.createFormProblem both "" { initial | createPhone = "+19195551234" } /= Nothing
                    , ContactAuth.createFormProblem both "" { initial | createPhone = "+19195551234", createConsent = True } /= Nothing
                    ]
        , test "a malformed phone or email is rejected" <|
            \_ ->
                Expect.equal [ True, True ]
                    [ ContactAuth.createFormProblem both "" { initial | createPhone = "555-1234", createConsent = True } /= Nothing
                    , ContactAuth.createFormProblem both "" { initial | createEmail = "nope", createConsent = True } /= Nothing
                    ]
        , test "a contact method on a server that doesn't verify it is ignored" <|
            \_ ->
                ContactAuth.createFormProblem { phoneEnabled = False, emailEnabled = False } "hunter2hunter2" { initial | createPhone = "garbage" }
                    |> Expect.equal Nothing
        , test "without SMS/email sign-up an empty password is just 'enter a password'" <|
            \_ ->
                ContactAuth.createFormProblem { phoneEnabled = False, emailEnabled = False } "" initial
                    |> Expect.equal (Just "Enter a password.")
        , test "createCodesComplete wants a code per contact method that was messaged" <|
            \_ ->
                let
                    c : ContactAuth.Challenge
                    c =
                        challenge { sentTo = [ "tel:+19195551234", "mailto:jon@example.com" ], expiresAt = Nothing, resendAvailableAt = Nothing }
                in
                Expect.equal [ False, False, True ]
                    [ ContactAuth.createCodesComplete c initial
                    , ContactAuth.createCodesComplete c { initial | createPhoneCode = "123456" }
                    , ContactAuth.createCodesComplete c { initial | createPhoneCode = "123456", createEmailCode = "654321" }
                    ]
        , test "createCodesComplete ignores the contact method nothing was sent to" <|
            \_ ->
                let
                    c : ContactAuth.Challenge
                    c =
                        challenge { sentTo = [ "mailto:jon@example.com" ], expiresAt = Nothing, resendAvailableAt = Nothing }
                in
                ContactAuth.createCodesComplete c { initial | createEmailCode = "654321" }
                    |> Expect.equal True
        ]


countdownTests : Test
countdownTests =
    describe "countdowns"
        [ test "formatCountdown" <|
            \_ ->
                Expect.equal [ "0:00", "0:05", "0:59", "1:00", "9:41", "10:00", "0:00" ]
                    (List.map ContactAuth.formatCountdown [ 0, 5, 59, 60, 581, 600, -3 ])
        , test "resendSecondsLeft rounds up and bottoms out at 0" <|
            \_ ->
                let
                    c : ContactAuth.Challenge
                    c =
                        challenge { sentTo = [], expiresAt = Nothing, resendAvailableAt = Just 60000 }
                in
                Expect.equal [ 60, 1, 1, 0, 0 ]
                    [ ContactAuth.resendSecondsLeft (Just (Time.millisToPosix 0)) c
                    , ContactAuth.resendSecondsLeft (Just (Time.millisToPosix 59999)) c
                    , ContactAuth.resendSecondsLeft (Just (Time.millisToPosix 59000)) c
                    , ContactAuth.resendSecondsLeft (Just (Time.millisToPosix 60000)) c
                    , ContactAuth.resendSecondsLeft (Just (Time.millisToPosix 90000)) c
                    ]
        , test "resendSecondsLeft is 0 before the first tick or without a resend time" <|
            \_ ->
                Expect.equal [ 0, 0 ]
                    [ ContactAuth.resendSecondsLeft Nothing (challenge { sentTo = [], expiresAt = Nothing, resendAvailableAt = Just 60000 })
                    , ContactAuth.resendSecondsLeft (Just (Time.millisToPosix 0)) (challenge { sentTo = [], expiresAt = Nothing, resendAvailableAt = Nothing })
                    ]
        , test "expiryNote counts down, then asks for a new code" <|
            \_ ->
                let
                    c : ContactAuth.Challenge
                    c =
                        challenge { sentTo = [], expiresAt = Just 600000, resendAvailableAt = Nothing }
                in
                Expect.equal
                    [ Just "Code expires in 10:00."
                    , Just "Code expires in 0:01."
                    , Just "This code has expired. Send a new one."
                    , Nothing
                    ]
                    [ ContactAuth.expiryNote (Just (Time.millisToPosix 0)) c
                    , ContactAuth.expiryNote (Just (Time.millisToPosix 599500)) c
                    , ContactAuth.expiryNote (Just (Time.millisToPosix 600000)) c
                    , ContactAuth.expiryNote Nothing c
                    ]
        , test "sentToLabel drops the scheme" <|
            \_ ->
                Expect.equal [ "+19195551234", "jon@example.com", "+19195551234 and jon@example.com" ]
                    [ ContactAuth.sentToLabel [ "tel:+19195551234" ]
                    , ContactAuth.sentToLabel [ "mailto:jon@example.com" ]
                    , ContactAuth.sentToLabel [ "tel:+19195551234", "mailto:jon@example.com" ]
                    ]
        ]


errorTests : Test
errorTests =
    describe "friendlyMessage"
        [ test "maps the verification errors" <|
            \_ ->
                [ "incorrect_code", "verification_expired", "too_many_attempts", "verification_recently_sent", "login_with_sms_not_enabled", "contact_already_verified" ]
                    |> List.map ContactAuth.friendlyMessage
                    |> List.all (\m -> m /= Nothing)
                    |> Expect.equal True
        , test "leaves other errors (password login's included) alone" <|
            \_ ->
                Expect.equal [ Nothing, Nothing, Nothing ]
                    [ ContactAuth.friendlyMessage "invalid_username_or_password"
                    , ContactAuth.friendlyMessage "username_already_exists"
                    , ContactAuth.friendlyMessage ""
                    ]
        ]


stateTests : Test
stateTests =
    describe "update"
        [ test "picking a different method clears the typed contact and code" <|
            \_ ->
                { initial | method = SmsMethod, contact = "+1919", code = "12" }
                    |> ContactAuth.update (ContactAuth.MethodSelected EmailMethod)
                    |> Expect.equal { initial | method = EmailMethod }
        , test "picking the same method keeps what was typed" <|
            \_ ->
                { initial | method = SmsMethod, contact = "+1919" }
                    |> ContactAuth.update (ContactAuth.MethodSelected SmsMethod)
                    |> Expect.equal { initial | method = SmsMethod, contact = "+1919" }
        , test "typing a code sanitizes it" <|
            \_ ->
                initial
                    |> ContactAuth.update (ContactAuth.CodeChanged "12 34 56 78")
                    |> .code
                    |> Expect.equal "123456"
        , test "dismissing the login challenge keeps the contact but drops the code" <|
            \_ ->
                { initial
                    | method = SmsMethod
                    , contact = "+19195551234"
                    , code = "123"
                    , loginChallenge = Just (challenge { sentTo = [ "tel:+19195551234" ], expiresAt = Nothing, resendAvailableAt = Nothing })
                }
                    |> ContactAuth.update ContactAuth.LoginChallengeDismissed
                    |> Expect.equal { initial | method = SmsMethod, contact = "+19195551234" }
        ]


staleReplyTests : Test
staleReplyTests =
    describe "stale auth replies"
        [ test "the reply to the latest request, while waiting, is applied" <|
            \_ ->
                ContactAuth.replyIsCurrent { currentId = 3, replyId = 3, submitting = True }
                    |> Expect.equal True
        , test "a reply to an earlier request is ignored" <|
            \_ ->
                ContactAuth.replyIsCurrent { currentId = 4, replyId = 3, submitting = True }
                    |> Expect.equal False
        , test "a reply is ignored once the form is no longer submitting, even with a matching id" <|
            \_ ->
                ContactAuth.replyIsCurrent { currentId = 3, replyId = 3, submitting = False }
                    |> Expect.equal False
        , test "picking a method or leaving a code step resets the form; typing doesn't" <|
            \_ ->
                Expect.equal [ True, True, True, False, False ]
                    [ ContactAuth.resetsForm (ContactAuth.MethodSelected SmsMethod)
                    , ContactAuth.resetsForm ContactAuth.LoginChallengeDismissed
                    , ContactAuth.resetsForm ContactAuth.CreateChallengeDismissed
                    , ContactAuth.resetsForm (ContactAuth.ContactChanged "+1")
                    , ContactAuth.resetsForm (ContactAuth.CodeChanged "123")
                    ]
        ]
