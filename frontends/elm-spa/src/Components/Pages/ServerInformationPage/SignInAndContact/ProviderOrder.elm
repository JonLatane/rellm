module Components.Pages.ServerInformationPage.SignInAndContact.ProviderOrder exposing
    ( addSelectionAfter
    , addable
    , append
    , moveDown
    , moveUp
    , removeAt
    )

{-| The pure list operations behind the provider-preference editors ("Preferred Verification
Providers" for SMS -- `preferredVerificationApis` -- and "Preferred Email Providers" -- `preferredEmailApis`).
Generic over the provider enum so both editors share them; `SignInAndContactTab` keeps the
`Maybe` edit state (`pending` order, which provider the Add dropdown has selected, save status) and
renders it.

A preference list's order IS the order the server tries providers in, so the editor offers
move-up/move-down (by index -- a provider appears at most once) rather than only remove-then-re-add.

-}


{-| The providers of `all` (in `all`'s order) not yet in `pending`.
-}
addable : List a -> List a -> List a
addable all pending =
    List.filter (\api -> not (List.member api pending)) all


{-| Which provider the Add dropdown should have selected given `pending`: `current` if it's still
addable, otherwise the first addable one (`Nothing` once everything is already listed).
-}
addSelectionAfter : List a -> Maybe a -> List a -> Maybe a
addSelectionAfter all current pending =
    let
        remaining : List a
        remaining =
            addable all pending
    in
    case current of
        Just api ->
            if List.member api remaining then
                Just api

            else
                List.head remaining

        Nothing ->
            List.head remaining


append : a -> List a -> List a
append api pending =
    if List.member api pending then
        pending

    else
        pending ++ [ api ]


removeAt : Int -> List a -> List a
removeAt index items =
    List.indexedMap Tuple.pair items
        |> List.filter (\( i, _ ) -> i /= index)
        |> List.map Tuple.second


{-| Swaps the item at `index` with the one before it (no-op for the first item/out of range).
-}
moveUp : Int -> List a -> List a
moveUp index items =
    if index <= 0 || index >= List.length items then
        items

    else
        swapAdjacent (index - 1) items


{-| Swaps the item at `index` with the one after it (no-op for the last item/out of range).
-}
moveDown : Int -> List a -> List a
moveDown index items =
    if index < 0 || index >= List.length items - 1 then
        items

    else
        swapAdjacent index items


swapAdjacent : Int -> List a -> List a
swapAdjacent index items =
    case ( List.take index items, List.drop index items ) of
        ( before, first :: second :: after ) ->
            before ++ (second :: first :: after)

        _ ->
            items
