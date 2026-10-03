module Components.MediaMaintenance exposing (deleteLinkPreviewImages, deleteUnownedMedia)

{-| The two admin-only media maintenance RPCs behind `Components.Pages.ServerInformationPage.SettingsTab`'s
Media Settings buttons. Kept out of `SettingsTab` itself because `deleteLinkPreviewImages` is fired by
`Shared.update`'s `ConfirmDelete` (after the `Shared.ConfirmDeleteLinkPreviewImages` dialog), and
`Shared` can't import a page tab.
-}

import Grpc
import Proto.Rellm.Rellm as Rellm
import Shared.AccountsPanel as AccountsPanel exposing (performWithAccountServer)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (withAccessToken)
import Task exposing (Task)


{-| Calls `DeleteLinkPreviewImages` -- unlinks every generated link preview image and makes every
linked post eligible for regeneration again. The old media is only orphaned, not deleted; see
`deleteUnownedMedia`.
-}
deleteLinkPreviewImages :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, () )
deleteLinkPreviewImages accountsPanelModel maybeAccountServer =
    performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.deleteLinkPreviewImages {}
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
                |> Task.map (always ())
        )


{-| Calls `DeleteUnownedMedia` -- deletes all media with no owner from storage and from any posts
still referencing it (including whatever `deleteLinkPreviewImages` just orphaned).
-}
deleteUnownedMedia :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, () )
deleteUnownedMedia accountsPanelModel maybeAccountServer =
    performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.deleteUnownedMedia {}
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
                |> Task.map (always ())
        )
