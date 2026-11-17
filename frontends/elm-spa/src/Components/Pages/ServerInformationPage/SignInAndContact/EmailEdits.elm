module Components.Pages.ServerInformationPage.SignInAndContact.EmailEdits exposing
    ( MailgunField(..)
    , MailgunForm
    , PostmarkField(..)
    , PostmarkForm
    , SendgridField(..)
    , SendgridForm
    , StalwartField(..)
    , StalwartForm
    , applyMailgun
    , applyPostmark
    , applySendgrid
    , applyStalwart
    , mailgunFormFrom
    , mailgunHasValues
    , postmarkFormFrom
    , postmarkHasValues
    , sendgridFormFrom
    , sendgridHasValues
    , setMailgunField
    , setPostmarkField
    , setSendgridField
    , setStalwartField
    , stalwartFormFrom
    , stalwartHasValues
    , toggleStalwartReceiving
    )

{-| The pure half of the email-provider editors on the Sign In & Contact tab -- Postmark, SendGrid,
Mailgun (HTTP-API providers) and Stalwart's _sending_ settings. Each provider has a `*Form` (what an
admin is typing), `*FormFrom` (seeds it from the stored config), and `apply*` (overlays it onto a
freshly re-fetched `ServerConfiguration`, the transform `AccountsPanel.updateServerConfig` wants).

Write-only secrets (`postmark_server_token`, `postmark_account_token`, `sendgrid_api_key`,
`mailgun_api_key`, `stalwart_smtp_password`, `stalwart_management_token`) are blanked by
`GetServerConfiguration`, so every `*FormFrom` seeds them blank, and sending one blank means "keep
what's stored" (the backend merges it back, same rule as Telnyx's API key). Nothing here ever nulls a
provider's whole config out -- `*_enabled` is itself the "off" switch -- so flipping a provider off
and on never loses its (non-secret) settings.

Stalwart is the one provider with two independent switches: _receiving_ (`stalwart_receiving_enabled`,
the in-cluster MTA hook, an instant toggle -- `toggleStalwartReceiving`) and _sending_ (everything
else, edited as a form -- `applyStalwart`). Each only ever touches its own fields: toggling receiving
off must not wipe the SMTP settings, and saving the sending form must not flip receiving.

-}

import Proto.Rellm
    exposing
        ( MailgunConfig
        , PostmarkConfig
        , SendgridConfig
        , ServerConfiguration
        , StalwartConfig
        , defaultMailgunConfig
        , defaultPostmarkConfig
        , defaultSendgridConfig
        , defaultStalwartConfig
        )



-- POSTMARK


type alias PostmarkForm =
    { enabled : Bool
    , serverToken : String
    , accountToken : String
    , fromAddress : String
    , fromName : String
    , messageStream : String
    }


type PostmarkField
    = PostmarkServerToken
    | PostmarkAccountToken
    | PostmarkFromAddress
    | PostmarkFromName
    | PostmarkMessageStream


postmarkFormFrom : Maybe PostmarkConfig -> PostmarkForm
postmarkFormFrom maybeConfig =
    let
        config : PostmarkConfig
        config =
            Maybe.withDefault defaultPostmarkConfig maybeConfig
    in
    { enabled = config.postmarkEnabled
    , serverToken = ""
    , accountToken = ""
    , fromAddress = config.postmarkFromAddress
    , fromName = config.postmarkFromName
    , messageStream = config.postmarkMessageStream
    }


setPostmarkField : PostmarkField -> String -> PostmarkForm -> PostmarkForm
setPostmarkField field text form =
    case field of
        PostmarkServerToken ->
            { form | serverToken = text }

        PostmarkAccountToken ->
            { form | accountToken = text }

        PostmarkFromAddress ->
            { form | fromAddress = text }

        PostmarkFromName ->
            { form | fromName = text }

        PostmarkMessageStream ->
            { form | messageStream = text }


applyPostmark : PostmarkForm -> ServerConfiguration -> ServerConfiguration
applyPostmark form config =
    { config
        | postmarkConfig =
            Just
                { postmarkEnabled = form.enabled
                , postmarkServerToken = form.serverToken
                , postmarkAccountToken = form.accountToken
                , postmarkFromAddress = String.trim form.fromAddress
                , postmarkFromName = String.trim form.fromName
                , postmarkMessageStream = String.trim form.messageStream
                }
    }


