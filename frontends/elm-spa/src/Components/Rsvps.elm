module Components.Rsvps exposing
    ( Model
    , Msg
    , Outcome
    , ViewConfig
    , init
    , newAnonymousRsvpConfirmed
    , occasionIdOf
    , parseAnonymousAuthToken
    , rsvpsAllowed
    , setAnonymousAuthToken
    , update
    , view
    )

{-| The RSVP UI for a single `Occasion` -- the Elm counterpart of the Tamagui app's
`EventRsvpManager`/`RsvpCard`. Used by both `Components.Pages.EventPage` (the full detail view,
including the list of everyone's RSVPs) and `Components.Pages.EventsPage`'s cards (`compact`:
just the RSVP buttons/form and a summary line linking through to the detail page).

**No RSVP-specific fetching, ever.** Unlike the React app's `loadRsvpData`, this never calls
`GetRsvps`: `GetEvents` already attaches `Occasion.rsvps`/`current_user_rsvp` for _every_ returned
occasion in a single batched query (see `backend/src/rpcs/events/get_events.rs`'s
`attach_occasion_rsvps`), honoring the same visibility rules `GetRsvps` does -- so the page's
existing `GetEvents` fetch (given the viewer's `anonymous_attendee_auth_token`, if any) is the
only read. Mutations (`UpsertRsvp`/`DeleteRsvp`) are recorded here as `Edit`s, which `applyEdits`
overlays onto whatever `Occasion` the host currently has -- so a host never has to
rewrite its own `Event`/`Occasion` storage, and a later refetch (which already includes those
changes) simply makes the overlay a no-op.

One `Model` per `Occasion` (hosts keep a `Dict` keyed by `occasionIdOf`). Instead of
copying the current RSVP into form fields (and syncing them back and forth), `Model.pending` only
holds what the viewer has _changed_; every displayed value is `pending ?? current RSVP ?? default`.

Unlike the React UI, only the status buttons save immediately (as there); name/guest-count/note
edits wait for an explicit Save, rather than being debounce-autosaved.

-}

import Components.Authors as Authors
import Components.Events as Events
import Components.Markdown as Markdown
import Components.Posts as Posts
import Grpc
import Html exposing (Html, a, button, div, h3, option, p, select, span, text, textarea)
import Html.Attributes exposing (attribute, class, disabled, href, placeholder, rel, selected, target, value)
import Html.Events exposing (onClick, onInput)
import Proto.Google.Protobuf
import Proto.Rellm
    exposing
        ( Event
        , Occasion
        , Rsvp
        , defaultAnonymousAttendee
        , defaultRsvp
        , defaultUserAttendee
        , wrapMediaReference
        )
import Proto.Rellm.Moderation exposing (Moderation(..))
import Proto.Rellm.Permission exposing (Permission(..))
import Proto.Rellm.Rellm as Rellm
import Proto.Rellm.Rsvp.Attendee as Attendee
import Proto.Rellm.RsvpStatus exposing (RsvpStatus(..))
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer, withAccessToken)
import Task exposing (Task)
import Time
import UI.Classes exposing (classes, openClosedClass)


type Mode
    = UserMode
    | AnonymousMode


{-| A mutation this viewer has made, overlaid onto the host's `Occasion` by `applyEdits`.
-}
type Edit
    = Upserted Rsvp
    | Deleted String


type SubmitStatus
    = Idle
    | Saving
    | Deleting
    | Failed String


{-| What the viewer has changed in the form so far -- `Nothing` means "not touched, show whatever
the current RSVP (or the default) says".
-}
type alias Pending =
    { status : Maybe RsvpStatus
    , name : Maybe String
    , guests : Maybe Int
    , publicNote : Maybe String
    , privateNote : Maybe String
    }


type alias Model =
    { edits : List Edit
    , mode : Maybe Mode
    , pending : Pending
    , showDetails : Bool
    , showCards : Bool

    -- Whether the list of everyone's RSVPs has ever been opened: it's only mounted from then on, so
    -- it can animate closed (see `.rsvp-cards-wrap`) without every card in a long listing paying
    -- for a list nobody opened.
    , cardsEverShown : Bool
    , confirmingDelete : Bool
    , submit : SubmitStatus

    -- The anonymous attendee's private token for this occasion (from the page's
    -- `?anonymousAuthToken=`, or assigned by the server on first anonymous RSVP).
    , anonymousAuthToken : Maybe String
    }


type Msg
    = ModeClicked Mode
    | StatusClicked RsvpStatus
    | NameChanged String
    | GuestsChanged String
    | PublicNoteChanged String
    | PrivateNoteChanged String
    | ToggleDetails
    | ToggleCards
    | SaveClicked
    | DeleteClicked
    | DeleteCancelled
    | DeleteConfirmed
    | NewAnonymousRsvpClicked
    | NewAnonymousRsvpConfirmed
    | EditClicked Mode
    | ModerationChanged Rsvp String
    | GotUpsert Bool (Result Grpc.Error ( Maybe AccountsPanel.Msg, Rsvp ))
    | GotDelete Rsvp (Result Grpc.Error ( Maybe AccountsPanel.Msg, Proto.Google.Protobuf.Empty ))


{-| What `update` needs from its host.
-}
type alias Context =
    { accounts : AccountsPanel.Model
    , targetHost : String
    , event : Event
    , occasion : Occasion
    }


{-| What a host has to do about an `update` beyond storing the new `Model`.
`tokenChange` is `Just newToken` when the anonymous auth token changed (`Nothing` inside meaning
"cleared") -- `EventPage` mirrors it into the URL so the private link survives a reload.
-}
type alias Outcome =
    { accountsPanelMsg : Maybe AccountsPanel.Msg
    , tokenChange : Maybe (Maybe String)

    -- "New RSVP" was clicked: the host should ask for confirmation
    -- (`Shared.ConfirmNewAnonymousRsvp`) and, once confirmed, send back `newAnonymousRsvpConfirmed`
    -- -- starting over forgets the current private link, so it's not done on a bare click.
    , confirmNewAnonymousRsvp : Bool
    }


