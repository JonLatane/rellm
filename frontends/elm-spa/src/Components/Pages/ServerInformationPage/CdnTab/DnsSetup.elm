module Components.Pages.ServerInformationPage.CdnTab.DnsSetup exposing
    ( HostProblem(..)
    , Plan
    , Step
    , cleanHost
    , isApex
    , plan
    , validateHost
    )

{-| The pure side of the CDN tab's "DNS setup" card: from the Frontend Host and Backend Host an admin
entered (or saved), work out the DNS records they need and the warnings worth showing. The view is
`CdnTab.dnsSetupView`; the shared record/explainer widgets are `Dns.View`.

The picture (see `ExternalCDNConfig` and the `GET /backend_host` notes in the protos): visitors reach the
**frontend host**, which the CDN (e.g. Cloudflare) owns and proxies to the **backend host**, where Rellm
really runs. Clients ask `https://<frontend host>/backend_host` which backend to connect to over gRPC, so
the backend host must be reachable directly (DNS only, not proxied).

-}

import Components.Pages.ServerInformationPage.Dns.Record exposing (DnsRecord)


type HostProblem
    = HostHasScheme
    | HostHasPath
    | HostHasSpaces
    | HostHasPort
    | HostNoDot
    | HostBadCharacters


{-| One numbered DNS step: a title, a one-line why, what to do at the DNS provider (`records`), things to
copy and run (`codeLines`), reference `links`, and a `badge` like "Proxied (orange cloud)".
-}
type alias Step =
    { title : String
    , why : String
    , badge : Maybe String
    , records : List DnsRecord
    , codeLines : List String
    , links : List ( String, String )
    , note : Maybe String
    }


{-| `frontend`/`backend` are the hosts the steps are written for (the entered ones when valid, else an
`example.com` placeholder, flagged by `*IsExample`); `warnings` are gentle one-liners.
-}
type alias Plan =
    { frontend : String
    , backend : String
    , frontendIsExample : Bool
    , backendIsExample : Bool
    , warnings : List String
    , steps : List Step
    }


exampleFrontend : String
exampleFrontend =
    "example.com"


exampleBackend : String
exampleBackend =
    "backend.example.com"


{-| Trims and lower-cases `host`, and drops a pasted scheme and anything after the host (path, query,
fragment), so a slightly-wrong entry can still drive the example records.
-}
cleanHost : String -> String
cleanHost host =
    let
        trimmed : String
        trimmed =
            String.toLower (String.trim host)

        afterScheme : String
        afterScheme =
            case String.indices "://" trimmed of
                index :: _ ->
                    String.dropLeft (index + 3) trimmed

                [] ->
                    trimmed
    in
    afterScheme
        |> String.split "/"
        |> List.head
        |> Maybe.withDefault ""
        |> String.split "?"
        |> List.head
        |> Maybe.withDefault ""
        |> String.split "#"
        |> List.head
        |> Maybe.withDefault ""


{-| What's wrong with an entered host, if anything -- `Nothing` for a plausible bare domain
(`example.com`, `api.example.co.uk`). An empty entry is `Nothing` too: "nothing entered yet" is the
caller's own state, not a mistake.
-}
validateHost : String -> Maybe HostProblem
validateHost host =
    let
        trimmed : String
        trimmed =
            String.trim host
    in
    if String.isEmpty trimmed then
        Nothing

    else if String.contains "://" trimmed then
        Just HostHasScheme

    else if String.any (\c -> c == '/' || c == '?' || c == '#') trimmed then
        Just HostHasPath

    else if String.any (\c -> c == ' ' || c == '\t') trimmed then
        Just HostHasSpaces

    else
        validateBare (cleanHost trimmed)


{-| The checks for a host that is already a bare, lower-cased token.
-}
validateBare : String -> Maybe HostProblem
validateBare cleaned =
    if String.contains ":" cleaned then
        Just HostHasPort

    else if not (String.contains "." cleaned) then
        Just HostNoDot

    else if not (String.all (\c -> Char.isAlphaNum c || c == '.' || c == '-') cleaned) || List.any String.isEmpty (String.split "." cleaned) then
        Just HostBadCharacters

    else
        Nothing


{-| A gentle one-liner for a problem, e.g. "Frontend host: enter just the domain, without https://".
-}
hostProblemText : String -> HostProblem -> String
hostProblemText label problem =
    label
        ++ ": "
        ++ (case problem of
                HostHasScheme ->
                    "enter just the domain, without http:// or https://."

                HostHasPath ->
                    "enter just the domain, without a path."

                HostHasSpaces ->
                    "spaces aren't allowed."

                HostHasPort ->
                    "leave the port off -- just the domain."

                HostNoDot ->
                    "this doesn't look like a domain (it needs a dot, like example.com)."

                HostBadCharacters ->
                    "use only letters, digits, dots and hyphens."
           )


