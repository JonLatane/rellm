module Components.QuotedLink exposing (AccountsInfo, Config, accountsInfo, contentEmbed, embedFromContent, targetOf, view, viewLink)

{-| The quoted post a Rellm `POST` embeds, when its `link` points at a post/event on a Rellm server
(`Shared.Federation.RellmLinks`) -- what `Components.Posts.postCard`/`postDetail`'s `quoteView` slot is
filled with. Rendered by the caller (not inside `Components.Posts`) because it needs state `Posts` can't
see without a dependency cycle: `Shared.QuoteLinks`' cache of fetched posts, and the `AccountsPanel` model for
which servers the user has and what we know about the rest.

What shows up depends on the link's server, mirroring `Components.ServerDependentView` (the Add/Enable
prompts on a post page) wherever the two overlap:

  - one of the user's servers, enabled: the quoted post as a card (`Components.Posts.quotedPostCard`) -- or,
    when it's an event's or occasion's (by `PostContext`, see `Shared.QuoteLinks.wantsEvent`), a read-only
    `Components.Events.eventCard` -- or a "Loading…" line until it arrives, or nothing if it can't be seen;
  - one of the user's servers, disabled: `ServerDependentView`'s own "Enable" prompt -- we don't read from a
    server the user switched off;
  - one the user hasn't added, that turned out to be a Rellm server: the card too (fetched anonymously, see
    `Shared.QuoteLinks`) with an "Add" button for that server under it, labelled with the logo and name
    `AccountsPanel` already previewed for it -- or, if the post itself can't be seen anonymously, just the
    button;
  - one the user hasn't added that isn't a Rellm server (or isn't known yet): nothing at all, so a post that
    merely links to some website looks exactly as it did before;
  - a Bluesky or Mastodon post (`Shared.Federation.FederatedLinks`): its card, with no server to add or enable,
    or nothing if it can't be fetched.

-}

import Components.Events as Events
import Components.MediaRenderer as MediaRenderer
import Components.Posts as Posts
import Components.ServerDependentView as ServerDependentView
import Dict exposing (Dict)
import Html exposing (Html, button, div, text)
import Html.Attributes exposing (class, title)
import Html.Events exposing (onClick)
import Proto.Rellm exposing (Event, Occasion, Post)
import Proto.Rellm.PostContext exposing (PostContext(..))
import Set exposing (Set)
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Shared.Federation.FederatedLinks as FederatedLinks
import Shared.Federation.RellmLinks exposing (Target)
import Shared.QuoteLinks as QuoteLinks
import Shared.Time as SharedTime
import Shared.UserPreferences as UserPreferences
import SocialMediaEmbed


type alias Config msg =
    { time : SharedTime.Model
    , basePath : String
    , accounts : AccountsInfo
    , quotes : QuoteLinks.Model
    , mediaPlayState : MediaRenderer.Model
    , onMediaPlayClicked : String -> msg

    -- For the per-network "Embed ... Links" opt-outs of `socialEmbedView`.
    , userPreferences : UserPreferences.Model

    -- The "Add <server>" button on a quote from a server the user hasn't added, and the "Enable" button
    -- of one they've disabled -- each gets the server's `frontendHost`.
    , onAddServerClicked : String -> msg
    , onEnableServerClicked : String -> msg

    -- For the event card's own (unused here) click handlers, which a quote doesn't offer.
    , noOp : msg
    }


{-| The parts of `AccountsPanel.Model` this view reads -- a narrower type than the whole model, so it's
buildable (and testable) on its own; callers pass `accountsInfo shared.accounts`.
-}
type alias AccountsInfo =
    { servers : List RellmServer
    , accounts : List RellmAccount
    , previews : Dict String RellmServer
    , nonRellmHosts : Set String
    , mainFrontendHost : String
    }


accountsInfo : AccountsPanel.Model -> AccountsInfo
accountsInfo model =
    { servers = model.servers
    , accounts = model.accounts
    , previews = model.recommendedServerConnections
    , nonRellmHosts = model.nonRellmHosts
    , mainFrontendHost = model.mainFrontendHost
    }


{-| What `post` quotes, if anything: only a top-level `POST` on a Rellm server (a reply's, event's or
federated post's `link` is just a link -- a federated post's own quote arrives already resolved in
`Post.quotedPost`, see `Shared.Federation.Bluesky`/`Mastodon`) whose `link` is a Rellm post/event link. `postServerHost` is the
server `post` came from, which a relative link means.
-}
targetOf : String -> Post -> Maybe QuoteLinks.Linked
targetOf postServerHost post =
    if post.context == POST && not (Posts.isFederatedHost postServerHost) && post.quotedPost == Nothing then
        post.link |> Maybe.andThen (QuoteLinks.parseLink postServerHost)

    else
        Nothing