type alias ViewConfig =
    { basePath : String
    , viewingServerHost : String
    , eventServerHost : String
    , maybeServer : Maybe RellmServer
    , maybeAccount : Maybe RellmAccount
    , now : Time.Posix

    -- Compact (card) mode: no list of everyone's RSVPs, the summary links to `occasionPath`
    -- instead of expanding it.
    , compact : Bool
    , event : Event
    , occasion : Occasion
    }



-- INIT


{-| `anonymousAuthToken` is the viewer's token for this occasion, if the page URL carried one --
see `parseAnonymousAuthToken`. `showCards` pre-expands the list of everyone's RSVPs (the
`?section=rsvp` link).
-}
init : Maybe String -> Bool -> Model
init anonymousAuthToken showCards =
    { edits = []
    , mode =
        if anonymousAuthToken /= Nothing then
            Just AnonymousMode

        else
            Nothing
    , pending = noPending
    , showDetails = False
    , showCards = showCards
    , cardsEverShown = showCards
    , confirmingDelete = False
    , submit = Idle
    , anonymousAuthToken = anonymousAuthToken
    }


noPending : Pending
noPending =
    { status = Nothing, name = Nothing, guests = Nothing, publicNote = Nothing, privateNote = Nothing }


{-| The `anonymousAuthToken` query parameter's value for `occasionId`. Accepts both the plain
`<token>` form (saveable per-occasion links; applies to whichever occasion the page is about) and
the `<occasionId>-<token>--<occasionId>-<token>` multi-occasion form, which can hold one token per
occasion for pages that show several (the web frontends all share this format, and the backend
accepts it too -- see `rpcs::events::parse_anonymous_auth_tokens`).
-}
parseAnonymousAuthToken : String -> String -> Maybe String
parseAnonymousAuthToken occasionId raw =
    let
        trimmed : String
        trimmed =
            String.trim raw
    in
    if String.isEmpty trimmed then
        Nothing

    else if not (String.contains "-" trimmed) then
        Just trimmed

    else
        tokenPairs trimmed
            |> List.filter (\( id, _ ) -> id == occasionId)
            |> List.head
            |> Maybe.map Tuple.second


tokenPairs : String -> List ( String, String )
tokenPairs raw =
    raw
        |> String.split "--"
        |> List.filterMap
            (\part ->
                case String.split "-" (String.trim part) of
                    [ id, token ] ->
                        if String.isEmpty id || String.isEmpty token then
                            Nothing

                        else
                            Just ( id, token )

                    _ ->
                        Nothing
            )


{-| The new raw `anonymousAuthToken` parameter after `occasionId`'s token becomes `newToken`
(`Nothing` removes it), keeping every other occasion's token -- always written in the
`<occasionId>-<token>--...` form; `Nothing` once none are left. A plain-form `raw` (see
`parseAnonymousAuthToken`) is by definition `occasionId`'s own, so it's replaced outright.
-}
setAnonymousAuthToken : String -> Maybe String -> Maybe String -> Maybe String
setAnonymousAuthToken occasionId newToken raw =
    let
        others : List ( String, String )
        others =
            case raw of
                Just value ->
                    if String.contains "-" value then
                        tokenPairs value |> List.filter (\( id, _ ) -> id /= occasionId)

                    else
                        []

                Nothing ->
                    []

        pairs : List ( String, String )
        pairs =
            case newToken of
                Just token ->
                    others ++ [ ( occasionId, token ) ]

                Nothing ->
                    others
    in
    if List.isEmpty pairs then
        Nothing

    else
        pairs |> List.map (\( id, token ) -> id ++ "-" ++ token) |> String.join "--" |> Just


{-| What a host sends back to a card/page's `Model` once its `Shared.ConfirmNewAnonymousRsvp`
modal is confirmed -- see `Outcome.confirmNewAnonymousRsvp`.
-}
newAnonymousRsvpConfirmed : Msg
newAnonymousRsvpConfirmed =
    NewAnonymousRsvpConfirmed


occasionIdOf : Occasion -> String
occasionIdOf occasion =
    occasion.post |> Maybe.map .id |> Maybe.withDefault ""



-- DATA


{-| Whether RSVPs are on for this occasion at all (`Occasion.info.rsvp_info` overrides
`Event.info`), and whether anonymous ones are.
-}
rsvpsAllowed : Event -> Occasion -> ( Bool, Bool )
rsvpsAllowed event occasion =
    let
        override : Maybe Proto.Rellm.OccasionRsvpInfo
        override =
            occasion.info |> Maybe.andThen .rsvpInfo

        allows : Bool
        allows =
            override
                |> Maybe.andThen .allowsRsvps
                |> orElse (event.info |> Maybe.andThen .allowsRsvps)
                |> Maybe.withDefault False

        allowsAnonymous : Bool
        allowsAnonymous =
            override
                |> Maybe.andThen .allowsAnonymousRsvps
                |> orElse (event.info |> Maybe.andThen .allowsAnonymousRsvps)
                |> Maybe.withDefault False
    in
    ( allows, allows && allowsAnonymous )


orElse : Maybe a -> Maybe a -> Maybe a
orElse fallback primary =
    case primary of
        Just _ ->
            primary

        Nothing ->
            fallback


{-| `occasion` with this viewer's own mutations overlaid -- see the module doc.
-}
applyEdits : Model -> Occasion -> Occasion
applyEdits model occasion =
    if List.isEmpty model.edits then
        occasion

    else
        let
            base : Proto.Rellm.Rsvps
            base =
                occasion.rsvps |> Maybe.withDefault Proto.Rellm.defaultRsvps

            applied : List Rsvp
            applied =
                List.foldl applyEdit base.rsvps model.edits
        in
        { occasion | rsvps = Just { base | rsvps = applied } }


applyEdit : Edit -> List Rsvp -> List Rsvp
applyEdit edit rsvps =
    case edit of
        Upserted rsvp ->
            if List.any (\r -> r.id == rsvp.id) rsvps then
                List.map
                    (\r ->
                        if r.id == rsvp.id then
                            rsvp

                        else
                            r
                    )
                    rsvps

            else
                rsvp :: rsvps

        Deleted id ->
            List.filter (\r -> r.id /= id) rsvps


