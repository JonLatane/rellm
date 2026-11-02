module Components.Pages.PostsPage.Paging exposing
    ( Entry
    , Frontier
    , Order(..)
    , Window
    , frontierOf
    , hasHiddenAbove
    , hasMoreBelow
    , initialWindow
    , isBinding
    , maxRendered
    , normalize
    , remainingBelow
    , revealAbove
    , revealBelow
    , revealStep
    , safeEntries
    , sortEntries
    , visible
    )

{-| The pure half of `Components.Pages.PostsPage`'s infinite scroll: which loaded posts are fit to show
yet, and which slice of those is actually rendered.

Posts come from several sources (Rellm servers, Mastodon instances, Bluesky accounts), each paged
separately and each ahead of the others by a different amount. Two problems follow, and this module is
the answer to both:

  - **Order.** A source that still has pages left may owe us a post older than anything it has handed over
    so far. Showing another source's older post above it would put the list out of order the moment that page
    lands, so `safeEntries` only lets through the posts no unfinished source could still precede -- the
    "frontier" (`Frontier`) of the list. A source that has nothing left (or whose pages are all in) never
    holds the list back.
  - **Size.** Rendering every loaded post is both slow and unnecessary, so a `Window` shows `shown` of the
    safe posts from a starting post, growing by `revealStep` as the reader nears the bottom. Once more than
    `maxRendered` would be on screen the oldest ones above are dropped (the reader's scroll position is
    held by the caller), and scrolling back up brings them back (`revealAbove`).

The window is anchored on a post's key (`Window.start`), not an index, so posts arriving above it (a refetch
landing, a new post) don't change what the reader is looking at.

-}


{-| What `sortEntries`/`safeEntries` need to know about a post: a stable `key`, its place in its own source's
response (`rank`, 0 for the first post, growing -- see `Components.Pages.PostsPage.PostAnimation.rank`) and its
timestamp in milliseconds. Extra fields (the post itself, its host) ride along.
-}
type alias Entry a =
    { a | key : String, rank : Float, millis : Int }


{-| How the feed is ordered: newest first, or by `rank` (position in the source's own ranking, interleaving
sources) with recency breaking ties -- the popular sort and text searches, where the response order is the
point.
-}
type Order
    = ByRecency
    | ByRank


{-| How far one source's loaded posts reach: its lowest `rank` is irrelevant, what matters is the _last_ one
it has handed over -- the highest `rank` (`ByRank`) or oldest `millis` (`ByRecency`). Everything the source
has not yet sent comes after that.
-}
type alias Frontier =
    { rank : Float, millis : Int }


{-| `entries` is one source's posts (in any order) -- `Nothing` for a source with none loaded, which has no
frontier to hold anything back at.
-}
frontierOf : List (Entry a) -> Maybe Frontier
frontierOf entries =
    case entries of
        [] ->
            Nothing

        first :: rest ->
            Just
                (List.foldl
                    (\entry frontier ->
                        { rank = max frontier.rank entry.rank
                        , millis = min frontier.millis entry.millis
                        }
                    )
                    { rank = first.rank, millis = first.millis }
                    rest
                )


{-| `entries` in display order -- see `Order`.
-}
sortEntries : Order -> List (Entry a) -> List (Entry a)
sortEntries order =
    case order of
        ByRecency ->
            List.sortBy (\entry -> -entry.millis)

        ByRank ->
            List.sortBy (\entry -> ( entry.rank, -entry.millis ))


{-| Where the safe part of the list ends, given the frontier of every source that still has pages to load:
the oldest of the newest-`millis` frontiers (`ByRecency`, a post older than that could be preceded by
something not loaded yet) or the lowest of the `rank` frontiers (`ByRank`). `Nothing` when no source has more
to give -- every loaded post is safe.
-}
limit : Order -> List Frontier -> Maybe Float
limit order frontiers =
    case order of
        ByRecency ->
            frontiers |> List.map (.millis >> toFloat) |> List.maximum

        ByRank ->
            frontiers |> List.map .rank |> List.minimum


{-| The posts of `entries` (already in display order) that nothing unloaded can come before, given the
`frontiers` of the sources with more pages to give.
-}
safeEntries : Order -> List Frontier -> List (Entry a) -> List (Entry a)
safeEntries order frontiers entries =
    case limit order frontiers of
        Nothing ->
            entries

        Just bound ->
            case order of
                ByRecency ->
                    List.filter (\entry -> toFloat entry.millis >= bound) entries

                ByRank ->
                    List.filter (\entry -> entry.rank <= bound) entries


