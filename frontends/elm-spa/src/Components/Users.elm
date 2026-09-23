module Components.Users exposing
    ( FederatedUserId(..)
    , allModerations
    , allPermissions
    , allowedVisibilities
    , authorAvatarUrl
    , avatarUrl
    , configurableServerPermissions
    , createFollow
    , defederateProfile
    , deleteFollow
    , deleteUser
    , federateProfile
    , fetchUserById
    , fetchUserByUsername
    , fetchUserListing
    , followersHref
    , followingHref
    , isReservedUsername
    , mediaReferenceUrl
    , moderationFromText
    , moderationPasses
    , moderationPending
    , moderationRejected
    , moderationText
    , parseFederatedUserId
    , parseUserRouteId
    , permissionFromText
    , permissionText
    , profileHref
    , resetPassword
    , startContactMethodVerification
    , startsWithReservedShortUrlCharacter
    , titleName
    , updateFollow
    , updateUser
    , userCard
    , userCardContactButtons
    , verifyContactMethod
    , userCardAvatar
    , userIdHref
    , usernameHref
    , visibilityFromText
    , visibilityText
    )

{-| Shared building blocks for displaying `Proto.Rellm.User`s -- the fetch
helpers both profile routes (`Pages.User.UserId_`, by id; `Pages.UsernameOrCustomTab_`, by
username) need against a specific `Shared.RellmServer`, the
`/user/:id[@host]`/`/:username[@host]` route id parsing/linking (mirroring
`Components.Posts`' `postHref`/`parsePostRouteId` for `/post/:id[@host]`), and
plain-English labels for a `User`'s `Visibility`/`Moderation`/`Permission`
fields.
-}

import Gen.Route
import Grpc
import Html exposing (Html, a, div, img, text)
import Html.Attributes exposing (alt, attribute, href, src)
import Proto.Google.Protobuf
import Proto.Rellm exposing (Author, ContactMethod, FederatedAccount, Follow, GetUsersResponse, User, VerifyContactMethodRequest, defaultGetUsersRequest, unwrapMediaReference)
import Proto.Rellm.Rellm as Rellm
import Proto.Rellm.Moderation exposing (Moderation(..))
import Proto.Rellm.Permission exposing (Permission(..))
import Proto.Rellm.UserListingType exposing (UserListingType(..))
import Proto.Rellm.Visibility exposing (Visibility(..))
import Set exposing (Set)
import Shared.AccountsPanel as AccountsPanel exposing (performWithAccountServer, performWithOptionalAccountServer)
import Shared.AccountsPanel.RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer, withAccessToken)
import Task exposing (Task)
import UI.Classes exposing (classes, hostnameToCSSClass)


{-| Fetches the user with `userId` from `maybeAccountServer`'s server,
authenticated as its account if any, anonymous otherwise. Returns a `Msg` to
dispatch if a token refresh happened, same convention as
`Components.PostCard.fetchPost`.
-}
fetchUserById :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> String
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, GetUsersResponse )
fetchUserById accountsPanelModel maybeAccountServer userId =
    fetchUsers accountsPanelModel maybeAccountServer { defaultGetUsersRequest | userId = Just userId }


{-| Like `fetchUserById`, but looks the user up by (exact) `username` instead.
-}
fetchUserByUsername :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> String
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, GetUsersResponse )
fetchUserByUsername accountsPanelModel maybeAccountServer username =
    fetchUsers accountsPanelModel maybeAccountServer { defaultGetUsersRequest | username = Just username }


{-| Fetches a `listingType` listing of users from `maybeAccountServer`'s
server -- `EVERYONE` for `/people`, or `FOLLOWING`/`FOLLOWERS`/`FRIENDS`
relative to `targetUserId` for a profile's own relationship pages (see
`Components.Pages.UsersPage`).

`searchText`, if non-blank (leading/trailing whitespace is trimmed, same
convention as `Components.Posts.fetchPosts`), switches `listingType` to its
`textSearchListingType` counterpart and sends it as `search_text` --
otherwise this is the plain (unscoped-by-search) listing `listingType` itself
already was.

-}
fetchUserListing :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> Maybe String
    -> UserListingType
    -> String
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, GetUsersResponse )
fetchUserListing accountsPanelModel maybeAccountServer targetUserId listingType searchText =
    let
        trimmedSearchText : String
        trimmedSearchText =
            String.trim searchText

        request : Proto.Rellm.GetUsersRequest
        request =
            if String.isEmpty trimmedSearchText then
                { defaultGetUsersRequest | userId = targetUserId, listingType = listingType }

            else
                { defaultGetUsersRequest
                    | userId = targetUserId
                    , listingType = textSearchListingType listingType
                    , searchText = Just trimmedSearchText
                }
    in
    fetchUsers accountsPanelModel maybeAccountServer request


{-| The `*_TEXT_SEARCH` counterpart of `listingType`, for `fetchUserListing`'s
non-blank-`searchText` case: `EVERYONE` -> `USERSTEXTSEARCH` (named
`USERS_TEXT_SEARCH`, not the bare `TEXT_SEARCH` used by `PostListingType`,
since proto3 enum values share one namespace across the whole `rellm`
package -- see `protos/users.proto`), and
`FOLLOWING`/`FOLLOWERS`/`FRIENDS`/`FOLLOWREQUESTS` -> their own
`*TEXTSEARCH` variant. Any other `UserListingType` is left as-is (there's no
search-scoped equivalent to switch to).
-}
textSearchListingType : UserListingType -> UserListingType
textSearchListingType listingType =
    case listingType of
        EVERYONE ->
            USERSTEXTSEARCH

        FOLLOWING ->
            FOLLOWINGTEXTSEARCH

        FOLLOWERS ->
            FOLLOWERSTEXTSEARCH

        FRIENDS ->
            FRIENDSTEXTSEARCH

        other ->
            other


