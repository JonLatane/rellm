module Shared.Countabilibar exposing
    ( AuthorCounts
    , Hidden
    , Kind(..)
    , Model
    , Msg(..)
    , ServerCounts
    , affectsPages
    , bar
    , closePanel
    , hidden
    , hiddenAuthorIds
    , init
    , isAuthorHidden
    , isHostHidden
    , isPanelOpen
    , noneHidden
    , panel
    , popoverUsers
    , remember
    , reset
    , restore
    , subscriptions
    , syncMsg
    , update
    )

{-| The "Countabilibar": a row at the bottom of the top nav, *below* `Shared.Breadcrumbs`' trail (see
`UI.headerNav`), counting the posts and events the page is currently showing -- per server when the
page spans several (each server a logo + name chip with its post/event counts), per user when it spans
just one. Every entry has a checkbox to its left (checked = visible); unchecking one hides that
server's/user's posts and events from the page, and checking it brings them back. With several
servers, tapping a server (not its checkbox) opens a popover, centered under the bar like
`Shared.Breadcrumbs`' own, listing the users counted on it -- the same checkboxes, one level down.

Wired into `Shared.Model` the same way `Shared.Breadcrumbs` is -- one app-wide model that whichever
page has something to count feeds, rather than each page owning its own bar. The feeding side is
`Components.Pages.PostsPage`/`EventsPage`: after every update they diff what they're showing against
what's registered here (`syncMsg`) and send the difference as one `Batch` of `CountPosts`/
`CountEvents`/`RemovePost`/`RemoveEvent`. `Main` calls `reset` on every route change so one page's
counts (and hidden servers/users) never leak into the next.


## Hiding

Hiding is just a flag from this module's point of view -- `PostsPage`/`EventsPage` read it back (see
`hidden`) and do the actual work: they stop fetching a hidden server entirely, ask the others to leave
a hidden user out (`GetPostsRequest.excluded_author_user_ids`/`GetEventsRequest.excluded_author_user_ids`,
so the space their posts took up in a response goes to everyone else instead of staying empty), and
fade whatever's already on screen out. Since the page then has nothing to count for them,
`HideHost`/`HideAuthor` copy their counts into `hiddenHosts`/`hiddenAuthors` first -- that cache is
what the bar keeps showing next to the unchecked box. Counts sent for something hidden are ignored, and
`ShowHost`/`ShowAuthor` restore the cache right away (the page's own refetch then corrects it), so the
entry doesn't blink out while the page is still fetching.


## Animation

The row itself grows/shrinks to nothing (a `grid-template-rows` transition, see `.countabilibar` in
nav.css) when the first entry arrives/the last one leaves -- which is also why its vertical padding
lives inside the clipped layer: closed, it takes up exactly zero height. Entries fade/collapse in and
out with `UI.Flip`, and slide to their new place when sorting by count reorders them -- the usual
FLIP recipe, measuring before and after via `Ports.measureElements` (see `MeasurePhase`). The popover
isn't animated beyond its open/close transition.

-}

import Animation
import Browser.Dom as Dom
import Components.Authors as Authors
import Dict exposing (Dict)
import Gen.Route as Route
import Html exposing (Html, a, button, div, img, input, span, text)
import Html.Attributes exposing (alt, checked, class, disabled, href, id, src, title, type_)
import Html.Events exposing (onCheck, onClick)
import Html.Keyed
import Json.Decode as Decode
import Ports
import Proto.Rellm exposing (Author)
import Set exposing (Set)
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.MastodonServers as MastodonServers
import Shared.AccountsPanel.RellmAccounts as RellmAccounts
import Shared.AccountsPanel.BlueskyAppViews as BlueskyAppViews
import Shared.AccountsPanel.RellmServers as RellmServers
import Task
import UI.Classes exposing (classes, escapeCSSClass, hostnameToCSSClass, openClosedClass)
import UI.Flip
import UI.HtmlEvents exposing (stopPropagationAndPreventDefaultOnClick)



-- MODEL


type alias Model =
    { -- What the page is showing right now, most-counted server first.
      serverCounts : List ServerCounts

    -- Cached counts of the servers/users currently unchecked, copied from `serverCounts` when they were
    -- hidden -- see the module doc.
    , hiddenHosts : List ServerCounts
    , hiddenAuthors : List ( String, AuthorCounts )

    -- Whose users `panel` is showing, if any.
    , openHost : Maybe String

    -- The bar's own entries and their animation state, derived from the counts above by `syncEntries`
    -- after every change. Entries that just left stay here (fading out) until `EntryRemoved`.
    , entries : Dict String Entry
    , phase : MeasurePhase

    -- What was unchecked on pages the reader has since left, by page path -- so going _back_ to one brings it
    -- back (`restore`), unlike any other way of arriving. Survives `reset`; in memory only.
    , remembered : Dict String Remembered

    -- The order the entries keep being rendered in while their old positions are being measured --
    -- see `MeasurePhase`.
    , frozenOrder : Maybe (List String)
    }


type alias ServerCounts =
    { host : String
    , postCount : Int
    , eventCount : Int

    -- Most-counted user first.
    , authorCounts : List AuthorCounts
    }


{-| Counts are the sizes of the id sets -- they're kept as their own fields only so readers don't
recompute them. An Event's id is its own Post's id, so the two kinds could share one set; they don't, so
`PostsPage` and `EventsPage` can each diff only the ids they themselves counted.
-}
type alias AuthorCounts =
    { author : Author
    , postCount : Int
    , eventCount : Int
    , postIds : Set String
    , eventIds : Set String
    }


