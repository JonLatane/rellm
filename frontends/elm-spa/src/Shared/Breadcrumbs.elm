module Shared.Breadcrumbs exposing (BreadcrumbRoot(..), Model, Msg(..), bar, init, previewPanel, update)

{-| A trail of "how did I get here" chips shown at the bottom of the top nav
(see `UI.headerNav`), for a Post reached by following a chain of replies (and,
eventually, Event/Occasion discussions) rather than directly: the root
thing's own title/name, then one avatar+username chip per reply on the way to
whichever Post is currently being viewed. Tapping any chip opens `replyPanel`,
a popup anchored just under the trail itself showing that chip's own Post --
so jumping back to an ancestor reply doesn't require actually navigating to
its own page. The open chip is tinted with `model.host`'s own
`background-color-primary` (see `UI.EmittedStylesheet`), so it's clear which
segment `replyPanel` is currently showing.

Wired into `Shared.Model`/`UI.elm` the same way `Shared.MarkdownPanel` is: one
shared occasion, populated contextually by whichever page has a chain to show
(currently just `Pages.Post.PostId_`, via `SetRoot`) rather than each page
owning its own breadcrumb state.

`FromPost` and `FromServerHost` are rendered -- `FromEvent` (an Event
Occasion's discussion, reached the same way) is a real variant already so
callers/`Model` don't need to change shape again once it's wired up, but its
`rootSegment`/its own ancestor-fetching aren't implemented yet.

`FromServerHost` is the odd one out: it isn't reached via a chain of replies
at all (see `SetRoot`'s own doc) -- `Pages.Home_` sets it to
`AccountsPanel.mainFrontendHost` since its feed isn't scoped to any one
server, just so the trail still shows _something_ identifying "home". A
`serverSegment` chip (server logo + name) is also what gets prepended at the
left of the trail on `FromPost`/`FromEvent` roots whenever `Model.host` isn't
`mainFrontendHost` -- see `bar`.

-}

import Components.Authors as Authors
import Components.Markdown as Markdown
import Components.MediaRenderer as MediaRenderer
import Components.MultiMediaRenderer as MultiMediaRenderer
import Components.Posts as Posts
import Components.Users as Users
import Gen.Route as Route
import Html exposing (Html, a, button, div, h1, img, span, text)
import Html.Attributes exposing (alt, class, href, src, title)
import Html.Events exposing (onClick)
import Proto.Rellm exposing (Post, User)
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (Branding, RellmServer)
import UI.Classes exposing (classes, hostnameToCSSClass, openClosedClass)
import UI.HtmlEvents exposing (stopPropagationAndPreventDefaultOnClick)


type alias Model =
    { root : Maybe BreadcrumbRoot

    -- The `frontendHost` every Post in `root`/`replies` lives on -- they're
    -- always all on the same server (a reply chain never crosses servers),
    -- needed to resolve the `RellmServer`/signed-in `Account` to
    -- render avatars/media/links with, same reasoning as
    -- `Shared.MarkdownPanel.Model`'s `targetHost`.
    , host : String

    -- The chain of replies from (but not including) `root` down to whichever
    -- Post is currently being viewed, root-first -- so the last entry is
    -- always the Post the page that called `SetRoot` is showing.
    , replies : List Post

    -- The id of whichever segment's `replyPanel` is currently open, if any --
    -- looked up against `root`/`replies` at render time (see `postFor`)
    -- rather than storing the `Post` itself a second time.
    , viewingPost : Maybe String
    , viewingHost : Bool
    }


type Msg
    = SetRoot BreadcrumbRoot String (List Post)
    | Clear
    | SegmentClicked String
    | ViewHost
    | CloseViewer
    | NoOp


type BreadcrumbRoot
    = FromPost Post
    | FromServerHost String
    | FromUser User


init : Model
init =
    { root = Nothing
    , host = ""
    , replies = []
    , viewingPost = Nothing
    , viewingHost = False
    }


update : Msg -> Model -> Model
update msg model =
    case msg of
        -- `FromServerHost` never has a reply chain of its own (see its own
        -- doc) -- `replies` is forced to `[]` here regardless of what's
        -- passed, rather than trusting every future caller to remember to
        -- pass `[]` itself.
        SetRoot ((FromServerHost host) as root) _ _ ->
            { root = Just root, host = host, replies = [], viewingPost = Nothing, viewingHost = False }

        SetRoot root host replies ->
            { root = Just root, host = host, replies = replies, viewingPost = Nothing, viewingHost = False }

        Clear ->
            init

        SegmentClicked postId ->
            if model.viewingPost == Just postId then
                { model | viewingPost = Nothing }

            else
                { model | viewingPost = Just postId, viewingHost = False }

        ViewHost ->
            { model | viewingHost = True, viewingPost = Nothing }

        CloseViewer ->
            { model | viewingHost = False, viewingPost = Nothing }

        NoOp ->
            model



-- VIEW


{-| The horizontally-scrollable trail itself -- empty (`text ""`) if no page
has set a `root` right now, or if there'd be nothing worth showing even with
one: no `replies` (so no actual reply chain to trace back through) on
`mainFrontendHost` (so there's no `hostSegment` server chip to show either --
see its own doc) leaves just a single "home" chip that says nothing a viewer
doesn't already know, e.g. `Pages.Home_`'s own `FromServerHost
mainFrontendHost` root, or a plain top-level Post that happens to already be
on `mainFrontendHost`. Mounted at the bottom of `.navbar` (see
`UI.headerNav`), not as a floating panel like `replyPanel` below.
-}
bar : AccountsPanel.Model -> Model -> Html Msg
bar accountsPanelModel model =
    case model.root of
        Nothing ->
            text ""

        Just root ->
            let
                isForUser : Bool
                isForUser =
                    case root of
                        FromUser _ ->
                            True

                        _ ->
                            False
            in
            if List.isEmpty model.replies && model.host == accountsPanelModel.mainFrontendHost && not isForUser then
                text ""

            else
                div [ classes [ "breadcrumbs-bar-container", hostnameToCSSClass model.host, "background-color-primary" ] ]
                    [ div [ classes [ "breadcrumbs-bar" ] ]
                        (List.intersperse separator
                            (hostSegment accountsPanelModel model root
                                ++ (rootSegment accountsPanelModel model root :: List.map (replySegment accountsPanelModel model) model.replies)
                            )
                        )
                    ]


separator : Html Msg
separator =
    span [ class "breadcrumb-separator" ] [ text "›" ]


{-| The server logo/name chip prepended at the very left of the trail
whenever `model.host` (the server every segment below actually lives on)
isn't `accountsPanelModel.mainFrontendHost` -- e.g. a reply chain or root Post
reached on a server other than the one "driving" the rest of the UI's chrome,
so it's clear which server this whole trail belongs to before ever reaching
`rootSegment` itself. A list so `bar` can just concat it onto the front of
the segments it interspersed with separators -- empty (no chip, no extra
separator) either when there's nothing to disambiguate, or when `root` is
already `FromServerHost` (`Pages.Home_`'s own root, always set to
`mainFrontendHost` -- see `Pages.Home_`), which would otherwise render this
same chip twice.
-}
hostSegment : AccountsPanel.Model -> Model -> BreadcrumbRoot -> List (Html Msg)
hostSegment accountsPanelModel model root =
    case root of
        FromServerHost _ ->
            []

        _ ->
            if model.host /= "" && model.host /= accountsPanelModel.mainFrontendHost then
                [ serverSegment accountsPanelModel model.host model.viewingHost ]

            else
                []


rootSegment : AccountsPanel.Model -> Model -> BreadcrumbRoot -> Html Msg
rootSegment accountsPanelModel model root =
    case root of
        FromPost post ->
            button
                [ classes (segmentClasses model "breadcrumb-root" post.id)
                , onClick (SegmentClicked post.id)
                ]
                [ span [ class "breadcrumb-root-title" ] [ text (Posts.postTitleText post) ] ]

        FromUser user ->
            let
                maybeServer : Maybe RellmServer
                maybeServer =
                    RellmServers.rellmServerForHost accountsPanelModel.servers model.host

                name : String
                name =
                    if String.isEmpty user.realName then
                        user.username

                    else
                        user.realName
            in
            a
                [ classes [ "breadcrumb-segment", "breadcrumb-root" ]
                , href <| "/" ++ user.username
                ]
                [ segmentAvatar name
                    (Maybe.andThen
                        (\server ->
                            let
                                maybeAccount : Maybe RellmAccount
                                maybeAccount =
                                    RellmAccounts.enabledRellmAccountForServer accountsPanelModel.accounts model.host
                            in
                            Users.avatarUrl server maybeAccount user
                        )
                        maybeServer
                    )
                , span [ class "breadcrumb-root-title" ] [ text name ]
                ]

        FromServerHost host ->
            serverSegment accountsPanelModel host model.viewingHost


{-| A single-line server logo + name chip -- a square logo image (or an
initial-letter placeholder, mirroring `segmentAvatar` below) followed by the
server's own branding name, clipped to one line with an ellipsis (see
`.breadcrumb-server` in nav.css). Deliberately not
`RellmServers.rellmServerNameAndLogo` -- that splits a server's name into an
emoji "badge" plus a fuller secondary line across two rows for the Accounts
Panel's own (much roomier) chips, which doesn't fit the trail's tight single
line. Always tinted with `host`'s own `background-color-primary` (see
`UI.EmittedStylesheet`), unconditionally rather than only while some segment
is `viewing` (contrast `segmentClasses`) -- there's no "open" state for this
chip, it's just always this server's own color. Renders nothing if `host`
isn't a known `RellmServer` yet (e.g. still being resolved).
-}
serverSegment : AccountsPanel.Model -> String -> Bool -> Html Msg
serverSegment accountsPanelModel host viewingHost =
    case RellmServers.rellmServerForHost accountsPanelModel.servers host of
        Just server ->
            let
                branding : Branding
                branding =
                    RellmServers.brandingOf server
            in
            button
                [ onClick <|
                    if viewingHost then
                        CloseViewer

                    else
                        ViewHost
                , classes
                    [ "breadcrumb-segment"
                    , "breadcrumb-server"
                    , hostnameToCSSClass host
                    , if viewingHost then
                        "background-color-nav"

                      else
                        "background-color-primary"
                    ]
                ]
                [ serverSegmentLogo branding
                , span [ class "breadcrumb-server-name" ] [ text branding.name ]
                ]

        Nothing ->
            text ""


