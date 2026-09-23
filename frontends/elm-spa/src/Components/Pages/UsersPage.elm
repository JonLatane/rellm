module Components.Pages.UsersPage exposing
    ( FederatedListingType(..)
    , FederatedTarget(..)
    , Model
    , Msg
    , fromShared
    , init
    , subscriptions
    , update
    , view
    )

{-| The shared guts of a "list of users" page: fetching a `UserListingType`
listing of users and rendering them as `Components.Users.userCard`s -- reused
by `Pages.People` (which adds its own "People" heading and passes
`target = Nothing`, an unfiltered `EVERYONE` listing aggregated across every
enabled server, mirroring `Components.Pages.PostsPage`'s own aggregation for
`Pages.Home_`) and `Pages.UsernameOrCustomTab_.{Following,Followers,Friends}`/
`Pages.User.UserId_.{Following,Followers,Friends}` (which pass the
already-resolved profile `User` paired with the host it was resolved from and
the relevant `UserListingType`, restricting the listing to that user's own
relationship, fetched from just that one host -- see `candidateSources` --
and adding a "Following | <name>"-style heading), mirroring
`Components.Pages.PostsPage`'s own `author` parameter and reuse by
`Pages.UsernameOrCustomTab_.Posts`/`Pages.User.UserId_.Posts`.

`federatedTarget` is `target`'s Mastodon/Bluesky counterpart -- see
`FederatedTarget`'s own doc. `Pages.UsernameOrCustomTab_.Followers`/`Following` pass one once
`Components.Users.parseFederatedUserId` recognizes the route's host as federated, mirroring
`Components.Pages.PostsPage.profileFeedSource`'s identical "separate field, mutually exclusive with
the Rellm one" shape. Unlike a Rellm `target`, there's no unfiltered "everyone" federated listing
(neither Mastodon nor Bluesky offers one) -- when `target`/`federatedTarget` are both `Nothing`
(`Pages.People`'s own unfiltered case), a non-blank search additionally fans out to every
browsed/connected Mastodon instance and (if any account is connected) Bluesky's own actor search,
alongside the always-present Rellm `EVERYONE` listing -- see `candidateSources`.

Like `PostsPage`, cards fade/scale in and out (see `UserAnimation`) as users
appear/disappear from the listing -- e.g. a search that narrows the results,
or a server being disabled -- via `UI.Flip`.

-}

import Animation
import Browser.Navigation
import Components.Authors as Authors
import Components.Users as Users
import Components.Users.FollowStatusAndButton as FollowStatusAndButton
import Components.Users.ProfileHeading as ProfileHeading
import Dict exposing (Dict)
import Effect exposing (Effect)
import Grpc
import Html exposing (Html, a, button, div, h2, input, p, text)
import Html.Attributes exposing (class, href, placeholder, style, title, type_, value)
import Html.Events exposing (onClick, onInput, preventDefaultOn)
import Html.Keyed
import Http
import Json.Decode as Decode
import Process
import Proto.Rellm exposing (GetUsersResponse, User)
import Proto.Rellm.UserListingType exposing (UserListingType(..))
import Set
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.BlueskyAccounts as BlueskyAccounts exposing (BlueskyAccount)
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Shared.Breadcrumbs as Breadcrumbs
import Shared.Federation.Bluesky as Bluesky
import Shared.Federation.Mastodon as Mastodon
import Task
import Time
import UI.Classes exposing (hostnameToCSSClass)
import UI.Flip
import Url.Builder



-- MODEL


{-| `Following`/`Followers` -- `Components.Users.parseFederatedUserId`'s Mastodon/Bluesky
counterpart to `Proto.Rellm.UserListingType`, deliberately narrower: neither platform has a
"Friends" (mutual-follow) or unfiltered "everyone" concept, so only these two apply. Named
`Federated*` (not reusing `UserListingType.FOLLOWING`/`FOLLOWERS`) since those proto values also
carry meanings (`*TEXTSEARCH`, `FRIENDS`, `EVERYONE`) that don't apply here at all.
-}
type FederatedListingType
    = FederatedFollowers
    | FederatedFollowing


{-| `target`'s Mastodon/Bluesky counterpart -- see `Model.federatedTarget`'s own doc. Carries just
enough to fetch and link back to the target account: `MastodonAccountTarget`'s `accountId` is
resolved ahead of time by the caller (`Mastodon.lookupAccount`, since `fetchFollowers`/`fetchFollowing`
key off it, not the username) -- `Pages.UsernameOrCustomTab_.Followers`/`Following` do this
themselves before ever calling `init`, mirroring `Components.Pages.MastodonUserProfilePage.init`'s
identical two-step resolve-then-fetch shape. A Bluesky target needs no such resolution -- `handle`
alone is what every AT Proto call already keys off.
-}
type FederatedTarget
    = MastodonAccountTarget { instanceHost : String, accountId : String, username : String } FederatedListingType
    | BlueskyAccountTarget { handle : String } FederatedListingType


type alias Model =
    { usersByServer : Dict String SourceFeed
    , userAnimations : Dict String UserAnimation

    -- The user + host + listing type to restrict the listing to, if any --
    -- `Nothing` for `Pages.People`'s unfiltered `EVERYONE` listing.
    , target : Maybe ( String, User, UserListingType )
    , federatedTarget : Maybe FederatedTarget

    -- One `FollowStatusAndButton.Model` per Rellm card (see `listedUserKey`) -- missing entries
    -- (i.e. every card whose button hasn't been clicked yet) are treated as
    -- `FollowStatusAndButton.init`, same "absent means default" convention as
    -- `Components.Pages.PostsPage`'s per-post state. Never populated for a `MastodonListedUser`/
    -- `BlueskyListedUser` row -- neither renders a follow button at all (see `userCardView`), so
    -- `FollowStatusAndButtonMsg` never fires for one.
    , followStatusAndButtons : Dict String FollowStatusAndButton.Model
    , navKey : Browser.Navigation.Key
    , path : String
    , searchText : String
    , searchGeneration : Int
    }


type Msg
    = GotUsers String UsersResult
    | Poll
    | Animate Animation.Msg
    | RemoveUser String
    | SharedMsg Shared.Msg
    | FollowStatusAndButtonMsg String FollowStatusAndButton.Msg
    | SearchTextChanged String
    | SearchDebounceElapsed Int
    | ClearSearchClicked


type SourceUsers
    = Loading
    | Loaded (List ListedUser)
    | Failed


{-| `accountId` is the enabled account (if any) the users were/are being
fetched with, so a later account enable/disable on the same server can be
detected as "the acting credential changed" and trigger a re-fetch -- same
convention as `Components.Pages.PostsPage.ServerFeed`. Always `Nothing` for a Mastodon/Bluesky
source (see `sourceAccountId`), same reasoning as `Components.Pages.PostsPage.feedSourceAccountId`.
-}
type alias SourceFeed =
    { status : SourceUsers
    , accountId : Maybe String
    }


{-| One entry `usersByServer` can hold in a `Loaded` list -- a real Rellm `User` (from a `GetUsers`
RPC), or a Mastodon `Account`/Bluesky `ActorProfile` translated client-side, mirroring
`Components.Pages.PostsPage.FeedSource`'s three-way split one level down (a listed _person_ instead
of a _post_). See `userSourceKey`/`sourceAccountId`/`fetchSourceEffect` for where the three cases
actually diverge.
-}
type ListedUser
    = RellmListedUser User
    | MastodonListedUser { instanceHost : String, account : Mastodon.Account }
    | BlueskyListedUser Bluesky.ActorProfile


{-| One source `usersByServer` can hold a listing for -- mirrors
`Components.Pages.PostsPage.FeedSource` exactly, just for `GetUsers`/account listings instead of
posts. `MastodonSearchSource`/`BlueskySearchSource` only ever appear when `target`/`federatedTarget`
are both `Nothing` and `model.searchText` is non-blank -- see `candidateSources`.
-}
type UserSource
    = RellmSource RellmServer
    | MastodonListingSource { instanceHost : String, accountId : String } FederatedListingType
    | BlueskyListingSource { handle : String } FederatedListingType
    | MastodonSearchSource { instanceHost : String }
    | BlueskySearchSource


{-| One `UserSource`'s fetch settling, normalized across the real-server (`Grpc.Error`/
`GetUsersResponse`) and Mastodon/Bluesky (`Http.Error`/plain `List ListedUser`) shapes -- mirrors
`Components.Pages.PostsPage.FeedResult` exactly.
-}
type UsersResult
    = UsersLoaded (List ListedUser) (Maybe AccountsPanel.Msg)
    | UsersFailed (Maybe AccountsPanel.Msg)


