module Components.UserPicker exposing
    ( Model
    , Msg
    , empty
    , init
    , selectedUsers
    , subscriptions
    , update
    , view
    , withInitialSelection
    )

{-| A single-server "pick one or more Users" list -- the recipient picker
`Shared.MarkdownPanel`'s `SendNewMessage` target uses to build a
`SendMessageRequest.toUserIds`. Structurally mirrors
`Components.Pages.UsersPage`'s unfiltered `EVERYONE` listing (fetch/search/
FLIP-animated list), but scoped to one already-known `host` -- a message's
recipients all have to be on the sender's own server, so unlike `UsersPage`
there's no "aggregate across every enabled server" story here -- and
multi-select (`ToggleSelected`, `selected`) instead of `userCard`'s follow
button.

Doesn't import `Shared` (only the leaf `Shared.AccountsPanel`), same
constraint `Shared.MarkdownPanel` itself is under -- `Shared` embeds
`Shared.MarkdownPanel` in `Panels`, so anything that module imports (this
included) can't import `Shared` back without cycling.

-}

import Animation
import Components.Users as Users
import Dict exposing (Dict)
import Grpc
import Html exposing (Html, button, div, img, input, p, span, text)
import Html.Attributes exposing (alt, attribute, class, id, placeholder, src, title, type_, value)
import Html.Events exposing (onClick, onInput, preventDefaultOn)
import Html.Keyed
import Json.Decode as Decode
import Process
import Proto.Rellm exposing (Author, GetUsersResponse, User, defaultUser, unwrapMediaReference)
import Proto.Rellm.UserListingType exposing (UserListingType(..))
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts
import Shared.AccountsPanel.RellmServers as RellmServers
import Task
import UI.Classes exposing (classes, hostnameToCSSClass)
import UI.Flip


type alias Model =
    { host : String
    , usersFeed : UsersFeed
    , userAnimations : Dict String UserAnimation
    , selected : Dict String User
    , searchText : String
    , searchGeneration : Int
    }


type UsersFeed
    = NotSearched
    | Loading
    | Loaded (List User)
    | Failed


type alias UserAnimation =
    { user : User
    , flip : UI.Flip.State Msg
    }


type Msg
    = GotUsers (Result Grpc.Error ( Maybe AccountsPanel.Msg, GetUsersResponse ))
    | Animate Animation.Msg
    | RemoveUser String
    | ToggleSelected User
    | SearchTextChanged String
    | SearchDebounceElapsed Int
    | ClearSearchClicked


{-| A `Model` with nothing fetched yet -- what `Shared.MarkdownPanel.init`
seeds itself with (there's no recipient list to show before `SendNewMessage`
is ever opened). `init` starts from this too.
-}
empty : String -> Model
empty host =
    { host = host
    , usersFeed = NotSearched
    , userAnimations = Dict.empty
    , selected = Dict.empty
    , searchText = ""
    , searchGeneration = 0
    }