{-| Whether a source with `frontier` is what holds the safe list back -- the one whose next page is the
next thing worth fetching (any other source with more to give is already further along than the bound).
-}
isBinding : Order -> List Frontier -> Frontier -> Bool
isBinding order frontiers frontier =
    case ( order, limit order frontiers ) of
        ( ByRecency, Just bound ) ->
            toFloat frontier.millis == bound

        ( ByRank, Just bound ) ->
            frontier.rank == bound

        _ ->
            False



-- WINDOW


{-| The rendered slice of the safe posts: `shown` of them from the one keyed `start` (`Nothing`: from the
very first). `shown` is a _wish_ -- it can exceed what is loaded, while the next page is on its way.
-}
type alias Window =
    { start : Maybe String
    , shown : Int
    }


{-| How many more posts each reach of the bottom (or top) brings in.
-}
revealStep : Int
revealStep =
    25


{-| The most posts rendered at once. Past that, reaching the bottom drops posts from the top.
-}
maxRendered : Int
maxRendered =
    100


initialWindow : Window
initialWindow =
    { start = Nothing, shown = revealStep }


{-| Where `window` starts in `keys` (the safe posts' keys, in display order): 0 for a window anchored to
the first post, or whose anchor is no longer there (it left the list -- the reader is shown from the top
rather than from nowhere).
-}
startIndex : List String -> Window -> Int
startIndex keys window =
    case window.start of
        Nothing ->
            0

        Just startKey ->
            keys
                |> List.indexedMap Tuple.pair
                |> List.filter (\( _, key ) -> key == startKey)
                |> List.head
                |> Maybe.map Tuple.first
                |> Maybe.withDefault 0


{-| `items` (in the same order as `keys`, which is how `Window` locates its start -- pass `List.map .key`)
that `window` renders.
-}
visible : (item -> String) -> Window -> List item -> List item
visible keyOf window items =
    let
        keys : List String
        keys =
            List.map keyOf items
    in
    items
        |> List.drop (startIndex keys window)
        |> List.take window.shown


{-| Brings in the next `revealStep` posts at the bottom.
-}
revealBelow : Window -> Window
revealBelow window =
    { window | shown = window.shown + revealStep }


{-| Brings back up to `revealStep` posts that were dropped from the top -- and, if that leaves more than
`maxRendered` on screen, drops the ones now furthest below.
-}
revealAbove : List String -> Window -> Window
revealAbove keys window =
    let
        start : Int
        start =
            startIndex keys window

        newStart : Int
        newStart =
            max 0 (start - revealStep)
    in
    { start =
        if newStart == 0 then
            Nothing

        else
            keys |> List.drop newStart |> List.head
    , shown = min maxRendered (window.shown + (start - newStart))
    }


{-| Keeps `window` within `maxRendered`: when more than that is on screen, the surplus is dropped from the
top (the window's start moves down by that many posts). `keys` are the safe posts' keys, in order. A window
whose start post has left the list starts over from the top instead.
-}
normalize : List String -> Window -> Window
normalize keys window =
    case window.start of
        Just startKey ->
            if List.member startKey keys then
                trimTop keys window

            else
                trimTop keys { window | start = Nothing }

        Nothing ->
            trimTop keys window


trimTop : List String -> Window -> Window
trimTop keys window =
    let
        start : Int
        start =
            startIndex keys window

        -- `shown` can run ahead of what's loaded (a page is on its way), which doesn't count as rendered.
        rendered : Int
        rendered =
            min window.shown (List.length keys - start)

        surplus : Int
        surplus =
            rendered - maxRendered
    in
    if surplus > 0 then
        { start = keys |> List.drop (start + surplus) |> List.head
        , shown = window.shown - surplus
        }

    else
        window


{-| Whether posts were dropped from the top (the reader can scroll up to bring them back).
-}
hasHiddenAbove : List String -> Window -> Bool
hasHiddenAbove keys window =
    startIndex keys window > 0


{-| How many safe posts are loaded but not yet rendered below the window.
-}
remainingBelow : List String -> Window -> Int
remainingBelow keys window =
    max 0 (List.length keys - startIndex keys window - window.shown)


hasMoreBelow : List String -> Window -> Bool
hasMoreBelow keys window =
    remainingBelow keys window > 0
