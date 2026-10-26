module SocialMediaEmbed exposing (Embed, fromLink, fromMarkdown, network, view)

{-| Embeds a link to a post on Facebook, Instagram, LinkedIn, Pinterest, TikTok, X (Twitter) or YouTube -- an Elm
take on [`react-social-media-embed`](https://github.com/justinmahar/react-social-media-embed), which the Tamagui
frontend uses. One module per network (`SocialMediaEmbed.YouTube`, ...), each with a pure `fromLink` that
recognizes its links and a `view`; `SocialMediaEmbed.Common` holds the shared pieces; this module picks the right
network for a link.

The pieces fit together as: `fromLink link` -> `Maybe Embed` -> `view`. A link that isn't one of those networks'
posts (or is a profile/channel link, with no post to show) is `Nothing`, so the caller shows nothing extra.

Styling is `public/style/social_media_embed.css`; iframe auto-resizing is a small `message` listener in
`public/index.html`.

-}

import Html exposing (Html)
import SocialMediaEmbed.Common as Common
import SocialMediaEmbed.Facebook as Facebook
import SocialMediaEmbed.Instagram as Instagram
import SocialMediaEmbed.LinkedIn as LinkedIn
import SocialMediaEmbed.Pinterest as Pinterest
import SocialMediaEmbed.TikTok as TikTok
import SocialMediaEmbed.X as X
import SocialMediaEmbed.YouTube as YouTube


type Embed
    = Facebook Facebook.Embed
    | Instagram Instagram.Embed
    | LinkedIn LinkedIn.Embed
    | Pinterest Pinterest.Embed
    | TikTok TikTok.Embed
    | X X.Embed
    | YouTube YouTube.Embed


{-| The embed for a link, if it's a post on one of the supported networks. The scheme is optional
(`youtu.be/abc` works).
-}
fromLink : String -> Maybe Embed
fromLink rawLink =
    Common.parseLink rawLink
        |> Maybe.andThen
            (\link ->
                firstJust
                    [ \_ -> YouTube.fromLink link |> Maybe.map YouTube
                    , \_ -> X.fromLink link |> Maybe.map X
                    , \_ -> Instagram.fromLink link |> Maybe.map Instagram
                    , \_ -> Facebook.fromLink link |> Maybe.map Facebook
                    , \_ -> TikTok.fromLink link |> Maybe.map TikTok
                    , \_ -> Pinterest.fromLink link |> Maybe.map Pinterest
                    , \_ -> LinkedIn.fromLink link |> Maybe.map LinkedIn
                    ]
            )


{-| The embeds for the Markdown links (`[label](href)`) in `markdown`, in order. -}
fromMarkdown : String -> List Embed
fromMarkdown markdown =
    markdown
        |> String.split "]("
        |> List.drop 1
        |> List.filterMap (String.split ")" >> List.head >> Maybe.andThen fromLink)


firstJust : List (() -> Maybe a) -> Maybe a
firstJust attempts =
    case attempts of
        [] ->
            Nothing

        attempt :: rest ->
            case attempt () of
                Just found ->
                    Just found

                Nothing ->
                    firstJust rest


view : Embed -> Html msg
view embed =
    case embed of
        Facebook inner ->
            Facebook.view inner

        Instagram inner ->
            Instagram.view inner

        LinkedIn inner ->
            LinkedIn.view inner

        Pinterest inner ->
            Pinterest.view inner

        TikTok inner ->
            TikTok.view inner

        X inner ->
            X.view inner

        YouTube inner ->
            YouTube.view inner


{-| The network's name, for tests and styling hooks.
-}
network : Embed -> String
network embed =
    case embed of
        Facebook _ ->
            "facebook"

        Instagram _ ->
            "instagram"

        LinkedIn _ ->
            "linkedin"

        Pinterest _ ->
            "pinterest"

        TikTok _ ->
            "tiktok"

        X _ ->
            "x"

        YouTube _ ->
            "youtube"