rsvpsOf : Occasion -> List Rsvp
rsvpsOf occasion =
    occasion.rsvps |> Maybe.map .rsvps |> Maybe.withDefault []


userRsvp : Maybe RellmAccount -> List Rsvp -> Maybe Rsvp
userRsvp maybeAccount rsvps =
    maybeAccount
        |> Maybe.andThen
            (\account ->
                rsvps
                    |> List.filter
                        (\rsvp ->
                            case rsvp.attendee of
                                Just (Attendee.UserAttendee user) ->
                                    user.userId == account.userId

                                _ ->
                                    False
                        )
                    |> List.head
            )


anonymousRsvp : Maybe String -> List Rsvp -> Maybe Rsvp
anonymousRsvp maybeToken rsvps =
    maybeToken
        |> Maybe.andThen
            (\token ->
                rsvps
                    |> List.filter
                        (\rsvp ->
                            case rsvp.attendee of
                                Just (Attendee.AnonymousAttendee anonymous) ->
                                    anonymous.authToken == Just token

                                _ ->
                                    False
                        )
                    |> List.head
            )


passes : Moderation -> Bool
passes moderation =
    moderation /= PENDING && moderation /= REJECTED


statusName : Bool -> RsvpStatus -> String
statusName isPast status =
    case status of
        GOING ->
            if isPast then
                "Went"

            else
                "Going"

        INTERESTED ->
            "Interested"

        NOTGOING ->
            if isPast then
                "Didn't Go"

            else
                "Not Going"

        REQUESTED ->
            "Invited"

        RsvpStatusUnrecognized_ _ ->
            "Unknown"


moderationDescription : Moderation -> String
moderationDescription moderation =
    case moderation of
        REJECTED ->
            "Rejected by the event owner. Visible only to attendee and owner."

        PENDING ->
            "Awaiting approval by the event owner. Visible only to attendee and owner."

        _ ->
            "Visible to anyone who can view this event."


{-| What the form currently shows/would submit, given `current` (the RSVP being edited, if any).
-}
type alias FormValues =
    { status : Maybe RsvpStatus
    , name : String
    , guests : Int
    , publicNote : String
    , privateNote : String
    }


formValues : Model -> Maybe Rsvp -> FormValues
formValues model current =
    { status = model.pending.status |> orElse (current |> Maybe.map .status)
    , name =
        model.pending.name
            |> orElse
                (current
                    |> Maybe.andThen
                        (\rsvp ->
                            case rsvp.attendee of
                                Just (Attendee.AnonymousAttendee anonymous) ->
                                    Just anonymous.name

                                _ ->
                                    Nothing
                        )
                )
            |> Maybe.withDefault ""
    , guests = model.pending.guests |> orElse (current |> Maybe.map .numberOfGuests) |> Maybe.withDefault 1
    , publicNote = model.pending.publicNote |> orElse (current |> Maybe.map .publicNote) |> Maybe.withDefault ""
    , privateNote = model.pending.privateNote |> orElse (current |> Maybe.map .privateNote) |> Maybe.withDefault ""
    }


{-| The RSVP the form is editing: this viewer's own, in whichever mode is open.
-}
editingRsvp : Model -> Maybe RellmAccount -> List Rsvp -> Maybe Rsvp
editingRsvp model maybeAccount rsvps =
    case model.mode of
        Just UserMode ->
            userRsvp maybeAccount rsvps

        Just AnonymousMode ->
            anonymousRsvp model.anonymousAuthToken rsvps

        Nothing ->
            Nothing


hasModified : Model -> Maybe Rsvp -> Bool
hasModified model current =
    case current of
        Nothing ->
            False

        Just rsvp ->
            let
                values : FormValues
                values =
                    formValues model current

                currentName : String
                currentName =
                    case rsvp.attendee of
                        Just (Attendee.AnonymousAttendee anonymous) ->
                            anonymous.name

                        _ ->
                            values.name
            in
            values.status
                /= Just rsvp.status
                || values.guests
                /= rsvp.numberOfGuests
                || values.publicNote
                /= rsvp.publicNote
                || values.privateNote
                /= rsvp.privateNote
                || values.name
                /= currentName


{-| Whether enough is known to submit: signed in (user mode), or a name entered (anonymous).
-}
canSubmit : Model -> Maybe RellmAccount -> FormValues -> Bool
canSubmit model maybeAccount values =
    case model.mode of
        Just UserMode ->
            maybeAccount /= Nothing

        Just AnonymousMode ->
            not (String.isEmpty (String.trim values.name))

        Nothing ->
            False


buildRsvp : Model -> Context -> Maybe RellmAccount -> FormValues -> RsvpStatus -> Rsvp
buildRsvp model ctx maybeAccount values status =
    { defaultRsvp
        | occasionId = occasionIdOf ctx.occasion
        , attendee =
            case model.mode of
                Just UserMode ->
                    Just (Attendee.UserAttendee { defaultUserAttendee | userId = maybeAccount |> Maybe.map .userId |> Maybe.withDefault "" })

                _ ->
                    Just
                        (Attendee.AnonymousAttendee
                            { defaultAnonymousAttendee | name = String.trim values.name, authToken = model.anonymousAuthToken }
                        )
        , status = status
        , numberOfGuests = values.guests
        , publicNote = values.publicNote
        , privateNote = values.privateNote
    }



-- RPCs


accountServerFor : Context -> AccountsPanel.MaybeAccountServer
accountServerFor ctx =
    ( RellmAccounts.enabledRellmAccountForServer ctx.accounts.accounts ctx.targetHost |> Maybe.map .userId
    , ctx.targetHost
    )


{-| Anonymous-capable (so `performWithOptionalAccountServer`, not `performWithAccountServer`)
-- both RPCs are open to logged-out viewers for anonymous RSVPs.
-}
upsertTask : Context -> Rsvp -> Task Grpc.Error ( Maybe AccountsPanel.Msg, Rsvp )
upsertTask ctx rsvp =
    AccountsPanel.performWithOptionalAccountServer ctx.accounts
        (accountServerFor ctx)
        (\server maybeToken ->
            Grpc.new Rellm.upsertRsvp rsvp
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken maybeToken
                |> Grpc.toTask
        )