{-| What's being counted. Replies aren't counted yet: `PostsPage` only counts while it's listing
top-level posts.
-}
type Kind
    = PostsKind
    | EventsKind


type Msg
    = CountPost String Author String
    | CountEvent String Author String
      -- The same, many at a time (host, then author and id per item) -- what a page registers after a
      -- server's response lands.
    | CountPosts String (List ( Author, String ))
    | CountEvents String (List ( Author, String ))
    | Reset
    | RemoveHost String
    | RemoveAuthor String Author
    | RemovePost String Author String
    | RemoveEvent String Author String
    | HideHost String
    | ShowHost String
    | ToggleHostVisibility String
    | HideAuthor String Author
    | ShowAuthor String Author
    | ToggleAuthorVisibility String Author
    | Batch (List Msg)
    | TogglePanel String
    | ClosePanel
      -- Plumbing for the entries' animations.
    | Animate Animation.Msg
    | EntryRemoved String
    | MoveSettled String
    | GotMeasuredRects Decode.Value
    | ReadyToMeasureNew


init : Model
init =
    { serverCounts = []
    , hiddenHosts = []
    , hiddenAuthors = []
    , openHost = Nothing
    , entries = Dict.empty
    , phase = Idle
    , remembered = Dict.empty
    , frozenOrder = Nothing
    }


{-| The servers and users that were unchecked on a page, each with the counts cached when they were hidden --
exactly the `hiddenHosts`/`hiddenAuthors` fields.
-}
type alias Remembered =
    { hosts : List ServerCounts
    , authors : List ( String, AuthorCounts )
    }


{-| Notes what is unchecked right now as what the page at `path` had unchecked (forgetting any earlier note
for it when nothing is) -- `Main` calls this as the reader leaves a page, just before `reset` clears it.
-}
remember : String -> Model -> Model
remember path model =
    if List.isEmpty model.hiddenHosts && List.isEmpty model.hiddenAuthors then
        { model | remembered = Dict.remove path model.remembered }

    else
        { model | remembered = Dict.insert path { hosts = model.hiddenHosts, authors = model.hiddenAuthors } model.remembered }


{-| Unchecks again what the page at `path` had unchecked when it was left (see `remember`) -- `Main` calls this
right after `reset`, when the reader went _back_ to it, and before the page's `init`, which reads what's hidden.
`known` says which servers still exist (an unchecked entry for one that was removed in the meantime would just
sit in the bar). Their cached counts come back with them, so the bar reads as it did until the page counts again.
-}
restore : (String -> Bool) -> String -> Model -> Model
restore known path model =
    case Dict.get path model.remembered of
        Just saved ->
            { model
                | hiddenHosts = List.filter (\server -> known server.host) saved.hosts
                , hiddenAuthors = List.filter (\( host, _ ) -> known host) saved.authors
            }
                |> syncEntries

        Nothing ->
            model


{-| Forgets every count and every hidden server/user (their entries animate out) -- called by `Main` on
every route change, *before* the new page's `init`, so that init already sees nothing hidden. Hiding is
per page visit: it's a filter on what that page is showing, and the next page may not even count.
-}
reset : Model -> Model
reset model =
    { model | serverCounts = [], hiddenHosts = [], hiddenAuthors = [], openHost = Nothing, phase = Idle, frozenOrder = Nothing }
        |> syncEntries



-- WHAT PAGES NEED TO KNOW


{-| The servers and users currently unchecked -- a snapshot `PostsPage`/`EventsPage` keep to notice
changes (`==`) and to filter by. Users are keyed by server, since a user id only means something there.
-}
type alias Hidden =
    { hosts : Set String
    , authors : Dict String (Set String)
    }


noneHidden : Hidden
noneHidden =
    { hosts = Set.empty, authors = Dict.empty }


hidden : Model -> Hidden
hidden model =
    { hosts = model.hiddenHosts |> List.map .host |> Set.fromList
    , authors =
        List.foldl
            (\( host, counts ) ->
                Dict.update host (\ids -> Just (Set.insert counts.author.userId (Maybe.withDefault Set.empty ids)))
            )
            Dict.empty
            model.hiddenAuthors
    }


isHostHidden : Hidden -> String -> Bool
isHostHidden state host =
    Set.member host state.hosts


isAuthorHidden : Hidden -> String -> String -> Bool
isAuthorHidden state host userId =
    Dict.get host state.authors |> Maybe.map (Set.member userId) |> Maybe.withDefault False


{-| The user ids hidden on `host`, in a stable order -- what goes in `excluded_author_user_ids`.
-}
hiddenAuthorIds : Hidden -> String -> List String
hiddenAuthorIds state host =
    Dict.get host state.authors |> Maybe.map Set.toList |> Maybe.withDefault []


{-| Whether `msg` can change which servers/users are hidden (or forget them), and so is something
`PostsPage`/`EventsPage` have to react to -- they're only told about these (see `Shared.notifiesPages`).
-}
affectsPages : Msg -> Bool
affectsPages msg =
    case msg of
        Reset ->
            True

        RemoveHost _ ->
            True

        RemoveAuthor _ _ ->
            True

        HideHost _ ->
            True

        ShowHost _ ->
            True

        ToggleHostVisibility _ ->
            True

        HideAuthor _ _ ->
            True

        ShowAuthor _ _ ->
            True

        ToggleAuthorVisibility _ _ ->
            True

        Batch msgs ->
            List.any affectsPages msgs

        _ ->
            False


isPanelOpen : Model -> Bool
isPanelOpen model =
    model.openHost /= Nothing


closePanel : Model -> Model
closePanel model =
    { model | openHost = Nothing }