fetchUsers :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> Proto.Rellm.GetUsersRequest
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, GetUsersResponse )
fetchUsers accountsPanelModel maybeAccountServer request =
    performWithOptionalAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server maybeToken ->
            Grpc.new Rellm.getUsers request
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken maybeToken
                |> Grpc.toTask
        )


{-| Reloads `userId` fresh via `GetUsers` (so any fields that changed
server-side since the caller's own copy isn't clobbered), applies `updateFn`
to that fresh copy, then submits the result via `UpdateUser` -- the "reload,
then write, then update" dance `Components.UserProfilePage`'s Real Name and
permissions editors both need, mirroring `Shared.MarkdownPanel.saveTask`'s
`PostContent` case (`GetPosts`+`UpdatePost`). Returns a `Msg` to dispatch if
a token refresh happened, alongside the updated `User`, same convention as
`fetchUserById`.
-}
updateUser :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> String
    -> (User -> User)
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, User )
updateUser accountsPanelModel maybeAccountServer userId updateFn =
    performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.getUsers { defaultGetUsersRequest | userId = Just userId }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
                |> Task.andThen
                    (\response ->
                        case List.head response.users of
                            Just freshUser ->
                                Grpc.new Rellm.updateUser (updateFn freshUser)
                                    |> Grpc.setHost (RellmServers.rellmServerUrl server)
                                    |> withAccessToken (Just token)
                                    |> Grpc.toTask

                            Nothing ->
                                Task.fail Grpc.NetworkError
                    )
        )


{-| Starts SMS verification of the current account's own phone
`ContactMethod` (self-only, per `backend/src/rpcs/users/start_contact_method_verification.rs`).
Unlike `updateUser`, this is a direct request/response RPC -- no
reload-then-write dance needed since the request just echoes the
`ContactMethod` being verified.
-}
startContactMethodVerification :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> ContactMethod
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, ContactMethod )
startContactMethodVerification accountsPanelModel maybeAccountServer contactMethod =
    performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.startContactMethodVerification contactMethod
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| Verifies a code sent by `startContactMethodVerification` against the
current account's own phone `ContactMethod` (self-only). Direct
request/response RPC, same shape as `startContactMethodVerification`.
-}
verifyContactMethod :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> VerifyContactMethodRequest
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, ContactMethod )
verifyContactMethod accountsPanelModel maybeAccountServer request =
    performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.verifyContactMethod request
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| Federates `maybeAccountServer`'s account's own profile (identified by the
caller's auth token, not any id in the request) with `target` -- unlike
`updateUser`, `FederateProfile`/`DefederateProfile` always act on the
signed-in caller themself, so there's no "self or admin" edit gate to check
here (see `backend/src/rpcs/federation/federate_profile.rs`).
-}
federateProfile :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> FederatedAccount
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, FederatedAccount )
federateProfile accountsPanelModel maybeAccountServer target =
    performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.federateProfile target
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| The inverse of `federateProfile` -- removes `target` from the account's
own `federatedProfiles`.
-}
defederateProfile :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> FederatedAccount
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, Proto.Google.Protobuf.Empty )
defederateProfile accountsPanelModel maybeAccountServer target =
    performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.defederateProfile target
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| Deletes `user` outright (`DeleteUser`, self-or-Admin gated server-side,
see `backend/src/rpcs/users/delete_user.rs`) -- unlike
`Components.Posts.deletePost`/`Components.Events.deleteEvent` (whose backend
handlers only ever look at `request.id`), `delete_user.rs` runs the _whole_
request through `validate_user` first, so a bare `{ defaultUser | id = ... }`
gets rejected (empty `username`, `Visibility::Unknown`, etc.) -- this takes
the already-loaded `User` (as held by `Resolver.Loaded`/`Shared.ConfirmUserDelete`)
and sends it through as-is instead. Used by
`Components.Pages.UserProfilePage`'s own Delete User button.
-}
deleteUser :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> User
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, Proto.Google.Protobuf.Empty )
deleteUser accountsPanelModel maybeAccountServer user =
    performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.deleteUser user
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| Resets `user`'s password to `password` (`ResetPassword`, self-or-Admin gated server-side, see
`backend/src/rpcs/authentication/reset_password.rs`) -- always passes `userId = Just user.id`
explicitly (rather than `Nothing`, which the RPC would otherwise resolve to "the caller"), so this
works identically whether the caller is resetting their own password or, as an Admin, someone
else's. Used by `Components.Pages.UserProfilePage`'s own Reset Password button.
-}
resetPassword :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> User
    -> String
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, Proto.Google.Protobuf.Empty )
resetPassword accountsPanelModel maybeAccountServer user password =
    performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.resetPassword { userId = Just user.id, password = password }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| Creates a `Follow` -- i.e. `follow.userId` requests to follow