{-| Doesn't fetch anything up front -- unlike `Components.Pages.UsersPage`'s
unfiltered `EVERYONE` browse, this picker never shows a "browse everyone"
listing at all, only search results (see `SearchTextChanged`), so there's
nothing to fetch until the user actually types something.
-}
init : String -> ( Model, Cmd Msg )
init host =
    ( empty host, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions model =
    UI.Flip.subscription Animate (List.map .flip (Dict.values model.userAnimations))


selectedUsers : Model -> List User
selectedUsers model =
    Dict.values model.selected


{-| Pre-selects `authors` (`Shared.MarkdownPanel`'s "Reply" flow -- see
`TargetType.SendNewMessage`'s own doc) without an extra fetch: `Author`
(what a `MessagingGroup`'s `members` carry) is a strict subset of `User`'s own
fields, so a synthetic `User` built straight from each `Author` -- via
`defaultUser`, same "overlay known fields onto a default record" trick used
throughout this codebase for constructing a placeholder -- is already enough
for `chipView`/`userRowView`'s display and `selectedUsers`' own `.id` (all
`sendMessageTask` actually needs). Meant to be called once, right after
`init`/`empty` -- later selection changes go through `ToggleSelected` as
usual, this doesn't touch `usersFeed`/search at all.
-}
withInitialSelection : List Author -> Model -> Model
withInitialSelection authors model =
    { model
        | selected =
            authors
                |> List.map
                    (\author ->
                        ( author.userId
                        , { defaultUser
                            | id = author.userId
                            , username = Maybe.withDefault "" author.username
                            , realName = Maybe.withDefault "" author.realName
                            , avatar = Maybe.map unwrapMediaReference author.avatar
                            , permissions = author.permissions
                          }
                        )
                    )
                |> Dict.fromList
    }


{-| The inner tuple's trailing `Bool` is `True` only when `ToggleSelected`
just *added* a user (as opposed to removing one, or any other `Msg`) --
callers (today, just `Shared.MarkdownPanel`) use it to refocus their own
search input, since this module doesn't own that concern (see
`Shared.MarkdownPanel.focusCmdFor`, which already owns the `Browser.Dom.focus
"user-picker-search-input"` / `NoOp` convention for this same id). Nested
rather than a 4-tuple -- Elm only accepts tuples up to three items -- same
convention `Shared.MarkdownPanel.update`'s own return type uses.
-}
update : AccountsPanel.Model -> Msg -> Model -> ( Model, Cmd Msg, ( Maybe AccountsPanel.Msg, Bool ) )
update accountsPanelModel msg model =
    case msg of
        GotUsers (Ok ( maybeAccountsPanelMsg, response )) ->
            ( { model | usersFeed = Loaded response.users } |> syncAnimations, Cmd.none, ( maybeAccountsPanelMsg, False ) )

        GotUsers (Err _) ->
            ( { model | usersFeed = Failed } |> syncAnimations, Cmd.none, ( Nothing, False ) )

        Animate animMsg ->
            let
                step : String -> UserAnimation -> ( Dict String UserAnimation, List (Cmd Msg) ) -> ( Dict String UserAnimation, List (Cmd Msg) )
                step key anim ( acc, accCmds ) =
                    let
                        ( newFlip, cmd ) =
                            UI.Flip.animate animMsg anim.flip
                    in
                    ( Dict.insert key { anim | flip = newFlip } acc, cmd :: accCmds )

                ( newAnimations, cmds ) =
                    Dict.foldl step ( Dict.empty, [] ) model.userAnimations
            in
            ( { model | userAnimations = newAnimations }, Cmd.batch cmds, ( Nothing, False ) )

        RemoveUser key ->
            ( { model | userAnimations = Dict.remove key model.userAnimations }, Cmd.none, ( Nothing, False ) )

        ToggleSelected user ->
            let
                wasSelected : Bool
                wasSelected =
                    Dict.member user.id model.selected

                newSelected : Dict String User
                newSelected =
                    if wasSelected then
                        Dict.remove user.id model.selected

                    else
                        Dict.insert user.id user model.selected
            in
            if wasSelected then
                ( { model | selected = newSelected }, Cmd.none, ( Nothing, False ) )

            else
                -- Picking a recipient clears the search -- same "back to a
                -- blank slate" state `ClearSearchClicked` leaves behind --
                -- so the now-empty input is ready for the next name.
                ( { model | selected = newSelected, searchText = "", searchGeneration = model.searchGeneration + 1, usersFeed = NotSearched } |> syncAnimations
                , Cmd.none
                , ( Nothing, True )
                )

        SearchTextChanged text ->
            let
                generation : Int
                generation =
                    model.searchGeneration + 1
            in
            if String.isEmpty (String.trim text) then
                ( { model | searchText = text, searchGeneration = generation, usersFeed = NotSearched } |> syncAnimations
                , Cmd.none
                , ( Nothing, False )
                )

            else
                ( { model | searchText = text, searchGeneration = generation }
                , Process.sleep 311 |> Task.perform (\_ -> SearchDebounceElapsed generation)
                , ( Nothing, False )
                )

        SearchDebounceElapsed generation ->
            if generation == model.searchGeneration then
                ( { model | usersFeed = Loading }, fetchCmd accountsPanelModel model.host model.searchText, ( Nothing, False ) )

            else
                ( model, Cmd.none, ( Nothing, False ) )

        ClearSearchClicked ->
            ( { model | searchText = "", searchGeneration = model.searchGeneration + 1, usersFeed = NotSearched } |> syncAnimations
            , Cmd.none
            , ( Nothing, False )
            )


fetchCmd : AccountsPanel.Model -> String -> String -> Cmd Msg
fetchCmd accountsPanelModel host searchText =
    Users.fetchUserListing
        accountsPanelModel
        ( RellmAccounts.enabledRellmAccountForServer accountsPanelModel.accounts host |> Maybe.map .userId, host )
        Nothing
        EVERYONE
        searchText
        |> Task.attempt GotUsers


syncAnimations : Model -> Model
syncAnimations model =
    let
        currentUsers : Dict String User
        currentUsers =
            case model.usersFeed of
                Loaded users ->
                    users |> List.map (\user -> ( user.id, user )) |> Dict.fromList

                _ ->
                    Dict.empty
    in
    { model
        | userAnimations =
            UI.Flip.syncAnimations
                RemoveUser
                (\user -> { user = user, flip = UI.Flip.enter })
                (\user anim -> { anim | user = user })
                currentUsers
                model.userAnimations
    }



-- VIEW


view : AccountsPanel.Model -> Model -> Html Msg
view accountsPanelModel model =
    div [ class "user-picker" ]
        [ selectedChipsView model
        , searchRowView model
        , listView accountsPanelModel model
        ]


selectedChipsView : Model -> Html Msg
selectedChipsView model =
    if Dict.isEmpty model.selected then
        text ""

    else
        div [ class "user-picker-chips" ] (Dict.values model.selected |> List.map chipView)


chipView : User -> Html Msg
chipView user =
    span [ class "user-picker-chip" ]
        [ text (Users.titleName user)
        , button
            [ type_ "button"
            , class "user-picker-chip-remove"
            , onClick (ToggleSelected user)
            , title "Remove"
            ]
            [ text "╳" ]
        ]


searchRowView : Model -> Html Msg
searchRowView model =
    div [ class "filter-controls-row" ]
        [ div [ class "filter-search-field" ]
            [ input
                [ type_ "text"
                , id "user-picker-search-input"
                , classes [ "filter-search-input", "user-picker-search-input" ]
                , placeholder "Search people..."
                , value model.searchText
                , onInput SearchTextChanged
                , onEscape ClearSearchClicked
                ]
                []
            , if String.isEmpty model.searchText then
                text ""

              else
                button
                    [ type_ "button"
                    , class "field-clear-button"
                    , onClick ClearSearchClicked
                    , title "Clear search"
                    ]
                    [ text "╳" ]
            ]
        ]


onEscape : msg -> Html.Attribute msg
onEscape msg =
    preventDefaultOn "keydown"
        (Decode.field "key" Decode.string
            |> Decode.andThen
                (\key ->
                    if key == "Escape" then
                        Decode.succeed ( msg, True )

                    else
                        Decode.fail "Not the Escape key"
                )
        )


listView : AccountsPanel.Model -> Model -> Html Msg
listView accountsPanelModel model =
    case model.usersFeed of
        NotSearched ->
            text ""

        Loading ->
            p [ class "posts-empty" ] [ text "Loading…" ]

        Failed ->
            p [ class "posts-empty" ] [ text "Couldn't load people." ]

        Loaded _ ->
            let
                sortedAnimations : List ( String, UserAnimation )
                sortedAnimations =
                    model.userAnimations
                        |> Dict.toList
                        |> List.sortBy (\( _, anim ) -> String.toLower anim.user.username)
            in
            if List.isEmpty sortedAnimations then
                p [ class "posts-empty" ] [ text "No people found." ]

            else
                Html.Keyed.node "div"
                    [ classes [ "user-picker-list", "flip-animated-column" ] ]
                    (List.map (userAnimationView accountsPanelModel model) sortedAnimations)


userAnimationView : AccountsPanel.Model -> Model -> ( String, UserAnimation ) -> ( String, Html Msg )
userAnimationView accountsPanelModel model ( key, anim ) =
    let
        pointerEventsAttr : List (Html.Attribute Msg)
        pointerEventsAttr =
            if anim.flip.removing then
                [ Html.Attributes.style "pointer-events" "none" ]

            else
                []
    in
    ( key
    , div (UI.Flip.itemAttributes UI.Flip.Vertical anim.flip False)
        [ div pointerEventsAttr [ userRowView accountsPanelModel model anim.user ] ]
    )


userRowView : AccountsPanel.Model -> Model -> User -> Html Msg
userRowView accountsPanelModel model user =
    let
        isSelected : Bool
        isSelected =
            Dict.member user.id model.selected

        maybeAvatarUrl : Maybe String
        maybeAvatarUrl =
            RellmServers.rellmServerForHost accountsPanelModel.servers model.host
                |> Maybe.andThen (\server -> Users.avatarUrl server (RellmAccounts.enabledRellmAccountForServer accountsPanelModel.accounts model.host) user)

        name : String
        name =
            Users.titleName user
    in
    button
        [ type_ "button"
        , classes
            ([ "user-card", "user-picker-row", hostnameToCSSClass model.host, "border-color-primary-anchor-50", "hover-border-color-primary-anchor", "background-color-primary-5" ]
                ++ (if isSelected then
                        [ "selected" ]

                    else
                        []
                   )
            )
        , onClick (ToggleSelected user)
        ]
        [ avatarView name maybeAvatarUrl
        , span [ class "user-card-details" ] [ text name ]
        , if isSelected then
            span [ class "user-picker-row-check" ] [ text "✓" ]

          else
            text ""
        ]


avatarView : String -> Maybe String -> Html Msg
avatarView name maybeUrl =
    case maybeUrl of
        Just url ->
            img [ class "user-card-avatar", src url, alt name, attribute "loading" "lazy" ] []

        Nothing ->
            div [ classes [ "user-card-avatar", "placeholder" ] ] [ text (RellmServers.initialLetter name) ]