{-| The message that brings what's registered here for `kind` in line with `shown` -- everything a page
is displaying right now, by host (the bar counts what's on screen, so `shown` already excludes whatever
`hidden` says to leave out; anything hidden is ignored here as well, so the two can't disagree).
`Nothing` when they already agree, so a page can call this after every update and send the result.

Hosts in `pendingHosts` are left alone entirely: a page that's still waiting for a fetch to land has
nothing reliable to say about them yet (right after a `ShowHost`/`ShowAuthor`, its cached counts are the
best information there is until then).

-}
syncMsg : Kind -> Set String -> Dict String (List ( Author, String )) -> Model -> Maybe Msg
syncMsg kind pendingHosts shown model =
    let
        state : Hidden
        state =
            hidden model

        hosts : List String
        hosts =
            Set.union (Set.fromList (Dict.keys shown)) (Set.fromList (List.map .host model.serverCounts))
                |> Set.toList
                |> List.filter (\host -> not (Set.member host pendingHosts) && not (isHostHidden state host))

        forHost : String -> List Msg
        forHost host =
            let
                wanted : List ( Author, String )
                wanted =
                    Dict.get host shown
                        |> Maybe.withDefault []
                        |> List.filter (\( author, _ ) -> not (isAuthorHidden state host author.userId))

                registered : List ( Author, String )
                registered =
                    model.serverCounts
                        |> List.filter (\server -> server.host == host)
                        |> List.concatMap .authorCounts
                        |> List.concatMap (\counts -> idsOf kind counts |> Set.toList |> List.map (\id -> ( counts.author, id )))

                key : ( Author, String ) -> ( String, String )
                key ( author, id ) =
                    ( author.userId, id )

                wantedKeys : Set ( String, String )
                wantedKeys =
                    wanted |> List.map key |> Set.fromList

                registeredKeys : Set ( String, String )
                registeredKeys =
                    registered |> List.map key |> Set.fromList

                additions : List ( Author, String )
                additions =
                    List.filter (\pair -> not (Set.member (key pair) registeredKeys)) wanted

                removals : List ( Author, String )
                removals =
                    List.filter (\pair -> not (Set.member (key pair) wantedKeys)) registered
            in
            (if List.isEmpty additions then
                []

             else
                [ countMsg kind host additions ]
            )
                ++ List.map (\( author, id ) -> removeMsg kind host author id) removals
    in
    case List.concatMap forHost hosts of
        [] ->
            Nothing

        msgs ->
            Just (Batch msgs)


countMsg : Kind -> String -> List ( Author, String ) -> Msg
countMsg kind host pairs =
    case kind of
        PostsKind ->
            CountPosts host pairs

        EventsKind ->
            CountEvents host pairs


removeMsg : Kind -> String -> Author -> String -> Msg
removeMsg kind host author id =
    case kind of
        PostsKind ->
            RemovePost host author id

        EventsKind ->
            RemoveEvent host author id


idsOf : Kind -> AuthorCounts -> Set String
idsOf kind counts =
    case kind of
        PostsKind ->
            counts.postIds

        EventsKind ->
            counts.eventIds



-- COUNTING


emptyAuthorCounts : Author -> AuthorCounts
emptyAuthorCounts author =
    { author = author, postCount = 0, eventCount = 0, postIds = Set.empty, eventIds = Set.empty }


emptyServerCounts : String -> ServerCounts
emptyServerCounts host =
    { host = host, postCount = 0, eventCount = 0, authorCounts = [] }


recountAuthor : AuthorCounts -> AuthorCounts
recountAuthor counts =
    { counts | postCount = Set.size counts.postIds, eventCount = Set.size counts.eventIds }


totalOfAuthor : AuthorCounts -> Int
totalOfAuthor counts =
    counts.postCount + counts.eventCount


{-| Drops users with nothing left, recounts everything and sorts users highest-first (ties by user id, so
the order never depends on insertion order).
-}
recountServer : ServerCounts -> ServerCounts
recountServer server =
    let
        authors : List AuthorCounts
        authors =
            server.authorCounts
                |> List.map recountAuthor
                |> List.filter (\counts -> totalOfAuthor counts > 0)
                |> List.sortBy (\counts -> ( negate (totalOfAuthor counts), counts.author.userId ))
    in
    { server
        | authorCounts = authors
        , postCount = List.sum (List.map .postCount authors)
        , eventCount = List.sum (List.map .eventCount authors)
    }


totalOfServer : ServerCounts -> Int
totalOfServer server =
    server.postCount + server.eventCount


serverFor : String -> Model -> ServerCounts
serverFor host model =
    model.serverCounts
        |> List.filter (\server -> server.host == host)
        |> List.head
        |> Maybe.withDefault (emptyServerCounts host)


{-| Stores `server` (an empty one removes its host), keeping `serverCounts` highest-first.
-}
putServer : ServerCounts -> Model -> Model
putServer server model =
    let
        others : List ServerCounts
        others =
            List.filter (\other -> other.host /= server.host) model.serverCounts

        recounted : ServerCounts
        recounted =
            recountServer server
    in
    { model
        | serverCounts =
            (if List.isEmpty recounted.authorCounts then
                others

             else
                recounted :: others
            )
                |> List.sortBy (\other -> ( negate (totalOfServer other), other.host ))
    }


updateAuthor : Author -> (AuthorCounts -> AuthorCounts) -> ServerCounts -> ServerCounts
updateAuthor author change server =
    let
        existing : AuthorCounts
        existing =
            server.authorCounts
                |> List.filter (\counts -> counts.author.userId == author.userId)
                |> List.head
                |> Maybe.withDefault (emptyAuthorCounts author)

        others : List AuthorCounts
        others =
            List.filter (\counts -> counts.author.userId /= author.userId) server.authorCounts
    in
    { server | authorCounts = change { existing | author = author } :: others }


addIds : Kind -> String -> List ( Author, String ) -> Model -> Model
addIds kind host pairs model =
    let
        state : Hidden
        state =
            hidden model

        countable : List ( Author, String )
        countable =
            List.filter (\( author, _ ) -> not (isAuthorHidden state host author.userId)) pairs

        addOne : ( Author, String ) -> ServerCounts -> ServerCounts
        addOne ( author, id ) server =
            updateAuthor author (insertId kind id) server
    in
    if isHostHidden state host || List.isEmpty countable then
        model

    else
        putServer (List.foldl addOne (serverFor host model) countable) model


removeIds : Kind -> String -> List ( Author, String ) -> Model -> Model
removeIds kind host pairs model =
    let
        removeOne : ( Author, String ) -> ServerCounts -> ServerCounts
        removeOne ( author, id ) server =
            if List.any (\counts -> counts.author.userId == author.userId) server.authorCounts then
                updateAuthor author (deleteId kind id) server

            else
                server
    in
    if List.any (\server -> server.host == host) model.serverCounts then
        putServer (List.foldl removeOne (serverFor host model) pairs) model

    else
        model


insertId : Kind -> String -> AuthorCounts -> AuthorCounts
insertId kind id counts =
    case kind of
        PostsKind ->
            { counts | postIds = Set.insert id counts.postIds }

        EventsKind ->
            { counts | eventIds = Set.insert id counts.eventIds }


deleteId : Kind -> String -> AuthorCounts -> AuthorCounts
deleteId kind id counts =
    case kind of
        PostsKind ->
            { counts | postIds = Set.remove id counts.postIds }

        EventsKind ->
            { counts | eventIds = Set.remove id counts.eventIds }


{-| Everything but the animation plumbing -- the data half of `update`.
-}
applyData : Msg -> Model -> Model
applyData msg model =
    case msg of
        CountPost host author id ->
            addIds PostsKind host [ ( author, id ) ] model

        CountEvent host author id ->
            addIds EventsKind host [ ( author, id ) ] model

        CountPosts host pairs ->
            addIds PostsKind host pairs model

        CountEvents host pairs ->
            addIds EventsKind host pairs model

        Reset ->
            reset model

        RemoveHost host ->
            { model
                | serverCounts = List.filter (\server -> server.host /= host) model.serverCounts
                , hiddenHosts = List.filter (\server -> server.host /= host) model.hiddenHosts
                , hiddenAuthors = List.filter (\( authorHost, _ ) -> authorHost /= host) model.hiddenAuthors
            }

        RemoveAuthor host author ->
            let
                withoutAuthor : ServerCounts -> ServerCounts
                withoutAuthor server =
                    { server | authorCounts = List.filter (\counts -> counts.author.userId /= author.userId) server.authorCounts }
            in
            { model
                | hiddenAuthors = List.filter (\( authorHost, counts ) -> not (authorHost == host && counts.author.userId == author.userId)) model.hiddenAuthors
            }
                |> (\cleaned -> putServer (withoutAuthor (serverFor host cleaned)) cleaned)

        RemovePost host author id ->
            removeIds PostsKind host [ ( author, id ) ] model

        RemoveEvent host author id ->
            removeIds EventsKind host [ ( author, id ) ] model

        HideHost host ->
            if List.any (\server -> server.host == host) model.hiddenHosts then
                model

            else
                { model
                    | hiddenHosts = serverFor host model :: model.hiddenHosts
                    , serverCounts = List.filter (\server -> server.host /= host) model.serverCounts
                }

        ShowHost host ->
            case List.filter (\server -> server.host == host) model.hiddenHosts |> List.head of
                Just cached ->
                    { model | hiddenHosts = List.filter (\server -> server.host /= host) model.hiddenHosts }
                        |> putServer cached

                Nothing ->
                    model

        ToggleHostVisibility host ->
            if List.any (\server -> server.host == host) model.hiddenHosts then
                applyData (ShowHost host) model

            else
                applyData (HideHost host) model

        HideAuthor host author ->
            let
                cached : Maybe AuthorCounts
                cached =
                    serverFor host model
                        |> .authorCounts
                        |> List.filter (\counts -> counts.author.userId == author.userId)
                        |> List.head
            in
            case cached of
                Just counts ->
                    { model | hiddenAuthors = ( host, counts ) :: model.hiddenAuthors }
                        |> (\hiding ->
                                putServer
                                    (serverFor host hiding
                                        |> (\server -> { server | authorCounts = List.filter (\other -> other.author.userId /= author.userId) server.authorCounts })
                                    )
                                    hiding
                           )

                Nothing ->
                    model

        ShowAuthor host author ->
            let
                isThis : ( String, AuthorCounts ) -> Bool
                isThis ( authorHost, counts ) =
                    authorHost == host && counts.author.userId == author.userId
            in
            case List.filter isThis model.hiddenAuthors |> List.head of
                Just ( _, cached ) ->
                    let
                        restored : Model
                        restored =
                            { model | hiddenAuthors = List.filter (not << isThis) model.hiddenAuthors }
                    in
                    putServer
                        (serverFor host restored |> updateAuthor cached.author (\_ -> cached))
                        restored

                Nothing ->
                    model

        ToggleAuthorVisibility host author ->
            if isAuthorHidden (hidden model) host author.userId then
                applyData (ShowAuthor host author) model

            else
                applyData (HideAuthor host author) model

        Batch msgs ->
            List.foldl applyData model msgs

        TogglePanel host ->
            { model
                | openHost =
                    if model.openHost == Just host then
                        Nothing

                    else
                        Just host
            }

        ClosePanel ->
            { model | openHost = Nothing }

        _ ->
            model


{-| Closes the popover once there's nothing left to show in it.
-}
settle : Model -> Model
settle model =
    case model.openHost of
        Just host ->
            if List.member host (allHosts model) then
                model

            else
                { model | openHost = Nothing }

        Nothing ->
            model



-- ENTRIES


type alias Entry =
    { data : EntryData
    , flip : UI.Flip.State Msg
    , move : UI.Flip.MoveState Msg
    }


type alias EntryData =
    { key : String
    , kind : EntryKind
    , posts : Int
    , events : Int
    , visible : Bool
    }


type EntryKind
    = ServerEntry String
    | AuthorEntry String Author


{-| Every server with anything to show -- counted, hidden, or just having hidden users.
-}
allHosts : Model -> List String
allHosts model =
    (List.map .host model.serverCounts ++ List.map .host model.hiddenHosts ++ List.map Tuple.first model.hiddenAuthors)
        |> Set.fromList
        |> Set.toList


{-| `Just` the one server's host when everything counted is on it (and it isn't itself hidden -- an
unchecked server has to stay a server entry to be checked again), so the bar lists its users instead.
-}
singleHost : Model -> Maybe String
singleHost model =
    case allHosts model of
        [ host ] ->
            if List.any (\server -> server.host == host) model.hiddenHosts then
                Nothing

            else
                Just host

        _ ->
            Nothing