deleteTask : Context -> Rsvp -> Task Grpc.Error ( Maybe AccountsPanel.Msg, Proto.Google.Protobuf.Empty )
deleteTask ctx rsvp =
    AccountsPanel.performWithOptionalAccountServer ctx.accounts
        (accountServerFor ctx)
        (\server maybeToken ->
            Grpc.new Rellm.deleteRsvp rsvp
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken maybeToken
                |> Grpc.toTask
        )



-- UPDATE


noOutcome : Outcome
noOutcome =
    { accountsPanelMsg = Nothing, tokenChange = Nothing, confirmNewAnonymousRsvp = False }


update : Context -> Msg -> Model -> ( Model, Cmd Msg, Outcome )
update ctx msg model =
    let
        maybeAccount : Maybe RellmAccount
        maybeAccount =
            RellmAccounts.enabledRellmAccountForServer ctx.accounts.accounts ctx.targetHost

        rsvps : List Rsvp
        rsvps =
            rsvpsOf (applyEdits model ctx.occasion)

        current : Maybe Rsvp
        current =
            editingRsvp model maybeAccount rsvps

        values : FormValues
        values =
            formValues model current

        busy : Bool
        busy =
            model.submit == Saving || model.submit == Deleting

        pendingChanged : (Pending -> Pending) -> ( Model, Cmd Msg, Outcome )
        pendingChanged change =
            ( { model | pending = change model.pending, submit = Idle }, Cmd.none, noOutcome )

        save : RsvpStatus -> ( Model, Cmd Msg, Outcome )
        save status =
            ( { model | submit = Saving }
            , upsertTask ctx (buildRsvp model ctx maybeAccount values status)
                |> Task.attempt (GotUpsert True)
            , noOutcome
            )
    in
    case msg of
        ModeClicked mode ->
            ( { model
                | mode =
                    if model.mode == Just mode then
                        Nothing

                    else
                        Just mode
                , pending = noPending
                , confirmingDelete = False
                , submit = Idle
              }
            , Cmd.none
            , noOutcome
            )

        EditClicked mode ->
            ( { model | mode = Just mode, pending = noPending, confirmingDelete = False, submit = Idle }, Cmd.none, noOutcome )

        StatusClicked status ->
            let
                updated : Model
                updated =
                    { model | pending = (\p -> { p | status = Just status }) model.pending }
            in
            if canSubmit model maybeAccount values && not busy then
                let
                    ( savingModel, cmd, outcome ) =
                        update ctx SaveClicked updated
                in
                ( savingModel, cmd, outcome )

            else
                ( updated, Cmd.none, noOutcome )

        NameChanged name ->
            pendingChanged (\p -> { p | name = Just name })

        GuestsChanged raw ->
            pendingChanged (\p -> { p | guests = String.toInt raw |> Maybe.map (clamp 1 52) |> orElse p.guests })

        PublicNoteChanged note ->
            pendingChanged (\p -> { p | publicNote = Just note })

        PrivateNoteChanged note ->
            pendingChanged (\p -> { p | privateNote = Just note })

        ToggleDetails ->
            ( { model | showDetails = not model.showDetails }, Cmd.none, noOutcome )

        ToggleCards ->
            ( { model | showCards = not model.showCards, cardsEverShown = True }, Cmd.none, noOutcome )

        SaveClicked ->
            case values.status of
                Just status ->
                    if canSubmit model maybeAccount values && not busy then
                        save status

                    else
                        ( model, Cmd.none, noOutcome )

                Nothing ->
                    ( model, Cmd.none, noOutcome )

        DeleteClicked ->
            ( { model | confirmingDelete = True }, Cmd.none, noOutcome )

        DeleteCancelled ->
            ( { model | confirmingDelete = False }, Cmd.none, noOutcome )

        DeleteConfirmed ->
            case current of
                Just rsvp ->
                    ( { model | submit = Deleting, confirmingDelete = False }
                    , deleteTask ctx rsvp |> Task.attempt (GotDelete rsvp)
                    , noOutcome
                    )

                Nothing ->
                    ( { model | confirmingDelete = False }, Cmd.none, noOutcome )

        NewAnonymousRsvpClicked ->
            ( model, Cmd.none, { noOutcome | confirmNewAnonymousRsvp = True } )

        NewAnonymousRsvpConfirmed ->
            ( { model | anonymousAuthToken = Nothing, pending = noPending, submit = Idle }
            , Cmd.none
            , { noOutcome | tokenChange = Just Nothing }
            )

        ModerationChanged rsvp raw ->
            case moderationFromString raw of
                Just moderation ->
                    ( { model | submit = Saving }
                    , upsertTask ctx { rsvp | moderation = moderation } |> Task.attempt (GotUpsert False)
                    , noOutcome
                    )

                Nothing ->
                    ( model, Cmd.none, noOutcome )

        GotUpsert ownForm (Ok ( accountsPanelMsg, rsvp )) ->
            let
                newToken : Maybe String
                newToken =
                    case rsvp.attendee of
                        Just (Attendee.AnonymousAttendee anonymous) ->
                            if ownForm then
                                anonymous.authToken

                            else
                                model.anonymousAuthToken

                        _ ->
                            model.anonymousAuthToken
            in
            ( { model
                | edits = model.edits ++ [ Upserted rsvp ]
                , pending =
                    if ownForm then
                        noPending

                    else
                        model.pending
                , submit = Idle
                , anonymousAuthToken = newToken
              }
            , Cmd.none
            , { noOutcome
                | accountsPanelMsg = accountsPanelMsg
                , tokenChange =
                    if newToken /= model.anonymousAuthToken then
                        Just newToken

                    else
                        Nothing
              }
            )

        GotUpsert _ (Err err) ->
            ( { model | submit = Failed (AccountsPanel.grpcErrorToString err) }, Cmd.none, noOutcome )

        GotDelete rsvp (Ok ( accountsPanelMsg, _ )) ->
            let
                wasAnonymous : Bool
                wasAnonymous =
                    case rsvp.attendee of
                        Just (Attendee.AnonymousAttendee _) ->
                            model.mode == Just AnonymousMode

                        _ ->
                            False
            in
            ( { model
                | edits = model.edits ++ [ Deleted rsvp.id ]
                , pending = noPending
                , submit = Idle
                , mode = Nothing
                , anonymousAuthToken =
                    if wasAnonymous then
                        Nothing

                    else
                        model.anonymousAuthToken
              }
            , Cmd.none
            , { noOutcome
                | accountsPanelMsg = accountsPanelMsg
                , tokenChange =
                    if wasAnonymous then
                        Just Nothing

                    else
                        Nothing
              }
            )

        GotDelete _ (Err err) ->
            ( { model | submit = Failed (AccountsPanel.grpcErrorToString err) }, Cmd.none, noOutcome )