fromRellmResult : Result Grpc.Error ( Maybe AccountsPanel.Msg, GetUsersResponse ) -> UsersResult
fromRellmResult result =
    case result of
        Ok ( maybeAccountsPanelMsg, response ) ->
            UsersLoaded (List.map RellmListedUser response.users) maybeAccountsPanelMsg

        Err _ ->
            UsersFailed Nothing


fromFederatedResult : Result Http.Error (List ListedUser) -> UsersResult
fromFederatedResult result =
    case result of
        Ok listedUsers ->
            UsersLoaded listedUsers Nothing

        Err _ ->
            UsersFailed Nothing


{-| `BlueskyListingSource`/`BlueskySearchSource`'s own `UsersResult` conversion -- mirrors
`Components.Pages.PostsPage.fromBlueskyResult` exactly (see its own doc): persists a silently-rotated
token pair on success, flags `needsReauth` once every refresh-and-retry is exhausted on failure.
-}
fromBlueskyResult : BlueskyAccount -> Result Http.Error ( BlueskyAccount, List ListedUser ) -> UsersResult
fromBlueskyResult account result =
    case result of
        Ok ( refreshedAccount, listedUsers ) ->
            UsersLoaded listedUsers
                (if refreshedAccount.accessToken == account.accessToken then
                    Nothing

                 else
                    Just (AccountsPanel.BlueskyAccountRefreshed refreshedAccount)
                )

        Err err ->
            UsersFailed
                (if BlueskyAccounts.isReauthError err then
                    Just (AccountsPanel.MarkBlueskyAccountNeedsReauth account.handle)

                 else
                    Nothing
                )


{-| `postsByServer`'s key for a given `UserSource` -- mirrors
`Components.Pages.PostsPage.feedSourceKey` exactly, including reusing the exact same
`"mastodon:"`/`"bluesky:"` shapes so a listed federated user's own profile link (built off this same
key, see `userCardView`) round-trips through `Components.Users.parseFederatedUserId` correctly.
-}
userSourceKey : UserSource -> String
userSourceKey source =
    case source of
        RellmSource server ->
            server.frontendHost

        MastodonListingSource ref _ ->
            "mastodon:" ++ ref.instanceHost

        BlueskyListingSource ref _ ->
            "bluesky:" ++ ref.handle

        MastodonSearchSource ref ->
            "mastodon:" ++ ref.instanceHost

        BlueskySearchSource ->
            "bluesky:search"


{-| The acting credential a `UserSource`'s listing is fetched with, if any -- mirrors
`Components.Pages.PostsPage.feedSourceAccountId` exactly: a real server's enabled account, or always
`Nothing` for Mastodon/Bluesky (neither is ever refetched on a credential change the way a Rellm
account is), which is exactly what makes `fetchNewSources` treat an already-fetched federated source
as unchanged forever except when it's newly added, or (for a search source) when `model.searchText`
itself changes -- see `applySearchChange`.
-}
sourceAccountId : Shared.Model -> UserSource -> Maybe String
sourceAccountId shared source =
    case source of
        RellmSource server ->
            RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts server.frontendHost
                |> Maybe.map RellmAccounts.rellmAccountId

        MastodonListingSource _ _ ->
            Nothing

        BlueskyListingSource _ _ ->
            Nothing

        MastodonSearchSource _ ->
            Nothing

        BlueskySearchSource ->
            Nothing