`follow.targetUserId`, subject to the target's own `defaultFollowModeration`
(see `Components.Users.FollowStatusAndButton`, this RPC's only caller).
-}
createFollow :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> Follow
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, Follow )
createFollow accountsPanelModel maybeAccountServer follow =
    performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.createFollow follow
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| Updates a `Follow`'s `targetUserModeration` -- only the `targetUserId`
side of a `Follow` may do this (i.e. approve/reject a follower), see
`Components.Users.FollowStatusAndButton`.
-}
updateFollow :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> Follow
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, Follow )
updateFollow accountsPanelModel maybeAccountServer follow =
    performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.updateFollow follow
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| Deletes a `Follow` -- either `follow.userId` unfollowing/cancelling a
follow request on `follow.targetUserId`, see
`Components.Users.FollowStatusAndButton`.
-}
deleteFollow :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> Follow
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, Proto.Google.Protobuf.Empty )
deleteFollow accountsPanelModel maybeAccountServer follow =
    performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.deleteFollow follow
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )



-- ROUTE / LINKS


{-| Usernames that can't be routed to via `/:username[@host]` since they'd
collide with this app's own top-level routes (`Pages.About`, `Pages.People`,
elm-spa's builtin `not-found`) or the `/user`/`/post` prefixes themselves --
e.g. a user named "about" is only ever reachable via `/user/:id[@host]`, never
`/about[@host]`. Compared case-insensitively, since the collision is with the
URL segment, not the display name.
-}
reservedUsernames : Set String
reservedUsernames =
    Set.fromList [ "about", "not-found", "user", "post", "people" ]


isReservedUsername : String -> Bool
isReservedUsername username =
    Set.member (String.toLower (String.trim username)) reservedUsernames


{-| Whether `segment`'s first character is one no username (`^[\w.-]+$`, `Users`' own
`validate_username`) or custom tab path (`^[a-z_]+$`, `validate_custom_tab_path`) could ever
legally start with -- see `backend/src/rpcs/validations/validate_fields.rs`'s
`RESERVED_LEAD_CHAR_RE`, which this set must stay in sync with. `Pages.UsernameOrCustomTab_`
checks this before falling back to a plain username/custom-tab lookup: a route segment starting
with one of these is unambiguously *not* a username or custom tab, so it's tried as a short
Post/Event URL instead (`Components.Pages.PostOrEventPage`) -- see `rellm.proto`'s own
`### /[-._~:/?[]@!$&'()*+,;%=]{postId}: Short Post/Event URLs` routing doc. `#` is deliberately
excluded: URL fragments never reach the server, so they're not part of this at all.
-}
startsWithReservedShortUrlCharacter : String -> Bool
startsWithReservedShortUrlCharacter segment =
    case String.uncons segment of
        Just ( firstChar, _ ) ->
            String.contains (String.fromChar firstChar) "-._~:/?[]@!$&'()*+,;%="

        Nothing ->
            False


{-| The `/user/:id[@host]` href for a user, as seen from `viewingServerHost`
(typically `shared.accounts.mainFrontendHost`) -- mirrors
`Components.Posts.postHref`.
-}
userIdHref : String -> String -> String -> String -> String
userIdHref basePath viewingServerHost userServerHost userId =
    basePath ++ Gen.Route.toHref (Gen.Route.User__UserId_ { userId = withHostSuffix viewingServerHost userServerHost userId })


{-| The `/:username[@host]` href for a user -- only meaningful when
`username` isn't reserved (see `isReservedUsername`); prefer `profileHref`
where the username might not be usable.
-}
usernameHref : String -> String -> String -> String -> String
usernameHref basePath viewingServerHost userServerHost username =
    basePath ++ Gen.Route.toHref (Gen.Route.UsernameOrCustomTab_ { usernameOrCustomTab = withHostSuffix viewingServerHost userServerHost username })


{-| The `/:username[@host]/followers` href for a user -- same username-routability caveat as
`usernameHref` itself (only meaningful for a real, non-reserved username), used directly by
`Components.Pages.MastodonUserProfilePage`/`BlueskyUserProfilePage` (a federated profile always has a
real, routable username -- there's no id-based fallback route for one, unlike a Rellm `User`).
-}
followersHref : String -> String -> String -> String -> String
followersHref basePath viewingServerHost userServerHost username =
    basePath ++ Gen.Route.toHref (Gen.Route.UsernameOrCustomTab___Followers { usernameOrCustomTab = withHostSuffix viewingServerHost userServerHost username })


{-| The `/:username[@host]/following` href for a user -- `followersHref`'s own doc, just the other
direction.
-}
followingHref : String -> String -> String -> String -> String
followingHref basePath viewingServerHost userServerHost username =
    basePath ++ Gen.Route.toHref (Gen.Route.UsernameOrCustomTab___Following { usernameOrCustomTab = withHostSuffix viewingServerHost userServerHost username })


{-| The best available profile link for a user: their `/:username[@host]`
route if they have one that's actually routable (non-empty, not reserved --
see `isReservedUsername`), falling back to the always-routable
`/user/:id[@host]` otherwise.
-}
profileHref : String -> String -> String -> { userId : String, username : String } -> String
profileHref basePath viewingServerHost userServerHost user =
    if String.isEmpty (String.trim user.username) || isReservedUsername user.username then
        userIdHref basePath viewingServerHost userServerHost user.userId

    else
        usernameHref basePath viewingServerHost userServerHost user.username