moderationFromString : String -> Maybe Moderation
moderationFromString raw =
    case raw of
        "approved" ->
            Just APPROVED

        "pending" ->
            Just PENDING

        "rejected" ->
            Just REJECTED

        "unmoderated" ->
            Just UNMODERATED

        _ ->
            Nothing


moderationToString : Moderation -> String
moderationToString moderation =
    case moderation of
        APPROVED ->
            "approved"

        PENDING ->
            "pending"

        REJECTED ->
            "rejected"

        _ ->
            "unmoderated"



-- VIEW


{-| Renders nothing at all when RSVPs aren't enabled for this occasion.
-}
view : (Msg -> msg) -> ViewConfig -> Model -> Html msg
view toMsg cfg model =
    let
        ( allowsRsvps, allowsAnonymous ) =
            rsvpsAllowed cfg.event cfg.occasion
    in
    if allowsRsvps then
        Html.map toMsg (blockView cfg allowsAnonymous model)

    else
        text ""


blockView : ViewConfig -> Bool -> Model -> Html Msg
blockView cfg allowsAnonymous model =
    let
        occasion : Occasion
        occasion =
            applyEdits model cfg.occasion

        rsvps : List Rsvp
        rsvps =
            rsvpsOf occasion

        canRsvpAsUser : Bool
        canRsvpAsUser =
            cfg.maybeAccount
                |> Maybe.map (\account -> List.member RSVPTOEVENTS account.permissions)
                |> Maybe.withDefault False

        currentUser : Maybe Rsvp
        currentUser =
            userRsvp cfg.maybeAccount rsvps

        currentAnon : Maybe Rsvp
        currentAnon =
            anonymousRsvp model.anonymousAuthToken rsvps

        isPast : Bool
        isPast =
            Events.occasionEndsOrStartsAt occasion
                |> Maybe.map (\at -> Time.posixToMillis at < Time.posixToMillis cfg.now)
                |> Maybe.withDefault False

        isOwner : Bool
        isOwner =
            case ( cfg.maybeAccount, cfg.event.post ) of
                ( Just account, Just post ) ->
                    Posts.isAuthor account post

                _ ->
                    False

        modeButton : Mode -> Maybe Rsvp -> String -> Html Msg
        modeButton mode currentForMode label =
            button
                [ classes
                    [ "rsvp-mode-button"
                    , if model.mode == Just mode then
                        "rsvp-mode-button-open"

                      else
                        "rsvp-mode-button-closed"
                    ]
                , onClick (ModeClicked mode)
                , disabled (model.submit == Saving || model.submit == Deleting)
                , attribute "aria-expanded"
                    (if model.mode == Just mode then
                        "true"

                     else
                        "false"
                    )
                ]
                [ span [ classes [ "rsvp-mode-button-icon", openClosedClass (model.mode == Just mode) ] ]
                    [ -- Three glyphs cross-fading/rotating in place rather than one being swapped
                      -- for another: a chevron while the form is open, else a "+" (no RSVP yet,
                      -- turning 45° into an "x"-like shape as it opens) or a pencil (editing one).
                      span [ classes [ "rsvp-mode-icon-chevron", openClosedClass (model.mode == Just mode) ] ] [ text "▼" ]
                    , span
                        [ classes
                            [ "rsvp-mode-icon-plus"
                            , openClosedClass (model.mode /= Just mode && currentForMode == Nothing)
                            ]
                        ]
                        [ text "＋" ]
                    , span
                        [ classes
                            [ "rsvp-mode-icon-edit"
                            , openClosedClass (model.mode /= Just mode && currentForMode /= Nothing)
                            ]
                        ]
                        [ text "✎" ]
                    ]
                , span [ class "rsvp-mode-button-label" ]
                    [ text label
                    , span [ class "rsvp-mode-button-status" ]
                        [ text
                            (case currentForMode of
                                Just rsvp ->
                                    statusName isPast rsvp.status

                                Nothing ->
                                    "RSVP"
                            )
                        ]
                    ]
                ]
    in
    div [ classes [ "event-rsvps", "background-color-primary-5" ] ]
        [ if canRsvpAsUser || allowsAnonymous then
            div [ class "rsvp-mode-buttons" ]
                [ if canRsvpAsUser then
                    modeButton UserMode currentUser "RSVP"

                  else
                    text ""
                , if allowsAnonymous then
                    modeButton AnonymousMode currentAnon "Anonymously"

                  else
                    text ""
                ]

          else
            p [ class "rsvp-login-hint" ] [ text "Log in to RSVP." ]
        , case model.mode of
            Just mode ->
                formView cfg isPast mode model currentUser currentAnon

            Nothing ->
                text ""
        , summaryView cfg model isOwner occasion
        , if model.cardsEverShown then
            cardsView cfg isPast isOwner model rsvps currentUser currentAnon

          else
            text ""
        ]