serverSegmentLogo : Branding -> Html msg
serverSegmentLogo branding =
    case branding.logoUrl of
        Just url ->
            img [ class "breadcrumb-server-logo", src url, alt branding.name ] []

        Nothing ->
            div [ classes [ "breadcrumb-server-logo", "placeholder" ] ] [ text (RellmServers.initialLetter branding.name) ]


replySegment : AccountsPanel.Model -> Model -> Post -> Html Msg
replySegment accountsPanelModel model post =
    let
        maybeServer : Maybe RellmServer
        maybeServer =
            RellmServers.rellmServerForHost accountsPanelModel.servers model.host

        maybeAccount : Maybe RellmAccount
        maybeAccount =
            RellmAccounts.enabledRellmAccountForServer accountsPanelModel.accounts model.host

        name : String
        name =
            Authors.name post.author
    in
    button
        [ classes (segmentClasses model "breadcrumb-reply" post.id)
        , onClick (SegmentClicked post.id)
        ]
        [ segmentAvatar name (Authors.avatarUrl maybeServer maybeAccount post.author)
        , span [ class "breadcrumb-reply-username" ] [ text name ]
        ]


{-| Mirrors `Components.PostCard.authorAvatar`/`UI.imageOrInitial` -- not
reused directly (importing either would cycle: `Components.PostCard` doesn't
import `Shared.Breadcrumbs`, but `UI` does, and `UI` is what `imageOrInitial`
lives in).
-}
segmentAvatar : String -> Maybe String -> Html msg
segmentAvatar name maybeUrl =
    case maybeUrl of
        Just url ->
            img [ classes [ "breadcrumb-reply-avatar" ], src url, alt name ] []

        Nothing ->
            div [ classes [ "breadcrumb-reply-avatar", "placeholder" ] ] [ text (RellmServers.initialLetter name) ]