withHostSuffix : String -> String -> String -> String
withHostSuffix viewingServerHost userServerHost id =
    if userServerHost == viewingServerHost then
        id

    else
        id ++ "@" ++ userServerHost


{-| The inverse of `withHostSuffix`: `rawId` is either a bare id/username (a
user on `mainFrontendHost`) or `id@host`/`username@host` (a user on some other,
federated server) -- mirrors `Components.Posts.parsePostRouteId`.
-}
parseUserRouteId : String -> String -> ( String, String )
parseUserRouteId mainFrontendHost rawId =
    case String.split "@" rawId of
        [ id, host ] ->
            ( id, host )

        _ ->
            ( rawId, mainFrontendHost )


{-| Recognizes a Mastodon/Bluesky profile from `parseUserRouteId`'s own `( username, host )` pair --
`host` is what actually carries the `"mastodon:"`/`"bluesky:"` tag (see
`Components.Pages.PostsPage.feedSourceKey`'s own construction, which every federated author link's
`href` is ultimately built from -- see `Components.Authors.href`), mirroring
`Components.Posts.parseFederatedPostId` exactly, one level up (a profile instead of a post).
`Nothing` for a real Rellm user's own `host` (or anything else unrecognized).
`Components.Pages.MastodonUserProfilePage`/`BlueskyUserProfilePage` are this module's own
counterparts to `Components.Pages.MastodonPostPage`/`BlueskyPostPage` -- see
`Pages.UsernameOrCustomTab_.initProfile`/`Pages.User.UserId_.init`, the two callers.
-}
type FederatedUserId
    = MastodonUserId { instanceHost : String, username : String }
    | BlueskyUserId { handle : String }


parseFederatedUserId : String -> String -> Maybe FederatedUserId
parseFederatedUserId username host =
    if String.startsWith "mastodon:" host then
        Just (MastodonUserId { instanceHost = String.dropLeft 9 host, username = username })

    else if String.startsWith "bluesky:" host then
        Just (BlueskyUserId { handle = username })

    else
        Nothing



-- DISPLAY


{-| A username display enriched with the user's Real Name, if they have one --
mirrors `Shared.RellmAccounts.rellmAccountDisplayName`.
-}
displayName : User -> String
displayName user =
    if String.isEmpty (String.trim user.realName) then
        user.username

    else
        user.realName ++ " (" ++ user.username ++ ")"


{-| A user's Real Name, if they have one, otherwise just their username --
unlike `displayName`, never both at once, since this is for contexts (e.g. a
browser tab title) too terse for the parenthetical.
-}
titleName : User -> String
titleName user =
    if String.isEmpty (String.trim user.realName) then
        user.username

    else
        user.realName


{-| The URL for a user's avatar, authorized with `maybeAccount`'s access token
if given -- avatars can be visibility-restricted, so an anonymous request (or
one from an account that isn't allowed to see it) may still 403 despite this
returning `Just` a URL. Mirrors `Shared.RellmAccounts.rellmAccountAvatarUrl`.
-}
avatarUrl : RellmServer -> Maybe RellmAccount -> User -> Maybe String
avatarUrl server maybeAccount user =
    mediaReferenceUrl server maybeAccount user.avatar


{-| Like `avatarUrl`, but for an `Author` (the smaller, post-embedded version
of a `User` -- see `Components.Posts.postAuthorHref`) instead of a full `User`.
-}
authorAvatarUrl : RellmServer -> Maybe RellmAccount -> Author -> Maybe String
authorAvatarUrl server maybeAccount author =
    mediaReferenceUrl server maybeAccount (Maybe.map unwrapMediaReference author.avatar)


{-| `avatarUrl`/`authorAvatarUrl`'s shared guts, exposed on its own too --
`Components.Pages.UserProfilePage`'s in-progress avatar edit uses it directly
(wrapping a bare `mediaId` in a throwaway `MediaReference`, see its own
`avatarPreviewUrl`) to preview a newly-picked media item that isn't
`user.avatar` yet.
-}
mediaReferenceUrl : RellmServer -> Maybe RellmAccount -> Maybe Proto.Rellm.MediaReference -> Maybe String
mediaReferenceUrl server maybeAccount maybeMedia =
    maybeMedia
        |> Maybe.andThen
            (\media ->
                RellmServers.mediaUrl server media.id
                    |> Maybe.map
                        (\base ->
                            case maybeAccount of
                                Just account ->
                                    base ++ "?authorization=" ++ account.accessToken.token

                                Nothing ->
                                    base
                        )
            )


{-| A compact card for a `user` in a list (`/people`, or a profile's own
Following/Followers/Friends pages -- see `Components.Pages.UsersPage`) --
links to their profile (`profileHref`), showing their avatar (or an
initial-letter placeholder, see `userCardAvatar`), `displayName`, and
follower/following counts, plus whatever `followStatusAndButton` renders at
the card's far right (a `Components.Users.FollowStatusAndButton.view`, mapped
into the caller's own `Msg` -- kept as a plain `Html msg` slot here rather
than this module importing that one directly, which would cycle back through
`FollowStatusAndButton`'s own dependency on `createFollow`/`updateFollow`/
`deleteFollow`/`moderationPasses` etc. here).

Like `Components.PostCard.postCard` (not "one plain `<a>`", as this used to be
and as its own doc comment used to claim) -- now that `userCardContactButtons`
renders real `tel:`/`mailto:` `<a>`s of their own, this needs `postCard`'s own
"stretched link" treatment too: nesting a real `<a>` inside another `<a>`
doesn't work in Elm, since every anchor's `href` navigation is wired up as its
own native click listener attached directly to *that* anchor's DOM node (see
`postCard`'s own doc comment for the full explanation), not by walking up to
the nearest enclosing one -- so a click on a contact button would fire both
listeners, and the outer (later, bubbled-to) one always wins, silently
overriding the tel:/mailto: navigation with a profile-navigate instead
(exactly the "underlying card gets clicked instead" bug this structure
avoids). So the card itself is a plain `div`; its first child is an invisible
`<a>` (`.user-card-link-overlay`) absolutely filling it, sitting *behind*
everything else -- `.user-card-contact-buttons`/`.follow-status-and-button`
both opt back into their own paint layer via `position: relative` (see
`users.css`) to stay independently clickable above it, while the rest (avatar,
name, meta text) has no interactive descendants of its own, so it's fine to
just sit visually behind the overlay and fall through to the same profile
navigation either way -- mirrors `.post-card-title`'s identical treatment.
-}
userCard : String -> String -> RellmServer -> Maybe RellmAccount -> Html msg -> User -> Html msg
userCard basePath viewingServerHost server maybeAccount followStatusAndButton user =
    div
        [ classes
            [ "user-card"
            , hostnameToCSSClass server.frontendHost
            , "border-color-primary-anchor-50"
            , "hover-border-color-primary-anchor"
            , "background-color-primary-5"
            ]
        ]
        [ a
            [ href (profileHref basePath viewingServerHost server.frontendHost { userId = user.id, username = user.username })
            , Html.Attributes.class "user-card-link-overlay"
            , Html.Attributes.attribute "aria-label" (displayName user)
            ]
            []
        , userCardAvatar (displayName user) (avatarUrl server maybeAccount user)
        , div [ Html.Attributes.class "user-card-details" ]
            [ div [] (text (displayName user) :: userCardBadges user)
            , div [ Html.Attributes.class "user-card-meta" ] [ text (userCardMetaText user) ]
            , div [ Html.Attributes.class "user-card-contact-buttons" ] (userCardContactButtons user)
            ]
        , followStatusAndButton
        ]