{-| Whether `host` is an apex (root) domain -- `example.com`, `example.co.uk` -- where a plain CNAME isn't
normally allowed (Cloudflare "flattens" one for you; other DNS hosts want A/AAAA instead). Two labels, or
three with a common second-level like `co`/`com`/`org` under a two-letter country code.
-}
isApex : String -> Bool
isApex host =
    case List.reverse (String.split "." host) of
        [ _, _ ] ->
            True

        tld :: second :: _ :: [] ->
            String.length tld == 2 && List.member second [ "co", "com", "org", "net", "gov", "edu", "ac" ]

        _ ->
            False


{-| The DNS steps and warnings for the hosts entered. An empty or unusable host is replaced by an
`example.com` placeholder (flagged `*IsExample`) so the card always shows the pattern. `secureMedia`
adds the step about the CDN's IP ranges.
-}
plan : { frontendHost : String, backendHost : String, secureMedia : Bool } -> Plan
plan input =
    let
        usable : String -> String -> ( String, Bool )
        usable entered placeholder =
            let
                cleaned : String
                cleaned =
                    cleanHost entered
            in
            if String.isEmpty cleaned || validateHost cleaned /= Nothing then
                ( placeholder, True )

            else
                ( cleaned, False )

        ( frontend, frontendIsExample ) =
            usable input.frontendHost exampleFrontend

        ( backend, backendIsExample ) =
            usable input.backendHost exampleBackend

        sameHost : Bool
        sameHost =
            not frontendIsExample && not backendIsExample && frontend == backend

        problemWarnings : List String
        problemWarnings =
            List.filterMap identity
                [ validateHost input.frontendHost |> Maybe.map (hostProblemText "Frontend host")
                , validateHost input.backendHost |> Maybe.map (hostProblemText "Backend host")
                ]
    in
    { frontend = frontend
    , backend = backend
    , frontendIsExample = frontendIsExample
    , backendIsExample = backendIsExample
    , warnings =
        problemWarnings
            ++ (if sameHost then
                    [ "Frontend and backend are the same host. The CDN would point at itself -- give the backend its own name, like backend." ++ frontend ++ "." ]

                else
                    []
               )
    , steps =
        [ frontendStep frontend backend
        , backendStep backend
        , checkStep frontend backend
        ]
            ++ (if input.secureMedia then
                    [ mediaStep ]

                else
                    []
               )
    }


frontendStep : String -> String -> Step
frontendStep frontend backend =
    { title = "Point the frontend host at the CDN"
    , why = "Your CDN (like Cloudflare) owns DNS for " ++ frontend ++ " and forwards visitors to Rellm."
    , badge = Just "Proxied (orange cloud)"
    , records =
        [ { recordType = "CNAME"
          , name =
                if isApex frontend then
                    "@"

                else
                    frontend
          , value = backend
          }
        ]
    , codeLines = []
    , links = []
    , note =
        if isApex frontend then
            Just "Root domain: Cloudflare flattens this CNAME for you. Elsewhere, use A/AAAA records with your server's IP instead."

        else
            Just "Or use A/AAAA records with your server's IP."
    }


backendStep : String -> Step
backendStep backend =
    { title = "Point the backend host at your server"
    , why = "This is where Rellm really runs. Keep it unproxied so gRPC on 443 reaches Rellm directly."
    , badge = Just "DNS only (grey cloud)"
    , records =
        [ { recordType = "A", name = backend, value = "<your server's IPv4>" }
        , { recordType = "AAAA", name = backend, value = "<your server's IPv6, if any>" }
        ]
    , codeLines = []
    , links = []
    , note = Just "Or one CNAME to your host's load balancer name (Kubernetes/cloud provider)."
    }


checkStep : String -> String -> Step
checkStep frontend backend =
    { title = "Check that clients can find the backend"
    , why = "Clients first ask the frontend for /backend_host, then connect to the backend it names."
    , badge = Nothing
    , records = []
    , codeLines = [ "https://" ++ frontend ++ "/backend_host", "curl https://" ++ frontend ++ "/backend_host" ]
    , links = []
    , note = Just ("It should answer with " ++ backend ++ ".")
    }


mediaStep : Step
mediaStep =
    { title = "Allow the CDN's IP ranges for media"
    , why = "Secure media only serves the CDN's own addresses."
    , badge = Nothing
    , records = []
    , codeLines = []
    , links = [ ( "Cloudflare IPv4 ranges", "https://www.cloudflare.com/ips-v4" ), ( "Cloudflare IPv6 ranges", "https://www.cloudflare.com/ips-v6" ) ]
    , note = Nothing
    }