{-| The embed for `post`'s quote -- `text ""` when it doesn't have one, or there's nothing to show (yet).
-}
view : Config msg -> String -> Post -> Html msg
view config postServerHost post =
    case targetOf postServerHost post of
        Just linked ->
            viewLinked config linked

        Nothing ->
            socialEmbedView config.userPreferences postServerHost post


{-| A `POST` whose `link` isn't a post on Rellm/Bluesky/Mastodon but one on Facebook, Instagram, LinkedIn, Pinterest,
TikTok, X or YouTube gets that post embedded (`SocialMediaEmbed`) -- wherever a post card or page shows
the quote slot, unless the viewer turned that network's embeds off (`UserPreferences.embedDisabled`). Same gate as
`targetOf`: only a top-level `POST` on a Rellm server. A top-level Bluesky `POST` is the exception: its `link` is
the post itself on bsky.app, so its embed comes from the links in its content (`embedFromContent`), unless its
sensitive media is still hidden.
-}
socialEmbedView : UserPreferences.Model -> String -> Post -> Html msg
socialEmbedView userPreferences postServerHost post =
    if post.context /= POST || post.quotedPost /= Nothing then
        text ""

    else if String.startsWith "bluesky:" postServerHost then
        if Posts.hasHiddenSensitiveMedia post then
            text ""

        else
            embedFromContent userPreferences post

    else if not (Posts.isFederatedHost postServerHost) then
        post.link
            |> Maybe.andThen SocialMediaEmbed.fromLink
            |> Maybe.andThen
                (\embed ->
                    if UserPreferences.embedDisabled (SocialMediaEmbed.network embed) userPreferences then
                        Nothing

                    else
                        Just embed
                )
            |> Maybe.map SocialMediaEmbed.view
            |> Maybe.withDefault (text "")

    else
        text ""


{-| The first link in `post`'s content that's a post on a network `SocialMediaEmbed` supports (YouTube, X, ...),
embedded unless the viewer turned that network's embeds off. For a Bluesky post, whose `Post.link` is the post
itself on bsky.app: `Shared.Federation.Bluesky.toPost` has already turned its link facets (and link card) into
Markdown links to their full URLs, so this also finds a link whose visible text was truncated.
-}
embedFromContent : UserPreferences.Model -> Post -> Html msg
embedFromContent userPreferences post =
    contentEmbed userPreferences post
        |> Maybe.map SocialMediaEmbed.view
        |> Maybe.withDefault (text "")


{-| What `embedFromContent` would show, if anything: lets a caller tell whether a post has an embed to hide
(a sensitive post with an embed but no images has no other media to put behind its reveal gate).
-}
contentEmbed : UserPreferences.Model -> Post -> Maybe SocialMediaEmbed.Embed
contentEmbed userPreferences post =
    post.content
        |> Maybe.withDefault ""
        |> SocialMediaEmbed.fromMarkdown
        |> List.filter (\embed -> not (UserPreferences.embedDisabled (SocialMediaEmbed.network embed) userPreferences))
        |> List.head


{-| The embed for a bare `link` (what `Shared.CreateNewPanel` previews) -- `postServerHost` is what a relative
one means, as for `Shared.Federation.RellmLinks.parse`.
-}
viewLink : Config msg -> String -> String -> Html msg
viewLink config postServerHost link =
    case QuoteLinks.parseLink postServerHost link of
        Just linked ->
            viewLinked config linked

        Nothing ->
            text ""


viewLinked : Config msg -> QuoteLinks.Linked -> Html msg
viewLinked config linked =
    case linked of
        QuoteLinks.RellmLink target ->
            viewTarget config target

        QuoteLinks.FederatedLink target ->
            viewFederated config target