{-| A popup, anchored just under `bar`'s own trail (see nav.css's
`.breadcrumb-reply-panel`), showing whichever segment's Post was last tapped
(see `viewing`) -- a smaller, read-only relative of
`Components.Posts.replyCard` (title if it's the root -- see `isRoot`,
author, media, content via `Components.Markdown` same as everywhere else Post
content renders, permalink; no Reply/load-more/collapse actions, which don't
make sense for a single already-in-hand Post shown out of its thread, and no
close button of its own -- tapping the open segment again, another segment, or
the shared backdrop all already close it, see `UI.sharedBackdrop`). Always
rendered, even closed, same "opening/closing is a CSS transition" convention
as every other panel here -- see `UI.Classes.openClosedClass`. `basePath` is
`Shared.Model.basePath`, needed for the author/permalink links.
-}
previewPanel : String -> AccountsPanel.Model -> Model -> Html Msg
previewPanel basePath accountsPanelModel model =
    div [ classes [ "breadcrumb-reply-panel", "nav-panel", openClosedClass (model.viewingPost /= Nothing || model.viewingHost) ] ]
        (if model.viewingHost then
            [ serverOverviewView basePath accountsPanelModel model ]

         else
            case postFor model model.viewingPost of
                Just post ->
                    [ replyCardView basePath accountsPanelModel model post ]

                Nothing ->
                    []
        )