entryData : Model -> List EntryData
entryData model =
    case singleHost model of
        Just host ->
            authorEntries model host

        Nothing ->
            allHosts model |> List.map (serverEntry model)


serverEntry : Model -> String -> EntryData
serverEntry model host =
    case List.filter (\server -> server.host == host) model.hiddenHosts |> List.head of
        Just cached ->
            { key = "s:" ++ host, kind = ServerEntry host, posts = cached.postCount, events = cached.eventCount, visible = False }

        Nothing ->
            let
                server : ServerCounts
                server =
                    serverFor host model
            in
            { key = "s:" ++ host, kind = ServerEntry host, posts = server.postCount, events = server.eventCount, visible = True }


authorEntries : Model -> String -> List EntryData
authorEntries model host =
    let
        entry : Bool -> AuthorCounts -> EntryData
        entry visible counts =
            { key = "u:" ++ host ++ "|" ++ counts.author.userId
            , kind = AuthorEntry host counts.author
            , posts = counts.postCount
            , events = counts.eventCount
            , visible = visible
            }
    in
    -- A hidden server's users are in its cache (`hiddenHosts`), all hidden along with it.
    (case List.filter (\server -> server.host == host) model.hiddenHosts |> List.head of
        Just cached ->
            List.map (entry False) cached.authorCounts

        Nothing ->
            List.map (entry True) (serverFor host model).authorCounts
    )
        ++ (model.hiddenAuthors |> List.filter (\( authorHost, _ ) -> authorHost == host) |> List.map (Tuple.second >> entry False))


