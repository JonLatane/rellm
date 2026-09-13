module Components.Authors exposing (avatar, avatarUrl, badges, compactBadges, link, name)

{-| Everything about displaying a `Proto.Rellm.Author` -- the
post/authorship-centric, cacheable-in-the-UI sibling of `User` embedded
directly in a `Post` (see `authentication.proto`'s own doc comment on
`Author`: "UI can cross-reference user details from its own cache (for things
like admin/bot icons)"). Since an `Author` already carries everything needed
to show one -- `username`, `avatar`, and `permissions` -- this module owns the
whole "avatar + name + profile link + Admin/Run Bots badges" combo
(`link`, built from `avatar`/`name`/`href`/`compactBadges`) as one shared
piece, rather than each caller assembling its own from parts.

`Post.author` is only ever a `Maybe Author` (an author-less post shouldn't
normally happen, but the proto doesn't guarantee one), so every function here
takes a `Maybe Author` and degrades gracefully -- `name` falls back to
"unknown", `href`/`avatarUrl` to `Nothing`, `link` to a plain (non-clickable)
`span`.

Used by `Components.Posts`' `postCard`/`postDetail`, `Components.PostReplies`'
`replyCard`, and `Shared.Breadcrumbs`' `replyCardView` -- all four now show
the exact same author rendering, badges included, rather than `PostReplies`
(the one place badges were first added) alone.

`badges`/`compactBadges` also work directly against a `Proto.Rellm.User`
(see `Components.Pages.UserProfilePage.usernameHeading`) -- both types have
their own `permissions : List Permission` field, so these two are written
against the structural `{ a | permissions : List Permission }` rather than
either concrete type.

Two badge renderings, both ordered Admin-then-Business-then-Run-Bots (if a
user/author has more than one):

  - `badges` -- verbose, as shown atop a profile page: Admin gets visible
    "🛡️ Admin" text, Business and Run Bots are bare emoji ("💼"/"🤖", no
    equally short label for either), all still with a `title` tooltip.
  - `compactBadges` -- for inline use next to a name (`link`'s own use),
    where there's no room for "Admin" as visible text: all bare emoji,
    `title`-only.

Either returns `[]` for an unprivileged user/author, so callers can just
append the result without their own empty-badges check.

-}

import Components.Users as Users
import Html exposing (Html, a, div, img, span, text)
import Html.Attributes exposing (alt, attribute, class, src, title)
import Proto.Rellm exposing (Author, unwrapMediaReference)
import Proto.Rellm.Permission exposing (Permission(..))
import Shared.AccountsPanel.RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import UI.Classes exposing (classes)


badges : { a | permissions : List Permission } -> List (Html msg)
badges entity =
    (if hasPermission ADMIN entity then
        [ span [ class "author-badge", title "Admin" ] [ text "🛡️ Admin" ] ]

     else
        []
    )
        ++ (if hasPermission BUSINESS entity then
                [ span [ class "author-badge", title "Business Account" ] [ text "💼" ] ]

            else
                []
           )
        ++ (if hasPermission RUNBOTS entity then
                [ span [ class "author-badge", title "Has Permission to Run Bots" ] [ text "🤖" ] ]

            else
                []
           )


compactBadges : { a | permissions : List Permission } -> List (Html msg)
compactBadges entity =
    (if hasPermission ADMIN entity then
        [ span [ class "author-badge-compact", title "Admin" ] [ text "🛡️" ] ]

     else
        []
    )
        ++ (if hasPermission BUSINESS entity then
                [ span [ class "author-badge-compact", title "Business Account" ] [ text "💼" ] ]

            else
                []
           )
        ++ (if hasPermission RUNBOTS entity then
                [ span [ class "author-badge-compact", title "Has Permission to Run Bots" ] [ text "🤖" ] ]

            else
                []
           )


{-| A small avatar/placeholder for an author, matching the size of the
Accounts Panel toggle's own avatars (`.post-author-avatar`, see `posts.css`).
Falls back to an initial-letter placeholder the same way `UI.imageOrInitial`
does elsewhere in the app; duplicated here rather than reusing that function
since `UI` itself imports `Components.Posts` (for `postCard`), so the reverse
import would be a cycle.
-}
avatar : String -> Maybe String -> Html msg
avatar authorName maybeUrl =
    case maybeUrl of
        Just url ->
            img [ class "post-author-avatar", src url, alt authorName, attribute "loading" "lazy" ] []

        Nothing ->
            div [ classes [ "post-author-avatar", "placeholder" ] ] [ text (RellmServers.initialLetter authorName) ]


{-| An author's avatar + name + Admin/Run Bots badges, linking to their
profile (see `href`) -- a `span` (not a link) if `maybeAuthor` is `Nothing`,
so the avatar still shows either way. Used by `Components.Posts`'
`postCard`/`postDetail`/`replyCard`, and `Shared.Breadcrumbs.replyCardView`
-- `postDetail`'s is a plain, unwrapped
link (fine as-is); `postCard`'s needs the "stretched link" dance in its own
doc comment to keep this independently clickable without nesting an `<a>`
inside `postCard`'s own enclosing one.
-}
link : String -> String -> String -> Maybe RellmServer -> Maybe RellmAccount -> Maybe Author -> Html msg
link basePath viewingServerHost hostServerHost maybeServer maybeAccount maybeAuthor =
    let
        authorName : String
        authorName =
            name maybeAuthor

        content : List (Html msg)
        content =
            avatar authorName (avatarUrl maybeServer maybeAccount maybeAuthor)
                :: text authorName
                :: (maybeAuthor |> Maybe.map compactBadges |> Maybe.withDefault [])
    in
    case href basePath viewingServerHost hostServerHost maybeAuthor of
        Just profileHref ->
            a [ Html.Attributes.href profileHref, class "post-author-link" ] content

        Nothing ->
            span [ class "post-author-link" ] content


{-| An author's display name -- "unknown" if `maybeAuthor` is `Nothing`
(shouldn't normally happen, but `Post.author` is optional) or has no
`username` set.
-}
name : Maybe Author -> String
name maybeAuthor =
    maybeAuthor
        |> Maybe.andThen .username
        |> Maybe.withDefault "unknown"


hasPermission : Permission -> { a | permissions : List Permission } -> Bool
hasPermission permission entity =
    List.member permission entity.permissions


{-| An author's profile link -- `Nothing` if `maybeAuthor` is `Nothing`. The
author is always on `hostServerHost` (the same server as the post it came
from; `Author` has no host of its own to look elsewhere) -- see
`Components.Users.profileHref`, which already falls back to `/user/:id` if
the username isn't routable.
-}
href : String -> String -> String -> Maybe Author -> Maybe String
href basePath viewingServerHost hostServerHost maybeAuthor =
    maybeAuthor
        |> Maybe.map
            (\author ->
                Users.profileHref basePath
                    viewingServerHost
                    hostServerHost
                    { userId = author.userId, username = routeUsername hostServerHost (Maybe.withDefault "" author.username) }
            )


{-| The bare username `Users.profileHref` needs to round-trip back through `Users.parseFederatedUserId`
-- `Shared.Federation.Mastodon.toAuthor`'s own `Author.username` is `"username@instanceHost"` (a
compound *display* string, shown as-is next to a Mastodon post -- see `name` below), not the bare
route-safe username `withHostSuffix`/`parseUserRouteId` expect (a single `@`, already spent on the
`@hostServerHost` suffix `profileHref` itself appends): passing the compound string through
unchanged would produce a route with two `@`s, which `parseUserRouteId`'s own `String.split "@"`
can't split back apart, so it'd resolve to nothing. Bluesky's `Author.username` (a bare handle, no
embedded host) needs no such stripping, and any real Rellm `Author` is already unaffected here since
`hostServerHost` for one never starts with `"mastodon:"`.
-}
routeUsername : String -> String -> String
routeUsername hostServerHost username =
    if String.startsWith "mastodon:" hostServerHost then
        String.split "@" username |> List.head |> Maybe.withDefault username

    else
        username


{-| An author's avatar URL -- `Nothing` if `maybeAuthor` is `Nothing`, `server`
isn't resolved yet (e.g. still connecting), or the author just has no avatar
set. `server` needs to be the actual resolved `Shared.RellmServer` --
building a media URL needs its connection details, not just its hostname (see
`Shared.RellmServers.mediaUrl`).

`author.avatar.url` (see that field's own doc in `protos/media.proto`) is checked first and used
as-is, with no `server`/`maybeAccount` needed at all -- this is how a Mastodon/Bluesky author's own
avatar (set by `Shared.Federation.Mastodon`/`Bluesky`'s own `toAuthor`, which always uses `.url` since
that avatar isn't and never will be Rellm-hosted media) actually shows up in `postCard`/`postDetail`/
`replyCard` instead of falling back to the initial-letter placeholder every real `Server`-dependent
path below would otherwise give a federated author, which has no real `Server` to resolve at all.
-}
avatarUrl : Maybe RellmServer -> Maybe RellmAccount -> Maybe Author -> Maybe String
avatarUrl maybeServer maybeAccount maybeAuthor =
    case maybeAuthor |> Maybe.andThen .avatar |> Maybe.map unwrapMediaReference |> Maybe.andThen .url of
        Just externalUrl ->
            Just externalUrl

        Nothing ->
            Maybe.map2 (\server author -> Users.authorAvatarUrl server maybeAccount author) maybeServer maybeAuthor
                |> Maybe.andThen identity
