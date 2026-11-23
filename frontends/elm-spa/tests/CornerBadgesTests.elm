module CornerBadgesTests exposing (suite)

{-| `UI.CornerBadges.view`: the Starred/Messages nav buttons' count badges. Every corner's badge is always
rendered (so showing/hiding is a CSS transition); only the corners given a `Just` spinner flag hold a `↻`,
which spins (`.loading`) only while that flag is `True` -- so Messages, Subscriptions and Fulfillment each
spin on their own.
-}

import Expect
import Html exposing (div)
import Test exposing (Test, describe, test)
import Test.Html.Query as Query
import Test.Html.Selector as Selector
import UI.CornerBadges as CornerBadges


render : List (Maybe Bool) -> List (Maybe Int) -> Query.Single msg
render spinners counts =
    div [] (CornerBadges.view "example.com" spinners counts)
        |> Query.fromHtml


badge : String -> Query.Single msg -> Query.Single msg
badge corner =
    Query.find [ Selector.class corner ]


spinnerIn : Query.Single msg -> Query.Multiple msg
spinnerIn =
    Query.findAll [ Selector.class "starred-count-spinner" ]


loadingSpinnerIn : Query.Single msg -> Query.Multiple msg
loadingSpinnerIn =
    Query.findAll [ Selector.classes [ "starred-count-spinner", "loading" ] ]


suite : Test
suite =
    describe "UI.CornerBadges.view"
        [ describe "nonZero"
            [ test "is Nothing at zero (a badge that hides)" <|
                \_ -> CornerBadges.nonZero 0 |> Expect.equal Nothing
            , test "is the count above zero" <|
                \_ -> CornerBadges.nonZero 3 |> Expect.equal (Just 3)
            ]
        , describe "corners"
            [ test "renders exactly one badge per count given (none for an empty list)" <|
                \_ ->
                    render [] []
                        |> Query.findAll [ Selector.class "starred-count-badge" ]
                        |> Query.count (Expect.equal 0)
            , test "a Nothing count is rendered but hidden (so it can fade out)" <|
                \_ ->
                    render [] [ Just 2, Nothing ]
                        |> badge "corner-badge-bottom-right"
                        |> Query.has [ Selector.class "count-badge-hidden" ]
            , test "a count is shown (not hidden) in its corner" <|
                \_ ->
                    render [] [ Just 2, Just 5 ]
                        |> badge "corner-badge-bottom-right"
                        |> Query.hasNot [ Selector.class "count-badge-hidden" ]
            ]
        , describe "spinners"
            [ test "only the corners given a spinner flag hold one" <|
                \_ ->
                    render [ Nothing, Just False ] [ Just 1, Just 2 ]
                        |> Query.findAll [ Selector.class "starred-count-spinner" ]
                        |> Query.count (Expect.equal 1)
            , test "a spinner is idle (not .loading) while its flag is False" <|
                \_ ->
                    render [ Just False ] [ Just 4 ]
                        |> loadingSpinnerIn
                        |> Query.count (Expect.equal 0)
            , test "each badge spins on its own: only the loading ones have a .loading spinner" <|
                \_ ->
                    render [ Just False, Just True, Just True ] [ Just 1, Just 2, Just 3 ]
                        |> Expect.all
                            [ badge "corner-badge-top-right" >> loadingSpinnerIn >> Query.count (Expect.equal 0)
                            , badge "corner-badge-bottom-right" >> loadingSpinnerIn >> Query.count (Expect.equal 1)
                            , badge "corner-badge-bottom-left" >> loadingSpinnerIn >> Query.count (Expect.equal 1)
                            ]
            , test "a loading spinner badge shows even when its count is hidden, with just the spinner and no number" <|
                \_ ->
                    render [ Nothing, Just True ] [ Just 1, Nothing ]
                        |> badge "corner-badge-bottom-right"
                        |> Expect.all
                            [ Query.hasNot [ Selector.class "count-badge-hidden" ]
                            , loadingSpinnerIn >> Query.count (Expect.equal 1)
                            , Query.hasNot [ Selector.class "starred-count-number" ]
                            ]
            , test "once loading ends at a hidden count the badge hides again, keeping its spinner element to fade out" <|
                \_ ->
                    render [ Nothing, Just False ] [ Just 1, Nothing ]
                        |> badge "corner-badge-bottom-right"
                        |> Expect.all
                            [ Query.has [ Selector.class "count-badge-hidden" ]
                            , spinnerIn >> Query.count (Expect.equal 1)
                            ]
            , test "the number sits in its own element next to the spinner (so the spinner/number gap rule can match)" <|
                \_ ->
                    render [ Just True ] [ Just 7 ]
                        |> badge "corner-badge-top-right"
                        |> Query.find [ Selector.class "starred-count-number" ]
                        |> Query.has [ Selector.text "7" ]
            ]
        ]