{-| The entries in the order they're rendered in: the `frozenOrder` while there is one (entries it
doesn't know yet go after those it does), `sortEntries` otherwise.
-}
viewOrder : Model -> List Entry
viewOrder model =
    case model.frozenOrder of
        Just frozen ->
            let
                rank : Entry -> Int
                rank entry =
                    frozen
                        |> List.indexedMap Tuple.pair
                        |> List.filter (\( _, key ) -> key == entry.data.key)
                        |> List.head
                        |> Maybe.map Tuple.first
                        |> Maybe.withDefault (List.length frozen)
            in
            sortEntries (Dict.values model.entries) |> List.sortBy rank

        Nothing ->
            sortEntries (Dict.values model.entries)


{-| Highest-first, ties by key (so the order is total and stable).
-}
sortEntries : List Entry -> List Entry
sortEntries =
    List.sortBy (\entry -> ( negate (entry.data.posts + entry.data.events), entry.data.key ))


{-| Reconciles `entries` with the counts: new ones fade in, gone ones fade out. A leaving entry keeps its
last data (and so its rank) -- see `UI.Flip.remove` on why relocating it would cancel its collapse.
-}
syncEntries : Model -> Model
syncEntries model =
    let
        current : Dict String EntryData
        current =
            entryData model |> List.map (\data -> ( data.key, data )) |> Dict.fromList
    in
    { model
        | entries =
            UI.Flip.syncAnimations
                EntryRemoved
                (\data -> { data = data, flip = UI.Flip.enter, move = UI.Flip.atRest })
                (\data entry -> { entry | data = data })
                current
                model.entries
    }


{-| The keys of the entries that aren't leaving, in display order.
-}
displayOrder : Model -> List String
displayOrder model =
    model.entries
        |> Dict.values
        |> List.filter (\entry -> not entry.flip.removing)
        |> sortEntries
        |> List.map (.data >> .key)


entryDomId : String -> String
entryDomId key =
    "countabilibar-entry-" ++ escapeCSSClass key



-- UPDATE


{-| Where `update`'s FLIP round trip is. The order changed, and the old positions have to be measured
before the new order paints -- but a port's result comes back a tick later, and Elm may well paint in
between, so the entries keep their old order (`Model.frozenOrder`) until the measurement is in
(`AwaitingOldRects`). Then the new order is let through, and once it has painted the new positions can be
measured (`AwaitingNewRects`) and the difference animated away.
-}
type MeasurePhase
    = Idle
    | AwaitingOldRects
    | AwaitingNewRects (Dict String UI.Flip.Rect)