postmarkHasValues : PostmarkConfig -> Bool
postmarkHasValues config =
    config.postmarkEnabled
        || not (String.isEmpty config.postmarkFromAddress)
        || not (String.isEmpty config.postmarkFromName)
        || not (String.isEmpty config.postmarkMessageStream)



-- SENDGRID


type alias SendgridForm =
    { enabled : Bool
    , apiKey : String
    , fromAddress : String
    , fromName : String
    , region : String
    }


type SendgridField
    = SendgridApiKey
    | SendgridFromAddress
    | SendgridFromName
    | SendgridRegion


sendgridFormFrom : Maybe SendgridConfig -> SendgridForm
sendgridFormFrom maybeConfig =
    let
        config : SendgridConfig
        config =
            Maybe.withDefault defaultSendgridConfig maybeConfig
    in
    { enabled = config.sendgridEnabled
    , apiKey = ""
    , fromAddress = config.sendgridFromAddress
    , fromName = config.sendgridFromName
    , region = config.sendgridRegion
    }


setSendgridField : SendgridField -> String -> SendgridForm -> SendgridForm
setSendgridField field text form =
    case field of
        SendgridApiKey ->
            { form | apiKey = text }

        SendgridFromAddress ->
            { form | fromAddress = text }

        SendgridFromName ->
            { form | fromName = text }

        SendgridRegion ->
            { form | region = text }


applySendgrid : SendgridForm -> ServerConfiguration -> ServerConfiguration
applySendgrid form config =
    { config
        | sendgridConfig =
            Just
                { sendgridEnabled = form.enabled
                , sendgridApiKey = form.apiKey
                , sendgridFromAddress = String.trim form.fromAddress
                , sendgridFromName = String.trim form.fromName
                , sendgridRegion = String.trim form.region
                }
    }


sendgridHasValues : SendgridConfig -> Bool
sendgridHasValues config =
    config.sendgridEnabled
        || not (String.isEmpty config.sendgridFromAddress)
        || not (String.isEmpty config.sendgridFromName)
        || not (String.isEmpty config.sendgridRegion)



-- MAILGUN


type alias MailgunForm =
    { enabled : Bool
    , apiKey : String
    , domain : String
    , region : String
    , fromAddress : String
    , fromName : String
    }


type MailgunField
    = MailgunApiKey
    | MailgunDomain
    | MailgunRegion
    | MailgunFromAddress
    | MailgunFromName


mailgunFormFrom : Maybe MailgunConfig -> MailgunForm
mailgunFormFrom maybeConfig =
    let
        config : MailgunConfig
        config =
            Maybe.withDefault defaultMailgunConfig maybeConfig
    in
    { enabled = config.mailgunEnabled
    , apiKey = ""
    , domain = config.mailgunDomain
    , region = config.mailgunRegion
    , fromAddress = config.mailgunFromAddress
    , fromName = config.mailgunFromName
    }


setMailgunField : MailgunField -> String -> MailgunForm -> MailgunForm
setMailgunField field text form =
    case field of
        MailgunApiKey ->
            { form | apiKey = text }

        MailgunDomain ->
            { form | domain = text }

        MailgunRegion ->
            { form | region = text }

        MailgunFromAddress ->
            { form | fromAddress = text }

        MailgunFromName ->
            { form | fromName = text }


applyMailgun : MailgunForm -> ServerConfiguration -> ServerConfiguration
applyMailgun form config =
    { config
        | mailgunConfig =
            Just
                { mailgunEnabled = form.enabled
                , mailgunApiKey = form.apiKey
                , mailgunDomain = String.trim form.domain
                , mailgunRegion = String.trim form.region
                , mailgunFromAddress = String.trim form.fromAddress
                , mailgunFromName = String.trim form.fromName
                }
    }


mailgunHasValues : MailgunConfig -> Bool
mailgunHasValues config =
    config.mailgunEnabled
        || not (String.isEmpty config.mailgunDomain)
        || not (String.isEmpty config.mailgunFromAddress)
        || not (String.isEmpty config.mailgunFromName)
        || not (String.isEmpty config.mailgunRegion)



-- STALWART