formView : ViewConfig -> Bool -> Mode -> Model -> Maybe Rsvp -> Maybe Rsvp -> Html Msg
formView cfg isPast mode model currentUser currentAnon =
    let
        editing : Maybe Rsvp
        editing =
            case mode of
                UserMode ->
                    currentUser

                AnonymousMode ->
                    currentAnon

        values : FormValues
        values =
            formValues model editing

        busy : Bool
        busy =
            model.submit == Saving || model.submit == Deleting

        submittable : Bool
        submittable =
            canSubmit model cfg.maybeAccount values

        modified : Bool
        modified =
            hasModified model editing

        statusButton : RsvpStatus -> Html Msg
        statusButton status =
            button
                [ classes
                    [ "rsvp-status-button"
                    , if values.status == Just status then
                        "rsvp-status-button-selected"

                      else
                        "rsvp-status-button-unselected"
                    ]
                , onClick (StatusClicked status)
                , disabled (not submittable || busy)
                , attribute "aria-pressed"
                    (if values.status == Just status then
                        "true"

                     else
                        "false"
                    )
                ]
                [ text (statusName isPast status) ]
    in
    div [ class "rsvp-form" ]
        [ case mode of
            AnonymousMode ->
                div [ class "rsvp-anonymous-header" ]
                    [ if model.anonymousAuthToken /= Nothing && currentAnon == Nothing then
                        p [ class "rsvp-note" ]
                            [ text "Your anonymous RSVP token was not found. Check the link you used to get here, or just create a new anonymous RSVP." ]

                      else
                        text ""
                    , Html.input
                        [ class "rsvp-name-input"
                        , placeholder "Anonymous Guest Name (required)"
                        , value values.name
                        , onInput NameChanged
                        , attribute "autocomplete" "name"
                        ]
                        []
                    ]

            UserMode ->
                text ""
        , button [ class "rsvp-details-toggle", onClick ToggleDetails, attribute "aria-expanded" (boolAttr model.showDetails) ]
            [ span [ classes [ "expandable-section-arrow", openClosedClass model.showDetails ] ] [ text "▼" ]
            , text " Attendees & Notes"
            ]
        , if model.showDetails then
            div [ class "rsvp-details" ]
                [ select [ class "rsvp-guests-select", onInput GuestsChanged ]
                    (List.range 1 52
                        |> List.map
                            (\n ->
                                option [ value (String.fromInt n), selected (n == values.guests) ]
                                    [ text
                                        (String.fromInt n
                                            ++ (if n == 1 then
                                                    " attendee"

                                                else
                                                    " attendees"
                                               )
                                        )
                                    ]
                            )
                    )
                , textarea
                    [ class "rsvp-note-input"
                    , placeholder "Public note (optional). Markdown is supported."
                    , value values.publicNote
                    , onInput PublicNoteChanged
                    ]
                    []
                , textarea
                    [ class "rsvp-note-input"
                    , placeholder "Private note for the event owner (optional). Markdown is supported."
                    , value values.privateNote
                    , onInput PrivateNoteChanged
                    ]
                    []
                ]

          else
            text ""
        , case ( mode, model.anonymousAuthToken ) of
            ( AnonymousMode, Nothing ) ->
                div [ class "rsvp-anonymous-explainer" ]
                    [ p [] [ text "• You will be assigned a private RSVP link." ]
                    , p [] [ text "• Use it to edit or delete your RSVP later." ]
                    , p [] [ text "• Save it in your browser bookmarks, notes app, or calendar app of choice." ]
                    ]

            _ ->
                text ""
        , div [ class "rsvp-status-row" ]
            [ div [ class "rsvp-status-buttons" ]
                [ statusButton GOING, statusButton INTERESTED, statusButton NOTGOING ]
            , span [ class "rsvp-save-indicator" ] [ text (saveIndicator model editing modified) ]
            ]
        , if not submittable then
            p [ class "rsvp-note" ]
                [ text
                    (case mode of
                        AnonymousMode ->
                            "Enter a name to RSVP anonymously."

                        UserMode ->
                            "Log in to RSVP."
                    )
                ]

          else
            text ""
        , case model.submit of
            Failed err ->
                p [ class "rsvp-error" ] [ text err ]

            _ ->
                text ""
        , case ( mode, model.anonymousAuthToken, currentAnon ) of
            ( AnonymousMode, Just token, Just _ ) ->
                let
                    occasionPath : String
                    occasionPath =
                        Events.occasionHref cfg.basePath cfg.viewingServerHost cfg.eventServerHost cfg.occasion
                in
                p [ class "rsvp-note" ]
                    [ text "Save "
                    , a [ href (occasionPath ++ "?anonymousAuthToken=" ++ token), target "_blank", rel "noopener noreferrer" ] [ text "this private RSVP link" ]
                    , text " to update your RSVP later."
                    ]

            _ ->
                text ""
        , div [ class "rsvp-form-actions" ]
            [ if modified && submittable then
                button
                    [ classes [ "post-visibility-save", "background-color-primary" ]
                    , onClick SaveClicked
                    , disabled busy
                    ]
                    [ text "Save" ]

              else
                text ""
            , if mode == AnonymousMode && model.anonymousAuthToken /= Nothing then
                button [ class "post-visibility-cancel", onClick NewAnonymousRsvpClicked, disabled busy ] [ text "New RSVP" ]

              else
                text ""
            , case editing of
                Just _ ->
                    if model.confirmingDelete then
                        span [ class "rsvp-confirm-delete" ]
                            [ text "Really delete this RSVP? "
                            , button [ class "post-visibility-cancel", onClick DeleteCancelled ] [ text "Cancel" ]
                            , button [ class "post-visibility-cancel", onClick DeleteConfirmed, disabled busy ] [ text "Delete" ]
                            ]

                    else
                        button [ class "post-visibility-cancel", onClick DeleteClicked, disabled busy ] [ text "Delete" ]

                Nothing ->
                    text ""
            ]
        ]


saveIndicator : Model -> Maybe Rsvp -> Bool -> String
saveIndicator model editing modified =
    case model.submit of
        Saving ->
            "Saving…"

        Deleting ->
            "Deleting…"

        _ ->
            if modified then
                "⚠ Unsaved changes"

            else
                case editing of
                    Just rsvp ->
                        if rsvp.moderation == REJECTED then
                            "⚠ Rejected by the event owner. Update your RSVP to re-submit for approval."

                        else if rsvp.moderation == PENDING then
                            "🛡 Saved. Hidden from others until the event owner approves."

                        else
                            "✓ Saved"

                    Nothing ->
                        ""


boolAttr : Bool -> String
boolAttr b =
    if b then
        "true"

    else
        "false"


