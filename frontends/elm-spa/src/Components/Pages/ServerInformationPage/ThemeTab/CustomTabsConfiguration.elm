module Components.Pages.ServerInformationPage.ThemeTab.CustomTabsConfiguration exposing (Model, Msg, applySharedMsg, init, subscriptions, update, view)

{-| The "Navigation Tabs" section of `Components.Pages.ServerInformationPage.ThemeTab` -- a
horizontally-scrolling strip previewing `UI.headerNav`'s own tab layout (`Home`, plus one chip per
`ServerConfiguration.customTabs.tabs`, see `UI.CustomNav`'s own module doc), editable by an admin
via the same "fetch fresh copy, then write" `AccountsPanel.updateServerConfig` dance every other
tab's editor uses. Split into its own module (sibling to `ThemeTab` rather than folded into it)
purely for size -- it's the single largest editor on the Server Information page (FLIP-animated
reordering, per-tab icon/target/title/path editing, plus the `Home` slot's own target choice), and
`ThemeTab` just wires this in as a sub-component (`Model`/`Msg` embedded in its own, `update`/`view`
calls forwarded) the same way `Components.Pages.ServerInformationPage` itself wires in `ThemeTab`/
`SettingsTab`/etc.
-}

import Animation
import Browser.Dom as Dom
import Components.Pages.ServerInformationPage.Common as Common
import Dict exposing (Dict)
import Effect exposing (Effect)
import Grpc
import Html exposing (Html, button, div, h3, input, option, select, span, text)
import Html.Attributes exposing (id, placeholder, selected, value)
import Html.Events exposing (onClick, onInput)
import Html.Keyed
import Proto.Rellm exposing (ServerConfiguration, defaultCustomNavigationTabSet)
import Proto.Rellm.NavigationTab exposing (NavigationTab(..))
import Proto.Rellm.NavigationTabStyle exposing (NavigationTabStyle)
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Shared.MyMediaPanel as MyMediaPanel
import Task
import UI.Classes exposing (classes, hostnameToCSSClass)
import UI.CustomNav as CustomNav
import UI.Flip



-- MODEL


type alias Model =
    { customTabsEdit : Maybe CustomTabsEdit
    }


type Msg
    = CustomTabsEditClicked
    | CustomTabsCancelClicked
    | CustomTabsSaveClicked
    | GotCustomTabsSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | CustomTabAddClicked
    | CustomTabRemoveClicked String
    | CustomTabRemoved String
    | CustomTabTargetKindChanged String String
    | CustomTabPostIdChanged String String
    | CustomTabTitleChanged String String
    | CustomTabPathChanged String String
    | CustomTabEmojiChanged String String
    | CustomTabChooseImageClicked String
    | CustomTabRemoveImageClicked String
    | CustomTabHomeTargetKindChanged String
    | CustomTabHomePostIdChanged String
    | CustomTabHomePinnedPostIdsChanged String
    | CustomTabHomeShowEventsStripToggled
    | CustomTabHomeEventsStripToRowToggled
    | CustomTabHomeEventsStripCalendarDisplayModeChanged String
    | TabStyleChanged String
    | GotTabStyleSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | MoveCustomTabLeftClicked String
    | MoveCustomTabRightClicked String
    | GotPreMoveCustomTabPositions String String Int (Result Dom.Error ( Dom.Element, Dom.Element ))
    | CustomTabMoveSettled String
    | AnimateCustomTabFlip Animation.Msg
    | AnimateCustomTabMove Animation.Msg


