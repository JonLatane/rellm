module Components.Pages.ServerInformationPage.SettingsTab exposing (Model, Msg, init, update, view)

{-| The Settings tab of `Components.Pages.ServerInformationPage` -- the three server-wide grantable
permission sets (Anonymous/Default/Basic User Permissions, `permissionsSection`, one per
`ServerPermissionsSet`) and the five per-feature settings sections (People/Groups/Posts/Events/
Media, `featureSettingsSection`, one per `FeatureSettingsSet`). Both mirror
`Components.Pages.UserProfilePage`'s own Permissions editor, just reading/writing a
`ServerConfiguration` (via `AccountsPanel.updateServerConfig`, the shared "fetch fresh copy, then
write" RPC helper) instead of a `User`'s `permissions`.
-}

import Components.Pages.ServerInformationPage.Common as Common
import Components.Posts as Posts
import Components.Users as Users
import Effect exposing (Effect)
import Grpc
import Html exposing (Html, button, div, h3, input, option, p, select, span, text)
import Html.Attributes exposing (disabled, selected, value)
import Html.Events exposing (onClick, onInput)
import Proto.Rellm exposing (ServerConfiguration, defaultEventSettings, defaultFeatureSettings, defaultMediaSettings, defaultPostSettings)
import Proto.Rellm.CalendarDisplayMode exposing (CalendarDisplayMode(..))
import Proto.Rellm.Moderation exposing (Moderation(..))
import Proto.Rellm.Permission exposing (Permission)
import Proto.Rellm.Visibility exposing (Visibility(..))
import Set exposing (Set)
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Task
import UI.Classes exposing (classes, openClosedClass)



-- MODEL


type alias Model =
    { anonymousPermissionsEdit : Maybe PermissionsEdit
    , defaultPermissionsEdit : Maybe PermissionsEdit
    , basicPermissionsEdit : Maybe PermissionsEdit
    , peopleSettingsEdit : Maybe FeatureSettingsEdit
    , groupSettingsEdit : Maybe FeatureSettingsEdit
    , postSettingsEdit : Maybe FeatureSettingsEdit
    , eventSettingsEdit : Maybe FeatureSettingsEdit
    , mediaSettingsEdit : Maybe FeatureSettingsEdit
    , collapsedFeatureSettings : Set String
    }


type Msg
    = PermissionsEditClicked ServerPermissionsSet
    | PermissionRemoveClicked ServerPermissionsSet Permission
    | PermissionAddSelectionChanged ServerPermissionsSet String
    | PermissionAddClicked ServerPermissionsSet
    | PermissionsCancelClicked ServerPermissionsSet
    | PermissionsSaveClicked ServerPermissionsSet
    | GotPermissionsSaveResult ServerPermissionsSet (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | FeatureSettingsSectionToggled FeatureSettingsSet
    | FeatureSettingsEditClicked FeatureSettingsSet
    | FeatureSettingsModerationChanged FeatureSettingsSet String
    | FeatureSettingsVisibilityChanged FeatureSettingsSet String
    | FeatureSettingsAliasSingularChanged FeatureSettingsSet String
    | FeatureSettingsAliasPluralChanged FeatureSettingsSet String
    | FeatureSettingsEnableRepliesToggled FeatureSettingsSet
    | FeatureSettingsCalendarLookbackDaysChanged FeatureSettingsSet String
    | FeatureSettingsCalendarDisplayModeChanged FeatureSettingsSet String
    | FeatureSettingsShowStartedOrLongEventsToggled FeatureSettingsSet
    | FeatureSettingsCancelClicked FeatureSettingsSet
    | FeatureSettingsSaveClicked FeatureSettingsSet
    | GotFeatureSettingsSaveResult FeatureSettingsSet (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))


{-| Which of `ServerConfiguration`'s three grantable-permission-list fields a
`permissionsSection`/`PermissionsEdit` is for -- lets `view` reuse the exact same editing machinery
for all three (Anonymous/Default/Basic) rather than tripling it, the way
`Components.Pages.UserProfilePage` doesn't need to since it only ever edits one user's own
`permissions`.
-}
type ServerPermissionsSet
    = AnonymousPermissions
    | DefaultPermissions
    | BasicPermissions


{-| Live only while one of the three server-wide permission sets (see `ServerPermissionsSet`) is
being edited by an admin -- `pending` is the in-progress set, `addSelection` is whatever the "Add
Permission" `<select>` currently has chosen (always one of `Components.Users.configurableServerPermissions`
not already in `pending`, see `resolveAddSelection`).
-}
type alias PermissionsEdit =
    { pending : List Permission
    , addSelection : Maybe Permission
    , status : AccountsPanel.FormStatus
    }


{-| Which of `ServerConfiguration`'s five per-feature settings a `featureSettingsSection`/
`FeatureSettingsEdit` is for -- lets `view` reuse the same editing machinery for
People/Groups/Posts/Events/Media, the same way `ServerPermissionsSet` does for the three
permission lists. `PostFeatureSettings`/`EventFeatureSettings` back `ServerConfiguration`'s
`PostSettings`/`EventSettings` fields (which also carry `enableReplies`, left untouched by this
editor -- see `applyFeatureSettingsFor`); the other three all back a plain `FeatureSettings`/
`MediaSettings`.
-}
type FeatureSettingsSet
    = PeopleFeatureSettings
    | GroupFeatureSettings
    | PostFeatureSettings
    | EventFeatureSettings
    | MediaFeatureSettings