{-| `previewPanel`'s content while `model.viewingHost` -- `hostSegment`/
`rootSegment`'s server chip's own equivalent of `replyCardView`, showing the
server itself rather than one of its Posts: its `RellmServers.rellmServerNameAndLogo`,
its `ServerInfo.description` (if any, same `Components.Markdown` rendering as
everywhere else server/Post content renders), and an info button through to
its full `Components.Pages.ServerInformationPage` (`serverOverviewInfoButton`).
Renders nothing if `model.host` isn't a known `RellmServer` yet, same
as `serverSegment`.
-}
serverOverviewView : String -> AccountsPanel.Model -> Model -> Html Msg
serverOverviewView basePath accountsPanelModel model =
    case RellmServers.rellmServerForHost accountsPanelModel.servers model.host of
        Just server ->
            let
                info : Proto.Rellm.ServerInfo
                info =
                    RellmServers.rellmServerInfoOf server
            in
            div [ class "breadcrumb-server-overview" ]
                [ div [ class "breadcrumb-server-overview-header" ]
                    [ RellmServers.rellmServerNameAndLogo server RellmServers.HorizontalServerLogo
                    , serverOverviewInfoButton basePath server
                    ]
                , case info.description of
                    Just description ->
                        Markdown.view [ class "breadcrumb-server-overview-description" ] description

                    Nothing ->
                        text ""
                ]

        Nothing ->
            text ""