{-| (RSVP count, attendee count) per bucket -- see `Proto.Rellm.Rsvps`' own doc for what each
covers (status buckets: moderation-passing only; `pending`: `PENDING`; rejected: not counted).
-}
type alias Totals =
    { going : ( Int, Int )
    , interested : ( Int, Int )
    , requested : ( Int, Int )
    , notGoing : ( Int, Int )
    , pending : ( Int, Int )
    }


emptyTotals : Totals
emptyTotals =
    { going = ( 0, 0 ), interested = ( 0, 0 ), requested = ( 0, 0 ), notGoing = ( 0, 0 ), pending = ( 0, 0 ) }


localTotals : List Rsvp -> Totals
localTotals =
    let
        bump : Rsvp -> ( Int, Int ) -> ( Int, Int )
        bump rsvp ( rsvpCount, attendees ) =
            ( rsvpCount + 1, attendees + rsvp.numberOfGuests )

        add : Rsvp -> Totals -> Totals
        add rsvp totals =
            if rsvp.moderation == PENDING then
                { totals | pending = bump rsvp totals.pending }

            else if passes rsvp.moderation then
                case rsvp.status of
                    GOING ->
                        { totals | going = bump rsvp totals.going }

                    INTERESTED ->
                        { totals | interested = bump rsvp totals.interested }

                    REQUESTED ->
                        { totals | requested = bump rsvp totals.requested }

                    NOTGOING ->
                        { totals | notGoing = bump rsvp totals.notGoing }

                    RsvpStatusUnrecognized_ _ ->
                        totals

            else
                totals
    in
    List.foldl add emptyTotals