{-| Stalwart's _sending_ settings. `smtpPort` stays a `String` while typing (`""`/`0` mean 587 on
the server); `applyStalwart` parses it. Receiving isn't part of this form -- see
`toggleStalwartReceiving`.
-}
type alias StalwartForm =
    { sendingEnabled : Bool
    , smtpHost : String
    , smtpPort : String
    , smtpUsername : String
    , smtpPassword : String
    , fromAddress : String
    , fromName : String
    , managementUrl : String
    , managementToken : String
    }


type StalwartField
    = StalwartSmtpHost
    | StalwartSmtpPort
    | StalwartSmtpUsername
    | StalwartSmtpPassword
    | StalwartFromAddress
    | StalwartFromName
    | StalwartManagementUrl
    | StalwartManagementToken


stalwartFormFrom : Maybe StalwartConfig -> StalwartForm
stalwartFormFrom maybeConfig =
    let
        config : StalwartConfig
        config =
            Maybe.withDefault defaultStalwartConfig maybeConfig
    in
    { sendingEnabled = config.stalwartSendingEnabled
    , smtpHost = config.stalwartSmtpHost
    , smtpPort =
        if config.stalwartSmtpPort == 0 then
            ""

        else
            String.fromInt config.stalwartSmtpPort
    , smtpUsername = config.stalwartSmtpUsername
    , smtpPassword = ""
    , fromAddress = config.stalwartFromAddress
    , fromName = config.stalwartFromName
    , managementUrl = config.stalwartManagementUrl
    , managementToken = ""
    }


setStalwartField : StalwartField -> String -> StalwartForm -> StalwartForm
setStalwartField field text form =
    case field of
        StalwartSmtpHost ->
            { form | smtpHost = text }

        StalwartSmtpPort ->
            { form | smtpPort = text }

        StalwartSmtpUsername ->
            { form | smtpUsername = text }

        StalwartSmtpPassword ->
            { form | smtpPassword = text }

        StalwartFromAddress ->
            { form | fromAddress = text }

        StalwartFromName ->
            { form | fromName = text }

        StalwartManagementUrl ->
            { form | managementUrl = text }

        StalwartManagementToken ->
            { form | managementToken = text }


{-| Overlays the sending form onto `config.stalwartConfig`, keeping whatever
`stalwartReceivingEnabled` is stored. An unparseable/blank port is sent as `0` ("use 587").
-}
applyStalwart : StalwartForm -> ServerConfiguration -> ServerConfiguration
applyStalwart form config =
    let
        existing : StalwartConfig
        existing =
            Maybe.withDefault defaultStalwartConfig config.stalwartConfig
    in
    { config
        | stalwartConfig =
            Just
                { existing
                    | stalwartSendingEnabled = form.sendingEnabled
                    , stalwartSmtpHost = String.trim form.smtpHost
                    , stalwartSmtpPort = String.toInt (String.trim form.smtpPort) |> Maybe.withDefault 0
                    , stalwartSmtpUsername = String.trim form.smtpUsername
                    , stalwartSmtpPassword = form.smtpPassword
                    , stalwartFromAddress = String.trim form.fromAddress
                    , stalwartFromName = String.trim form.fromName
                    , stalwartManagementUrl = String.trim form.managementUrl
                    , stalwartManagementToken = form.managementToken
                }
    }


{-| Flips only `stalwartReceivingEnabled`, creating a default `StalwartConfig` if there is none yet.
Never nulls `stalwartConfig` out: it also holds the _sending_ settings (SMTP host/credentials, from
address, ...), which turning receiving off must leave alone.
-}
toggleStalwartReceiving : ServerConfiguration -> ServerConfiguration
toggleStalwartReceiving config =
    let
        existing : StalwartConfig
        existing =
            Maybe.withDefault defaultStalwartConfig config.stalwartConfig
    in
    { config | stalwartConfig = Just { existing | stalwartReceivingEnabled = not existing.stalwartReceivingEnabled } }


stalwartHasValues : StalwartConfig -> Bool
stalwartHasValues config =
    config.stalwartReceivingEnabled
        || config.stalwartSendingEnabled
        || not (String.isEmpty config.stalwartSmtpHost)
        || not (String.isEmpty config.stalwartFromAddress)