{-| Identifies one listed row in `model.followStatusAndButtons`/`model.userAnimations` -- a Rellm
`User.id` alone isn't unique across every listed server (see `Components.Users.Resolver`'s own
by-id/by-username `Lookup`, federated ids aren't globally unique either), so `host` disambiguates,
mirroring `Components.Pages.UserProfilePage.federatedKey`. `MastodonListedUser`/`BlueskyListedUser`
never actually need `host` to disambiguate (an `Account.id`/`handle` is already unique to its own
instance/network), but take it anyway for a uniform signature.
-}
listedUserKey : String -> ListedUser -> String
listedUserKey host listedUser =
    case listedUser of
        RellmListedUser user ->
            user.id ++ "@" ++ host

        MastodonListedUser { instanceHost, account } ->
            "mastodon:" ++ instanceHost ++ ":" ++ account.id

        BlueskyListedUser profile ->
            "bluesky:" ++ profile.handle


{-| The name a listed row sorts/displays by -- mirrors `usersListView`'s own prior
`anim.user.username` sort key, generalized across all three `ListedUser` cases.
-}
listedUserSortName : ListedUser -> String
listedUserSortName listedUser =
    case listedUser of
        RellmListedUser user ->
            user.username

        MastodonListedUser { account } ->
            account.username

        BlueskyListedUser profile ->
            profile.handle


{-| A user card's fade in/out state, keyed in `userAnimations` by
`listedUserKey` (the same host+id key `followStatusAndButtons`
already uses -- both dicts identify a card the same way, so there's no need
for a second key convention) so it survives independently of `usersByServer`
-- a server being disabled (or re-fetched under a different account, or a
search narrowing the results) drops/replaces its users in `usersByServer`
immediately, but a `removing` `flip` entry here keeps rendering its
last-known `listedUser`/`host` until its fade-out finishes, instead of the card
just vanishing. Mirrors `Components.Pages.PostsPage.PostAnimation` exactly --
see `UI.Flip` for what `flip` itself drives.
-}
type alias UserAnimation =
    { host : String
    , listedUser : ListedUser
    , flip : UI.Flip.State Msg
    }


{-| `navKey`/`path`, from the calling page's own `Request`, are what let
`searchRowView`'s search box persist `search_text` as a URL query param (see
`pushSearchUrl`) without this module needing to know which page-specific
`Gen.Params.*` type that `Request` is actually parameterized over -- mirrors
`Components.Pages.PostsPage.init` exactly, just without a context param (there
being no `Users` equivalent of `PostContext` to choose between). `query`,
that same `Request`'s already-parsed `.query`, seeds `searchText` back out of
the URL on load, so a shared/reloaded link reproduces the same search.

`federatedTarget` seeds `Model.federatedTarget` directly -- `Nothing` for every caller except
`Pages.UsernameOrCustomTab_.Followers`/`Following`'s federated branch. Mirrors
`Components.Pages.PostsPage.init`'s own trailing `profileFeedSource` param.

-}
init : Shared.Model -> Maybe ( String, User, UserListingType ) -> Maybe FederatedTarget -> Browser.Navigation.Key -> String -> Dict String String -> ( Model, Effect Msg )
init shared target federatedTarget navKey path query =
    let
        ( fetchedModel, fetchEffect ) =
            fetchNewSources shared
                { usersByServer = Dict.empty
                , userAnimations = Dict.empty
                , target = target
                , federatedTarget = federatedTarget
                , followStatusAndButtons = Dict.empty
                , navKey = navKey
                , path = path
                , searchText = Dict.get "search_text" query |> Maybe.withDefault ""
                , searchGeneration = 0
                }
    in
    -- Closes any open panel (Accounts, Starred, etc.) unconditionally on
    -- load -- mirrors `Components.Pages.PostsPage.init`'s own unconditional
    -- close, see its doc comment for why `setBreadcrumbsRoot` alone isn't
    -- enough here.
    ( fetchedModel, Effect.batch [ fetchEffect, Effect.fromShared Shared.CloseAllPanels, setBreadcrumbsRoot shared fetchedModel ] )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Time.every 30000 (\_ -> Poll)
        , UI.Flip.subscription Animate (List.map .flip (Dict.values model.userAnimations))
        ]



-- UPDATE


{-| Lets `Main` forward a `Shared.Msg` that didn't originate from this page
(see `Main.notifyPageOfSharedMsg`) into `update`'s `SharedMsg` branch, without
exposing the `SharedMsg` constructor itself -- mirrors
`Components.Pages.PostsPage.fromShared`.
-}
fromShared : Shared.Msg -> Msg
fromShared =
    SharedMsg


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    let
        ( newModel, effect ) =
            updateInner shared msg model
    in
    ( newModel, Effect.batch [ effect, setBreadcrumbsRoot shared newModel ] )