{-| "📞 <number>"/"✉️ <address>" `tel:`/`mailto:` buttons for `userCard` -- shown only for whichever
of `user.phone`/`user.email` is both present (already server-gated by each `ContactMethod`'s own
`visibility` -- see `visible_contact_method` on the backend, so a `Just` here already means this
viewer may see it at all) and holds a validly-schemed `value` (defensively re-checked here via
`String.startsWith`, not just trusted, in case of a malformed/mismatched-scheme value). The button's
own label is the icon plus the scheme stripped off `value` (e.g. `"📞 +15555550123"`), plus a
trailing "✅" (the actual emoji, not a plain ✓/✔ symbol -- deliberately picked to read as a colorful
verified badge rather than blend in with the rest of the label) when that `ContactMethod`'s own
`verifiedAt` is set, so the actual number/address (and its verification status) is visible without a
click -- `href` still carries the full `tel:`/`mailto:` value. Renders as plain
`<a href="tel:…">`/`<a href="mailto:…">` links; inside `userCard`'s own profile-link `<a>` these end
up nested (technically invalid HTML5), but harmless there: both Elm's own click-routing and every
evergreen browser's native default action resolve a click to whichever anchor is nearest the actual
click target, so the innermost (phone/email) link is what fires, never a competing profile
navigation. Exposed (not just used locally) so `Components.Pages.UserProfilePage.profileDetail` can
render the same links above its own "Contact Methods" section, for a viewer who can see the values
but -- unlike the profile's own owner/an admin -- can't edit them (so that section itself is hidden
for them entirely).
-}
userCardContactButtons : User -> List (Html msg)
userCardContactButtons user =
    let
        contactButton : String -> String -> ContactMethod -> Maybe (Html msg)
        contactButton scheme icon contactMethod =
            contactMethod.value
                |> Maybe.andThen
                    (\value ->
                        if String.startsWith scheme value then
                            Just
                                (a [ href value, Html.Attributes.class "user-card-contact-button" ]
                                    [ text
                                        (icon
                                            ++ " "
                                            ++ String.dropLeft (String.length scheme) value
                                            ++ (if contactMethod.verifiedAt /= Nothing then
                                                    " ✅"

                                                else
                                                    ""
                                               )
                                        )
                                    ]
                                )

                        else
                            Nothing
                    )
    in
    List.filterMap identity
        [ user.phone |> Maybe.andThen (contactButton "tel:" "📞")
        , user.email |> Maybe.andThen (contactButton "mailto:" "✉️")
        ]


