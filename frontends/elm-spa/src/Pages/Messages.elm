module Pages.Messages exposing (Model, Msg, fromShared, page)

{-| `/messages` -- the signed-in user's `MessagingGroup`s, expandable into
their messages, going two-pane whenever `?messaging_group=<id>[@host]`,
`?from_email=<address>[&from_email_host=<host>]`, or `?message=<id>[@host]`
is set (`#message-<id>` autoscrolls to a specific message once its thread
loads) -- one query param per `Components.Messages.Conversation`, see
`MessagesPage.groupQueryParams`'s own doc on why `from_email` needs a
separate host param rather than reusing the other two kinds' `id@host`
suffix. Thin `Effect`/`Shared`/URL-owning wrapper around
`Components.Pages.MessagesPage`, which can't depend on `Shared` itself since
`Shared.MessagingPanel` embeds it too -- see that module's own doc.
-}

import Components.FulfillmentThreads as Fulfillment
import Components.Messages as Messages
import Components.Pages.MessagesPage as MessagesPage
import Dict
import Effect exposing (Effect)
import Gen.Params.Messages exposing (Params)
import Html
import Page
import Request
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.MarkdownPanel as MarkdownPanel
import Shared.MessagingPanel as MessagingPanel
import UI
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared req =
    Page.advanced
        { init = init shared req
        , update = update shared
        , view = view shared req
        , subscriptions = subscriptions
        }


type alias Model =
    MessagesPage.Model


type Msg
    = PageMsg MessagesPage.Msg
    | SharedMsg Shared.Msg