updateInner : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
updateInner shared msg model =
    case msg of
        GotUsers sourceKey (UsersLoaded listedUsers maybeAccountsPanelMsg) ->
            let
                accountEffect : Effect Msg
                accountEffect =
                    maybeAccountsPanelMsg
                        |> Maybe.map (Shared.AccountsPanelMsg >> Effect.fromShared)
                        |> Maybe.withDefault Effect.none
            in
            ( { model
                | usersByServer =
                    Dict.update sourceKey
                        (Maybe.map (\feed -> { feed | status = Loaded listedUsers }))
                        model.usersByServer
              }
                |> syncAnimations
            , accountEffect
            )

        GotUsers sourceKey (UsersFailed maybeAccountsPanelMsg) ->
            ( { model
                | usersByServer =
                    Dict.update sourceKey (Maybe.map (\feed -> { feed | status = Failed })) model.usersByServer
              }
                |> syncAnimations
            , maybeAccountsPanelMsg
                |> Maybe.map (Shared.AccountsPanelMsg >> Effect.fromShared)
                |> Maybe.withDefault Effect.none
            )

        Poll ->
            fetchNewSources shared model

        Animate animMsg ->
            let
                step : String -> UserAnimation -> ( Dict String UserAnimation, List (Cmd Msg) ) -> ( Dict String UserAnimation, List (Cmd Msg) )
                step key anim ( animations, accCmds ) =
                    let
                        ( newFlip, cmd ) =
                            UI.Flip.animate animMsg anim.flip
                    in
                    ( Dict.insert key { anim | flip = newFlip } animations, cmd :: accCmds )

                ( newAnimations, cmds ) =
                    Dict.foldl step ( Dict.empty, [] ) model.userAnimations
            in
            ( { model | userAnimations = newAnimations }, Effect.batch (List.map Effect.fromCmd cmds) )

        RemoveUser key ->
            ( { model | userAnimations = Dict.remove key model.userAnimations }, Effect.none )

        SharedMsg subMsg ->
            let
                ( fetchedModel, fetchEffect ) =
                    case subMsg of
                        Shared.AccountsPanelMsg _ ->
                            fetchNewSources shared model

                        _ ->
                            ( model, Effect.none )
            in
            ( fetchedModel, Effect.batch [ Effect.fromShared subMsg, fetchEffect ] )

        FollowStatusAndButtonMsg key subMsg ->
            case findUserForKey shared model key of
                Just ( server, account, user ) ->
                    let
                        ( newFollowStatusAndButton, followEffect ) =
                            FollowStatusAndButton.update shared
                                server
                                account
                                user
                                subMsg
                                (Dict.get key model.followStatusAndButtons |> Maybe.withDefault FollowStatusAndButton.init)

                        newModel : Model
                        newModel =
                            { model | followStatusAndButtons = Dict.insert key newFollowStatusAndButton model.followStatusAndButtons }

                        mappedFollowEffect : Effect Msg
                        mappedFollowEffect =
                            Effect.map (FollowStatusAndButtonMsg key) followEffect
                    in
                    case subMsg of
                        FollowStatusAndButton.GotFollowResult (Ok _) ->
                            ( newModel, Effect.batch [ mappedFollowEffect, fetchSourceEffect shared newModel (RellmSource server) ] )

                        FollowStatusAndButton.GotUnfollowResult (Ok _) ->
                            ( newModel, Effect.batch [ mappedFollowEffect, fetchSourceEffect shared newModel (RellmSource server) ] )

                        FollowStatusAndButton.GotModerationResult (Ok _) ->
                            ( newModel, Effect.batch [ mappedFollowEffect, fetchSourceEffect shared newModel (RellmSource server) ] )

                        _ ->
                            ( newModel, mappedFollowEffect )

                Nothing ->
                    ( model, Effect.none )

        SearchTextChanged text ->
            let
                generation : Int
                generation =
                    model.searchGeneration + 1
            in
            ( { model | searchText = text, searchGeneration = generation }
            , Process.sleep 311
                |> Task.perform (\_ -> SearchDebounceElapsed generation)
                |> Effect.fromCmd
            )

        SearchDebounceElapsed generation ->
            if generation == model.searchGeneration then
                applySearchChange shared model

            else
                -- A later edit (or ClearSearchClicked/ContextChanged) already
                -- bumped searchGeneration past this timer's -- it's stale, ignore it.
                ( model, Effect.none )

        ClearSearchClicked ->
            applySearchChange shared { model | searchText = "", searchGeneration = model.searchGeneration + 1 }


{-| Every `UserSource` this listing should ever fetch from -- a single-element list for either kind
of target (`federatedTarget`'s own account, or `target`'s own host), or, for the unfiltered `Pages.People`
case (`target`/`federatedTarget` both `Nothing`), every enabled Rellm server unconditionally plus --
only once `model.searchText` is non-blank -- every browsed/connected Mastodon instance's own search
and (if any Bluesky account is connected) one Bluesky actor search. Mirrors
`Components.Pages.PostsPage.relevantFeedSources` exactly, one level up (listed _people_ instead of
_posts_): neither Mastodon nor Bluesky offers an unscoped "everyone" listing the way Rellm's own
`EVERYONE` does, so search is the only way either ever contributes to this unfiltered case at all.
-}
candidateSources : Shared.Model -> Model -> List UserSource
candidateSources shared model =
    case model.federatedTarget of
        Just (MastodonAccountTarget ref listingType) ->
            [ MastodonListingSource { instanceHost = ref.instanceHost, accountId = ref.accountId } listingType ]

        Just (BlueskyAccountTarget ref listingType) ->
            [ BlueskyListingSource ref listingType ]

        Nothing ->
            case model.target of
                Just ( host, _, _ ) ->
                    RellmServers.rellmServerForHost shared.accounts.servers host
                        |> Maybe.map (RellmSource >> List.singleton)
                        |> Maybe.withDefault []

                Nothing ->
                    List.map RellmSource (AccountsPanel.enabledServers shared.accounts)
                        ++ (if String.isEmpty (String.trim model.searchText) then
                                []

                            else
                                List.map (\instanceHost -> MastodonSearchSource { instanceHost = instanceHost }) (mastodonHostsToSearch shared)
                                    ++ (if List.isEmpty shared.accounts.blueskyAccounts then
                                            []

                                        else
                                            [ BlueskySearchSource ]
                                       )
                           )


{-| Every Mastodon instance worth searching once `Pages.People`'s own search box has a query --
mirrors `Components.Pages.PostsPage.mastodonHostsToFetch` exactly (both OAuth-connected accounts'
own instances and anonymously-browsed-and-enabled ones, deduplicated).
-}
mastodonHostsToSearch : Shared.Model -> List String
mastodonHostsToSearch shared =
    (List.map .instanceHost shared.accounts.mastodonAccounts
        ++ (shared.accounts.browsedMastodonInstances |> List.filter .enabled |> List.map .host)
    )
        |> Set.fromList
        |> Set.toList