measureOwner : String
measureOwner =
    "countabilibar"


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Animate animMsg ->
            let
                step : String -> Entry -> ( Dict String Entry, List (Cmd Msg) ) -> ( Dict String Entry, List (Cmd Msg) )
                step key entry ( entries, cmds ) =
                    let
                        ( newFlip, flipCmd ) =
                            UI.Flip.animate animMsg entry.flip

                        ( newMove, moveCmd ) =
                            UI.Flip.moveAnimate animMsg entry.move
                    in
                    ( Dict.insert key { entry | flip = newFlip, move = newMove } entries, flipCmd :: moveCmd :: cmds )

                ( newEntries, allCmds ) =
                    Dict.foldl step ( Dict.empty, [] ) model.entries
            in
            ( { model | entries = newEntries }, Cmd.batch allCmds )

        EntryRemoved key ->
            ( { model | entries = Dict.remove key model.entries }, Cmd.none )

        MoveSettled key ->
            ( { model | entries = Dict.update key (Maybe.map (\entry -> { entry | move = settledMove entry.move })) model.entries }
            , Cmd.none
            )

        GotMeasuredRects payload ->
            case UI.Flip.measuredResults measureOwner payload of
                Nothing ->
                    ( model, Cmd.none )

                Just results ->
                    case ( Decode.decodeValue UI.Flip.rectsDecoder results, model.phase ) of
                        ( Ok rects, AwaitingOldRects ) ->
                            -- Wait a frame (the same recipe as everywhere else that measures twice):
                            -- Elm paints a changed model on the next one.
                            ( { model | phase = AwaitingNewRects rects, frozenOrder = Nothing }
                            , Task.attempt (\_ -> ReadyToMeasureNew) Dom.getViewport
                            )

                        ( Ok newRects, AwaitingNewRects oldRects ) ->
                            ( startMoves oldRects newRects { model | phase = Idle }, Cmd.none )

                        _ ->
                            ( { model | phase = Idle, frozenOrder = Nothing }, Cmd.none )

        ReadyToMeasureNew ->
            case model.phase of
                AwaitingNewRects oldRects ->
                    ( model, UI.Flip.measureElementsCmd measureOwner entryDomId (Dict.keys oldRects) )

                _ ->
                    ( model, Cmd.none )

        _ ->
            let
                before : List String
                before =
                    displayOrder model

                changed : Model
                changed =
                    model |> applyData msg |> settle |> syncEntries

                after : List String
                after =
                    displayOrder changed

                -- Only entries that were on screen before *and* are staying can slide; ones coming/going
                -- animate in/out instead, and that alone slides the rest.
                staying : List String
                staying =
                    List.filter (\key -> List.member key after) before

                stayingAfter : List String
                stayingAfter =
                    List.filter (\key -> List.member key before) after
            in
            if model.phase == Idle && List.length staying >= 2 && staying /= stayingAfter then
                ( { changed | phase = AwaitingOldRects, frozenOrder = Just before }
                , UI.Flip.measureElementsCmd measureOwner entryDomId staying
                )

            else
                ( changed, Cmd.none )


settledMove : UI.Flip.MoveState Msg -> UI.Flip.MoveState Msg
settledMove move =
    { move | moving = False }


{-| The "Invert" and "Play" of FLIP: starts each entry that's moved sliding from where it was.
-}
startMoves : Dict String UI.Flip.Rect -> Dict String UI.Flip.Rect -> Model -> Model
startMoves oldRects newRects model =
    let
        slide : String -> Entry -> Entry
        slide key entry =
            case ( Dict.get key oldRects, Dict.get key newRects ) of
                ( Just old, Just new ) ->
                    if abs (old.x - new.x) < 0.5 && abs (old.y - new.y) < 0.5 then
                        entry

                    else
                        { entry | move = UI.Flip.startMove (MoveSettled key) ( old.x - new.x, old.y - new.y ) entry.move }

                _ ->
                    entry
    in
    { model | entries = Dict.map slide model.entries }


subscriptions : Model -> Sub Msg
subscriptions model =
    let
        entries : List Entry
        entries =
            Dict.values model.entries
    in
    Sub.batch
        [ Animation.subscription Animate (List.map (.flip >> .style) entries ++ List.map (.move >> .style) entries)
        , if model.phase == Idle then
            Sub.none

          else
            Ports.elementsMeasured GotMeasuredRects
        ]



-- VIEW


