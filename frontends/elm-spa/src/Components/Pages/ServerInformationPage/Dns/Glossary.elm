module Components.Pages.ServerInformationPage.Dns.Glossary exposing
    ( emailExplainer
    , meaningOf
    )

{-| Plain-language one-liners for the email-DNS jargon the Sign In & Contact tab shows (SPF, DKIM,
DMARC, MX) -- the single place that wording lives, so the explainer, the chips' tap-to-explain line
and the check rows all say the same thing.
-}


{-| What a record/check is, in one short line. Matches on the lower-cased name containing `spf`,
`dkim`, `dmarc` or `mx` (so "DKIM (selector a)", "SPF record" and "Incoming mail (MX)" all resolve); `Nothing` otherwise.
-}
meaningOf : String -> Maybe String
meaningOf name =
    let
        lower : String
        lower =
            String.toLower name
    in
    emailExplainer
        |> List.filter (\( label, _, _ ) -> String.contains (String.toLower label) lower)
        |> List.head
        |> Maybe.map (\( _, short, _ ) -> short)


{-| `( label, one-line meaning, extra detail )` for each record, in display order. The one-liners are the
server's own wording (`copy.rs` in the backend's `contact_integrations_status`), so the UI and the status
messages agree.
-}
emailExplainer : List ( String, String, String )
emailExplainer =
    [ ( "SPF", "SPF lists which servers may send email for your domain.", "" )
    , ( "DKIM", "DKIM adds a digital signature that proves an email really came from your domain.", "" )
    , ( "DMARC"
      , "DMARC tells receivers what to do with fake email sent as your domain, and sends you reports about it."
      , "none = just watch, quarantine = spam folder, reject = bounce it."
      )
    , ( "MX", "MX records say where email sent to your domain is delivered.", "" )
    ]
