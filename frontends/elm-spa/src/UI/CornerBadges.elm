module UI.CornerBadges exposing (Badge, nonZero, view)

{-| The count badges in a nav toggle's corners (Starred, Messages), with an optional spinner on each.
-}

import Html exposing (Html, span, text)
import Html.Attributes exposing (class)
import UI.Classes exposing (classes, hostnameToCSSClass)


{-| One corner's badge: see `view`.
-}
type alias Badge =
    { count : Maybe Int
    , more : Bool
    , spinner : Maybe Bool
    }


{-| `Just n` only when `n` is above zero -- for corner badges that stay hidden at zero (see `view`).
-}
nonZero : Int -> Maybe Int
nonZero n =
    if n > 0 then
        Just n

    else
        Nothing


{-| The count badges in a nav toggle's corners -- our "summed count" style, used by both the Starred and
Messages buttons. Counts fill the corners in a fixed order: top-right, bottom-right, bottom-left, then
(for a fourth) top-left. A `Nothing` leaves its corner empty (a count that's hidden at zero) but still
holds its place, so a given kind of count always lands in the same corner.

  - Starred: top-right is the stars in this browser, bottom-right the server-side stars (when any) -- the
    same two numbers as the panel's Browser and Server tabs.
  - Messages: top-right is unread Messages, bottom-right unread Subscriptions notes, bottom-left
    Fulfillment orders awaiting a host admin (server admins).

Each `Badge` has its `count` (`Nothing` hides it), `more` (the real total is higher than `count`, shown as
"40+" -- for a list that is only loaded up to a cap) and `spinner`: `Nothing` for a badge with no spinner,
`Just loading` for one that holds a spinning `↻` (`.starred-count-spinner`, which CSS-transitions its width
and opacity in and out) while `loading`. A spinner badge that is loading shows even at a hidden/zero count
(just the spinner, no number); once loading ends at zero it fades out.
-}
view : String -> List Badge -> List (Html msg)
view mainFrontendHost badges =
    let
        corners : List String
        corners =
            [ "corner-badge-top-right", "corner-badge-bottom-right", "corner-badge-bottom-left", "corner-badge-top-left" ]

        badge : String -> Badge -> Html msg
        badge corner b =
            -- Always rendered (a `Nothing` count just gets `.count-badge-hidden`) so showing/hiding
            -- transitions in CSS instead of the element appearing/vanishing. A hidden badge keeps
            -- "0" as its text so it doesn't change shape while fading out.
            let
                loading : Bool
                loading =
                    b.spinner == Just True

                hasSpinner : Bool
                hasSpinner =
                    b.spinner /= Nothing

                -- "40+" for a list that was only loaded up to a cap; nothing to add to a zero.
                plus : String
                plus =
                    if b.more then
                        "+"

                    else
                        ""

                maybeCount : Maybe Int
                maybeCount =
                    if loading && b.count == Nothing then
                        Just 0

                    else
                        b.count

                count : Int
                count =
                    Maybe.withDefault 0 maybeCount
            in
            span
                [ classes
                    ([ "starred-count-badge"
                     , corner
                     , hostnameToCSSClass mainFrontendHost
                     , "background-color-nav"
                     , "border-color-primary-text"
                     ]
                        ++ (if maybeCount == Nothing then
                                [ "count-badge-hidden" ]

                            else
                                []
                           )
                    )
                ]
                ((if hasSpinner then
                    [ span
                        [ classes
                            ("starred-count-spinner"
                                :: (if loading then
                                        [ "loading" ]

                                    else
                                        []
                                   )
                            )
                        ]
                        [ text "↻" ]
                    ]

                  else
                    []
                 )
                    ++ (if hasSpinner then
                            -- A real element (not a bare text node) so CSS can tell the spinner has a
                            -- sibling; no element at all for a zero count that's just the spinner.
                            if count == 0 then
                                []

                            else
                                [ span [ class "starred-count-number" ] [ text (String.fromInt count ++ plus) ] ]

                        else
                            [ text (String.fromInt count ++ plus) ]
                       )
                )
    in
    List.map2 badge corners badges
