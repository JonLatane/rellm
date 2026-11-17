module SignInAndContactEmailEditsTests exposing (suite)

import Components.Pages.ServerInformationPage.SignInAndContact.EmailEdits as EmailEdits exposing (StalwartField(..))
import Expect
import Proto.Rellm exposing (defaultServerConfiguration, defaultStalwartConfig)
import Test exposing (Test, describe, test)


configWithStalwart : Bool -> Bool -> Proto.Rellm.ServerConfiguration
configWithStalwart receiving sending =
    { defaultServerConfiguration
        | stalwartConfig =
            Just
                { defaultStalwartConfig
                    | stalwartReceivingEnabled = receiving
                    , stalwartSendingEnabled = sending
                    , stalwartSmtpHost = "stalwart.email.svc"
                    , stalwartSmtpPort = 587
                    , stalwartFromAddress = "login@example.com"
                    , stalwartSmtpUsername = "rellm"
                }
    }


suite : Test
suite =
    describe "Sign In & Contact email-provider edits"
        [ describe "Stalwart receiving toggle"
            [ test "turning receiving off keeps the sending settings" <|
                \_ ->
                    configWithStalwart True True
                        |> EmailEdits.toggleStalwartReceiving
                        |> .stalwartConfig
                        |> Expect.equal
                            (Just
                                { defaultStalwartConfig
                                    | stalwartReceivingEnabled = False
                                    , stalwartSendingEnabled = True
                                    , stalwartSmtpHost = "stalwart.email.svc"
                                    , stalwartSmtpPort = 587
                                    , stalwartFromAddress = "login@example.com"
                                    , stalwartSmtpUsername = "rellm"
                                }
                            )
            , test "never nulls the config out, even when nothing else is set" <|
                \_ ->
                    configWithStalwart True False
                        |> EmailEdits.toggleStalwartReceiving
                        |> .stalwartConfig
                        |> Maybe.map .stalwartReceivingEnabled
                        |> Expect.equal (Just False)
            , test "turning it on with no config creates one" <|
                \_ ->
                    defaultServerConfiguration
                        |> EmailEdits.toggleStalwartReceiving
                        |> .stalwartConfig
                        |> Expect.equal (Just { defaultStalwartConfig | stalwartReceivingEnabled = True })
            ]
        , describe "Stalwart sending form"
            [ test "saving it leaves the receiving flag alone" <|
                \_ ->
                    let
                        form : EmailEdits.StalwartForm
                        form =
                            EmailEdits.stalwartFormFrom (configWithStalwart True False).stalwartConfig
                                |> (\f -> { f | sendingEnabled = True })
                    in
                    EmailEdits.applyStalwart form (configWithStalwart True False)
                        |> .stalwartConfig
                        |> Maybe.map (\c -> ( c.stalwartReceivingEnabled, c.stalwartSendingEnabled ))
                        |> Expect.equal (Just ( True, True ))
            , test "secrets seed blank and the port round-trips" <|
                \_ ->
                    let
                        form : EmailEdits.StalwartForm
                        form =
                            EmailEdits.stalwartFormFrom (configWithStalwart False True).stalwartConfig
                    in
                    ( form.smtpPassword, form.managementToken, form.smtpPort )
                        |> Expect.equal ( "", "", "587" )
            , test "an unparseable port is sent as 0 (the server's 587 default)" <|
                \_ ->
                    let
                        form : EmailEdits.StalwartForm
                        form =
                            EmailEdits.stalwartFormFrom Nothing
                                |> EmailEdits.setStalwartField StalwartSmtpPort "nope"
                    in
                    EmailEdits.applyStalwart form defaultServerConfiguration
                        |> .stalwartConfig
                        |> Maybe.map .stalwartSmtpPort
                        |> Expect.equal (Just 0)
            ]
        , describe "HTTP-API providers"
            [ test "secrets start blank and blank is sent on save (keep what's stored)" <|
                \_ ->
                    let
                        applied : Proto.Rellm.ServerConfiguration
                        applied =
                            defaultServerConfiguration
                                |> EmailEdits.applyPostmark (EmailEdits.postmarkFormFrom Nothing)
                                |> EmailEdits.applySendgrid (EmailEdits.sendgridFormFrom Nothing)
                                |> EmailEdits.applyMailgun (EmailEdits.mailgunFormFrom Nothing)
                    in
                    ( applied.postmarkConfig |> Maybe.map (\c -> ( c.postmarkServerToken, c.postmarkAccountToken ))
                    , applied.sendgridConfig |> Maybe.map .sendgridApiKey
                    , applied.mailgunConfig |> Maybe.map .mailgunApiKey
                    )
                        |> Expect.equal ( Just ( "", "" ), Just "", Just "" )
            , test "non-secret fields are trimmed" <|
                \_ ->
                    let
                        form : EmailEdits.PostmarkForm
                        form =
                            EmailEdits.postmarkFormFrom Nothing
                                |> EmailEdits.setPostmarkField EmailEdits.PostmarkFromAddress "  login@example.com "
                    in
                    EmailEdits.applyPostmark form defaultServerConfiguration
                        |> .postmarkConfig
                        |> Maybe.map .postmarkFromAddress
                        |> Expect.equal (Just "login@example.com")
            , test "hasValues is false for an untouched default config" <|
                \_ ->
                    Expect.equal
                        [ EmailEdits.postmarkHasValues Proto.Rellm.defaultPostmarkConfig
                        , EmailEdits.sendgridHasValues Proto.Rellm.defaultSendgridConfig
                        , EmailEdits.mailgunHasValues Proto.Rellm.defaultMailgunConfig
                        , EmailEdits.stalwartHasValues defaultStalwartConfig
                        ]
                        [ False, False, False, False ]
            ]
        ]