{-| A Bluesky or Mastodon post: just the card (it links through to Rellm's own page for it), or a loading line --
there's no server to add or enable. Nothing if it couldn't be fetched (not public, not a Mastodon host, ...).
-}
viewFederated : Config msg -> FederatedLinks.Target -> Html msg
viewFederated config target =
    case QuoteLinks.entryForLinked config.quotes (QuoteLinks.FederatedLink target) of
        Just (QuoteLinks.Loaded quoted) ->
            div [ class "quoted-post" ]
                [ Posts.quotedPostCard
                    config.time
                    config.basePath
                    config.accounts.mainFrontendHost
                    (federatedHost target)
                    Nothing
                    Nothing
                    config.mediaPlayState
                    config.onMediaPlayClicked
                    Nothing
                    quoted
                ]

        Just QuoteLinks.Loading ->
            div [ class "quoted-post-loading" ] [ text "Loading quoted post…" ]

        _ ->
            text ""


{-| The synthetic `postServerHost` a federated post is rendered under (`Components.Posts.isFederatedHost`), which
`Posts.postHref` turns into its `/post/…@bluesky` / `@mastodon:{host}` page.
-}
federatedHost : FederatedLinks.Target -> String
federatedHost target =
    case target of
        FederatedLinks.MastodonStatus { instanceHost } ->
            "mastodon:" ++ instanceHost

        _ ->
            "bluesky:"


viewTarget : Config msg -> Target -> Html msg
viewTarget config target =
    case RellmServers.rellmServerForHost config.accounts.servers target.host of
        Just _ ->
            ServerDependentView.view
                { hostname = target.host
                , servers = config.accounts.servers
                , accounts = config.accounts.accounts
                , connectStatus = ServerDependentView.NotConnected
                , previews = config.accounts.previews
                , onConnectClicked = config.onAddServerClicked target.host
                , onEnableClicked = config.onEnableServerClicked target.host
                }
                (\_ _ -> entryView config target)

        Nothing ->
            if Set.member target.host config.accounts.nonRellmHosts then
                text ""

            else
                case QuoteLinks.entryFor config.quotes target of
                    Just (QuoteLinks.Loaded quoted) ->
                        div [ class "quoted-post" ] [ card config target quoted, addServerRow config target ]

                    Just (QuoteLinks.LoadedEvent event occasion) ->
                        div [ class "quoted-post" ] [ eventCard config target event occasion, addServerRow config target ]

                    _ ->
                        -- Not (yet) a post we can show -- but if the host did turn out to be a Rellm server, the
                        -- button is still worth having (the post may just need an account there).
                        if (Dict.get target.host config.accounts.previews |> Maybe.andThen .connected) /= Nothing then
                            div [ class "quoted-post" ] [ addServerRow config target ]

                        else
                            text ""


entryView : Config msg -> Target -> Html msg
entryView config target =
    case QuoteLinks.entryFor config.quotes target of
        Just (QuoteLinks.Loaded quoted) ->
            card config target quoted

        Just (QuoteLinks.LoadedEvent event occasion) ->
            eventCard config target event occasion

        Just (QuoteLinks.Awaiting _) ->
            div [ class "quoted-post-loading" ] [ text "Loading quoted post…" ]

        Just QuoteLinks.Loading ->
            div [ class "quoted-post-loading" ] [ text "Loading quoted post…" ]

        _ ->
            text ""


card : Config msg -> Target -> Post -> Html msg
card config target quoted =
    Posts.quotedPostCard
        config.time
        config.basePath
        config.accounts.mainFrontendHost
        target.host
        -- What the quote's media needs to be addressed: the server's own record when the user has added it, else
        -- the preview connection the quote was fetched over; and, for a server they're signed in to, that account.
        (case RellmServers.rellmServerForHost config.accounts.servers target.host of
            Just server ->
                Just server

            Nothing ->
                Dict.get target.host config.accounts.previews
        )
        (RellmAccounts.enabledRellmAccountForServer config.accounts.accounts target.host)
        config.mediaPlayState
        config.onMediaPlayClicked
        Nothing
        quoted


{-| A quoted event as `Components.Events.eventCard` -- the card an events listing shows, read-only: no RSVP,
calendar-export or sync controls (`Events.noCardSlots`), which need the page's own state.
-}
eventCard : Config msg -> Target -> Event -> Occasion -> Html msg
eventCard config target event occasion =
    Events.eventCard
        config.time
        config.basePath
        config.accounts.mainFrontendHost
        target.host
        (RellmServers.rellmServerForHost config.accounts.servers target.host)
        (RellmAccounts.enabledRellmAccountForServer config.accounts.accounts target.host)
        (\_ -> config.noOp)
        config.mediaPlayState
        config.onMediaPlayClicked
        MediaRenderer.ExtraSmall
        False
        Nothing
        False
        False
        False
        Nothing
        (\_ -> False)
        (\_ -> Nothing)
        (\_ -> config.noOp)
        (\_ _ -> config.noOp)
        Events.noCardSlots
        event
        occasion


{-| "Add <logo> <name>" -- `ServerDependentView`'s own button, label and wording, for a quote's server the
user hasn't added.
-}
addServerRow : Config msg -> Target -> Html msg
addServerRow config target =
    div [ class "quoted-post-server-row" ]
        [ button
            [ class "server-action-button"
            , onClick (config.onAddServerClicked target.host)
            , title ("Add " ++ target.host)
            ]
            [ text "Add "
            , ServerDependentView.hostLabel
                (RellmServers.previewOf config.accounts.servers config.accounts.previews target.host)
            ]
        ]