{-| What to display as the occasion's RSVP totals. `GetEvents` caps how many `rsvps` it returns
per occasion but always reports the full totals on `Rsvps` (see its proto doc), so those are the
source of truth -- adjusted by however this viewer's own `edits` changed the loaded RSVPs since
(a refetch's totals already include those changes, which is why this is a delta, and why it never
drops below what's actually loaded).
-}
totalsFor : Model -> Occasion -> Totals
totalsFor model occasion =
    let
        loaded : List Rsvp
        loaded =
            rsvpsOf occasion

        applied : Totals
        applied =
            localTotals (rsvpsOf (applyEdits model occasion))

        before : Totals
        before =
            localTotals loaded

        server : Totals
        server =
            case occasion.rsvps of
                Just r ->
                    { going = ( r.goingCount, r.goingAttendees )
                    , interested = ( r.interestedCount, r.interestedAttendees )
                    , requested = ( r.requestedCount, r.requestedAttendees )
                    , notGoing = ( r.notGoingCount, r.notGoingAttendees )
                    , pending = ( r.pendingCount, r.pendingAttendees )
                    }

                Nothing ->
                    emptyTotals

        combine : (Totals -> ( Int, Int )) -> ( Int, Int )
        combine field =
            let
                ( sc, sa ) =
                    field server

                ( ac, aa ) =
                    field applied

                ( bc, ba ) =
                    field before
            in
            ( max ac (sc + ac - bc), max aa (sa + aa - ba) )
    in
    { going = combine .going
    , interested = combine .interested
    , requested = combine .requested
    , notGoing = combine .notGoing
    , pending = combine .pending
    }


formatCount : ( Int, Int ) -> String
formatCount ( rsvpCount, attendees ) =
    let
        rsvpText : String
        rsvpText =
            String.fromInt rsvpCount
                ++ (if rsvpCount == 1 then
                        " RSVP"

                    else
                        " RSVPs"
                   )
    in
    if rsvpCount == attendees then
        rsvpText

    else
        rsvpText
            ++ " | "
            ++ String.fromInt attendees
            ++ (if attendees == 1 then
                    " attendee"

                else
                    " attendees"
               )


{-| The "Going 3 RSVPs / Interested ..." summary, doubling as the expand/collapse toggle for the
list of everyone's RSVPs (`cardsView`) -- on cards as well as the detail page.
-}
summaryView : ViewConfig -> Model -> Bool -> Occasion -> Html Msg
summaryView cfg model isOwner occasion =
    let
        rsvps : List Rsvp
        rsvps =
            rsvpsOf occasion

        totals : Totals
        totals =
            totalsFor model cfg.occasion

        going : ( Int, Int )
        going =
            totals.going

        interested : ( Int, Int )
        interested =
            totals.interested

        invited : ( Int, Int )
        invited =
            totals.requested

        pendingTotals : ( Int, Int )
        pendingTotals =
            totals.pending

        row : String -> String -> ( Int, Int ) -> Html Msg
        row extraClass label counts =
            div [ class "rsvp-summary-row" ]
                [ span [ class extraClass ] [ text label ]
                , span [ class "rsvp-summary-count" ] [ text (formatCount counts) ]
                ]

        content : List (Html Msg)
        content =
            [ div [ class "rsvp-summary-rows" ]
                [ if Tuple.first pendingTotals > 0 then
                    row "rsvp-summary-pending"
                        (if cfg.compact then
                            "Pending"

                         else if isOwner then
                            "Pending Your Approval"

                         else
                            "Pending Owner Approval"
                        )
                        pendingTotals

                  else
                    text ""
                , if Tuple.first going > 0 || (Tuple.first pendingTotals == 0 && Tuple.first interested == 0 && Tuple.first invited == 0) then
                    row "rsvp-summary-going" "Going" going

                  else
                    text ""
                , if Tuple.first interested > 0 then
                    row "rsvp-summary-interested" "Interested" interested

                  else
                    text ""
                , if Tuple.first invited > 0 then
                    row "rsvp-summary-interested" "Invited" invited

                  else
                    text ""
                ]
            , span [ class "rsvp-summary-chevron" ]
                [ span [ classes [ "expandable-section-arrow", openClosedClass model.showCards ] ] [ text "▼" ] ]
            ]
    in
    if List.isEmpty rsvps && totals == emptyTotals then
        div [ classes [ "rsvp-summary", "rsvp-summary-empty" ] ] content

    else
        button [ classes [ "rsvp-summary", "rsvp-summary-button" ], onClick ToggleCards, attribute "aria-expanded" (boolAttr model.showCards) ]
            content


cardsView : ViewConfig -> Bool -> Bool -> Model -> List Rsvp -> Maybe Rsvp -> Maybe Rsvp -> Html Msg
cardsView cfg isPast isOwner model rsvps currentUser currentAnon =
    let
        sortKey : Rsvp -> Int
        sortKey rsvp =
            case rsvp.status of
                NOTGOING ->
                    -1

                GOING ->
                    2

                REQUESTED ->
                    1

                INTERESTED ->
                    0

                RsvpStatusUnrecognized_ _ ->
                    -1

        sorted : List Rsvp
        sorted =
            rsvps
                |> List.sortBy
                    (\rsvp ->
                        ( negate (sortKey rsvp)
                        , case rsvp.attendee of
                            Just (Attendee.UserAttendee _) ->
                                0

                            _ ->
                                1
                        )
                    )

        yours : List Rsvp
        yours =
            List.filterMap identity [ currentAnon, currentUser ]

        notYours : Rsvp -> Bool
        notYours rsvp =
            not (List.any (\own -> own.id == rsvp.id) yours)

        pending : List Rsvp
        pending =
            sorted |> List.filter (\rsvp -> rsvp.moderation == PENDING && notYours rsvp)

        others : List Rsvp
        others =
            sorted |> List.filter (\rsvp -> passes rsvp.moderation && notYours rsvp)

        rejected : List Rsvp
        rejected =
            sorted |> List.filter (\rsvp -> rsvp.moderation == REJECTED && notYours rsvp)

        section : String -> List ( Rsvp, Maybe Mode ) -> Html Msg
        section heading cards =
            if List.isEmpty cards then
                text ""

            else
                div [ class "rsvp-card-section" ]
                    (h3 [ class "rsvp-card-section-heading" ] [ text heading ]
                        :: List.map (\( rsvp, editMode ) -> cardView cfg isPast isOwner model editMode rsvp) cards
                    )

        plain : List Rsvp -> List ( Rsvp, Maybe Mode )
        plain =
            List.map (\rsvp -> ( rsvp, Nothing ))

        sections : List (Html Msg)
        sections =
            [ section
                (if List.length yours /= 1 then
                    "Your RSVPs"

                 else
                    "Your RSVP"
                )
                (List.filterMap identity
                    [ currentAnon |> Maybe.map (\rsvp -> ( rsvp, Just AnonymousMode ))
                    , currentUser |> Maybe.map (\rsvp -> ( rsvp, Just UserMode ))
                    ]
                )
            , section "Pending RSVPs" (plain pending)
            , section "Others' RSVPs" (plain others)
            , section "Rejected RSVPs" (plain rejected)
            ]
    in
    div [ classes [ "rsvp-cards-wrap", openClosedClass model.showCards ] ]
        [ div [ classes [ "rsvp-cards", if cfg.compact then "rsvp-cards-compact" else "rsvp-cards-detail" ] ]
            sections
        ]



cardView : ViewConfig -> Bool -> Bool -> Model -> Maybe Mode -> Rsvp -> Html Msg
cardView cfg isPast isOwner model editMode rsvp =
    let
        attendeeView : Html Msg
        attendeeView =
            case rsvp.attendee of
                Just (Attendee.UserAttendee user) ->
                    Authors.link cfg.basePath
                        cfg.viewingServerHost
                        cfg.eventServerHost
                        cfg.maybeServer
                        cfg.maybeAccount
                        (Just
                            { userId = user.userId
                            , username = user.username
                            , avatar = user.avatar |> Maybe.map wrapMediaReference
                            , realName = user.realName
                            , permissions = user.permissions
                            }
                        )

                Just (Attendee.AnonymousAttendee anonymous) ->
                    div [ class "rsvp-card-anonymous" ]
                        [ span [ class "rsvp-card-anonymous-label" ] [ text "Anonymous" ]
                        , span [ class "rsvp-card-anonymous-name" ] [ text anonymous.name ]
                        ]

                Nothing ->
                    text ""

        statusClass : String
        statusClass =
            case rsvp.status of
                GOING ->
                    "rsvp-summary-going"

                INTERESTED ->
                    "rsvp-summary-interested"

                REQUESTED ->
                    "rsvp-summary-interested"

                _ ->
                    ""
    in
    div [ classes [ "rsvp-card", "border-color-primary-anchor-50" ] ]
        [ div [ class "rsvp-card-header" ]
            [ div [ class "rsvp-card-attendee" ] [ attendeeView ]
            , div [ class "rsvp-card-status" ]
                [ span [ class statusClass ] [ text (statusName isPast rsvp.status) ]
                , span [ class "rsvp-card-guests" ]
                    [ text
                        (String.fromInt rsvp.numberOfGuests
                            ++ (if rsvp.numberOfGuests > 1 then
                                    " attendees"

                                else
                                    " attendee"
                               )
                        )
                    ]
                ]
            , case editMode of
                Just mode ->
                    button [ class "rsvp-card-edit", onClick (EditClicked mode), attribute "aria-label" "Edit RSVP" ] [ text "✎" ]

                Nothing ->
                    text ""
            ]
        , if String.isEmpty (String.trim rsvp.publicNote) then
            text ""

          else
            Markdown.view [ class "rsvp-card-note" ] rsvp.publicNote
        , if String.isEmpty (String.trim rsvp.privateNote) then
            text ""

          else
            div []
                [ div [ class "rsvp-card-private-heading" ] [ text "Private Note" ]
                , Markdown.view [ class "rsvp-card-note" ] rsvp.privateNote
                ]
        , if isOwner then
            select
                [ class "rsvp-moderation-select"
                , onInput (ModerationChanged rsvp)
                , disabled (model.submit == Saving)
                , attribute "aria-label" "Moderation"
                ]
                (List.map
                    (\( moderation, label ) ->
                        option
                            [ value (moderationToString moderation)
                            , selected (moderationToString rsvp.moderation == moderationToString moderation)
                            ]
                            [ text label ]
                    )
                    [ ( APPROVED, "Approved" ), ( PENDING, "Pending" ), ( REJECTED, "Rejected" ), ( UNMODERATED, "Unmoderated" ) ]
                )

          else if not (passes rsvp.moderation) then
            div [ class "rsvp-note" ] [ text (moderationDescription rsvp.moderation) ]

          else
            text ""
        ]
