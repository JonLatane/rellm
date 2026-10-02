module Components.FederatedAuthors exposing
    ( FederatedAuthor
    , isUnverified
    , unverifiedTitle
    , warningBadge
    , withWarningOverlay
    )

{-| The shared bits of `Components.Pages.UserProfilePage`'s "federated" mode, where its
embedded `PostsPage`/`EventsPage` copies also show the posts/events of every other profile the
viewed user has `federated_profiles`-linked (on other servers, or even other accounts on the
_same_ server) alongside the user's own.

A link is only trustworthy when it's mutual -- anyone can list `jon@bullcity.social` among their
own `federated_profiles` without `jon` ever agreeing to it. `verified` captures that (the linked
profile's own `federated_profiles` points back at the viewed user, see
`Components.Pages.UserProfilePage.federatedAuthors`); anything still unverified is flagged with
a warning overlay on its cards (`withWarningOverlay`) and beside its calendar titles
(`unverifiedTitle`).

-}

import Html exposing (Html, div, span, text)
import Html.Attributes exposing (attribute, style, title)


{-| One extra profile (beyond the page's own `author`) to fetch from. `host` is the
server's frontend host, `userId` the profile's user id on it.
-}
type alias FederatedAuthor =
    { host : String
    , userId : String
    , verified : Bool
    }


{-| Whether something authored by `authorId` on `host` came from an unverified
`FederatedAuthor` -- always `False` for the page's own `author` (never in `authors`) and for
everything on a verified link.
-}
isUnverified : List FederatedAuthor -> String -> Maybe String -> Bool
isUnverified authors host maybeAuthorId =
    case maybeAuthorId of
        Just authorId ->
            List.any (\a -> not a.verified && a.host == host && a.userId == authorId) authors

        Nothing ->
            False


warningText : String
warningText =
    "Unverified federated profile: this account is linked from this user's profile, but doesn't link back to it, so it may not actually be the same person."


{-| Prefix for a calendar event's title (plain text, FullCalendar has no HTML titles here).
-}
unverifiedTitle : Bool -> String -> String
unverifiedTitle unverified title_ =
    if unverified then
        "⚠️ " ++ title_

    else
        title_


{-| The ⚠️ itself, positioned in the top-right corner of its (`position: relative`) parent.
-}
warningBadge : Html msg
warningBadge =
    span
        [ title warningText
        , attribute "role" "img"
        , attribute "aria-label" warningText
        , style "position" "absolute"
        , style "top" "0.25em"
        , style "right" "0.5em"
        , style "z-index" "1"
        , style "cursor" "help"
        , style "font-size" "1.25em"
        ]
        [ text "⚠️" ]


{-| Wraps a card with `warningBadge` when `unverified`; a pass-through otherwise (no extra
wrapper node, so verified/own cards render exactly as before).
-}
withWarningOverlay : Bool -> Html msg -> Html msg
withWarningOverlay unverified card =
    if unverified then
        div [ style "position" "relative" ] [ card, warningBadge ]

    else
        card