init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared req =
    let
        -- One of `?messaging_group=`/`?from_email=`/`?message=` -- see
        -- `Components.Messages.Conversation`'s own doc on why each kind gets
        -- its own param rather than overloading one, and `MessagesPage.groupQueryParams`'s
        -- doc on why `from_email` alone needs a separate `from_email_host`
        -- param instead of `parseGroupRouteId`'s shared `id@host` suffix
        -- (an email address already contains its own `@`).
        selectedGroup : Maybe Messages.Conversation
        selectedGroup =
            case Dict.get "messaging_group" req.query of
                Just raw ->
                    let
                        ( groupId, host ) =
                            Messages.parseGroupRouteId shared.accounts.mainFrontendHost raw
                    in
                    Just (Messages.MessagingGroup host groupId)

                Nothing ->
                    case Dict.get "from_email" req.query of
                        Just fromEmail ->
                            let
                                host : String
                                host =
                                    Dict.get "from_email_host" req.query |> Maybe.withDefault shared.accounts.mainFrontendHost
                            in
                            Just (Messages.FromEmail host fromEmail)

                        Nothing ->
                            Dict.get "message" req.query
                                |> Maybe.map
                                    (\raw ->
                                        let
                                            ( messageId, host ) =
                                                Messages.parseGroupRouteId shared.accounts.mainFrontendHost raw
                                        in
                                        Messages.SoloMessage host messageId
                                    )

        pendingScrollMessageId : Maybe String
        pendingScrollMessageId =
            req.url.fragment
                |> Maybe.andThen
                    (\fragment ->
                        if String.startsWith "message-" fragment then
                            Just (String.dropLeft 8 fragment)

                        else
                            Nothing
                    )

        searchText : String
        searchText =
            Dict.get "search_text" req.query |> Maybe.withDefault ""

        -- `?subscription_messages=<id>[@host]` -- one Fulfillment thread (a Rellm hosting
        -- subscription's notes), the subscription counterpart of `?messaging_group=`. Same `id@host`
        -- encoding; `#subscription-message-<n>` (a note's position) is the matching fragment.
        selectedSubscriptionThread : Maybe String
        selectedSubscriptionThread =
            Dict.get "subscription_messages" req.query
                |> Maybe.map
                    (\raw ->
                        let
                            ( subscriptionId, host ) =
                                Messages.parseGroupRouteId shared.accounts.mainFrontendHost raw
                        in
                        Fulfillment.threadKey host subscriptionId
                    )

        -- `?fulfillment_order=<id>[@host]` -- one admin Fulfillment-tab order, same encoding.
        selectedOrder : Maybe String
        selectedOrder =
            Dict.get "fulfillment_order" req.query
                |> Maybe.map
                    (\raw ->
                        let
                            ( orderId, host ) =
                                Messages.parseGroupRouteId shared.accounts.mainFrontendHost raw
                        in
                        "admin/" ++ Fulfillment.threadKey host orderId
                    )

        ( initialModel, cmd ) =
            MessagesPage.init shared.accounts (Just { navKey = req.key, path = req.url.path }) selectedGroup pendingScrollMessageId searchText

        -- An admin order deep link wins; otherwise the user's own subscription thread, if either is given.
        selectedThreadKey : Maybe String
        selectedThreadKey =
            if selectedOrder /= Nothing then
                selectedOrder

            else
                selectedSubscriptionThread

        model : Model
        model =
            case selectedThreadKey of
                Just key ->
                    MessagesPage.selectSubscriptionThread key initialModel

                Nothing ->
                    initialModel
    in
    ( model, Effect.batch [ Effect.fromCmd (Cmd.map PageMsg cmd), Effect.fromShared Shared.CloseAllPanels ] )


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    case msg of
        -- Intercepted before `applyPageMsg`/`MessagesPage.update` (whose own
        -- handling is a no-op, see the constructor's own doc) -- this is the
        -- one `MessagesPage.Msg` that actually needs `Shared`, which that
        -- module can't depend on itself. Opens the shared Markdown panel on
        -- a `SendNewMessage` pre-seeded with `recipients` (the other thread
        -- participants, computed at the button's own click site) and
        -- `ref`'s own host (`Messages.conversationHost`) -- a reply always
        -- sends from the same server the messaging group lives on.
        PageMsg (MessagesPage.ReplyClicked ref recipients) ->
            ( model, Effect.fromShared (Shared.MarkdownPanelMsg (MarkdownPanel.Open (MarkdownPanel.SendNewMessage recipients) (Messages.conversationHost ref))) )

        -- The header row's "Compose" button (`MessagesPage.searchRowView`,
        -- see `ComposeClicked`'s own doc) -- same interception trick as
        -- `ReplyClicked` above, just with no particular recipients and
        -- defaulting "sending as" to the first enabled account's server,
        -- same as this used to work back when it was a standalone button
        -- built directly here (`sendMessageButton`). Hidden entirely by
        -- `MessagesPage.composeButtonView` itself with nobody signed in
        -- anywhere, so this branch is only ever reached with at least one
        -- enabled account -- but falls back to a no-op rather than crashing
        -- if that invariant somehow doesn't hold.
        PageMsg MessagesPage.ComposeClicked ->
            case AccountsPanel.enabledAccounts shared.accounts of
                [] ->
                    ( model, Effect.none )

                firstAccount :: _ ->
                    ( model, Effect.fromShared (Shared.MarkdownPanelMsg (MarkdownPanel.Open (MarkdownPanel.SendNewMessage []) firstAccount.server)) )

        -- A "Mark [un]read" round trip (either the auto-mark-read that
        -- fires when a thread's viewed, or the explicit "Mark unread"
        -- button, see `MessagesPage.GotMarkReadResult`'s own doc) landing
        -- while this page owns the mounted `MessagesPage.Model` -- also
        -- refreshes `Shared.MessagingPanel`'s own, *separate* embedded copy
        -- (`MessagesPage.ForceRefresh`, same "unconditionally refetch"
        -- mechanism the `SendNewMessage`-succeeded case already uses for it
        -- -- see `Shared.elm`'s own `MarkdownPanelMsg` branch, and
        -- `ForceRefresh`'s own doc on why plain `Poll` can't do this),
        -- since it doesn't otherwise learn this page's read/unread changes
        -- at all.
        PageMsg ((MessagesPage.GotMarkReadResult (Ok _)) as subMsg) ->
            let
                ( updatedModel, pageEffect ) =
                    applyPageMsg shared subMsg model
            in
            ( updatedModel
            , Effect.batch [ pageEffect, Effect.fromShared (Shared.MessagingPanelMsg (MessagingPanel.PageMsg MessagesPage.ForceRefresh)) ]
            )

        -- Same idea for the Fulfillment tab: marking a thread's notes read here also refreshes the
        -- embedded panel's own, separate copy (and so its nav-button unread total).
        PageMsg ((MessagesPage.FulfillmentMsg (Fulfillment.GotMarkedRead _ (Ok _))) as subMsg) ->
            let
                ( updatedModel, pageEffect ) =
                    applyPageMsg shared subMsg model
            in
            ( updatedModel
            , Effect.batch [ pageEffect, Effect.fromShared (Shared.MessagingPanelMsg (MessagingPanel.PageMsg MessagesPage.ForceRefresh)) ]
            )

        PageMsg subMsg ->
            applyPageMsg shared subMsg model

        SharedMsg subMsg ->
            let
                ( updatedModel, updateEffect ) =
                    case subMsg of
                        Shared.AccountsPanelMsg _ ->
                            applyPageMsg shared MessagesPage.Poll model

                        -- A group link clicked in the embedded `Shared.MessagingPanel`
                        -- while already on this very page -- see
                        -- `MessagesPage.EmbeddedGroupLinkClicked`'s own doc for the
                        -- full "why" (a same-path query-only URL change doesn't
                        -- otherwise reach this page's `init`/`update` at all).
                        Shared.MessagingPanelMsg (MessagingPanel.PageMsg (MessagesPage.EmbeddedGroupLinkClicked ref)) ->
                            applyPageMsg shared (MessagesPage.SyncSelectedGroup ref) model

                        -- The message-level counterpart, immediately above --
                        -- a message row (not just a group row) clicked in the
                        -- embedded panel while already on this page -- see
                        -- `MessagesPage.EmbeddedMessageLinkClicked`'s own doc.
                        Shared.MessagingPanelMsg (MessagingPanel.PageMsg (MessagesPage.EmbeddedMessageLinkClicked ref messageId)) ->
                            applyPageMsg shared (MessagesPage.SyncSelectedMessage ref messageId) model

                        -- The reverse of `PageMsg (MessagesPage.GotMarkReadResult
                        -- (Ok _))`, above -- a "Mark [un]read" round trip
                        -- completing *inside the embedded panel itself*
                        -- (open on top of this very page) refetches this
                        -- page's own, separate `Model` too, so both copies
                        -- of the same messages stay in sync regardless of
                        -- which surface the read/unread change was actually
                        -- made from.
                        Shared.MessagingPanelMsg (MessagingPanel.PageMsg (MessagesPage.GotMarkReadResult (Ok _))) ->
                            applyPageMsg shared MessagesPage.ForceRefresh model

                        -- A subscription thread link clicked in the embedded panel while already on this page:
                        -- same reasoning as `EmbeddedGroupLinkClicked` above (a same-path, query-only URL
                        -- change never reaches this page's `init`/`update`).
                        Shared.MessagingPanelMsg (MessagingPanel.PageMsg (MessagesPage.EmbeddedThreadLinkClicked key)) ->
                            applyPageMsg shared (MessagesPage.SyncSelectedThread key) model

                        -- ...and the reverse, for the Fulfillment tab inside the embedded panel.
                        Shared.MessagingPanelMsg (MessagingPanel.PageMsg (MessagesPage.FulfillmentMsg (Fulfillment.GotMarkedRead _ (Ok _)))) ->
                            applyPageMsg shared MessagesPage.ForceRefresh model

                        -- A `ComposeClicked`/`ReplyClicked` send actually
                        -- landing while this is the mounted page -- the only
                        -- `MarkdownPanel.TargetType` reachable from here at
                        -- all (both above). Dispatches `MessagesPage.MessageSent`
                        -- with exactly where the new `Message` landed (its own
                        -- `messagingGroup`, plus `host` -- threaded through by
                        -- `MarkdownPanel.sendMessageTask` since neither's
                        -- otherwise recoverable once the RPC's done, see
                        -- `MarkdownPanel.GotSendMessageResult`'s own doc), so
                        -- the page can force-refetch that exact thread
                        -- (`MessageSent`'s own doc: plain `ForceRefresh`
                        -- alone wouldn't refresh an already-open thread at
                        -- all) and navigate/scroll to the new message, same
                        -- as landing on its own `#message-<id>` permalink
                        -- directly. `Shared.MessagingPanel`'s own embedded
                        -- copy gets a plain listing refresh directly from
                        -- `Shared.update` instead (see its `MarkdownPanelMsg`
                        -- branch) -- it has no URL/thread-detail view of its
                        -- own to navigate within, see `MessageSent`'s own doc.
                        -- Falls back to a plain `ForceRefresh` on the
                        -- (shouldn't-happen -- `send_message.rs` always
                        -- attaches one) chance the response has no
                        -- `messagingGroup`.
                        Shared.MarkdownPanelMsg (MarkdownPanel.GotSendMessageResult (Ok ( _, host, sentMessage ))) ->
                            case sentMessage.messagingGroup of
                                Just group ->
                                    applyPageMsg shared
                                        (MessagesPage.MessageSent (Messages.MessagingGroup host group.id) sentMessage.id)
                                        model

                                Nothing ->
                                    applyPageMsg shared MessagesPage.ForceRefresh model

                        _ ->
                            ( model, Effect.none )
            in
            ( updatedModel, Effect.batch [ Effect.fromShared subMsg, updateEffect ] )


applyPageMsg : Shared.Model -> MessagesPage.Msg -> Model -> ( Model, Effect Msg )
applyPageMsg shared subMsg model =
    let
        ( newModel, cmd, maybeAccountsPanelMsg ) =
            MessagesPage.update shared.accounts subMsg model

        accountEffect : Effect Msg
        accountEffect =
            maybeAccountsPanelMsg
                |> Maybe.map (Shared.AccountsPanelMsg >> Effect.fromShared)
                |> Maybe.withDefault Effect.none
    in
    ( newModel, Effect.batch [ Effect.fromCmd (Cmd.map PageMsg cmd), accountEffect ] )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.map PageMsg (MessagesPage.subscriptions model)


view : Shared.Model -> Request.With Params -> Model -> View Msg
view shared req model =
    { title = UI.pageTitle shared [ "Messages" ]
    , body =
        UI.layout shared
            req.route
            SharedMsg
            [ Html.map PageMsg (MessagesPage.view shared.time shared.basePath shared.accounts model) ]
    }


{-| Lets `Main` forward a `Shared.Msg` that didn't originate from this page --
see `Components.Pages.UsersPage.fromShared`.
-}
fromShared : Shared.Msg -> Msg
fromShared =
    SharedMsg