{-| Duplicated (rather than reusing `Components.Authors.compactBadges`) since
`Authors` itself imports this module (for `userCard`, mirroring `avatarUrl`/
`profileHref` elsewhere), so the reverse import would be a cycle -- same
reasoning as `userCardAvatar` above.
-}
userCardBadges : User -> List (Html msg)
userCardBadges user =
    (if List.member ADMIN user.permissions then
        [ Html.span [ Html.Attributes.class "author-badge-compact", Html.Attributes.title "Admin" ] [ text "🛡️" ] ]

     else
        []
    )
        ++ (if List.member BUSINESS user.permissions then
                [ Html.span [ Html.Attributes.class "author-badge-compact", Html.Attributes.title "Business Account" ] [ text "💼" ] ]

            else
                []
           )
        ++ (if List.member RUNBOTS user.permissions then
                [ Html.span [ Html.Attributes.class "author-badge-compact", Html.Attributes.title "Has Permission to Run Bots" ] [ text "🤖" ] ]

            else
                []
           )


{-| Duplicated (rather than reusing `UI.imageOrInitial`) since `UI` itself
imports this module (for `userCard`, mirroring `avatarUrl`/`profileHref`
elsewhere), so the reverse import would be a cycle -- same reasoning as
`Components.PostCard`'s own private `authorAvatar`.
-}
userCardAvatar : String -> Maybe String -> Html msg
userCardAvatar name maybeUrl =
    case maybeUrl of
        Just url ->
            img [ Html.Attributes.class "user-card-avatar", src url, alt name, attribute "loading" "lazy" ] []

        Nothing ->
            div [ classes [ "user-card-avatar", "placeholder" ] ] [ text (RellmServers.initialLetter name) ]


{-| "N followers · N following" for `userCard` -- either half is dropped
entirely (rather than shown as "0") when that count isn't present at all
(`User.followerCount`/`followingCount` are both optional).
-}
userCardMetaText : User -> String
userCardMetaText user =
    [ user.followerCount |> Maybe.map (\c -> String.fromInt c ++ " followers")
    , user.followingCount |> Maybe.map (\c -> String.fromInt c ++ " following")
    ]
        |> List.filterMap identity
        |> String.join " · "


{-| Display text for a User's visibility -- mirrors
`Components.Posts.postVisibilityText`, which is Post-specific.
-}
visibilityText : Visibility -> String
visibilityText visibility =
    case visibility of
        PRIVATE ->
            "Private"

        LIMITED ->
            "Limited"

        SERVERPUBLIC ->
            "Server Public"

        GLOBALPUBLIC ->
            "Global Public"

        DIRECT ->
            "Direct"

        VISIBILITYUNKNOWN ->
            "Unknown"

        VisibilityUnrecognized_ _ ->
            "Unknown"


{-| The visibility options offered by a User's visibility-editing `<select>`
(see `Components.Pages.UserProfilePage`) -- mirrors `Components.Posts.allVisibilities`
(duplicated rather than imported, since `Posts` itself imports this module,
so the reverse import would be a cycle -- same reasoning as `userCardAvatar`
above), excluding `DIRECT` (the proto itself marks it `[TODO]`/unimplemented,
see `protos/visibility_moderation.proto`) and `VISIBILITYUNKNOWN` (never a
valid value to _set_). Order matches `visibilityText`/the proto's own
declaration order.
-}
allVisibilities : List Visibility
allVisibilities =
    [ PRIVATE, LIMITED, SERVERPUBLIC, GLOBALPUBLIC ]


{-| The reverse of `visibilityText` -- looks up a `Visibility` by its display
label, the same round-trip `permissionFromText` does for `Permission`.
`Nothing` for any text that isn't one of `allVisibilities`' labels (shouldn't
happen, since the `<select>`'s own options are always built from
`allVisibilities` in the first place).
-}
visibilityFromText : String -> Maybe Visibility
visibilityFromText text =
    allVisibilities |> List.filter (\visibility -> visibilityText visibility == text) |> List.head


{-| Which of `allVisibilities` `permissions` may pick for a User -- mirrors
`backend/src/rpcs/users/update_user.rs`'s own permission check: setting
`GLOBALPUBLIC` needs `PUBLISHUSERSGLOBALLY` (or `ADMIN`); every other
visibility is always pickable by whoever's already allowed to edit the
profile at all (see `Components.Pages.UserProfilePage.canEditProfile`).
`currentVisibility` is always included even if it wouldn't otherwise be
pickable, so an account whose permission was revoked after the profile was
already elevated still sees its own current value in the list (just can't
newly pick it again) -- mirrors `Components.Posts.allowedVisibilities`.
-}
allowedVisibilities : List Permission -> Visibility -> List Visibility
allowedVisibilities permissions currentVisibility =
    let
        canPublishGlobally : Bool
        canPublishGlobally =
            List.member PUBLISHUSERSGLOBALLY permissions || List.member ADMIN permissions
    in
    allVisibilities
        |> List.filter (\visibility -> visibility /= GLOBALPUBLIC || canPublishGlobally || visibility == currentVisibility)


moderationText : Moderation -> String
moderationText moderation =
    case moderation of
        UNMODERATED ->
            "Unmoderated"

        PENDING ->
            "Pending"

        APPROVED ->
            "Approved"

        REJECTED ->
            "Rejected"

        MODERATIONUNKNOWN ->
            "Unknown"

        ModerationUnrecognized_ _ ->
            "Unknown"


