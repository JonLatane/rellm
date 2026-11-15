module Components.Pages.ServerInformationPage.Common exposing (accountsPanelEffect, adminAccountFor, subdomainOwnerAccountFor, subdomainSettingsFor, editCancelButton, editErrorView, editSaveButton, editSaveButtonWhen, flagSwitch, settingsNote, settingsRow, switchDisplay)

{-| Shared, `msg`-generic bits reused by 2+ of `Components.Pages.ServerInformationPage`'s tab
submodules (`AboutTab`/`ThemeTab`/`SettingsTab`/`FederationTab`) -- pulled out so none of them have
to duplicate the same Save/Cancel/error/toggle-switch look, or the same "is this the signed-in
account, and are they an admin on this server" check.
-}

import Effect exposing (Effect)
import Html exposing (Html, button, div, input, label, p, span, text)
import Html.Attributes exposing (checked, class, disabled, type_)
import Html.Events exposing (onClick)
import Shared
import Shared.AccountsPanel as AccountsPanel
import Proto.Rellm exposing (SubdomainSettings)
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers
import UI.Classes exposing (classes)


{-| The signed-in, enabled account (if any) on `targetHost`, but only if it actually has `ADMIN` --
what every tab gates its own Edit buttons/editors on. Renaming (or any other `ConfigureServer`
mutation) is only possible for a server that's already known, so this only ever matches once the
page has resolved an `RellmServer` for `targetHost` to begin with.
-}
adminAccountFor : Shared.Model -> String -> Maybe RellmAccount
adminAccountFor shared targetHost =
    RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts targetHost
        |> Maybe.andThen
            (\account ->
                if RellmAccounts.isAdmin account then
                    Just account

                else
                    Nothing
            )


{-| The `SubdomainSettings` of `targetHost`'s configuration -- `Just` only when `targetHost` is a Rellm Subdomain
(`jon.bullcity.social`; see `ServerConfiguration.subdomain_settings`), whose page shows only the tabs that make
sense for one user and whose saves go through `SaveMarketSubscription` instead of `ConfigureServer`.
-}
subdomainSettingsFor : Shared.Model -> String -> Maybe SubdomainSettings
subdomainSettingsFor shared targetHost =
    RellmServers.rellmServerForHost shared.accounts.servers targetHost
        |> Maybe.andThen (\server -> (RellmServers.configurationOf server).subdomainSettings)


{-| On a subdomain, the signed-in account that *owns* it (`SubdomainSettings.subdomainOf` is its user id) -- the
subdomain's equivalent of `adminAccountFor`: the only account whose Edit buttons show, saving via
`SaveMarketSubscription`. `Nothing` on a normal server, or for anyone else.
-}
subdomainOwnerAccountFor : Shared.Model -> String -> Maybe RellmAccount
subdomainOwnerAccountFor shared targetHost =
    subdomainSettingsFor shared targetHost
        |> Maybe.andThen
            (\settings ->
                RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts targetHost
                    |> Maybe.andThen
                        (\account ->
                            if account.userId == settings.subdomainOf then
                                Just account

                            else
                                Nothing
                        )
            )


{-| Turns a `Maybe AccountsPanel.Msg` (as returned by `AccountsPanel.updateServerConfig`, if a
token refresh happened) into an `Effect` to forward it, `Effect.none` otherwise. Mirrors
`UserProfilePage.accountsPanelEffect`.
-}
accountsPanelEffect : Maybe AccountsPanel.Msg -> Effect msg
accountsPanelEffect maybeAccountsPanelMsg =
    maybeAccountsPanelMsg
        |> Maybe.map (Shared.AccountsPanelMsg >> Effect.fromShared)
        |> Maybe.withDefault Effect.none


editSaveButton : msg -> AccountsPanel.FormStatus -> Html msg
editSaveButton onSave status =
    button
        [ classes [ "server-details-rename-save", "background-color-primary" ]
        , onClick onSave
        , disabled (status == AccountsPanel.Submitting)
        ]
        [ text
            (if status == AccountsPanel.Submitting then
                "Saving…"

             else
                "Save"
            )
        ]


{-| `editSaveButton`, except it's only highlighted (the server's primary color) while `changed` --
i.e. while the edit differs from what's saved -- and a plain neutral button otherwise.
-}
editSaveButtonWhen : Bool -> msg -> AccountsPanel.FormStatus -> Html msg
editSaveButtonWhen changed onSave status =
    button
        [ classes
            (if changed then
                [ "server-details-rename-save", "background-color-primary" ]

             else
                [ "server-details-rename-save" ]
            )
        , onClick onSave
        , disabled (status == AccountsPanel.Submitting)
        ]
        [ text
            (if status == AccountsPanel.Submitting then
                "Saving…"

             else
                "Save"
            )
        ]


editCancelButton : msg -> AccountsPanel.FormStatus -> Html msg
editCancelButton onCancel status =
    button [ class "server-details-rename-cancel", onClick onCancel, disabled (status == AccountsPanel.Submitting) ] [ text "Cancel" ]


editErrorView : AccountsPanel.FormStatus -> Html msg
editErrorView status =
    case status of
        AccountsPanel.Errored err ->
            span [ class "server-details-rename-error" ] [ text err ]

        _ ->
            text ""


{-| One label + right-aligned value/control row, reused across every tab's editors (feature
settings, CDN config, Facebook auth fields, ...) -- `.server-details-feature-settings-row` in
servers.css (label-left/control-right, `justify-content: space-between`).
-}
settingsRow : String -> Html msg -> Html msg
settingsRow label_ control =
    div [ class "server-details-feature-settings-row" ]
        [ span [ class "server-details-feature-settings-label" ] [ text label_ ]
        , control
        ]


{-| A small, dimmed explanatory note meant to sit directly under a `settingsRow` (no margin of its
own, so it reads as part of that row).
-}
settingsNote : String -> Html msg
settingsNote note =
    p [ class "server-details-feature-settings-note" ] [ text note ]


{-| A checkbox styled as a toggle switch, same `.switch`/`.slider` classes as `UI.switchInput` --
not reused directly since that function's `toggleMsg` is hard-coded to `Shared.Msg`, and every
caller here has its own tab-local `Msg`.
-}
flagSwitch : Bool -> msg -> Html msg
flagSwitch isChecked toggleMsg =
    label [ class "switch" ]
        [ input [ type_ "checkbox", checked isChecked, onClick toggleMsg ] []
        , span [ class "slider" ] []
        ]


{-| An always-disabled toggle switch -- for settings this page shows but never lets this viewer
(or, for the CDN tab, no viewer at all yet) edit. Styled identically to `UI.elm`'s own
`switchInput` (same `.switch`/`.disabled`/`.slider` classes, see `switch.css`), just without
needing a live `Shared.Msg` to fire (it never will).
-}
switchDisplay : Bool -> Html msg
switchDisplay isChecked =
    label [ classes [ "switch", "disabled" ] ]
        [ input [ type_ "checkbox", checked isChecked, disabled True ] []
        , span [ class "slider" ] []
        ]