{-| Mirrors `UI.serverInfoButton` -- not reused directly since `UI` itself
imports `Shared.Breadcrumbs` (for `previewPanel`), so the reverse import would
cycle; closes this panel's own viewer (`CloseViewer`) rather than the Accounts
Panel on click, same `stopPropagationAndPreventDefaultOnClick` reasoning
(nested inside `previewPanel`, not another link).
-}
serverOverviewInfoButton : String -> RellmServer -> Html Msg
serverOverviewInfoButton basePath server =
    let
        -- Disconnected servers (see `RellmServer.connected`) default to
        -- `https:` -- `ServerInformationPage`'s own probe re-negotiates anyway.
        serverIdentifier : String
        serverIdentifier =
            (if server.connected |> Maybe.map .tls |> Maybe.withDefault True then
                "https:"

             else
                "http:"
            )
                ++ server.frontendHost
    in
    a
        [ classes [ "panel-icon-button", "info-button", "breadcrumb-server-overview-info-button" ]
        , href (basePath ++ Route.toHref (Route.Server__ServerIdentifier_ { serverIdentifier = serverIdentifier }))
        , stopPropagationAndPreventDefaultOnClick CloseViewer
        , title ("About " ++ server.frontendHost)
        ]
        [ text "i" ]


replyCardView : String -> AccountsPanel.Model -> Model -> Post -> Html Msg
replyCardView basePath accountsPanelModel model post =
    let
        maybeServer : Maybe RellmServer
        maybeServer =
            RellmServers.rellmServerForHost accountsPanelModel.servers model.host

        maybeAccount : Maybe RellmAccount
        maybeAccount =
            RellmAccounts.enabledRellmAccountForServer accountsPanelModel.accounts model.host
    in
    div [ class "breadcrumb-reply-card" ]
        [ if isRoot model post then
            h1 [ class "breadcrumb-reply-card-title" ] [ text (Posts.postTitleText post) ]

          else
            text ""
        , div [ class "breadcrumb-reply-card-meta" ]
            [ Authors.link basePath accountsPanelModel.mainFrontendHost model.host maybeServer maybeAccount post.author
            , a
                [ href (Posts.postHref basePath accountsPanelModel.mainFrontendHost model.host post)
                , class "breadcrumb-reply-card-permalink"
                ]
                [ text "🔗" ]
            ]
        , case maybeServer of
            Just server ->
                MultiMediaRenderer.previewExtraSmall server maybeAccount MediaRenderer.init (\_ -> NoOp) (\_ -> NoOp) post.media

            Nothing ->
                text ""
        , case post.content of
            Just content ->
                Markdown.view [ class "breadcrumb-reply-card-content" ] content

            Nothing ->
                text ""
        ]


{-| Every Post a segment currently renders for -- `root` (if it's a `FromPost`)
followed by `replies` -- used both to render the trail itself and to look up
`viewing`'s Post for `replyPanel`.
-}
segments : Model -> List Post
segments model =
    case model.root of
        Just (FromPost post) ->
            post :: model.replies

        _ ->
            model.replies


postFor : Model -> Maybe String -> Maybe Post
postFor model maybePostId =
    maybePostId
        |> Maybe.andThen (\postId -> segments model |> List.filter (\post -> post.id == postId) |> List.head)


{-| The classes for a segment button: always `"breadcrumb-segment"` plus its
own kind (`"breadcrumb-root"`/`"breadcrumb-reply"`); additionally
`[ hostnameToCSSClass model.host, "background-color-primary" ]` (see
`UI.EmittedStylesheet`) when this segment's Post is the one `replyPanel`
currently has open, tinting it with that server's own primary color to mark
it as the open one.
-}
segmentClasses : Model -> String -> String -> List String
segmentClasses model kindClass postId =
    "breadcrumb-segment"
        :: kindClass
        :: (if model.viewingPost == Just postId then
                [ hostnameToCSSClass model.host, "background-color-nav" ]

            else
                []
           )


{-| Whether `post` is `model`'s own root (as opposed to one of its `replies`)
-- the root is the only segment with a real title shown on its `replyCardView`;
a reply never has one worth showing on its own card, same as
`Components.PostReplies` never shows one for its own cards.
-}
isRoot : Model -> Post -> Bool
isRoot model post =
    case model.root of
        Just (FromPost rootPost) ->
            rootPost.id == post.id

        _ ->
            False