{-| The moderation-status options offered by a User's moderation-editing
`<select>` (see `Components.Pages.UserProfilePage`) -- mirrors
`Components.Posts.allModerations` (duplicated for the same cycle-avoiding
reason as `allVisibilities` above), excluding `MODERATIONUNKNOWN`, never a
valid value to _set_. Order matches the proto's own declaration order.
-}
allModerations : List Moderation
allModerations =
    [ UNMODERATED, PENDING, APPROVED, REJECTED ]


{-| The reverse of `moderationText` -- same `<select>`-value round-trip
`visibilityFromText` does for `Visibility`.
-}
moderationFromText : String -> Maybe Moderation
moderationFromText text =
    allModerations |> List.filter (\moderation -> moderationText moderation == text) |> List.head


{-| Whether a `Moderation` (e.g. a `Follow`'s `targetUserModeration`) counts
as "in effect" -- the subject is visible/active. Mirrors the Tamagui app's
`utils/moderation_utils.ts` `passes`.
-}
moderationPasses : Moderation -> Bool
moderationPasses moderation =
    moderation == UNMODERATED || moderation == APPROVED


{-| Whether a `Moderation` is still awaiting a decision -- mirrors the
Tamagui app's `utils/moderation_utils.ts` `pending`.
-}
moderationPending : Moderation -> Bool
moderationPending moderation =
    moderation == PENDING


{-| Whether a `Moderation` has been explicitly declined -- mirrors the
Tamagui app's `utils/moderation_utils.ts` `rejected`.
-}
moderationRejected : Moderation -> Bool
moderationRejected moderation =
    moderation == REJECTED


{-| A plain-English label for a `Permission` -- e.g. for a profile's
permissions list. Order matches `permissions.proto`.
-}
permissionText : Permission -> String
permissionText permission =
    case permission of
        PERMISSIONUNKNOWN ->
            "Unknown"

        VIEWUSERS ->
            "View Users"

        PUBLISHUSERSLOCALLY ->
            "Publish Users Locally"

        PUBLISHUSERSGLOBALLY ->
            "Publish Users Globally"

        MODERATEUSERS ->
            "Moderate Users"

        FOLLOWUSERS ->
            "Follow Users"

        GRANTBASICPERMISSIONS ->
            "Grant Basic Permissions"

        VIEWGROUPS ->
            "View Groups"

        CREATEGROUPS ->
            "Create Groups"

        PUBLISHGROUPSLOCALLY ->
            "Publish Groups Locally"

        PUBLISHGROUPSGLOBALLY ->
            "Publish Groups Globally"

        MODERATEGROUPS ->
            "Moderate Groups"

        JOINGROUPS ->
            "Join Groups"

        INVITEGROUPMEMBERS ->
            "Invite Group Members"

        VIEWPOSTS ->
            "View Posts"

        CREATEPOSTS ->
            "Create Posts"

        PUBLISHPOSTSLOCALLY ->
            "Publish Posts Locally"

        PUBLISHPOSTSGLOBALLY ->
            "Publish Posts Globally"

        MODERATEPOSTS ->
            "Moderate Posts"

        REPLYTOPOSTS ->
            "Reply To Posts"

        EDITPOSTTITLESANDLINKS ->
            "Edit Post Titles And Links"

        VIEWEVENTS ->
            "View Events"

        CREATEEVENTS ->
            "Create Events"

        PUBLISHEVENTSLOCALLY ->
            "Publish Events Locally"

        PUBLISHEVENTSGLOBALLY ->
            "Publish Events Globally"

        MODERATEEVENTS ->
            "Moderate Events"

        RSVPTOEVENTS ->
            "RSVP To Events"

        SYNCEVENTSFROMICS ->
            "Sync Events from iCal"

        SYNCPOSTSFROMRSS ->
            "Sync Posts from RSS"

        SYNCPOSTSFROMATOM ->
            "Sync Posts from Atom"

        VIEWMEDIA ->
            "View Media"

        CREATEMEDIA ->
            "Create Media"

        PUBLISHMEDIALOCALLY ->
            "Publish Media Locally"

        PUBLISHMEDIAGLOBALLY ->
            "Publish Media Globally"

        MODERATEMEDIA ->
            "Moderate Media"

        BUSINESS ->
            "Business"

        RUNBOTS ->
            "Run Bots"

        ADMIN ->
            "Admin"

        VIEWPRIVATECONTACTMETHODS ->
            "View Private Contact Methods"

        EDITCLUSTERSETTINGS ->
            "Edit Cluster Settings"

        SYNCEVENTSTOFACEBOOK ->
            "Sync Events To Facebook"

        SYNCPOSTSTOFACEBOOK ->
            "Sync Posts To Facebook"

        SYNCEVENTSTOINSTAGRAM ->
            "Sync Events To Instagram"

        SYNCPOSTSTOINSTAGRAM ->
            "Sync Posts To Instagram"

        SYNCEVENTSTOMASTODON ->
            "Sync Events To Mastodon"

        SYNCPOSTSTOMASTODON ->
            "Sync Posts To Mastodon"

        SYNCEVENTSTOBLUESKY ->
            "Sync Events To Bluesky"

        SYNCPOSTSTOBLUESKY ->
            "Sync Posts To Bluesky"

        SYNCEVENTSTOXTWITTER ->
            "Sync Events To X (Twitter)"

        SYNCPOSTSTOXTWITTER ->
            "Sync Posts To X (Twitter)"

        SYNCEVENTSTOTHREADS ->
            "Sync Events To Threads"

        SYNCPOSTSTOTHREADS ->
            "Sync Posts To Threads"

        READPERSONALMESSAGES ->
            "Read Personal Messages"

        READALLSYSTEMMESSAGES ->
            "Read All System Messages"

        CREATEAIPROVIDERS ->
            "Create AI Providers"

        PermissionUnrecognized_ _ ->
            "Unknown"


{-| Every real `Permission` a user could actually be granted (excludes
`PERMISSIONUNKNOWN`/`PermissionUnrecognized_`, which aren't grantable) -- the
full set an admin picks from in `Components.UserProfilePage`'s permissions
editor's "Add Permission" `<select>`. Order matches `permissionText`/
`permissions.proto`.
-}
allPermissions : List Permission
allPermissions =
    [ VIEWUSERS
    , PUBLISHUSERSLOCALLY
    , PUBLISHUSERSGLOBALLY
    , MODERATEUSERS
    , FOLLOWUSERS
    , GRANTBASICPERMISSIONS
    , VIEWGROUPS
    , CREATEGROUPS
    , PUBLISHGROUPSLOCALLY
    , PUBLISHGROUPSGLOBALLY
    , MODERATEGROUPS
    , JOINGROUPS
    , INVITEGROUPMEMBERS
    , VIEWPOSTS
    , CREATEPOSTS
    , PUBLISHPOSTSLOCALLY
    , PUBLISHPOSTSGLOBALLY
    , MODERATEPOSTS
    , REPLYTOPOSTS
    , EDITPOSTTITLESANDLINKS
    , VIEWEVENTS
    , CREATEEVENTS
    , PUBLISHEVENTSLOCALLY
    , PUBLISHEVENTSGLOBALLY
    , MODERATEEVENTS
    , RSVPTOEVENTS
    , SYNCEVENTSFROMICS
    , SYNCEVENTSTOFACEBOOK
    , SYNCPOSTSTOFACEBOOK
    , SYNCEVENTSTOINSTAGRAM
    , SYNCPOSTSTOINSTAGRAM
    , SYNCEVENTSTOMASTODON
    , SYNCPOSTSTOMASTODON
    , SYNCEVENTSTOBLUESKY
    , SYNCPOSTSTOBLUESKY
    , SYNCEVENTSTOXTWITTER
    , SYNCPOSTSTOXTWITTER
    , SYNCEVENTSTOTHREADS
    , SYNCPOSTSTOTHREADS
    , VIEWMEDIA
    , CREATEMEDIA
    , PUBLISHMEDIALOCALLY
    , PUBLISHMEDIAGLOBALLY
    , MODERATEMEDIA
    , READPERSONALMESSAGES
    , READALLSYSTEMMESSAGES
    , CREATEAIPROVIDERS
    , BUSINESS
    , RUNBOTS
    , ADMIN
    , VIEWPRIVATECONTACTMETHODS
    ]


{-| The permissions grantable server-wide, i.e. what an admin can put in
`ServerConfiguration`'s `anonymousUserPermissions`/`defaultUserPermissions`/
`basicUserPermissions` -- unlike `allPermissions` (a single user's own grant
list), this excludes anything that only makes sense granted to one person at
a time (`ADMIN`, `MODERATE*`, `GRANT_BASIC_PERMISSIONS`, `FOLLOW_USERS`,
`INVITE_GROUP_MEMBERS`, `REPLY_TO_POSTS`, `BUSINESS`,
`RUN_BOTS`, `VIEW_PRIVATE_CONTACT_METHODS`). Same list for all three sets --
mirrors the Tamagui app's `server_details_screen.tsx` `configurableUserPermissions`,
which likewise reuses one list across its Anonymous/Default/Basic editors
(see `Components.Pages.ServerInformationPage.permissionsSection`).
-}
configurableServerPermissions : List Permission
configurableServerPermissions =
    [ VIEWUSERS
    , PUBLISHUSERSLOCALLY
    , PUBLISHUSERSGLOBALLY
    , VIEWGROUPS
    , CREATEGROUPS
    , VIEWMEDIA
    , CREATEMEDIA
    , PUBLISHMEDIALOCALLY
    , PUBLISHMEDIAGLOBALLY
    , PUBLISHGROUPSLOCALLY
    , PUBLISHGROUPSGLOBALLY
    , JOINGROUPS
    , VIEWPOSTS
    , CREATEPOSTS
    , PUBLISHPOSTSLOCALLY
    , PUBLISHPOSTSGLOBALLY
    , VIEWEVENTS
    , CREATEEVENTS
    , RSVPTOEVENTS
    , PUBLISHEVENTSLOCALLY
    , PUBLISHEVENTSGLOBALLY
    , SYNCEVENTSFROMICS
    , READPERSONALMESSAGES
    ]


{-| The reverse of `permissionText` -- looks up a `Permission` by its display
label. Needed because a plain HTML `<select>`'s value/`onInput` are just
strings; `Components.UserProfilePage`'s "Add Permission" picker uses
`permissionText` for each `<option>`'s label and reads this back on change.
`Nothing` for any text that isn't one of `allPermissions`' labels (shouldn't
happen, since the `<select>`'s own options are always built from
`allPermissions` in the first place).
-}
permissionFromText : String -> Maybe Permission
permissionFromText text =
    allPermissions |> List.filter (\permission -> permissionText permission == text) |> List.head