{-| The listing fetch (as an `Effect`, ready to batch/return directly) for one `source` -- shared by
`fetchNewSources` (kicked off for every source that needs a fresh fetch) and `update`'s own
`FollowStatusAndButtonMsg` branch (kicked off unconditionally for just the acted-on Rellm server,
once a `FollowStatusAndButton` action against one of its listed users succeeds).
-}
fetchSourceEffect : Shared.Model -> Model -> UserSource -> Effect Msg
fetchSourceEffect shared model source =
    let
        key : String
        key =
            userSourceKey source
    in
    case source of
        RellmSource server ->
            Users.fetchUserListing
                shared.accounts
                ( RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts server.frontendHost |> Maybe.map .userId
                , server.frontendHost
                )
                (model.target |> Maybe.map (\( _, user, _ ) -> user.id))
                (model.target |> Maybe.map (\( _, _, listingType ) -> listingType) |> Maybe.withDefault EVERYONE)
                model.searchText
                |> Task.attempt (fromRellmResult >> GotUsers key)
                |> Effect.fromCmd

        MastodonListingSource ref listingType ->
            (case listingType of
                FederatedFollowers ->
                    Mastodon.fetchFollowers ref.instanceHost ref.accountId

                FederatedFollowing ->
                    Mastodon.fetchFollowing ref.instanceHost ref.accountId
            )
                |> Task.map (List.map (\account -> MastodonListedUser { instanceHost = ref.instanceHost, account = account }))
                |> Task.attempt (fromFederatedResult >> GotUsers key)
                |> Effect.fromCmd

        MastodonSearchSource ref ->
            Mastodon.searchAccounts ref.instanceHost model.searchText
                |> Task.map (List.map (\account -> MastodonListedUser { instanceHost = ref.instanceHost, account = account }))
                |> Task.attempt (fromFederatedResult >> GotUsers key)
                |> Effect.fromCmd

        BlueskyListingSource ref listingType ->
            case shared.accounts.blueskyAccounts of
                viewerAccount :: _ ->
                    BlueskyAccounts.performWithBlueskyAccount viewerAccount
                        (\accessToken ->
                            case listingType of
                                FederatedFollowers ->
                                    Bluesky.fetchFollowers accessToken ref.handle

                                FederatedFollowing ->
                                    Bluesky.fetchFollows accessToken ref.handle
                        )
                        |> Task.map (Tuple.mapSecond (List.map BlueskyListedUser))
                        |> Task.attempt (fromBlueskyResult viewerAccount >> GotUsers key)
                        |> Effect.fromCmd

                [] ->
                    -- No connected Bluesky account to authenticate this request with at all (AT
                    -- Proto has no anonymous access -- see `Shared.Federation.Bluesky`'s own doc).
                    -- Resolves immediately to `UsersFailed` (rather than `Effect.none`, which would
                    -- leave this source stuck at `Loading` forever) -- mirrors
                    -- `Components.Pages.BlueskyUserProfilePage.init`'s identical fallback.
                    Task.fail (Http.BadStatus 401)
                        |> Task.attempt (fromFederatedResult >> GotUsers key)
                        |> Effect.fromCmd

        BlueskySearchSource ->
            case shared.accounts.blueskyAccounts of
                viewerAccount :: _ ->
                    BlueskyAccounts.performWithBlueskyAccount viewerAccount (\accessToken -> Bluesky.searchActors accessToken model.searchText)
                        |> Task.map (Tuple.mapSecond (List.map BlueskyListedUser))
                        |> Task.attempt (fromBlueskyResult viewerAccount >> GotUsers key)
                        |> Effect.fromCmd

                [] ->
                    Task.fail (Http.BadStatus 401)
                        |> Task.attempt (fromFederatedResult >> GotUsers key)
                        |> Effect.fromCmd


{-| Fetches `sourcesToFetch` using the current `model.searchText`, and drops
any already-fetched source that's no longer a `candidateSources` member --
shared by `fetchNewSources` (which only passes the sources that actually need
it) and `applySearchChange` (which always passes every `candidateSources`
member, since a changed search must re-fetch everything regardless of whether
that source's acting account also happens to have changed) -- mirrors
`Components.Pages.PostsPage.refetchFeeds`, including its same-account
`status`-preserving departure from a plain `Loading` reset -- see that
module's own doc comment for why (a source already `Loaded` under the same
acting account keeps its last-known users on screen while re-fetching, rather
than flickering every card out and back in via `syncAnimations`).
-}
refetchSources : Shared.Model -> Model -> List UserSource -> ( Model, Effect Msg )
refetchSources shared model sourcesToFetch =
    let
        sources : List UserSource
        sources =
            candidateSources shared model

        keptKeys : List String
        keptKeys =
            List.map userSourceKey sources

        fetchEffect : UserSource -> Effect Msg
        fetchEffect source =
            fetchSourceEffect shared model source

        prunedUsersByServer : Dict String SourceFeed
        prunedUsersByServer =
            Dict.filter (\key _ -> List.member key keptKeys) model.usersByServer

        markSource : UserSource -> Dict String SourceFeed -> Dict String SourceFeed
        markSource source dict =
            let
                key : String
                key =
                    userSourceKey source

                accountId : Maybe String
                accountId =
                    sourceAccountId shared source

                statusIfSameAccount : Maybe SourceUsers
                statusIfSameAccount =
                    Dict.get key dict
                        |> Maybe.andThen
                            (\feed ->
                                if feed.accountId == accountId then
                                    Just feed.status

                                else
                                    Nothing
                            )
            in
            Dict.insert key
                { status = Maybe.withDefault Loading statusIfSameAccount, accountId = accountId }
                dict
    in
    ( { model
        | usersByServer =
            List.foldl markSource prunedUsersByServer sourcesToFetch
      }
    , Effect.batch (List.map fetchEffect sourcesToFetch)
    )
        |> Tuple.mapFirst syncAnimations


{-| See `Components.Pages.PostsPage.fetchNewFeeds`'s doc comment -- same
drop-stale-sources/re-fetch-on-account-change/poll-fallback approach, just
against `GetUsers`/Mastodon/Bluesky listings instead of `GetPosts`, and scoped to `candidateSources`
rather than unconditionally every enabled server.
-}
fetchNewSources : Shared.Model -> Model -> ( Model, Effect Msg )
fetchNewSources shared model =
    let
        sources : List UserSource
        sources =
            candidateSources shared model

        sourcesToFetch : List UserSource
        sourcesToFetch =
            sources
                |> List.filter
                    (\source ->
                        case Dict.get (userSourceKey source) model.usersByServer of
                            Nothing ->
                                True

                            Just feed ->
                                feed.accountId /= sourceAccountId shared source
                    )
    in
    refetchSources shared model sourcesToFetch


{-| Re-fetches every `candidateSources` member (unconditionally -- unlike
`fetchNewSources`, a changed search has to override every already-Loaded
feed, not just sources whose acting account changed) and persists the new
`search_text` to the URL -- the single path `SearchDebounceElapsed` and
`ClearSearchClicked` both funnel through. Mirrors
`Components.Pages.PostsPage.applySearchChange` exactly.
-}
applySearchChange : Shared.Model -> Model -> ( Model, Effect Msg )
applySearchChange shared model =
    let
        ( refetchedModel, refetchEffect ) =
            refetchSources shared model (candidateSources shared model)
    in
    ( refetchedModel, Effect.batch [ refetchEffect, pushSearchUrl refetchedModel ] )


{-| Keeps `Shared.Breadcrumbs` pointed at this listing's own root:
`FromServerHost mainFrontendHost` for `Pages.People`'s unfiltered listing
(`model.target == Nothing`), or `FromUser` the already-resolved `target` user
once there is one (`Pages.UsernameOrCustomTab_.{Following,Followers,Friends}`/
`Pages.User.UserId_.{Following,Followers,Friends}`) -- mirrors
`Components.Pages.PostsPage.setBreadcrumbsRoot` exactly, just keyed off
`target`'s `User` instead of `author`'s, reissued after every `update`, a
no-op once already in sync via the same equality check.

A no-op entirely once `model.federatedTarget` is set -- there's no federated-account counterpart to
`Breadcrumbs.BreadcrumbRoot` to build one from (every existing variant expects a real `Post`/`User`/
Rellm host), so this simply leaves whatever root the page navigated here from in place, same
"nothing to update" choice `Components.Pages.MastodonPostPage`/`BlueskyPostPage`/
`MastodonUserProfilePage`/`BlueskyUserProfilePage` already make by never touching breadcrumbs at all.

-}
setBreadcrumbsRoot : Shared.Model -> Model -> Effect Msg
setBreadcrumbsRoot shared model =
    if model.federatedTarget /= Nothing then
        Effect.none

    else
        let
            ( root, host ) =
                case model.target of
                    Just ( targetHost, user, _ ) ->
                        ( Breadcrumbs.FromUser user, targetHost )

                    Nothing ->
                        ( Breadcrumbs.FromServerHost shared.accounts.mainFrontendHost, shared.accounts.mainFrontendHost )
        in
        if shared.breadcrumbs.root == Just root then
            Effect.none

        else
            Effect.fromShared (Shared.BreadcrumbsMsg (Breadcrumbs.SetRoot root host []))


{-| Persists `model.searchText` to the URL as a `search_text` query param, via
`replaceUrl` (not `pushUrl` -- editing the search box shouldn't spam browser
history with one entry per debounce fire). Omitted entirely when blank, so
the common case keeps a clean URL. Mirrors
`Components.Pages.PostsPage.pushSearchUrl`, just without a `context` param.
-}
pushSearchUrl : Model -> Effect Msg
pushSearchUrl model =
    let
        searchTextParam : List Url.Builder.QueryParameter
        searchTextParam =
            if String.isEmpty (String.trim model.searchText) then
                []

            else
                [ Url.Builder.string "search_text" model.searchText ]
    in
    Browser.Navigation.replaceUrl model.navKey (model.path ++ Url.Builder.toQuery searchTextParam)
        |> Effect.fromCmd



-- ANIMATION


{-| Reconciles `userAnimations` with the users currently `Loaded` in
`usersByServer`: starts a fade-in for newly-seen users, a fade-out for users
that dropped out (rather than deleting them outright), and un-interrupts a
still-fading-out card that reappeared. Safe/cheap to call after every
`usersByServer` change, so `update`/`refetchSources` just call it
unconditionally wherever that dict might have changed. `RemoveUser` is what
actually drops a gone user's animation entry once its fade-out finishes. See
`UI.Flip.syncAnimations` for the shared reconciliation logic this hands its
own `UserAnimation` shape to (mirrored by `Components.Pages.PostsPage.syncAnimations`).
-}
syncAnimations : Model -> Model
syncAnimations model =
    let
        currentUsers : Dict String ( String, ListedUser )
        currentUsers =
            model.usersByServer
                |> Dict.toList
                |> List.concatMap
                    (\( host, feed ) ->
                        case feed.status of
                            Loaded listedUsers ->
                                List.map (\listedUser -> ( listedUserKey host listedUser, ( host, listedUser ) )) listedUsers

                            _ ->
                                []
                    )
                |> Dict.fromList
    in
    { model
        | userAnimations =
            UI.Flip.syncAnimations
                RemoveUser
                (\( host, listedUser ) -> { host = host, listedUser = listedUser, flip = UI.Flip.enter })
                (\( host, listedUser ) anim -> { anim | host = host, listedUser = listedUser })
                currentUsers
                model.userAnimations
    }



-- VIEW


view : Shared.Model -> Model -> Html Msg
view shared model =
    div []
        [ targetHeadingView shared model
        , if model.federatedTarget == Nothing then
            searchRowView model

          else
            text ""
        , usersListView shared model
        ]


{-| Search box (debounced, see `SearchTextChanged`/`SearchDebounceElapsed`) --
mirrors `Components.Pages.PostsPage.searchRowView`, just without a context
chooser (there's no `Users` equivalent of `PostContext` to pick between, so
no `.filter-controls-trailing` here), reusing the generic
`.filter-search-field`/`.filter-search-input`/`.field-clear-button` CSS
classes (`ui/filter_bar.css`) -- already shared across Posts/Events/Users
pages (see `targetHeadingView`'s own reuse of `.posts-page-heading` below),
so no new CSS is needed here. Hidden entirely for a `federatedTarget` (see
`view`) -- neither Mastodon's nor Bluesky's followers/following endpoints
accept a search query at all, so showing a box that can't actually filter
anything would be misleading.
-}
searchRowView : Model -> Html Msg
searchRowView model =
    div [ class "filter-controls-row" ]
        [ div [ class "filter-search-field" ]
            [ input
                [ type_ "text"
                , class "filter-search-input"
                , placeholder "Search people..."
                , value model.searchText
                , onInput SearchTextChanged
                , onEscape ClearSearchClicked
                ]
                []
            , if String.isEmpty model.searchText then
                text ""

              else
                button
                    [ type_ "button"
                    , class "field-clear-button"
                    , onClick ClearSearchClicked
                    , title "Clear search"
                    ]
                    [ text "╳" ]
            ]
        ]


{-| Fires `msg` (and suppresses the key's default effect) when Escape is
pressed in a text input -- mirrors `Components.Pages.PostsPage.onEscape`.
-}
onEscape : msg -> Html.Attribute msg
onEscape msg =
    preventDefaultOn "keydown"
        (Decode.field "key" Decode.string
            |> Decode.andThen
                (\key ->
                    if key == "Escape" then
                        Decode.succeed ( msg, True )

                    else
                        Decode.fail "Not the Escape key"
                )
        )


{-| "Following"/"Followers"/"Friends" alone once there's a `target`/`federatedTarget` to filter
by (even before that account has actually rendered), upgraded to e.g. "Following | <name>" via
`Components.Users.ProfileHeading.nameHeader` (Rellm) or a plain avatar/handle (Mastodon/Bluesky, see
`federatedTargetHeadingView`) -- absent entirely for `Pages.People`'s unfiltered listing (both
`Nothing`), which supplies its own "People" heading instead. Mirrors
`Components.Pages.PostsPage.authorHeadingView` exactly.
-}
targetHeadingView : Shared.Model -> Model -> Html Msg
targetHeadingView shared model =
    case model.federatedTarget of
        Just target ->
            federatedTargetHeadingView shared target

        Nothing ->
            case model.target of
                Nothing ->
                    text ""

                Just ( host, targetUser, listingType ) ->
                    let
                        profileUrl : String
                        profileUrl =
                            Users.usernameHref "" shared.accounts.mainFrontendHost host targetUser.username
                    in
                    div [ class "posts-page-heading" ]
                        [ h2 [] [ text (listingTypeHeading listingType) ]
                        , a [ href profileUrl, class <| hostnameToCSSClass host ]
                            [ case RellmServers.rellmServerForHost shared.accounts.servers host of
                                Just server ->
                                    ProfileHeading.nameHeader server (RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts host) targetUser

                                Nothing ->
                                    ProfileHeading.usernameHeading targetUser
                            ]
                        ]


{-| `targetHeadingView`'s Mastodon/Bluesky counterpart -- a plain avatar-less (see
`Components.Authors.avatar`'s own `Nothing`-url fallback; there's no fetched profile on hand here to
get one from, only the identifiers `FederatedTarget` itself carries -- a deliberately minor
simplification versus the full `MastodonUserProfilePage`/`BlueskyUserProfilePage` header, since this
is just a "Following | @user" bar, not the profile itself) handle/username link back to that
account's own profile page.
-}
federatedTargetHeadingView : Shared.Model -> FederatedTarget -> Html Msg
federatedTargetHeadingView shared target =
    let
        info : { heading : String, userServerHost : String, username : String, displayHandle : String }
        info =
            case target of
                MastodonAccountTarget ref listingType ->
                    { heading = federatedListingTypeHeading listingType
                    , userServerHost = "mastodon:" ++ ref.instanceHost
                    , username = ref.username
                    , displayHandle = ref.username ++ "@" ++ ref.instanceHost
                    }

                BlueskyAccountTarget ref listingType ->
                    { heading = federatedListingTypeHeading listingType
                    , userServerHost = "bluesky:" ++ ref.handle
                    , username = ref.handle
                    , displayHandle = ref.handle
                    }

        profileUrl : String
        profileUrl =
            Users.usernameHref "" shared.accounts.mainFrontendHost info.userServerHost info.username
    in
    div [ class "posts-page-heading" ]
        [ h2 [] [ text info.heading ]
        , a [ href profileUrl, class (hostnameToCSSClass info.userServerHost) ]
            [ Authors.avatar info.displayHandle Nothing
            , text ("@" ++ info.displayHandle)
            ]
        ]


federatedListingTypeHeading : FederatedListingType -> String
federatedListingTypeHeading listingType =
    case listingType of
        FederatedFollowing ->
            "Following"

        FederatedFollowers ->
            "Followers"


listingTypeHeading : UserListingType -> String
listingTypeHeading listingType =
    case listingType of
        FOLLOWING ->
            "Following"

        FOLLOWERS ->
            "Followers"

        FRIENDS ->
            "Friends"

        _ ->
            "People"


usersListView : Shared.Model -> Model -> Html Msg
usersListView shared model =
    if Dict.isEmpty model.usersByServer then
        p [ class "posts-empty" ] [ text "Connect to a server to see people." ]

    else
        let
            sortedAnimations : List ( String, UserAnimation )
            sortedAnimations =
                model.userAnimations
                    |> Dict.toList
                    |> List.sortBy (\( _, anim ) -> String.toLower (listedUserSortName anim.listedUser))
        in
        if List.isEmpty sortedAnimations then
            p [ class "posts-empty" ] [ text "No people yet." ]

        else
            Html.Keyed.node "div"
                [ class "users-list flip-animated-column" ]
                (List.map (userAnimationView shared model) sortedAnimations)


{-| Wraps `userCardView` in a fading/scaling/collapsing animated `<div>` (see
`syncAnimations`) -- mirrors `Components.Pages.PostsPage.postAnimationView`
exactly, including the inner clip `div`'s `pointer-events: none` while
`removing`, so a fading-out card can't be clicked/followed while it's on its
way out.
-}
userAnimationView : Shared.Model -> Model -> ( String, UserAnimation ) -> ( String, Html Msg )
userAnimationView shared model ( key, anim ) =
    let
        pointerEventsAttr : List (Html.Attribute Msg)
        pointerEventsAttr =
            if anim.flip.removing then
                [ style "pointer-events" "none" ]

            else
                []
    in
    ( key
    , div (UI.Flip.itemAttributes UI.Flip.Vertical anim.flip False)
        [ div pointerEventsAttr [ userCardView shared model ( anim.host, anim.listedUser ) ] ]
    )


userCardView : Shared.Model -> Model -> ( String, ListedUser ) -> Html Msg
userCardView shared model ( host, listedUser ) =
    case listedUser of
        RellmListedUser user ->
            case RellmServers.rellmServerForHost shared.accounts.servers host of
                Just server ->
                    let
                        key : String
                        key =
                            listedUserKey host listedUser

                        followStatusAndButtonModel : FollowStatusAndButton.Model
                        followStatusAndButtonModel =
                            Dict.get key model.followStatusAndButtons |> Maybe.withDefault FollowStatusAndButton.init

                        maybeAccount : Maybe RellmAccount
                        maybeAccount =
                            RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts host
                    in
                    Users.userCard shared.basePath
                        shared.accounts.mainFrontendHost
                        server
                        maybeAccount
                        (Html.map (FollowStatusAndButtonMsg key) (FollowStatusAndButton.view followStatusAndButtonModel maybeAccount user))
                        user

                Nothing ->
                    text ""

        MastodonListedUser { instanceHost, account } ->
            mastodonUserCard shared instanceHost account

        BlueskyListedUser profile ->
            blueskyUserCard shared profile


{-| A listed Mastodon account's row -- no follow/moderation affordances at all (unlike a Rellm
`userCard`'s own `FollowStatusAndButton`) since this is someone else's federated account, not one
Rellm itself has any notion of following/moderating -- mirrors the row `Components.Pages.MastodonUsersPage`
used to render before its functionality moved here. Reuses `Users.userCard`'s own `.user-card`/
`.user-card-details`/`.user-card-meta` CSS so a mixed Rellm+Mastodon+Bluesky `Pages.People` search
result list reads as one consistent list, not two visually different ones stitched together.
-}
mastodonUserCard : Shared.Model -> String -> Mastodon.Account -> Html Msg
mastodonUserCard shared instanceHost account =
    let
        handle : String
        handle =
            account.username ++ "@" ++ instanceHost
    in
    a
        [ href (Users.usernameHref shared.basePath shared.accounts.mainFrontendHost ("mastodon:" ++ instanceHost) account.username)
        , class "user-card"
        ]
        [ Users.userCardAvatar handle account.avatarUrl
        , div [ class "user-card-details" ]
            [ div [] [ text ("⇄ " ++ (account.displayName |> Maybe.withDefault ("@" ++ handle))) ]
            , div [ class "user-card-meta" ] [ text ("@" ++ handle) ]
            ]
        ]


{-| `mastodonUserCard`'s Bluesky counterpart.
-}
blueskyUserCard : Shared.Model -> Bluesky.ActorProfile -> Html Msg
blueskyUserCard shared profile =
    a
        [ href (Users.usernameHref shared.basePath shared.accounts.mainFrontendHost ("bluesky:" ++ profile.handle) profile.handle)
        , class "user-card"
        ]
        [ Users.userCardAvatar profile.handle profile.avatarUrl
        , div [ class "user-card-details" ]
            [ div [] [ text ("⇄ " ++ (profile.displayName |> Maybe.withDefault ("@" ++ profile.handle))) ]
            , div [ class "user-card-meta" ] [ text ("@" ++ profile.handle) ]
            ]
        ]


{-| The `RellmServer`/signed-in `RellmAccount`/`User` a
`FollowStatusAndButtonMsg key` refers to -- looked up fresh out of
`model.usersByServer` each time (rather than carried in the `Msg` itself),
since the `User` a `Follow` action needs is whatever's currently loaded, not
a stale snapshot from whenever the button was rendered. Only ever matches a `RellmListedUser` row --
`FollowStatusAndButtonMsg` never fires for a `MastodonListedUser`/`BlueskyListedUser` row at all,
since neither renders a follow button (see `userCardView`).
-}
findUserForKey : Shared.Model -> Model -> String -> Maybe ( RellmServer, RellmAccount, User )
findUserForKey shared model key =
    model.usersByServer
        |> Dict.toList
        |> List.concatMap
            (\( host, feed ) ->
                case feed.status of
                    Loaded listedUsers ->
                        listedUsers
                            |> List.filterMap
                                (\listedUser ->
                                    case listedUser of
                                        RellmListedUser user ->
                                            Just ( host, user )

                                        _ ->
                                            Nothing
                                )
                            |> List.filter (\( userHost, user ) -> listedUserKey userHost (RellmListedUser user) == key)

                    _ ->
                        []
            )
        |> List.head
        |> Maybe.andThen
            (\( host, user ) ->
                Maybe.map2 (\server account -> ( server, account, user ))
                    (RellmServers.rellmServerForHost shared.accounts.servers host)
                    (RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts host)
            )