{-| Live only while one of the five per-feature settings (see `FeatureSettingsSet`) is being
edited by an admin -- mirrors `PermissionsEdit`, just over `FeatureSettings`/`PostSettings`/
`EventSettings`/`MediaSettings`'s shared fields. Not every field applies to every
`FeatureSettingsSet` (`MediaSettings` has no alias, People/Groups have no `enableReplies`, only
Events have a calendar lookback/display mode -- see `featureSettingsFieldsFor`, which gates which
rows `featureSettingsDisplayView`/`featureSettingsEditView` show), so this carries all of them
regardless of `set` and `applyFeatureSettingsFor` only writes back the ones the real proto type
underneath actually has. `aliasSingular`/`aliasPlural`/`calendarLookbackDays` are the raw pending
`<input>` text (empty means "unset" -- see `optionalString`/`optionalNonNegativeInt`), not the
`Maybe String`/`Maybe Int` the proto itself uses.
-}
type alias FeatureSettingsEdit =
    { visible : Bool
    , moderation : Moderation
    , visibility : Visibility
    , aliasSingular : String
    , aliasPlural : String
    , enableReplies : Bool
    , calendarLookbackDays : String
    , calendarDisplayMode : CalendarDisplayMode
    , showStartedOrLongEventsByDefault : Bool
    , status : AccountsPanel.FormStatus
    }


init : Model
init =
    { anonymousPermissionsEdit = Nothing
    , defaultPermissionsEdit = Nothing
    , basicPermissionsEdit = Nothing
    , peopleSettingsEdit = Nothing
    , groupSettingsEdit = Nothing
    , postSettingsEdit = Nothing
    , eventSettingsEdit = Nothing
    , mediaSettingsEdit = Nothing
    , collapsedFeatureSettings = Set.empty
    }



-- UPDATE