{-| Live only while `ServerConfiguration.customTabs`' `tabs` list (see `UI.CustomNav.effectiveTabs`)
is being edited by an admin -- mirrors `FederationTab.FederationEdit` almost exactly (same
`pending`/FLIP-animation shape, over `CustomTabEntry` instead of `FederatedServer`), just with two
extras: `nextEntryId` (a monotonic counter minting each entry's own `entryId` -- unlike a
`FederatedServer`'s naturally-unique `host`, nothing about a tab is guaranteed unique up front, so
entries need a synthetic key for `UI.Flip`'s animation `Dict`s/DOM ids/list identity) and
`editingIconFor` (which entry's icon `Shared.MyMediaPanel` is currently picking for, if any -- see
`applySharedMsg`, mirroring `ThemeTab.LogoEdit`'s own `Shared.MyMediaPanel` integration).

The `home` slot rides along as its own `home` field, not part of `pending` -- it's not a
`CustomTabEntry` at all (no icon/title/path/reorder), just a plain `UI.CustomNav.HomePageConfig`
(reused directly rather than a bespoke type -- `home.target`'s own proto doc restriction to
`HOME_TAB`/`EVENTS_TAB`/`POSTS_TAB`/a `post_id` is enforced entirely by `homeTargetSelect` only ever
offering `UI.CustomNav.selectableHomeTargetKinds`, never by the type itself). `pinnedPostIdsText` is
`home.pinnedPostIds`' own raw `<input>` text (comma-separated, parsed at save -- see
`applyCustomTabs`), kept separate from `home` itself for the same reason `CustomTabEntry.title`
stays raw text rather than living pre-parsed on `home`: reformatting it back from the parsed list on
every keystroke (e.g. collapsing a trailing ", " while still typing the next id) would fight the
admin's own typing. It saves/cancels in the same round-trip as `pending`
(`CustomTabsSaveClicked`/`applyCustomTabs`, `CustomTabsCancelClicked`) since both live under the
same "Navigation Tabs" section/Edit button.

`ServerConfiguration.customTabs.tabStyle` is _not_ part of this edit -- unlike `home`/`pending`, it's
a standalone setting (see `tabStyleRow`/`TabStyleChanged`) that saves immediately on change, with no
Edit/Save/Cancel of its own, since it's a single independent choice rather than a multi-field form.

-}
type alias CustomTabsEdit =
    { pending : List CustomTabEntry
    , home : CustomNav.HomePageConfig
    , pinnedPostIdsText : String
    , nextEntryId : Int
    , editingIconFor : Maybe String
    , status : AccountsPanel.FormStatus
    , itemAnimations : Dict String (UI.Flip.State Msg)
    , moveAnimations : Dict String (UI.Flip.MoveState Msg)
    }


{-| One in-progress tab in a `CustomTabsEdit.pending` -- `target`/`icon`/`path` mirror
`UI.CustomNav.CustomTab`'s own fields exactly (this _is_ a `CustomTab`, plus `entryId`); `title` is
the raw `<input>` text (empty means "unset," same `optionalString` convention as
`applyCustomTabs`'s own use). `path` is a plain `<input>` too (see `customTabEditChip`'s own Path
row) -- the backend's `validate_configuration` rejects anything that isn't `[a-z_]+` on save,
surfaced the same way any other server-side rejection is (`Common.editErrorView`), rather than
duplicating that regex client-side.
-}
type alias CustomTabEntry =
    { entryId : String
    , target : CustomNav.CustomTabTarget
    , icon : CustomNav.CustomTabIcon
    , title : String
    , path : String
    }


init : Model
init =
    { customTabsEdit = Nothing }


subscriptions : Model -> Sub Msg
subscriptions model =
    case model.customTabsEdit of
        Just edit ->
            Sub.batch
                [ UI.Flip.subscription AnimateCustomTabFlip (Dict.values edit.itemAnimations)
                , UI.Flip.moveSubscription AnimateCustomTabMove (Dict.values edit.moveAnimations)
                ]

        Nothing ->
            Sub.none



-- UPDATE


update : Shared.Model -> String -> Maybe RellmServer -> Msg -> Model -> ( Model, Effect Msg )
update shared targetHost maybeServer msg model =
    case msg of
        CustomTabsEditClicked ->
            case maybeServer of
                Just server ->
                    let
                        config : ServerConfiguration
                        config =
                            RellmServers.configurationOf server

                        entries : List CustomTabEntry
                        entries =
                            CustomNav.effectiveTabs config.customTabs |> List.indexedMap customTabEntryFrom
                    in
                    ( { model
                        | customTabsEdit =
                            Just
                                { pending = entries
                                , home = CustomNav.homeConfig config.customTabs
                                , pinnedPostIdsText = String.join ", " (CustomNav.homeConfig config.customTabs).pinnedPostIds
                                , nextEntryId = List.length entries
                                , editingIconFor = Nothing
                                , status = AccountsPanel.Idle
                                , itemAnimations = entries |> List.map (\entry -> ( entry.entryId, UI.Flip.restingState )) |> Dict.fromList
                                , moveAnimations = Dict.empty
                                }
                      }
                    , Effect.none
                    )

                Nothing ->
                    ( model, Effect.none )

        CustomTabsCancelClicked ->
            ( { model | customTabsEdit = Nothing }, Effect.fromShared (Shared.MyMediaPanelMsg MyMediaPanel.CloseClicked) )

        CustomTabsSaveClicked ->
            case ( model.customTabsEdit, Common.adminAccountFor shared targetHost ) of
                ( Just edit, Just account ) ->
                    ( { model | customTabsEdit = Just { edit | status = AccountsPanel.Submitting } }
                    , AccountsPanel.updateServerConfig shared.accounts ( Just account.userId, targetHost ) (applyCustomTabs edit)
                        |> Task.attempt GotCustomTabsSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotCustomTabsSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            ( { model | customTabsEdit = Nothing }
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotCustomTabsSaveResult (Err err) ->
            ( { model | customTabsEdit = model.customTabsEdit |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) }
            , Effect.none
            )

        CustomTabAddClicked ->
            case model.customTabsEdit of
                Just edit ->
                    let
                        entryId : String
                        entryId =
                            "tab-" ++ String.fromInt edit.nextEntryId

                        newEntry : CustomTabEntry
                        newEntry =
                            { entryId = entryId
                            , target = CustomNav.TargetTab EVENTSTAB
                            , icon = CustomNav.EmojiIcon "✨"
                            , title = ""
                            , path = CustomNav.defaultPathFor (CustomNav.TargetTab EVENTSTAB)
                            }
                    in
                    ( { model
                        | customTabsEdit =
                            Just
                                { edit
                                    | pending = edit.pending ++ [ newEntry ]
                                    , nextEntryId = edit.nextEntryId + 1
                                    , itemAnimations = Dict.insert entryId UI.Flip.enter edit.itemAnimations
                                }
                      }
                    , Effect.none
                    )

                Nothing ->
                    ( model, Effect.none )

        CustomTabRemoveClicked entryId ->
            ( { model
                | customTabsEdit =
                    model.customTabsEdit
                        |> Maybe.map
                            (\edit ->
                                let
                                    currentState : UI.Flip.State Msg
                                    currentState =
                                        Dict.get entryId edit.itemAnimations |> Maybe.withDefault UI.Flip.restingState
                                in
                                { edit | itemAnimations = Dict.insert entryId (UI.Flip.remove (CustomTabRemoved entryId) currentState) edit.itemAnimations }
                            )
              }
            , Effect.none
            )

        CustomTabRemoved entryId ->
            ( { model
                | customTabsEdit =
                    model.customTabsEdit
                        |> Maybe.map
                            (\edit ->
                                { edit
                                    | pending = List.filter (\entry -> entry.entryId /= entryId) edit.pending
                                    , itemAnimations = Dict.remove entryId edit.itemAnimations
                                    , editingIconFor =
                                        if edit.editingIconFor == Just entryId then
                                            Nothing

                                        else
                                            edit.editingIconFor
                                }
                            )
              }
            , Effect.none
            )

        CustomTabTargetKindChanged entryId text ->
            ( { model
                | customTabsEdit =
                    model.customTabsEdit
                        |> Maybe.map
                            (mapPendingEntry entryId
                                (\entry ->
                                    case CustomNav.targetKindFromText text of
                                        Just (CustomNav.KindTab navTab) ->
                                            { entry | target = CustomNav.TargetTab navTab }

                                        Just CustomNav.KindPost ->
                                            case entry.target of
                                                CustomNav.TargetPost _ ->
                                                    entry

                                                _ ->
                                                    { entry | target = CustomNav.TargetPost "" }

                                        Just CustomNav.KindProfile ->
                                            { entry | target = CustomNav.TargetProfile }

                                        Nothing ->
                                            entry
                                )
                            )
              }
            , Effect.none
            )

        CustomTabPostIdChanged entryId text ->
            ( { model | customTabsEdit = model.customTabsEdit |> Maybe.map (mapPendingEntry entryId (\entry -> { entry | target = CustomNav.TargetPost text })) }
            , Effect.none
            )

        CustomTabTitleChanged entryId text ->
            ( { model | customTabsEdit = model.customTabsEdit |> Maybe.map (mapPendingEntry entryId (\entry -> { entry | title = text })) }
            , Effect.none
            )

        CustomTabPathChanged entryId text ->
            ( { model | customTabsEdit = model.customTabsEdit |> Maybe.map (mapPendingEntry entryId (\entry -> { entry | path = text })) }
            , Effect.none
            )

        CustomTabEmojiChanged entryId text ->
            ( { model | customTabsEdit = model.customTabsEdit |> Maybe.map (mapPendingEntry entryId (\entry -> { entry | icon = CustomNav.EmojiIcon text })) }
            , Effect.none
            )

        CustomTabChooseImageClicked entryId ->
            ( { model | customTabsEdit = model.customTabsEdit |> Maybe.map (\edit -> { edit | editingIconFor = Just entryId }) }
            , Effect.fromShared (Shared.MyMediaPanelMsg (MyMediaPanel.Open (Just (MyMediaPanel.SingleSelect { imagesOnly = True, initialSelection = Nothing })) targetHost))
            )

        CustomTabRemoveImageClicked entryId ->
            ( { model | customTabsEdit = model.customTabsEdit |> Maybe.map (mapPendingEntry entryId (\entry -> { entry | icon = CustomNav.EmojiIcon "" })) }
            , Effect.none
            )

        MoveCustomTabLeftClicked entryId ->
            ( model
            , model.customTabsEdit
                |> Maybe.map (\edit -> UI.Flip.beginReorder .entryId customTabChipDomId GotPreMoveCustomTabPositions -1 entryId edit.pending)
                |> Maybe.withDefault Cmd.none
                |> Effect.fromCmd
            )

        MoveCustomTabRightClicked entryId ->
            ( model
            , model.customTabsEdit
                |> Maybe.map (\edit -> UI.Flip.beginReorder .entryId customTabChipDomId GotPreMoveCustomTabPositions 1 entryId edit.pending)
                |> Maybe.withDefault Cmd.none
                |> Effect.fromCmd
            )

        GotPreMoveCustomTabPositions entryId _ offset (Err _) ->
            ( { model
                | customTabsEdit =
                    model.customTabsEdit |> Maybe.map (\edit -> { edit | pending = UI.Flip.moveListItemBy .entryId offset entryId edit.pending })
              }
            , Effect.none
            )

        GotPreMoveCustomTabPositions entryId neighborEntryId offset (Ok ( chipEl, neighborEl )) ->
            ( { model
                | customTabsEdit =
                    model.customTabsEdit
                        |> Maybe.map
                            (\edit ->
                                { edit
                                    | pending = UI.Flip.moveListItemBy .entryId offset entryId edit.pending
                                    , moveAnimations = UI.Flip.applyReorder UI.Flip.Horizontal CustomTabMoveSettled entryId neighborEntryId chipEl neighborEl edit.moveAnimations
                                }
                            )
              }
            , Effect.none
            )

        CustomTabMoveSettled entryId ->
            ( { model
                | customTabsEdit =
                    model.customTabsEdit
                        |> Maybe.map (\edit -> { edit | moveAnimations = Dict.update entryId (Maybe.map (\state -> { state | moving = False })) edit.moveAnimations })
              }
            , Effect.none
            )

        AnimateCustomTabFlip animMsg ->
            case model.customTabsEdit of
                Just edit ->
                    let
                        step : String -> UI.Flip.State Msg -> ( Dict String (UI.Flip.State Msg), List (Cmd Msg) ) -> ( Dict String (UI.Flip.State Msg), List (Cmd Msg) )
                        step key state ( states, stepCmds ) =
                            let
                                ( newState, cmd ) =
                                    UI.Flip.animate animMsg state
                            in
                            ( Dict.insert key newState states, cmd :: stepCmds )

                        ( newAnimations, cmds ) =
                            Dict.foldl step ( Dict.empty, [] ) edit.itemAnimations
                    in
                    ( { model | customTabsEdit = Just { edit | itemAnimations = newAnimations } }, Effect.fromCmd (Cmd.batch cmds) )

                Nothing ->
                    ( model, Effect.none )

        AnimateCustomTabMove animMsg ->
            case model.customTabsEdit of
                Just edit ->
                    let
                        step : String -> UI.Flip.MoveState Msg -> ( Dict String (UI.Flip.MoveState Msg), List (Cmd Msg) ) -> ( Dict String (UI.Flip.MoveState Msg), List (Cmd Msg) )
                        step key state ( states, stepCmds ) =
                            let
                                ( newState, cmd ) =
                                    UI.Flip.moveAnimate animMsg state
                            in
                            ( Dict.insert key newState states, cmd :: stepCmds )

                        ( newAnimations, cmds ) =
                            Dict.foldl step ( Dict.empty, [] ) edit.moveAnimations
                    in
                    ( { model | customTabsEdit = Just { edit | moveAnimations = newAnimations } }, Effect.fromCmd (Cmd.batch cmds) )

                Nothing ->
                    ( model, Effect.none )

        CustomTabHomeTargetKindChanged text ->
            ( { model
                | customTabsEdit =
                    model.customTabsEdit
                        |> Maybe.map
                            (mapHome
                                (\home ->
                                    case CustomNav.homeTargetKindFromText text of
                                        Just (CustomNav.KindTab navTab) ->
                                            { home | target = CustomNav.TargetTab navTab }

                                        Just CustomNav.KindPost ->
                                            case home.target of
                                                CustomNav.TargetPost _ ->
                                                    home

                                                _ ->
                                                    { home | target = CustomNav.TargetPost "" }

                                        _ ->
                                            home
                                )
                            )
              }
            , Effect.none
            )

        CustomTabHomePostIdChanged text ->
            ( { model | customTabsEdit = model.customTabsEdit |> Maybe.map (mapHome (\home -> { home | target = CustomNav.TargetPost text })) }
            , Effect.none
            )

        CustomTabHomePinnedPostIdsChanged text ->
            ( { model | customTabsEdit = model.customTabsEdit |> Maybe.map (\edit -> { edit | pinnedPostIdsText = text }) }
            , Effect.none
            )

        CustomTabHomeShowEventsStripToggled ->
            ( { model | customTabsEdit = model.customTabsEdit |> Maybe.map (mapHome (\home -> { home | showEventsStrip = not home.showEventsStrip })) }
            , Effect.none
            )

        CustomTabHomeEventsStripToRowToggled ->
            ( { model | customTabsEdit = model.customTabsEdit |> Maybe.map (mapHome (\home -> { home | defaultEventsStripToRow = not home.defaultEventsStripToRow })) }
            , Effect.none
            )

        CustomTabHomeEventsStripCalendarDisplayModeChanged text ->
            ( { model
                | customTabsEdit =
                    model.customTabsEdit
                        |> Maybe.map
                            (mapHome
                                (\home ->
                                    case CustomNav.calendarDisplayModeFromText text of
                                        Just mode ->
                                            { home | defaultEventsStripCalendarDisplayMode = mode }

                                        Nothing ->
                                            home
                                )
                            )
              }
            , Effect.none
            )

        TabStyleChanged text ->
            case ( CustomNav.navigationTabStyleFromText text, Common.adminAccountFor shared targetHost ) of
                ( Just style, Just account ) ->
                    ( model
                    , AccountsPanel.updateServerConfig shared.accounts ( Just account.userId, targetHost ) (applyTabStyle style)
                        |> Task.attempt GotTabStyleSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotTabStyleSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            ( model
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotTabStyleSaveResult (Err _) ->
            -- No dedicated error UI -- `tabStyleRow`'s `<select>` isn't part of any edit session
            -- (see `TabStyleChanged`'s own doc), so there's no form/status to surface it on; a
            -- failed save just leaves the nav showing whatever style the last successful save set,
            -- same as picking a value and then losing connectivity before it lands.
            ( model, Effect.none )


{-| Reacts to a `Shared.Msg` forwarded through by the parent's own `SharedMsg` branch -- only the
shared `Shared.MyMediaPanel` chooser (opened by `CustomTabChooseImageClicked`) reporting a tap
matters here, gated on `customTabsEdit.editingIconFor` naming the entry that's actually mid-pick (so
an unrelated Browse-mode tap elsewhere can't be mistaken for an icon pick). Mirrors
`ThemeTab.applySharedMsg`'s own `MediaItemClicked` handling -- `ThemeTab.applySharedMsg` itself
forwards here alongside its own `logoEdit` handling, since both can be live `Shared.MyMediaPanel`
consumers (never simultaneously in practice, but each only reacts if it's the one actually mid-pick).
-}
applySharedMsg : Shared.Msg -> Model -> Model
applySharedMsg subMsg model =
    { model
        | customTabsEdit =
            case subMsg of
                Shared.MyMediaPanelMsg (MyMediaPanel.MediaItemClicked mediaId) ->
                    model.customTabsEdit
                        |> Maybe.map
                            (\edit ->
                                case edit.editingIconFor of
                                    Just entryId ->
                                        { edit | editingIconFor = Nothing }
                                            |> mapPendingEntry entryId (\entry -> { entry | icon = CustomNav.MediaIcon mediaId })

                                    Nothing ->
                                        edit
                            )

                _ ->
                    model.customTabsEdit
    }


{-| `CustomTabsEditClicked`'s starting point -- one `CustomTabEntry` per `UI.CustomNav.effectiveTabs`
entry (so a freshly-opened editor starts from `defaultTabs` when `customTabs` itself is unset,
same "unset means the code-defined defaults" rule `CustomNav.effectiveTabs` already encodes),
`index` minting each entry's own stable `entryId` (see `CustomTabsEdit`'s own doc).
-}
customTabEntryFrom : Int -> CustomNav.CustomTab -> CustomTabEntry
customTabEntryFrom index tab =
    { entryId = "tab-" ++ String.fromInt index
    , target = tab.target
    , icon = tab.icon
    , title = Maybe.withDefault "" tab.title
    , path = tab.path
    }


{-| Updates the one entry of `edit.pending` matching `entryId`, if any -- every per-entry field
Msg's shared plumbing. Mirrors `FederationTab.mapPendingHost`.
-}
mapPendingEntry : String -> (CustomTabEntry -> CustomTabEntry) -> CustomTabsEdit -> CustomTabsEdit
mapPendingEntry entryId fn edit =
    { edit
        | pending =
            edit.pending
                |> List.map
                    (\entry ->
                        if entry.entryId == entryId then
                            fn entry

                        else
                            entry
                    )
    }


{-| Updates `edit.home` -- every `Home`-slot field Msg's shared plumbing, mirroring `mapPendingEntry`'s
identical role for `edit.pending`.
-}
mapHome : (CustomNav.HomePageConfig -> CustomNav.HomePageConfig) -> CustomTabsEdit -> CustomTabsEdit
mapHome fn edit =
    { edit | home = fn edit.home }


{-| Empty (after trimming) `<input>` text round-trips to `Nothing` -- `applyCustomTabs`' own entry
`title` fields represent "unset" this way, mirroring `SettingsTab.optionalString`'s identical
convention for its own editors' alias fields.
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


{-| `CustomTabsSaveClicked`'s transform, passed to `AccountsPanel.updateServerConfig` the same way
every other editor's transform is -- overlays `edit.pending` (in the edit's own order) onto a
freshly re-fetched `ServerConfiguration`'s `customTabs.tabs`, and `edit.home`/`edit.pinnedPostIdsText`
onto `customTabs.home` (via `UI.CustomNav.toProtoHomeConfig`, which is what actually enforces the
allowed-targets restriction, see that function's own doc). Each tab entry's blank `title` round-trips
to `Nothing` (see `optionalString`); `path` is sent as-is -- the backend's `validate_configuration` is
the actual authority on whether it's a valid `[a-z_]+` slug (see `CustomTabEntry`'s own doc), surfaced
back through `GotCustomTabsSaveResult`'s `Err` branch same as any other rejected save. A blank
`edit.home.target`'s `TargetPost ""` (an admin who's switched Home to "Custom Post" but hasn't typed
an id yet) round-trips through unvalidated too, same light-touch style -- as does an empty entry in
`pinnedPostIdsText` (a trailing/doubled comma), silently dropped by `parsePinnedPostIds` rather than
saved as a blank id.
-}
applyCustomTabs : CustomTabsEdit -> ServerConfiguration -> ServerConfiguration
applyCustomTabs edit config =
    let
        existing : Proto.Rellm.CustomNavigationTabSet
        existing =
            Maybe.withDefault defaultCustomNavigationTabSet config.customTabs

        toProtoCustomTab : CustomTabEntry -> Proto.Rellm.CustomNavigationTab
        toProtoCustomTab entry =
            CustomNav.toProtoTab
                { target = entry.target, icon = entry.icon, title = optionalString entry.title, path = entry.path }

        home : CustomNav.HomePageConfig
        home =
            edit.home |> withPinnedPostIds (parsePinnedPostIds edit.pinnedPostIdsText)

        withPinnedPostIds : List String -> CustomNav.HomePageConfig -> CustomNav.HomePageConfig
        withPinnedPostIds pinnedPostIds homeConfig =
            { homeConfig | pinnedPostIds = pinnedPostIds }
    in
    { config
        | customTabs =
            Just
                { existing
                    | tabs = edit.pending |> List.map toProtoCustomTab
                    , home = CustomNav.toProtoHomeConfig home
                }
    }


{-| `TabStyleChanged`'s transform -- overlays just `tabStyle` onto a freshly re-fetched
`ServerConfiguration`'s `customTabs`, leaving `home`/`tabs` untouched. Separate from
`applyCustomTabs` because this setting saves immediately on every change (see `tabStyleRow`'s own
doc), not as part of that editor's own Save/Cancel round-trip.
-}
applyTabStyle : NavigationTabStyle -> ServerConfiguration -> ServerConfiguration
applyTabStyle style config =
    let
        existing : Proto.Rellm.CustomNavigationTabSet
        existing =
            Maybe.withDefault defaultCustomNavigationTabSet config.customTabs
    in
    { config | customTabs = Just { existing | tabStyle = style } }


{-| `edit.pinnedPostIdsText`'s parse, at save time -- comma-separated (not also whitespace-separated
like `ExternalCDNConfig.media_ipv4_allowlist`'s own CSV convention, since a Post id -- unlike an IP
range -- isn't guaranteed never to contain a space), trimmed, and blank entries (an empty string, or
one that's all whitespace -- e.g. a trailing/doubled comma) dropped.
-}
parsePinnedPostIds : String -> List String
parsePinnedPostIds text =
    text
        |> String.split ","
        |> List.map String.trim
        |> List.filter (not << String.isEmpty)


{-| The DOM `id` a custom-tab chip is rendered with while `customTabsEdit` is active -- the
`UI.Flip.Horizontal` counterpart `MoveCustomTabLeftClicked`/`MoveCustomTabRightClicked` measure.
Mirrors `FederationTab.federatedServerChipDomId`.
-}
customTabChipDomId : String -> String
customTabChipDomId entryId =
    "custom-tab-chip-" ++ entryId



-- VIEW


{-| The "Navigation Tabs" section -- a horizontal `Home` chip (always the server's own logo/name,
see `homeTabChip`'s own doc for why its _look_ stays fixed even though what it links to is editable
too, via `edit.home`) followed by one chip per `UI.CustomNav.effectiveTabs` entry, previewing
exactly the order/icons `UI.headerNav` itself would show for this `server` if it were
`Shared.AccountsPanel.Model.mainFrontendHost` (see `UI.CustomNav`'s own module doc). Plain display
chips (`customTabsDisplayView`) when nothing's being edited, or the FLIP-reorderable editor
(`customTabsEditorView`) once `CustomTabsEditClicked` has started one -- same split as `ThemeTab`'s
own `colorEditorRow`/`logoEditorView`. `Home`'s own target (Default vs. a custom Post, `homeEditChip`)
saves/cancels in that same editor, alongside `pending` (see `CustomTabsEdit`'s own doc for why it
isn't a `CustomTabEntry` itself).
-}
view : RellmServer -> Maybe RellmAccount -> Model -> Html Msg
view server maybeAdminAccount model =
    div []
        [ div [ Html.Attributes.class "server-details-custom-tabs" ]
            [ h3 [ classes [ "section-title" ] ] [ text "Navigation Tabs" ]
            , case model.customTabsEdit of
                Just edit ->
                    customTabsEditorView server edit

                Nothing ->
                    customTabsDisplayView server (CustomNav.effectiveTabs (RellmServers.configurationOf server).customTabs)
            , case ( model.customTabsEdit, maybeAdminAccount ) of
                ( Nothing, Just _ ) ->
                    button [ Html.Attributes.class "server-details-rename-button", onClick CustomTabsEditClicked ] [ text "Edit Tabs" ]

                _ ->
                    text ""
            ]
        , tabStyleRow server maybeAdminAccount
        ]


{-| "Tab Style" -- the `NavigationTabStyle` picker for how `UI.headerNav` lays every tab out
(icon-only/text-only/icon+text, see `UI.CustomNav.navigationTabStyleClass`). Its own section, below
the whole "Navigation Tabs" one above (and unrelated to `model.customTabsEdit`) -- unlike
`home`/`pending`, this is a single independent setting that saves immediately on change
(`TabStyleChanged`), not a multi-field form with its own Edit/Save/Cancel. Just a live `<select>`
for a server admin, or plain read-only text for everyone else.
-}
tabStyleRow : RellmServer -> Maybe RellmAccount -> Html Msg
tabStyleRow server maybeAdminAccount =
    let
        currentStyle : NavigationTabStyle
        currentStyle =
            CustomNav.effectiveTabStyle (RellmServers.configurationOf server).customTabs
    in
    div [ Html.Attributes.class "server-details-setting" ]
        [ Common.settingsRow "Tab Style"
            (case maybeAdminAccount of
                Just _ ->
                    tabStyleSelect currentStyle

                Nothing ->
                    text (CustomNav.navigationTabStyleText currentStyle)
            )
        ]


tabStyleSelect : NavigationTabStyle -> Html Msg
tabStyleSelect currentStyle =
    select [ onInput TabStyleChanged ]
        (CustomNav.allNavigationTabStyles
            |> List.map
                (\style ->
                    option
                        [ value (CustomNav.navigationTabStyleText style), selected (style == currentStyle) ]
                        [ text (CustomNav.navigationTabStyleText style) ]
                )
        )


customTabsDisplayView : RellmServer -> List CustomNav.CustomTab -> Html Msg
customTabsDisplayView server tabs =
    div [ Html.Attributes.class "custom-tabs-strip" ] (homeTabChip server :: List.map (customTabChip server) tabs)


{-| The `Home` slot's own read-only chip (`customTabsDisplayView`) -- always the server's own
logo/name (`RellmServers.rellmServerNameAndLogo`, same content `UI.homeLinkContent` shows in the real
nav), regardless of `customTabs.home`. Deliberately stays this way even though what it links to is
editable (`homeEditChip`, `customTabsEditorView`'s own use while an edit is in progress): the chip
strip previews _where the Home tab sits in the nav_, not what page it currently renders, and every
other tab's own chip is keyed off its `icon`/`title`, neither of which a `home` override ever sets
(see `UI.CustomNav.homeTarget`'s own doc). Shown in `customTabsDisplayView` so the preview always
reads as "this is where Home sits, then your tabs."
-}
homeTabChip : RellmServer -> Html msg
homeTabChip server =
    div [ classes [ "server-chip", "custom-tab-chip", "custom-tab-chip-home", hostnameToCSSClass server.frontendHost ] ]
        [ div [ classes [ "server-chip-top", "background-color-primary" ] ]
            [ RellmServers.rellmServerNameAndLogo server RellmServers.RegularServerLogo ]
        , div [ classes [ "server-chip-bottom", "background-color-nav" ] ]
            [ span [ Html.Attributes.class "custom-tab-chip-label" ] [ text "Home" ] ]
        ]


customTabChip : RellmServer -> CustomNav.CustomTab -> Html msg
customTabChip server tab =
    div [ classes [ "server-chip", "custom-tab-chip", hostnameToCSSClass server.frontendHost ] ]
        [ div [ classes [ "server-chip-top", "background-color-primary", "custom-tab-chip-icon-row" ] ]
            [ CustomNav.iconView server tab.icon ]
        , div [ classes [ "server-chip-bottom", "background-color-nav" ] ]
            [ span [ Html.Attributes.class "custom-tab-chip-label" ] [ text (CustomNav.resolvedTitle tab) ] ]
        ]


{-| The chip strip (add/remove/reorder-animated via `UI.Flip`, mirroring `FederationTab.federationEditorView`
almost exactly), the "Add Tab" button, and the Save/Cancel actions -- everything shown once
`CustomTabsEditClicked` has started an edit. `homeEditChip` is always the strip's first, non-FLIP,
non-reorderable entry (see its own doc) -- it edits `edit.home` directly rather than being one of
`edit.pending`.
-}
customTabsEditorView : RellmServer -> CustomTabsEdit -> Html Msg
customTabsEditorView server edit =
    div [ Html.Attributes.class "server-details-custom-tabs-edit" ]
        [ Html.Keyed.node "div"
            [ classes [ "custom-tabs-strip", "flip-animated-row" ] ]
            (( "home", homeEditChip server edit )
                :: (edit.pending
                        |> List.indexedMap
                            (\index entry -> ( entry.entryId, customTabEditChipFlip server edit (List.length edit.pending) index entry ))
                   )
            )
        , div [ Html.Attributes.class "server-details-permissions-actions" ]
            [ button [ Html.Attributes.class "server-details-rename-button", onClick CustomTabAddClicked ] [ text "Add Tab" ] ]
        , div [ Html.Attributes.class "server-details-permissions-actions" ]
            [ Common.editSaveButton CustomTabsSaveClicked edit.status
            , Common.editCancelButton CustomTabsCancelClicked edit.status
            ]
        , Common.editErrorView edit.status
        ]


{-| Wraps `customTabEditChip` in a fading/scaling/collapsing animated outer `div` (entering when
freshly added via `CustomTabAddClicked`, removing when `CustomTabRemoveClicked`) -- mirrors
`FederationTab.federatedServerEditChipFlip` exactly, just over `CustomTabEntry` instead of
`FederatedServer`.
-}
customTabEditChipFlip : RellmServer -> CustomTabsEdit -> Int -> Int -> CustomTabEntry -> Html Msg
customTabEditChipFlip server edit count index entry =
    let
        flipState : UI.Flip.State Msg
        flipState =
            Dict.get entry.entryId edit.itemAnimations |> Maybe.withDefault UI.Flip.restingState

        isMoving : Bool
        isMoving =
            Dict.get entry.entryId edit.moveAnimations |> Maybe.map .moving |> Maybe.withDefault False

        pointerEventsAttr : List (Html.Attribute Msg)
        pointerEventsAttr =
            if flipState.removing then
                [ Html.Attributes.style "pointer-events" "none" ]

            else
                []
    in
    div (UI.Flip.itemAttributes UI.Flip.Horizontal flipState isMoving)
        [ div pointerEventsAttr [ customTabEditChip server edit count index entry ] ]


{-| One custom tab's editor chip: left/right reorder arrows flanking the icon editor (mirrors
`FederationTab.federatedServerEditChip`'s own layout), then the "type of tab" `<select>` (plus a
Post-id `<input>` when that's the chosen kind), a Title `<input>`, and a remove button.
-}
customTabEditChip : RellmServer -> CustomTabsEdit -> Int -> Int -> CustomTabEntry -> Html Msg
customTabEditChip server edit count index entry =
    let
        moveAttrs : List (Html.Attribute Msg)
        moveAttrs =
            edit.moveAnimations |> Dict.get entry.entryId |> Maybe.map UI.Flip.moveAttributes |> Maybe.withDefault []

        showBackward : Bool
        showBackward =
            index > 0

        showForward : Bool
        showForward =
            index < count - 1

        reorderPair : { backward : Html Msg, forward : Html Msg }
        reorderPair =
            UI.Flip.reorderButtonPair UI.Flip.Horizontal
                { moveBackward = onClick (MoveCustomTabLeftClicked entry.entryId)
                , moveForward = onClick (MoveCustomTabRightClicked entry.entryId)
                , canMoveBackward = showBackward
                , canMoveForward = showForward
                }
    in
    div
        (id (customTabChipDomId entry.entryId)
            :: classes [ "server-chip", "custom-tab-chip", "custom-tab-chip-edit", hostnameToCSSClass server.frontendHost ]
            :: moveAttrs
        )
        [ div [ classes [ "server-chip-top", "background-color-primary" ] ]
            [ div [ Html.Attributes.class "server-chip-logo-row" ]
                [ div [ Html.Attributes.classList [ ( "reorder-arrow", True ), ( "reorder-arrow-hidden", not showBackward ) ] ] [ reorderPair.backward ]
                , customTabIconEditor server entry
                , div [ Html.Attributes.classList [ ( "reorder-arrow", True ), ( "reorder-arrow-hidden", not showForward ) ] ] [ reorderPair.forward ]
                ]
            ]
        , div [ classes [ "server-chip-bottom", "background-color-nav", "custom-tab-chip-edit-fields" ] ]
            (List.concat
                [ [ customTabTargetSelect entry ]
                , case entry.target of
                    CustomNav.TargetPost postId ->
                        [ input
                            [ Html.Attributes.class "custom-tab-post-id-input"
                            , placeholder "Post ID"
                            , value postId
                            , onInput (CustomTabPostIdChanged entry.entryId)
                            ]
                            []
                        ]

                    CustomNav.TargetTab _ ->
                        []

                    CustomNav.TargetProfile ->
                        []
                , [ input
                        [ Html.Attributes.class "custom-tab-title-input"
                        , placeholder (CustomNav.resolvedTitle { target = entry.target, icon = entry.icon, title = Nothing, path = entry.path })
                        , value entry.title
                        , onInput (CustomTabTitleChanged entry.entryId)
                        ]
                        []
                  , input
                        [ Html.Attributes.class "custom-tab-path-input"
                        , placeholder
                            (case entry.target of
                                CustomNav.TargetProfile ->
                                    "username"

                                _ ->
                                    "path (a-z, _)"
                            )
                        , value entry.path
                        , onInput (CustomTabPathChanged entry.entryId)
                        ]
                        []
                  , button
                        [ Html.Attributes.class "remove-btn"
                        , onClick (CustomTabRemoveClicked entry.entryId)
                        , Html.Attributes.title "Remove tab"
                        ]
                        [ text "╳" ]
                  ]
                ]
            )
        ]


{-| An entry's icon editor: a live preview (`CustomNav.iconView`), an emoji `<input>` (only shown
while `entry.icon` is already an `EmojiIcon` -- typing into it always keeps it one, see
`CustomTabEmojiChanged`), and either a "Image…" button (opens `Shared.MyMediaPanel`, see
`CustomTabChooseImageClicked`/`applySharedMsg`) or, once a `MediaIcon`'s chosen, a "Use Emoji" button
reverting to a blank `EmojiIcon` instead.
-}
customTabIconEditor : RellmServer -> CustomTabEntry -> Html Msg
customTabIconEditor server entry =
    div [ Html.Attributes.class "custom-tab-icon-editor" ]
        [ div [ Html.Attributes.class "custom-tab-icon-preview" ] [ CustomNav.iconView server entry.icon ]
        , case entry.icon of
            CustomNav.EmojiIcon emoji ->
                input
                    [ Html.Attributes.class "custom-tab-emoji-input"
                    , placeholder "✨"
                    , value emoji
                    , onInput (CustomTabEmojiChanged entry.entryId)
                    ]
                    []

            CustomNav.MediaIcon _ ->
                text ""
        , div [ Html.Attributes.class "custom-tab-icon-actions" ]
            [ button [ Html.Attributes.class "custom-tab-icon-choose", onClick (CustomTabChooseImageClicked entry.entryId) ] [ text "Image…" ]
            , case entry.icon of
                CustomNav.MediaIcon _ ->
                    button [ Html.Attributes.class "custom-tab-icon-choose", onClick (CustomTabRemoveImageClicked entry.entryId) ] [ text "Use Emoji" ]

                CustomNav.EmojiIcon _ ->
                    text ""
            ]
        ]


customTabTargetSelect : CustomTabEntry -> Html Msg
customTabTargetSelect entry =
    select [ onInput (CustomTabTargetKindChanged entry.entryId) ]
        (CustomNav.selectableTargetKinds
            |> List.map
                (\kind ->
                    option
                        [ value (CustomNav.targetKindText kind), selected (CustomNav.targetKind entry.target == kind) ]
                        [ text (CustomNav.targetKindText kind) ]
                )
        )


{-| The `Home` slot's own editor chip -- shown in place of the plain `homeTabChip` while
`customTabsEdit` is active (`customTabsEditorView`'s own use). No reorder arrows (`home` always
sits first, isn't part of `edit.pending`), no icon editor (its look stays fixed, see
`homeTabChip`'s own doc), no Title/Path `<input>` or remove button (`home` isn't a `CustomTabEntry`
and can't be removed) -- just the server logo up top, then `homeTargetSelect` (plus a conditional
Post-id `<input>`, when `edit.home.target` is a `CustomNav.TargetPost`), a Pinned Posts `<input>`
(meaningful for every target, so always shown -- see `CustomHomePage.pinned_post_ids`' own proto
doc), and, only when `edit.home.target` is a `CustomNav.TargetPost` (the only target the "Show
Events strip" toggle actually does anything for -- see `CustomHomePage.show_events_strip`'s own
proto doc), the events-strip toggle and its own conditional row/calendar-mode controls. Mirrors
`customTabEditChip`'s own bottom row.
-}
homeEditChip : RellmServer -> CustomTabsEdit -> Html Msg
homeEditChip server edit =
    div [ classes [ "server-chip", "custom-tab-chip", "custom-tab-chip-home", "custom-tab-chip-edit", hostnameToCSSClass server.frontendHost ] ]
        [ div [ classes [ "server-chip-top", "background-color-primary" ] ]
            [ RellmServers.rellmServerNameAndLogo server RellmServers.RegularServerLogo ]
        , div [ classes [ "server-chip-bottom", "background-color-nav", "custom-tab-chip-edit-fields" ] ]
            (List.concat
                [ [ homeTargetSelect edit.home.target ]
                , case edit.home.target of
                    CustomNav.TargetPost postId ->
                        [ input
                            [ Html.Attributes.class "custom-tab-post-id-input"
                            , placeholder "Post ID"
                            , value postId
                            , onInput CustomTabHomePostIdChanged
                            ]
                            []
                        ]

                    _ ->
                        []
                , [ input
                        [ Html.Attributes.class "custom-tab-pinned-post-ids-input"
                        , placeholder "Pinned post IDs (comma-separated)"
                        , value edit.pinnedPostIdsText
                        , onInput CustomTabHomePinnedPostIdsChanged
                        ]
                        []
                  ]
                , case edit.home.target of
                    CustomNav.TargetPost _ ->
                        homeEventsStripFields edit.home

                    _ ->
                        []
                ]
            )
        ]


{-| The "Show Events strip"/row-vs-calendar/calendar-granularity controls -- only ever shown by
`homeEditChip` when `edit.home.target` is a `CustomNav.TargetPost` (see that function's own doc for
why every other target leaves `show_events_strip` alone rather than offering a control for it).
-}
homeEventsStripFields : CustomNav.HomePageConfig -> List (Html Msg)
homeEventsStripFields home =
    Common.settingsRow "Show Events strip above Post" (Common.flagSwitch home.showEventsStrip CustomTabHomeShowEventsStripToggled)
        :: (if home.showEventsStrip then
                [ Common.settingsRow "Default Events strip to row layout" (Common.flagSwitch home.defaultEventsStripToRow CustomTabHomeEventsStripToRowToggled)
                , select [ onInput CustomTabHomeEventsStripCalendarDisplayModeChanged ]
                    (CustomNav.allCalendarDisplayModes
                        |> List.map
                            (\mode ->
                                option
                                    [ value (CustomNav.calendarDisplayModeText mode)
                                    , selected (home.defaultEventsStripCalendarDisplayMode == mode)
                                    ]
                                    [ text (CustomNav.calendarDisplayModeText mode) ]
                            )
                    )
                ]

            else
                []
           )


{-| The "type" `<select>` for the `Home` slot -- `UI.CustomNav.selectableHomeTargetKinds` (Home
Page/Events Page/Posts Page/Custom Post) rather than `customTabTargetSelect`'s fuller
`selectableTargetKinds`, since `home`'s own proto doc restricts it to fewer choices (no
People/About/Profile). Mirrors `customTabTargetSelect`'s own shape exactly, just over
`UI.CustomNav.homeTargetKindFromText` instead of `targetKindFromText`.
-}
homeTargetSelect : CustomNav.CustomTabTarget -> Html Msg
homeTargetSelect target =
    select [ onInput CustomTabHomeTargetKindChanged ]
        (CustomNav.selectableHomeTargetKinds
            |> List.map
                (\kind ->
                    option
                        [ value (CustomNav.targetKindText kind), selected (CustomNav.targetKind target == kind) ]
                        [ text (CustomNav.targetKindText kind) ]
                )
        )