{-| The bar itself. Always rendered (empty, and zero-height, while there's nothing to count) so that
appearing and disappearing is a plain CSS height transition -- see `.countabilibar` in nav.css.
-}
bar : AccountsPanel.Model -> Model -> Html Msg
bar accountsPanelModel model =
    let
        sorted : List Entry
        sorted =
            viewOrder model

        isOpen : Bool
        isOpen =
            List.any (\entry -> not entry.flip.removing) sorted
    in
    div
        [ classes
            [ "countabilibar"
            , hostnameToCSSClass accountsPanelModel.mainFrontendHost
            , "background-color-primary"
            , openClosedClass isOpen
            ]
        ]
        [ div [ class "countabilibar-clip" ]
            [ Html.Keyed.node "div"
                [ classes [ "countabilibar-row", "flip-animated-row" ] ]
                (List.map (\entry -> ( entry.data.key, entryView accountsPanelModel model entry )) sorted)
            ]
        ]


entryView : AccountsPanel.Model -> Model -> Entry -> Html Msg
entryView accountsPanelModel model entry =
    let
        data : EntryData
        data =
            entry.data

        isPanelHost : Bool
        isPanelHost =
            case data.kind of
                ServerEntry host ->
                    model.openHost == Just host

                AuthorEntry _ _ ->
                    False

        body : Html Msg
        body =
            case data.kind of
                ServerEntry host ->
                    button
                        [ classes [ "countabilibar-body", "countabilibar-server-body" ]
                        , onClick (TogglePanel host)
                        , title ("Users on " ++ host)
                        ]
                        [ serverLabel accountsPanelModel host, countsView data ]

                AuthorEntry host author ->
                    div [ class "countabilibar-body" ]
                        [ authorLabel accountsPanelModel host author, countsView data ]
    in
    -- The classless-ish `slot` is what `flip.css` clips and pads (its right padding is the gap between
    -- chips), so the chip itself -- the thing that slides -- keeps its own border and padding.
    div (UI.Flip.itemAttributes UI.Flip.Horizontal entry.flip entry.move.moving)
        [ div [ class "countabilibar-slot" ]
            [ div
                (id (entryDomId data.key)
                :: classes
                    ("countabilibar-entry"
                        :: (if data.visible then
                                []

                            else
                                [ "is-hidden" ]
                           )
                        ++ (if isPanelHost then
                                [ "is-panel-open" ]

                            else
                                []
                           )
                    )
                :: UI.Flip.moveAttributes entry.move
            )
            [ visibilityCheckbox True data.visible data.kind, body ]
            ]
        ]


{-| `isEnabled` is `False` for a user of a hidden server (listed in the popover, but only the server's own
checkbox can bring them back).
-}
visibilityCheckbox : Bool -> Bool -> EntryKind -> Html Msg
visibilityCheckbox isEnabled isVisible kind =
    input
        [ type_ "checkbox"
        , class "countabilibar-checkbox"
        , checked isVisible
        , disabled (not isEnabled)
        , title
            (if not isEnabled then
                "Hidden with its server – show the server first"

             else if isVisible then
                "Showing – uncheck to hide"

             else
                "Hidden – check to show"
            )
        , onCheck
            (\nowChecked ->
                case ( kind, nowChecked ) of
                    ( ServerEntry host, True ) ->
                        ShowHost host

                    ( ServerEntry host, False ) ->
                        HideHost host

                    ( AuthorEntry host author, True ) ->
                        ShowAuthor host author

                    ( AuthorEntry host author, False ) ->
                        HideAuthor host author
            )
        ]
        []


{-| A server the way the nav's Home button shows it: logo on the left, its (possibly two-line) name on the
right. Mastodon instances and Bluesky accounts/AppViews (hosts `"mastodon:<instance>"`/`"bluesky:<handle or
host>"`, see `Components.Pages.PostsPage.feedSourceKey`) get the same layout from what's known about them
(`federatedLabel`); a plain host name until a Rellm server is known.
-}
serverLabel : AccountsPanel.Model -> String -> Html msg
serverLabel accountsPanelModel host =
    case RellmServers.rellmServerForHost accountsPanelModel.servers host of
        Just server ->
            RellmServers.rellmServerNameAndLogo server RellmServers.HorizontalServerLogo

        Nothing ->
            if String.startsWith "mastodon:" host then
                let
                    instanceHost : String
                    instanceHost =
                        String.dropLeft 9 host

                    instance : Maybe MastodonServers.BrowsedMastodonInstance
                    instance =
                        accountsPanelModel.browsedMastodonInstances
                            |> List.filter (\browsed -> browsed.host == instanceHost)
                            |> List.head
                in
                federatedLabel False
                    (instance |> Maybe.andThen .logoUrl)
                    (instance
                        |> Maybe.andThen .displayName
                        |> Maybe.andThen
                            (\name ->
                                -- Many instances never customize their name from the generic "Mastodon".
                                if String.trim name == "Mastodon" then
                                    Nothing

                                else
                                    Just name
                            )
                        |> Maybe.withDefault instanceHost
                    )
                    "⇄ Mastodon"

            else if String.startsWith "bluesky:" host then
                let
                    handleOrHost : String
                    handleOrHost =
                        String.dropLeft 8 host
                in
                case List.filter (\account -> account.handle == handleOrHost) accountsPanelModel.blueskyAccounts |> List.head of
                    Just account ->
                        federatedLabel True account.avatarUrl (Maybe.withDefault account.handle account.displayName) "⇄ Bluesky"

                    Nothing ->
                        federatedLabel False
                            (BlueskyAppViews.logoUrlFor (AccountsPanel.allBlueskyServers accountsPanelModel) handleOrHost)
                            (BlueskyAppViews.displayName handleOrHost)
                            "⇄ Bluesky"

            else
                span [ class "countabilibar-host" ] [ text host ]


{-| `serverLabel`'s layout for a server that isn't a Rellm one: `RellmServers.rellmServerNameAndLogo`'s
own markup (so it's styled the same), with a logo image -- or the name's initial -- and a "⇄ Mastodon"/
"⇄ Bluesky" second line.
-}
federatedLabel : Bool -> Maybe String -> String -> String -> Html msg
federatedLabel circularLogo logoUrl name service =
    div [ class "server-name-and-logo horizontal" ]
        [ case logoUrl of
            Just url ->
                img
                    [ classes ("server-logo-image" :: (if circularLogo then [ "server-logo-image-circular" ] else []))
                    , src url
                    , alt name
                    ]
                    []

            Nothing ->
                div [ class "server-logo-placeholder" ] [ text (RellmServers.initialLetter name) ]
        , div [ class "server-name-breakdown", title name ]
            [ div [ class "server-name-primary" ] [ text name ]
            , div [ class "server-name-secondary" ] [ text service ]
            ]
        ]


{-| A user's avatar and "username | Real Name" (just the username without a distinct real name).
-}
authorLabel : AccountsPanel.Model -> String -> Author -> Html msg
authorLabel accountsPanelModel host author =
    let
        username : String
        username =
            if String.startsWith "mastodon:" host then
                -- A Mastodon author's username is "user@instance"; the instance is already the server.
                Authors.name (Just author) |> String.split "@" |> List.head |> Maybe.withDefault ""

            else
                Authors.name (Just author)

        realName : String
        realName =
            author.realName |> Maybe.map String.trim |> Maybe.withDefault ""
    in
    span [ class "countabilibar-author" ]
        [ Authors.avatar username
            (Authors.avatarUrl
                (RellmServers.rellmServerForHost accountsPanelModel.servers host)
                (RellmAccounts.enabledRellmAccountForServer accountsPanelModel.accounts host)
                (Just author)
            )
        , span [ class "countabilibar-author-name" ]
            (span [ class "countabilibar-username" ] [ text username ]
                :: (if String.isEmpty realName || realName == username then
                        []

                    else
                        [ span [ class "countabilibar-real-name" ] [ text (" | " ++ realName) ] ]
                   )
            )
        ]


countsView : EntryData -> Html msg
countsView data =
    let
        part : Int -> String -> List String
        part count noun =
            if count > 0 then
                [ String.fromInt count ++ " " ++ noun ++ (if count == 1 then "" else "s") ]

            else
                []
    in
    span [ class "countabilibar-counts" ]
        [ text
            (case part data.posts "post" ++ part data.events "event" of
                [] ->
                    "0"

                parts ->
                    String.join " · " parts
            )
        ]


{-| The popover under the bar (see the module doc): the users counted on `openHost` -- hidden ones too,
unchecked -- highest-first, with the same checkboxes the bar's own user entries have. Always rendered, like
every other panel, so opening/closing is a CSS transition; mounted as a `.navbar` child (see
`UI.headerNav`) so it anchors under the whole bar.
-}
panel : String -> AccountsPanel.Model -> Model -> Html Msg
panel basePath accountsPanelModel model =
    case model.openHost of
        Just host ->
            div [ classes [ "countabilibar-panel", "nav-panel", openClosedClass True ] ]
                [ div [ class "countabilibar-panel-header" ]
                    [ serverLabel accountsPanelModel host
                    , case RellmServers.rellmServerForHost accountsPanelModel.servers host of
                        Just server ->
                            serverInfoButton basePath server

                        Nothing ->
                            text ""
                    ]
                , div [ class "countabilibar-panel-list" ]
                    (authorEntries model host
                        |> List.sortBy (\data -> ( negate (data.posts + data.events), data.key ))
                        |> List.map (panelRow basePath accountsPanelModel (List.any (\server -> server.host == host) model.hiddenHosts))
                    )
                ]

        Nothing ->
            div [ classes [ "countabilibar-panel", "nav-panel", openClosedClass False ] ] []


{-| `authorLabel`, linked to the user's profile (a federated user's too -- `Authors.href` resolves those the
same way a post card's author link does). Closes the popover: the nav isn't a page, so going to the
profile doesn't otherwise change anything it's showing.
-}
authorLink : String -> AccountsPanel.Model -> String -> Author -> Html Msg
authorLink basePath accountsPanelModel host author =
    case Authors.href basePath accountsPanelModel.mainFrontendHost host (Just author) of
        Just profileHref ->
            a
                [ classes [ "countabilibar-author-link" ]
                , href profileHref
                , stopPropagationAndPreventDefaultOnClick ClosePanel
                ]
                [ authorLabel accountsPanelModel host author ]

        Nothing ->
            authorLabel accountsPanelModel host author


{-| The circular "i" next to the server's name -- to its `ServerInformationPage` -- the one a server chip
in the Accounts Panel has (`UI.serverInfoButton`, which this mirrors: `UI` imports this module, so it
can't be reused). Closes the popover like `authorLink`.
-}
serverInfoButton : String -> RellmServers.RellmServer -> Html Msg
serverInfoButton basePath server =
    let
        -- Disconnected servers default to `https:` -- `ServerInformationPage`'s own probe re-negotiates.
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
        [ classes [ "panel-icon-button", "info-button", "countabilibar-info-button" ]
        , href (basePath ++ Route.toHref (Route.Server__ServerIdentifier_ { serverIdentifier = serverIdentifier }))
        , stopPropagationAndPreventDefaultOnClick ClosePanel
        , title ("About " ++ server.frontendHost)
        ]
        [ text "i" ]


{-| What the popover lists for `host`, as `( user id, visible, posts + events )`, highest-first.
-}
popoverUsers : String -> Model -> List ( String, Bool, Int )
popoverUsers host model =
    authorEntries model host
        |> List.sortBy (\data -> ( negate (data.posts + data.events), data.key ))
        |> List.filterMap
            (\data ->
                case data.kind of
                    AuthorEntry _ author ->
                        Just ( author.userId, data.visible, data.posts + data.events )

                    ServerEntry _ ->
                        Nothing
            )


panelRow : String -> AccountsPanel.Model -> Bool -> EntryData -> Html Msg
panelRow basePath accountsPanelModel hostHidden data =
    case data.kind of
        AuthorEntry host author ->
            div
                [ classes
                    ("countabilibar-panel-row"
                        :: (if data.visible then
                                []

                            else
                                [ "is-hidden" ]
                           )
                    )
                ]
                [ visibilityCheckbox (not hostHidden) data.visible data.kind
                , authorLink basePath accountsPanelModel host author
                , countsView data
                ]

        ServerEntry _ ->
            text ""