update : Shared.Model -> String -> Maybe RellmServer -> Msg -> Model -> ( Model, Effect Msg )
update shared targetHost maybeServer msg model =
    case msg of
        PermissionsEditClicked set ->
            case maybeServer of
                Just server ->
                    let
                        currentPermissions : List Permission
                        currentPermissions =
                            permissionsFor set (RellmServers.configurationOf server)
                    in
                    ( setPermissionsEditFor set (Just (newPermissionsEdit currentPermissions)) model, Effect.none )

                Nothing ->
                    ( model, Effect.none )

        PermissionRemoveClicked set permission ->
            ( setPermissionsEditFor set
                (permissionsEditFor set model
                    |> Maybe.map
                        (\edit ->
                            let
                                pending : List Permission
                                pending =
                                    List.filter ((/=) permission) edit.pending
                            in
                            { edit | pending = pending, addSelection = resolveAddSelection edit.addSelection pending }
                        )
                )
                model
            , Effect.none
            )

        PermissionAddSelectionChanged set text ->
            ( setPermissionsEditFor set
                (permissionsEditFor set model |> Maybe.map (\edit -> { edit | addSelection = Users.permissionFromText text }))
                model
            , Effect.none
            )

        PermissionAddClicked set ->
            ( setPermissionsEditFor set
                (permissionsEditFor set model
                    |> Maybe.map
                        (\edit ->
                            case edit.addSelection of
                                Just permission ->
                                    let
                                        pending : List Permission
                                        pending =
                                            edit.pending ++ [ permission ]
                                    in
                                    { edit | pending = pending, addSelection = resolveAddSelection Nothing pending }

                                Nothing ->
                                    edit
                        )
                )
                model
            , Effect.none
            )

        PermissionsCancelClicked set ->
            ( setPermissionsEditFor set Nothing model, Effect.none )

        PermissionsSaveClicked set ->
            case ( permissionsEditFor set model, Common.adminAccountFor shared targetHost ) of
                ( Just edit, Just account ) ->
                    ( setPermissionsEditFor set (Just { edit | status = AccountsPanel.Submitting }) model
                    , AccountsPanel.updateServerConfig shared.accounts ( Just account.userId, targetHost ) (applyPermissionsFor set edit.pending)
                        |> Task.attempt (GotPermissionsSaveResult set)
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotPermissionsSaveResult set (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            ( setPermissionsEditFor set Nothing model
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotPermissionsSaveResult set (Err err) ->
            ( setPermissionsEditFor set
                (permissionsEditFor set model |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }))
                model
            , Effect.none
            )

        FeatureSettingsSectionToggled set ->
            ( { model | collapsedFeatureSettings = toggleSetMember (featureSettingsKey set) model.collapsedFeatureSettings }, Effect.none )

        FeatureSettingsEditClicked set ->
            case maybeServer of
                Just server ->
                    let
                        current : FeatureSettingsSummary
                        current =
                            currentFeatureSettingsFor set (RellmServers.configurationOf server)
                    in
                    ( setFeatureSettingsEditFor set
                        (Just
                            { visible = current.visible
                            , moderation = current.moderation
                            , visibility = current.visibility
                            , aliasSingular = Maybe.withDefault "" current.aliasSingular
                            , aliasPlural = Maybe.withDefault "" current.aliasPlural
                            , enableReplies = Maybe.withDefault False current.enableReplies
                            , calendarLookbackDays = current.calendarLookbackDays |> Maybe.map String.fromInt |> Maybe.withDefault ""
                            , calendarDisplayMode = Maybe.withDefault CALENDARDISPLAYWEEK current.calendarDisplayMode
                            , showStartedOrLongEventsByDefault = Maybe.withDefault False current.showStartedOrLongEventsByDefault
                            , status = AccountsPanel.Idle
                            }
                        )
                        model
                    , Effect.none
                    )

                Nothing ->
                    ( model, Effect.none )

        FeatureSettingsModerationChanged set text ->
            ( setFeatureSettingsEditFor set
                (featureSettingsEditFor set model
                    |> Maybe.map (\edit -> { edit | moderation = Users.moderationFromText text |> Maybe.withDefault edit.moderation })
                )
                model
            , Effect.none
            )

        FeatureSettingsVisibilityChanged set text ->
            ( setFeatureSettingsEditFor set
                (featureSettingsEditFor set model
                    |> Maybe.map (\edit -> { edit | visibility = Posts.visibilityFromText text |> Maybe.withDefault edit.visibility })
                )
                model
            , Effect.none
            )

        FeatureSettingsAliasSingularChanged set text ->
            ( setFeatureSettingsEditFor set
                (featureSettingsEditFor set model |> Maybe.map (\edit -> { edit | aliasSingular = text }))
                model
            , Effect.none
            )

        FeatureSettingsAliasPluralChanged set text ->
            ( setFeatureSettingsEditFor set
                (featureSettingsEditFor set model |> Maybe.map (\edit -> { edit | aliasPlural = text }))
                model
            , Effect.none
            )

        FeatureSettingsEnableRepliesToggled set ->
            ( setFeatureSettingsEditFor set
                (featureSettingsEditFor set model |> Maybe.map (\edit -> { edit | enableReplies = not edit.enableReplies }))
                model
            , Effect.none
            )

        FeatureSettingsCalendarLookbackDaysChanged set text ->
            ( setFeatureSettingsEditFor set
                (featureSettingsEditFor set model |> Maybe.map (\edit -> { edit | calendarLookbackDays = text }))
                model
            , Effect.none
            )

        FeatureSettingsCalendarDisplayModeChanged set text ->
            ( setFeatureSettingsEditFor set
                (featureSettingsEditFor set model
                    |> Maybe.map (\edit -> { edit | calendarDisplayMode = calendarDisplayModeFromText text |> Maybe.withDefault edit.calendarDisplayMode })
                )
                model
            , Effect.none
            )

        FeatureSettingsShowStartedOrLongEventsToggled set ->
            ( setFeatureSettingsEditFor set
                (featureSettingsEditFor set model |> Maybe.map (\edit -> { edit | showStartedOrLongEventsByDefault = not edit.showStartedOrLongEventsByDefault }))
                model
            , Effect.none
            )

        FeatureSettingsCancelClicked set ->
            ( setFeatureSettingsEditFor set Nothing model, Effect.none )

        FeatureSettingsSaveClicked set ->
            case ( featureSettingsEditFor set model, Common.adminAccountFor shared targetHost ) of
                ( Just edit, Just account ) ->
                    ( setFeatureSettingsEditFor set (Just { edit | status = AccountsPanel.Submitting }) model
                    , AccountsPanel.updateServerConfig shared.accounts ( Just account.userId, targetHost ) (applyFeatureSettingsFor set edit)
                        |> Task.attempt (GotFeatureSettingsSaveResult set)
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotFeatureSettingsSaveResult set (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            ( setFeatureSettingsEditFor set Nothing model
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotFeatureSettingsSaveResult set (Err err) ->
            ( setFeatureSettingsEditFor set
                (featureSettingsEditFor set model |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }))
                model
            , Effect.none
            )


{-| `model`'s in-progress `PermissionsEdit` for one `ServerPermissionsSet`, alongside its setter
`setPermissionsEditFor` just below -- lets `update`/`view` treat all three sections generically
instead of a `case` per Msg per section.
-}
permissionsEditFor : ServerPermissionsSet -> Model -> Maybe PermissionsEdit
permissionsEditFor set model =
    case set of
        AnonymousPermissions ->
            model.anonymousPermissionsEdit

        DefaultPermissions ->
            model.defaultPermissionsEdit

        BasicPermissions ->
            model.basicPermissionsEdit


setPermissionsEditFor : ServerPermissionsSet -> Maybe PermissionsEdit -> Model -> Model
setPermissionsEditFor set edit model =
    case set of
        AnonymousPermissions ->
            { model | anonymousPermissionsEdit = edit }

        DefaultPermissions ->
            { model | defaultPermissionsEdit = edit }

        BasicPermissions ->
            { model | basicPermissionsEdit = edit }


{-| One `ServerPermissionsSet`'s current list out of a `ServerConfiguration`, alongside its writer
`applyPermissionsFor` just below.
-}
permissionsFor : ServerPermissionsSet -> ServerConfiguration -> List Permission
permissionsFor set config =
    case set of
        AnonymousPermissions ->
            config.anonymousUserPermissions

        DefaultPermissions ->
            config.defaultUserPermissions

        BasicPermissions ->
            config.basicUserPermissions


applyPermissionsFor : ServerPermissionsSet -> List Permission -> ServerConfiguration -> ServerConfiguration
applyPermissionsFor set permissions config =
    case set of
        AnonymousPermissions ->
            { config | anonymousUserPermissions = permissions }

        DefaultPermissions ->
            { config | defaultUserPermissions = permissions }

        BasicPermissions ->
            { config | basicUserPermissions = permissions }


{-| Toggles a single `Set` member -- `FeatureSettingsSectionToggled`'s own plumbing, generic since
nothing else here needs a `Set` yet.
-}
toggleSetMember : comparable -> Set comparable -> Set comparable
toggleSetMember key set =
    if Set.member key set then
        Set.remove key set

    else
        Set.insert key set


{-| The URL-param-style key `collapsedFeatureSettings` stores per `FeatureSettingsSet` -- distinct
from `featureSettingsLabel`'s user-facing text so relabeling one never silently breaks the other.
-}
featureSettingsKey : FeatureSettingsSet -> String
featureSettingsKey set =
    case set of
        PeopleFeatureSettings ->
            "people"

        GroupFeatureSettings ->
            "group"

        PostFeatureSettings ->
            "post"

        EventFeatureSettings ->
            "event"

        MediaFeatureSettings ->
            "media"


featureSettingsLabel : FeatureSettingsSet -> String
featureSettingsLabel set =
    case set of
        PeopleFeatureSettings ->
            "People"

        GroupFeatureSettings ->
            "Groups"

        PostFeatureSettings ->
            "Posts"

        EventFeatureSettings ->
            "Events"

        MediaFeatureSettings ->
            "Media"


{-| `model`'s in-progress `FeatureSettingsEdit` for one `FeatureSettingsSet`, alongside its setter
`setFeatureSettingsEditFor` just below -- mirrors `permissionsEditFor`/`setPermissionsEditFor`.
-}
featureSettingsEditFor : FeatureSettingsSet -> Model -> Maybe FeatureSettingsEdit
featureSettingsEditFor set model =
    case set of
        PeopleFeatureSettings ->
            model.peopleSettingsEdit

        GroupFeatureSettings ->
            model.groupSettingsEdit

        PostFeatureSettings ->
            model.postSettingsEdit

        EventFeatureSettings ->
            model.eventSettingsEdit

        MediaFeatureSettings ->
            model.mediaSettingsEdit


setFeatureSettingsEditFor : FeatureSettingsSet -> Maybe FeatureSettingsEdit -> Model -> Model
setFeatureSettingsEditFor set edit model =
    case set of
        PeopleFeatureSettings ->
            { model | peopleSettingsEdit = edit }

        GroupFeatureSettings ->
            { model | groupSettingsEdit = edit }

        PostFeatureSettings ->
            { model | postSettingsEdit = edit }

        EventFeatureSettings ->
            { model | eventSettingsEdit = edit }

        MediaFeatureSettings ->
            { model | mediaSettingsEdit = edit }


{-| Only `UNMODERATED`/`PENDING` are valid `default_moderation` values (see
`protos/server_configuration.proto`'s own `FeatureSettings` doc) -- unlike
`Components.Users.allModerations`, which also offers `APPROVED`/`REJECTED` (valid on a Post/User's
own moderation, but not as a server-wide default).
-}
allowedDefaultModerations : List Moderation
allowedDefaultModerations =
    [ UNMODERATED, PENDING ]


{-| Only `SERVER_PUBLIC`/`GLOBAL_PUBLIC` are valid `default_visibility` values (same doc as
`allowedDefaultModerations`) -- unlike `Components.Posts.allVisibilities`, which also offers
`PRIVATE`/`LIMITED`.
-}
allowedDefaultVisibilities : List Visibility
allowedDefaultVisibilities =
    [ SERVERPUBLIC, GLOBALPUBLIC ]


allCalendarDisplayModes : List CalendarDisplayMode
allCalendarDisplayModes =
    [ CALENDARDISPLAYWEEK, CALENDARDISPLAYMONTH, CALENDARDISPLAYDAY ]


{-| Short UI labels for `CalendarDisplayMode` -- the enum's own protobuf names
(`CALENDAR_DISPLAY_WEEK`/etc.) are that verbose purely because protobuf enum values are
conventionally namespaced by their enum's name; the UI just needs "Week"/"Month"/"Day" (per this
page's own admin instructions).
-}
calendarDisplayModeText : CalendarDisplayMode -> String
calendarDisplayModeText mode =
    case mode of
        CALENDARDISPLAYWEEK ->
            "Week"

        CALENDARDISPLAYMONTH ->
            "Month"

        CALENDARDISPLAYDAY ->
            "Day"

        CalendarDisplayModeUnrecognized_ _ ->
            "Week"


calendarDisplayModeFromText : String -> Maybe CalendarDisplayMode
calendarDisplayModeFromText text =
    allCalendarDisplayModes |> List.filter (\mode -> calendarDisplayModeText mode == text) |> List.head


{-| Which of the "extra" fields (beyond `visible`/`defaultModeration`/`defaultVisibility`, which
every `FeatureSettingsSet` has) actually exist on the real proto type underneath `set` -- gates
which rows `featureSettingsDisplayView`/`featureSettingsEditView` show, and which fields
`applyFeatureSettingsFor` writes back. `MediaSettings` has none of them; `FeatureSettings`
(People/Groups) has only alias; `PostSettings` adds replies; `EventSettings` alone has all four.
-}
featureSettingsFieldsFor : FeatureSettingsSet -> { alias : Bool, replies : Bool, calendarLookback : Bool, calendarDisplayMode : Bool, showStartedOrLongEventsByDefault : Bool }
featureSettingsFieldsFor set =
    case set of
        PeopleFeatureSettings ->
            { alias = True, replies = False, calendarLookback = False, calendarDisplayMode = False, showStartedOrLongEventsByDefault = False }

        GroupFeatureSettings ->
            { alias = True, replies = False, calendarLookback = False, calendarDisplayMode = False, showStartedOrLongEventsByDefault = False }

        PostFeatureSettings ->
            { alias = True, replies = True, calendarLookback = False, calendarDisplayMode = False, showStartedOrLongEventsByDefault = False }

        EventFeatureSettings ->
            { alias = True, replies = True, calendarLookback = True, calendarDisplayMode = True, showStartedOrLongEventsByDefault = True }

        MediaFeatureSettings ->
            { alias = False, replies = False, calendarLookback = False, calendarDisplayMode = False, showStartedOrLongEventsByDefault = False }


{-| `currentFeatureSettingsFor`'s return shape -- every field every `FeatureSettingsSet` might show,
`Maybe`-wrapped for the four that not all of them have (see `featureSettingsFieldsFor`).
-}
type alias FeatureSettingsSummary =
    { visible : Bool
    , moderation : Moderation
    , visibility : Visibility
    , aliasSingular : Maybe String
    , aliasPlural : Maybe String
    , enableReplies : Maybe Bool
    , calendarLookbackDays : Maybe Int
    , calendarDisplayMode : Maybe CalendarDisplayMode
    , showStartedOrLongEventsByDefault : Maybe Bool
    }


{-| One `FeatureSettingsSet`'s current settings, defaulted (via `defaultFeatureSettings`/
`defaultPostSettings`/`defaultEventSettings`/`defaultMediaSettings`) the same way
`applyLogoChoice`/`applyColorFor` default their own optional message fields -- `ServerConfiguration`'s
`peopleSettings`/etc. are all `Maybe`-wrapped even though the proto itself doesn't mark them
`optional` (every message-typed field is implicitly optional in proto3). Each branch builds its own
`FeatureSettingsSummary` literal rather than sharing one polymorphic accessor across
`FeatureSettings`/`PostSettings`/`EventSettings`/`MediaSettings` -- those four types don't all have
the same fields (see `featureSettingsFieldsFor`), so there's no single row-polymorphic record they
all fit.
-}
currentFeatureSettingsFor : FeatureSettingsSet -> ServerConfiguration -> FeatureSettingsSummary
currentFeatureSettingsFor set config =
    case set of
        PeopleFeatureSettings ->
            let
                s : Proto.Rellm.FeatureSettings
                s =
                    Maybe.withDefault defaultFeatureSettings config.peopleSettings
            in
            { visible = s.visible, moderation = s.defaultModeration, visibility = s.defaultVisibility, aliasSingular = s.aliasSingular, aliasPlural = s.aliasPlural, enableReplies = Nothing, calendarLookbackDays = Nothing, calendarDisplayMode = Nothing, showStartedOrLongEventsByDefault = Nothing }

        GroupFeatureSettings ->
            let
                s : Proto.Rellm.FeatureSettings
                s =
                    Maybe.withDefault defaultFeatureSettings config.groupSettings
            in
            { visible = s.visible, moderation = s.defaultModeration, visibility = s.defaultVisibility, aliasSingular = s.aliasSingular, aliasPlural = s.aliasPlural, enableReplies = Nothing, calendarLookbackDays = Nothing, calendarDisplayMode = Nothing, showStartedOrLongEventsByDefault = Nothing }

        PostFeatureSettings ->
            let
                s : Proto.Rellm.PostSettings
                s =
                    Maybe.withDefault defaultPostSettings config.postSettings
            in
            { visible = s.visible, moderation = s.defaultModeration, visibility = s.defaultVisibility, aliasSingular = s.aliasSingular, aliasPlural = s.aliasPlural, enableReplies = s.enableReplies, calendarLookbackDays = Nothing, calendarDisplayMode = Nothing, showStartedOrLongEventsByDefault = Nothing }

        EventFeatureSettings ->
            let
                s : Proto.Rellm.EventSettings
                s =
                    Maybe.withDefault defaultEventSettings config.eventSettings
            in
            { visible = s.visible, moderation = s.defaultModeration, visibility = s.defaultVisibility, aliasSingular = s.aliasSingular, aliasPlural = s.aliasPlural, enableReplies = s.enableReplies, calendarLookbackDays = s.calendarLookbackDays, calendarDisplayMode = Just s.defaultCalendarDisplayMode, showStartedOrLongEventsByDefault = Just s.showStartedOrLongEventsByDefault }

        MediaFeatureSettings ->
            let
                s : Proto.Rellm.MediaSettings
                s =
                    Maybe.withDefault defaultMediaSettings config.mediaSettings
            in
            { visible = s.visible, moderation = s.defaultModeration, visibility = s.defaultVisibility, aliasSingular = Nothing, aliasPlural = Nothing, enableReplies = Nothing, calendarLookbackDays = Nothing, calendarDisplayMode = Nothing, showStartedOrLongEventsByDefault = Nothing }


{-| Overlays a `FeatureSettingsEdit`'s `visible`/`moderation`/`visibility` onto whichever of
`FeatureSettings`/`PostSettings`/`EventSettings`/`MediaSettings` `settings` already is, leaving
every other field untouched -- the trio every one of the four types shares. `applyFeatureSettingsFor`
layers each type's own extra fields (alias/replies/lookback/display mode) on top of this per branch,
since those aren't uniform across all four the way this trio is.
-}
updatedFeatureSettings : FeatureSettingsEdit -> { r | visible : Bool, defaultModeration : Moderation, defaultVisibility : Visibility } -> { r | visible : Bool, defaultModeration : Moderation, defaultVisibility : Visibility }
updatedFeatureSettings edit settings =
    { settings | visible = edit.visible, defaultModeration = edit.moderation, defaultVisibility = edit.visibility }


{-| Empty (after trimming) `<input>` text round-trips to `Nothing` -- how every optional-string
field on this page's editors (`aliasSingular`/`aliasPlural` here, `FacebookAuthFieldEdit`'s
`appId`/`appSecret` elsewhere) represents "unset."
-}
optionalString : String -> Maybe String
optionalString text =
    let
        trimmed : String
        trimmed =
            String.trim text
    in
    if String.isEmpty trimmed then
        Nothing

    else
        Just trimmed


{-| `calendarLookbackDays`'s pending `<input type="number">` text -> the proto's `optional uint32`.
Blank or unparseable text, or a negative number, both mean "unset" (falls back to the server's own
built-in default) -- there's no inline validation error for a bad value here, matching this page's
existing light-touch validation style (e.g. a blank Facebook App Secret is silently a no-op, not an
error).
-}
optionalNonNegativeInt : String -> Maybe Int
optionalNonNegativeInt text =
    String.toInt (String.trim text)
        |> Maybe.andThen
            (\n ->
                if n >= 0 then
                    Just n

                else
                    Nothing
            )


{-| `FeatureSettingsSaveClicked`'s transform, passed to `AccountsPanel.updateServerConfig` the same
way `applyPermissionsFor`'s result is -- overlays `edit`'s trio onto a freshly re-fetched
`ServerConfiguration`'s matching field (defaulted the same way `currentFeatureSettingsFor` is), then
layers on whichever of alias/replies/lookback/display mode that field's real type actually has (see
`featureSettingsFieldsFor`) -- `MediaSettings` gets none of them, `FeatureSettings` (People/Groups)
gets alias only, `PostSettings` adds replies, and `EventSettings` gets all four.
-}
applyFeatureSettingsFor : FeatureSettingsSet -> FeatureSettingsEdit -> ServerConfiguration -> ServerConfiguration
applyFeatureSettingsFor set edit config =
    case set of
        PeopleFeatureSettings ->
            let
                updated : Proto.Rellm.FeatureSettings
                updated =
                    updatedFeatureSettings edit (Maybe.withDefault defaultFeatureSettings config.peopleSettings)
            in
            { config | peopleSettings = Just { updated | aliasSingular = optionalString edit.aliasSingular, aliasPlural = optionalString edit.aliasPlural } }

        GroupFeatureSettings ->
            let
                updated : Proto.Rellm.FeatureSettings
                updated =
                    updatedFeatureSettings edit (Maybe.withDefault defaultFeatureSettings config.groupSettings)
            in
            { config | groupSettings = Just { updated | aliasSingular = optionalString edit.aliasSingular, aliasPlural = optionalString edit.aliasPlural } }

        PostFeatureSettings ->
            let
                updated : Proto.Rellm.PostSettings
                updated =
                    updatedFeatureSettings edit (Maybe.withDefault defaultPostSettings config.postSettings)
            in
            { config
                | postSettings =
                    Just
                        { updated
                            | aliasSingular = optionalString edit.aliasSingular
                            , aliasPlural = optionalString edit.aliasPlural
                            , enableReplies = Just edit.enableReplies
                        }
            }

        EventFeatureSettings ->
            let
                updated : Proto.Rellm.EventSettings
                updated =
                    updatedFeatureSettings edit (Maybe.withDefault defaultEventSettings config.eventSettings)
            in
            { config
                | eventSettings =
                    Just
                        { updated
                            | aliasSingular = optionalString edit.aliasSingular
                            , aliasPlural = optionalString edit.aliasPlural
                            , enableReplies = Just edit.enableReplies
                            , calendarLookbackDays = optionalNonNegativeInt edit.calendarLookbackDays
                            , defaultCalendarDisplayMode = edit.calendarDisplayMode
                            , showStartedOrLongEventsByDefault = edit.showStartedOrLongEventsByDefault
                        }
            }

        MediaFeatureSettings ->
            { config | mediaSettings = Just (updatedFeatureSettings edit (Maybe.withDefault defaultMediaSettings config.mediaSettings)) }


{-| Starts a `PermissionsEdit` off `currentPermissions` (that set's own, as currently configured) --
`addSelection` defaults to the first grantable permission not already in that list, same as
`resolveAddSelection` picks after every add/remove. Mirrors
`Components.Pages.UserProfilePage.newPermissionsEdit`.
-}
newPermissionsEdit : List Permission -> PermissionsEdit
newPermissionsEdit currentPermissions =
    { pending = currentPermissions
    , addSelection = resolveAddSelection Nothing currentPermissions
    , status = AccountsPanel.Idle
    }


{-| Keeps the "Add Permission" `<select>`'s selection valid as `pending` changes: keeps `current`
if it's still addable (not already in `pending`), otherwise falls back to the first still-addable
permission (`Nothing` if every permission's already been added). Mirrors `UserProfilePage`'s own.
-}
resolveAddSelection : Maybe Permission -> List Permission -> Maybe Permission
resolveAddSelection current pending =
    let
        available : List Permission
        available =
            addablePermissions pending
    in
    case current of
        Just permission ->
            if List.member permission available then
                Just permission

            else
                List.head available

        Nothing ->
            List.head available


addablePermissions : List Permission -> List Permission
addablePermissions pending =
    Users.configurableServerPermissions |> List.filter (\permission -> not (List.member permission pending))



-- VIEW


view : RellmServer -> Maybe RellmAccount -> Model -> Html Msg
view server maybeAdminAccount model =
    let
        config : ServerConfiguration
        config =
            RellmServers.configurationOf server
    in
    div [ Html.Attributes.class "server-details-tab-content server-details-settings" ]
        ([ permissionsSection AnonymousPermissions "Anonymous User Permissions" maybeAdminAccount model.anonymousPermissionsEdit config.anonymousUserPermissions
         , permissionsSection DefaultPermissions "Default User Permissions" maybeAdminAccount model.defaultPermissionsEdit config.defaultUserPermissions
         , permissionsSection BasicPermissions "Basic User Permissions" maybeAdminAccount model.basicPermissionsEdit config.basicUserPermissions
         ]
            ++ ([ PeopleFeatureSettings, GroupFeatureSettings, PostFeatureSettings, EventFeatureSettings, MediaFeatureSettings ]
                    |> List.map
                        (\set ->
                            featureSettingsSection set
                                maybeAdminAccount
                                (featureSettingsEditFor set model)
                                (Set.member (featureSettingsKey set) model.collapsedFeatureSettings)
                                (currentFeatureSettingsFor set config)
                        )
               )
        )


{-| One of the three server-wide permission sections (Anonymous/Default/Basic, distinguished by
`set`) -- plain badges (plus an Edit button, for an admin) when this section has no in-progress
`PermissionsEdit`, or the removable-badges + Add Permission + Save/Cancel editor while being
edited. Mirrors `Components.Pages.UserProfilePage.permissionsSection` exactly, just over a
`ServerConfiguration`'s permission list instead of a `User`'s.
-}
permissionsSection : ServerPermissionsSet -> String -> Maybe RellmAccount -> Maybe PermissionsEdit -> List Permission -> Html Msg
permissionsSection set label_ maybeAdminAccount maybeEdit permissions =
    case maybeEdit of
        Just edit ->
            div [ Html.Attributes.class "server-details-permissions server-details-permissions-edit" ]
                [ h3 [ classes [ "section-title" ] ] [ text label_ ]
                , div [ Html.Attributes.class "permission-badges" ] (edit.pending |> List.map (permissionEditBadge set))
                , div [ Html.Attributes.class "server-details-permissions-add" ]
                    [ select [ onInput (PermissionAddSelectionChanged set) ]
                        (addablePermissions edit.pending
                            |> List.map
                                (\permission ->
                                    option
                                        [ value (Users.permissionText permission)
                                        , selected (edit.addSelection == Just permission)
                                        ]
                                        [ text (Users.permissionText permission) ]
                                )
                        )
                    , button
                        [ Html.Attributes.class "server-details-rename-button"
                        , onClick (PermissionAddClicked set)
                        , disabled (edit.addSelection == Nothing || edit.status == AccountsPanel.Submitting)
                        ]
                        [ text "Add Permission" ]
                    ]
                , div [ Html.Attributes.class "server-details-permissions-actions" ]
                    [ Common.editSaveButton (PermissionsSaveClicked set) edit.status
                    , Common.editCancelButton (PermissionsCancelClicked set) edit.status
                    ]
                , Common.editErrorView edit.status
                ]

        Nothing ->
            div [ Html.Attributes.class "server-details-permissions" ]
                [ h3 [ classes [ "section-title" ] ] [ text label_ ]
                , if List.isEmpty permissions then
                    p [] [ text "None." ]

                  else
                    div [ Html.Attributes.class "permission-badges" ]
                        (permissions |> List.map (\permission -> span [ Html.Attributes.class "permission-badge" ] [ text (Users.permissionText permission) ]))
                , case maybeAdminAccount of
                    Just _ ->
                        button [ Html.Attributes.class "server-details-rename-button", onClick (PermissionsEditClicked set) ] [ text <| "Edit " ++ label_ ]

                    Nothing ->
                        text ""
                ]


permissionEditBadge : ServerPermissionsSet -> Permission -> Html Msg
permissionEditBadge set permission =
    span [ Html.Attributes.class "permission-badge editable" ]
        [ text (Users.permissionText permission)
        , button
            [ Html.Attributes.class "permission-remove"
            , onClick (PermissionRemoveClicked set permission)
            , Html.Attributes.title ("Remove " ++ Users.permissionText permission)
            ]
            [ text "×" ]
        ]


{-| One of the five per-feature settings sections (People/Groups/Posts/Events/Media, distinguished
by `set`) -- a collapsible panel (`expanded`, toggled by `FeatureSettingsSectionToggled`, defaulted
to expanded -- see `Model.collapsedFeatureSettings`), reusing the same `.section-title`/
`.expandable-section-title`/`.expandable-section-arrow` header look
`Components.Pages.UserProfilePage.expandableProfileSection` establishes for its own
Permissions/Sync sections. The body is `featureSettingsDisplayView` (plain text/a disabled
checkbox, plus an Edit button for an admin) when this section has no in-progress
`FeatureSettingsEdit`, or `featureSettingsEditView` (an enabled checkbox + Moderation/Visibility
`<select>`s + Save/Cancel) while being edited -- mirrors `permissionsSection`'s own edit/non-edit
split, just collapsible.

Follows `UserProfilePage.expandableProfileSection`'s own conventions: the body
(`expandable-section-content`/`-content-inner`) is always mounted rather than appearing/disappearing
outright, so `profiles.css`'s `grid-template-rows` 0fr/1fr trick can animate it open/closed, and the
arrow is a single static "▼" rotated via `.expandable-section-arrow.is-open` instead of a glyph swap
between "▸"/"▾".
-}
featureSettingsSection : FeatureSettingsSet -> Maybe RellmAccount -> Maybe FeatureSettingsEdit -> Bool -> FeatureSettingsSummary -> Html Msg
featureSettingsSection set maybeAdminAccount maybeEdit collapsed current =
    let
        expanded : Bool
        expanded =
            not collapsed
    in
    div [ Html.Attributes.class "server-details-feature-settings" ]
        [ h3
            [ classes [ "section-title", "expandable-section-title" ]
            , onClick (FeatureSettingsSectionToggled set)
            ]
            [ span [ classes [ "expandable-section-arrow", openClosedClass expanded ] ] [ text "▼" ]
            , text (featureSettingsLabel set)
            ]
        , div
            [ classes [ "expandable-section-content", openClosedClass expanded, "border-color-primary-anchor-50" ] ]
            [ div [ Html.Attributes.class "expandable-section-content-inner" ]
                [ case maybeEdit of
                    Just edit ->
                        featureSettingsEditView set edit

                    Nothing ->
                        featureSettingsDisplayView set maybeAdminAccount current
                ]
            ]
        ]


{-| The non-editing body of a `featureSettingsSection` -- `visible`/`enableReplies` are always
disabled toggle switches (`Common.switchDisplay`, the same `.switch`/`.slider` control `CdnTab` uses
for its own read-only flags), everything else is plain monospace text, mirroring `Pages.Post.PostId_`'s
`moderationView`/`visibilityView` non-editing case. Which of alias/replies/lookback/display mode
actually show is gated by `featureSettingsFieldsFor set` -- e.g. Media shows none of them, only
Events shows a display mode. The Edit button is only shown to an admin (`maybeAdminAccount`), same
as `permissionsSection`.
-}
featureSettingsDisplayView : FeatureSettingsSet -> Maybe RellmAccount -> FeatureSettingsSummary -> Html Msg
featureSettingsDisplayView set maybeAdminAccount current =
    let
        fields : { alias : Bool, replies : Bool, calendarLookback : Bool, calendarDisplayMode : Bool, showStartedOrLongEventsByDefault : Bool }
        fields =
            featureSettingsFieldsFor set

        textValue : String -> Html Msg
        textValue text_ =
            span [ Html.Attributes.class "server-details-feature-settings-value" ] [ text text_ ]
    in
    div [ Html.Attributes.class "server-details-feature-settings-display" ]
        (List.concat
            [ [ -- Common.settingsRow "Visible" (Common.switchDisplay current.visible),
                Common.settingsRow "Moderation" (textValue (Users.moderationText current.moderation))
              , Common.settingsRow "Visibility" (textValue (Posts.visibilityText current.visibility))
              ]
            , if fields.alias then
                [ Common.settingsRow "Alias (Singular)" (textValue (Maybe.withDefault "—" current.aliasSingular))
                , Common.settingsRow "Alias (Plural)" (textValue (Maybe.withDefault "—" current.aliasPlural))
                ]

              else
                []
            , if fields.replies then
                [ Common.settingsRow "Enable Replies" (Common.switchDisplay (Maybe.withDefault False current.enableReplies)) ]

              else
                []
            , if fields.calendarLookback then
                [ Common.settingsRow "Calendar Lookback (Days)" (textValue (current.calendarLookbackDays |> Maybe.map String.fromInt |> Maybe.withDefault "—")) ]

              else
                []
            , if fields.calendarDisplayMode then
                [ Common.settingsRow "Default Calendar Display Mode" (textValue (current.calendarDisplayMode |> Maybe.map calendarDisplayModeText |> Maybe.withDefault "—")) ]

              else
                []
            , if fields.showStartedOrLongEventsByDefault then
                [ Common.settingsRow "Show Started/Long Events by Default" (Common.switchDisplay (Maybe.withDefault False current.showStartedOrLongEventsByDefault)) ]

              else
                []
            , [ case maybeAdminAccount of
                    Just _ ->
                        button [ Html.Attributes.class "server-details-rename-button", onClick (FeatureSettingsEditClicked set) ] [ text <| "Edit " ++ (featureSettingsLabel set) ++ " Settings" ]

                    Nothing ->
                        text ""
              ]
            ]
        )


{-| The editing body of a `featureSettingsSection` -- an enabled toggle switch (`Common.flagSwitch`,
same control the Federated Servers tab's own flags use) for `visible`/`enableReplies`, right-aligned
`<select>`s for `moderation`/`visibility`/`calendarDisplayMode`, and `<input>`s for the two alias
fields/`calendarLookbackDays`, mirroring `Pages.Post.PostId_`'s `moderationView`/`visibilityView`
editing case. `moderation`/`visibility` are narrowed to `allowedDefaultModerations`/
`allowedDefaultVisibilities` (the only values `ServerConfiguration`'s own doc allows for a
`default_moderation`/`default_visibility`); which of the rest actually show is gated by
`featureSettingsFieldsFor set`, same as `featureSettingsDisplayView`.
-}
featureSettingsEditView : FeatureSettingsSet -> FeatureSettingsEdit -> Html Msg
featureSettingsEditView set edit =
    let
        fields : { alias : Bool, replies : Bool, calendarLookback : Bool, calendarDisplayMode : Bool, showStartedOrLongEventsByDefault : Bool }
        fields =
            featureSettingsFieldsFor set

        textInput : (String -> Msg) -> String -> Html Msg
        textInput onChange currentValue =
            input
                [ Html.Attributes.class "server-details-rename-input"
                , value currentValue
                , onInput onChange
                , disabled (edit.status == AccountsPanel.Submitting)
                ]
                []
    in
    div [ Html.Attributes.class "server-details-feature-settings-edit" ]
        (List.concat
            [ [ --Common.settingsRow "Visible" (Common.flagSwitch edit.visible (FeatureSettingsVisibleToggled set)),
                Common.settingsRow "Moderation"
                    (select [ onInput (FeatureSettingsModerationChanged set) ]
                        (allowedDefaultModerations
                            |> List.map
                                (\moderation ->
                                    option
                                        [ value (Users.moderationText moderation), selected (edit.moderation == moderation) ]
                                        [ text (Users.moderationText moderation) ]
                                )
                        )
                    )
              , Common.settingsRow "Visibility"
                    (select [ onInput (FeatureSettingsVisibilityChanged set) ]
                        (allowedDefaultVisibilities
                            |> List.map
                                (\visibility ->
                                    option
                                        [ value (Posts.visibilityText visibility), selected (edit.visibility == visibility) ]
                                        [ text (Posts.visibilityText visibility) ]
                                )
                        )
                    )
              ]
            , if fields.alias then
                [ Common.settingsRow "Alias (Singular)" (textInput (FeatureSettingsAliasSingularChanged set) edit.aliasSingular)
                , Common.settingsRow "Alias (Plural)" (textInput (FeatureSettingsAliasPluralChanged set) edit.aliasPlural)
                ]

              else
                []
            , if fields.replies then
                [ Common.settingsRow "Enable Replies" (Common.flagSwitch edit.enableReplies (FeatureSettingsEnableRepliesToggled set)) ]

              else
                []
            , if fields.calendarLookback then
                [ Common.settingsRow "Calendar Lookback (Days)"
                    (input
                        [ Html.Attributes.class "server-details-rename-input"
                        , Html.Attributes.type_ "number"
                        , Html.Attributes.min "0"
                        , value edit.calendarLookbackDays
                        , onInput (FeatureSettingsCalendarLookbackDaysChanged set)
                        , disabled (edit.status == AccountsPanel.Submitting)
                        ]
                        []
                    )
                ]

              else
                []
            , if fields.calendarDisplayMode then
                [ Common.settingsRow "Default Calendar Display Mode"
                    (select [ onInput (FeatureSettingsCalendarDisplayModeChanged set) ]
                        (allCalendarDisplayModes
                            |> List.map
                                (\mode ->
                                    option
                                        [ value (calendarDisplayModeText mode), selected (edit.calendarDisplayMode == mode) ]
                                        [ text (calendarDisplayModeText mode) ]
                                )
                        )
                    )
                ]

              else
                []
            , if fields.showStartedOrLongEventsByDefault then
                [ Common.settingsRow "Show Started/Long Events by Default" (Common.flagSwitch edit.showStartedOrLongEventsByDefault (FeatureSettingsShowStartedOrLongEventsToggled set)) ]

              else
                []
            , [ div [ Html.Attributes.class "server-details-feature-settings-actions" ]
                    [ Common.editSaveButton (FeatureSettingsSaveClicked set) edit.status
                    , Common.editCancelButton (FeatureSettingsCancelClicked set) edit.status
                    ]
              , Common.editErrorView edit.status
              ]
            ]
        )
