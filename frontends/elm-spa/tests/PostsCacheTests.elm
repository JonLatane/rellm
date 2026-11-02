module PostsCacheTests exposing (suite)

{-| Tests for `Shared.PostsCache` -- when a saved posts feed may be shown again (only on back-navigation, for the
same settings, within four hours), and what drops one (accounts changing, a post deleted, one created).
-}

import Components.Pages.PostsPage.Paging as Paging
import Dict
import Expect
import Proto.Rellm exposing (defaultPost)
import Proto.Rellm.PostContext exposing (PostContext(..))
import Shared.PostsCache as PostsCache exposing (CachedFeed, Settings, Snapshot)
import Test exposing (Test, describe, test)
import Time


settings : Settings
settings =
    { searchText = "", context = POST, sort = "recent", publishedBefore = Nothing }


feed : String -> Maybe String -> List String -> CachedFeed
feed host accountId postIds =
    { posts = List.map (\id -> { defaultPost | id = id }) postIds
    , accountId = accountId
    , host = host
    , excludedAuthorIds = []
    , next = Nothing
    , rankBase = 1
    , fetchedAt = Just (Time.millisToPosix 1000)
    }


snapshot : Settings -> List CachedFeed -> Snapshot
snapshot snapshotSettings feeds =
    { feeds = feeds |> List.map (\f -> ( f.host, f )) |> Dict.fromList
    , window = Paging.initialWindow
    , settings = snapshotSettings
    }


stored : List ( String, Snapshot ) -> PostsCache.Model
stored entries =
    List.foldl (\( key, s ) model -> PostsCache.update (PostsCache.Store key s) model) PostsCache.empty entries


keysOf : PostsCache.Model -> List String
keysOf model =
    model.snapshots |> List.map Tuple.first


suite : Test
suite =
    describe "Shared.PostsCache"
        [ restoring
        , expiry
        , reconciling
        , evicting
        , labels
        ]


restoring : Test
restoring =
    let
        withSnapshot : PostsCache.Model
        withSnapshot =
            stored [ ( "/posts", snapshot settings [ feed "a.example" Nothing [ "1" ] ] ) ]
    in
    describe "restorable"
        [ test "never unless the navigation was a browser back" <|
            \_ ->
                PostsCache.restorable "/posts" settings withSnapshot
                    |> Expect.equal Nothing
        , test "on a back-navigation, the snapshot saved for that page" <|
            \_ ->
                PostsCache.restorable "/posts" settings (PostsCache.setRestoring True withSnapshot)
                    |> Maybe.map (.feeds >> Dict.keys)
                    |> Expect.equal (Just [ "a.example" ])
        , test "not another page's" <|
            \_ ->
                PostsCache.restorable "/" settings (PostsCache.setRestoring True withSnapshot)
                    |> Expect.equal Nothing
        , test "not when the page starts with other settings (a different search, say)" <|
            \_ ->
                PostsCache.restorable "/posts" { settings | searchText = "cats" } (PostsCache.setRestoring True withSnapshot)
                    |> Expect.equal Nothing
        , test "not once the first page after it has had its chance" <|
            \_ ->
                withSnapshot
                    |> PostsCache.setRestoring True
                    |> PostsCache.update PostsCache.ConsumeRestore
                    |> PostsCache.restorable "/posts" settings
                    |> Expect.equal Nothing
        , test "storing a page again replaces it and puts it first; a few are kept" <|
            \_ ->
                let
                    keys : List String
                    keys =
                        List.range 1 10 |> List.map (\i -> "/page" ++ String.fromInt i)

                    model : PostsCache.Model
                    model =
                        stored (List.map (\k -> ( k, snapshot settings [ feed "a.example" Nothing [] ] )) keys)
                            |> PostsCache.update (PostsCache.Store "/page5" (snapshot settings [ feed "a.example" Nothing [] ]))
                in
                ( List.length model.snapshots, List.head (keysOf model), List.filter ((==) "/page5") (keysOf model) |> List.length )
                    |> Expect.equal ( 8, Just "/page5", 1 )
        , test "evicting forgets one page's snapshot" <|
            \_ ->
                PostsCache.update (PostsCache.Evict "/posts") withSnapshot
                    |> keysOf
                    |> Expect.equal []
        ]


expiry : Test
expiry =
    let
        fetched : Time.Posix
        fetched =
            Time.millisToPosix 1000000
    in
    describe "expired"
        [ test "fresh within four hours" <|
            \_ ->
                PostsCache.expired (Time.millisToPosix (1000000 + PostsCache.expiryMs)) (Just fetched)
                    |> Expect.equal False
        , test "expired after four hours" <|
            \_ ->
                PostsCache.expired (Time.millisToPosix (1000000 + PostsCache.expiryMs + 1)) (Just fetched)
                    |> Expect.equal True
        , test "posts of unknown age are not trusted" <|
            \_ ->
                PostsCache.expired fetched Nothing
                    |> Expect.equal True
        ]


reconciling : Test
reconciling =
    let
        model : PostsCache.Model
        model =
            stored
                [ ( "/posts"
                  , snapshot settings
                        [ feed "a.example" (Just "a.example|7") [ "1" ]
                        , feed "b.example" Nothing [ "2" ]
                        , feed "mastodon:m.example" Nothing [ "3" ]
                        ]
                  )
                ]

        hostsAfter : PostsCache.Model -> List String
        hostsAfter m =
            m.snapshots |> List.concatMap (Tuple.second >> .feeds >> Dict.keys)
    in
    describe "reconcile"
        [ test "nothing changes while every feed was fetched as the account acting on its server" <|
            \_ ->
                PostsCache.reconcile
                    (\host ->
                        if host == "a.example" then
                            Just "a.example|7"

                        else
                            Nothing
                    )
                    False
                    model
                    |> hostsAfter
                    |> Expect.equal [ "a.example", "b.example", "mastodon:m.example" ]
        , test "signing out of a server drops that server's feed (and only that)" <|
            \_ ->
                PostsCache.reconcile (\_ -> Nothing) True model
                    |> hostsAfter
                    |> Expect.equal [ "b.example", "mastodon:m.example" ]
        , test "so does acting as someone else" <|
            \_ ->
                PostsCache.reconcile (\host -> Just (host ++ "|8")) True model
                    |> hostsAfter
                    |> Expect.equal []
        , test "a snapshot left with no feeds is forgotten" <|
            \_ ->
                stored [ ( "/posts", snapshot settings [ feed "a.example" (Just "a.example|7") [ "1" ] ] ) ]
                    |> PostsCache.reconcile (\_ -> Nothing) True
                    |> keysOf
                    |> Expect.equal []
        , test "'Following' snapshots go whenever the accounts change at all" <|
            \_ ->
                let
                    following : PostsCache.Model
                    following =
                        stored [ ( "/posts", snapshot { settings | sort = "following" } [ feed "b.example" Nothing [ "2" ] ] ) ]
                in
                ( PostsCache.reconcile (\_ -> Nothing) False following |> keysOf
                , PostsCache.reconcile (\_ -> Nothing) True following |> keysOf
                )
                    |> Expect.equal ( [ "/posts" ], [] )
        ]


evicting : Test
evicting =
    let
        model : PostsCache.Model
        model =
            stored
                [ ( "/posts", snapshot settings [ feed "a.example" Nothing [ "1", "2" ] ] )
                , ( "/", snapshot settings [ feed "b.example" Nothing [ "1" ] ] )
                ]
    in
    describe "eviction"
        [ test "a deleted post drops the snapshots showing it, on its own server" <|
            \_ ->
                PostsCache.evictPost "a.example" "1" model
                    |> keysOf
                    |> Expect.equal [ "/" ]
        , test "a post that isn't in a snapshot leaves it alone" <|
            \_ ->
                PostsCache.evictPost "a.example" "9" model
                    |> keysOf
                    |> Expect.equal [ "/", "/posts" ]
        , test "a post created on a server drops the snapshots with its posts" <|
            \_ ->
                PostsCache.evictHost "b.example" model
                    |> keysOf
                    |> Expect.equal [ "/posts" ]
        ]


labels : Test
labels =
    describe "ageLabel"
        [ test "nothing to say up to five minutes" <|
            \_ ->
                ( PostsCache.ageLabel 0, PostsCache.ageLabel (5 * 60000) )
                    |> Expect.equal ( Nothing, Nothing )
        , test "minutes, then hours" <|
            \_ ->
                [ 5 * 60000 + 1, 7 * 60000 + 59999, 59 * 60000 + 59999, 60 * 60000, 119 * 60000, 3 * 3600000 + 1 ]
                    |> List.map PostsCache.ageLabel
                    |> Expect.equal
                        [ Just "5 minutes"
                        , Just "7 minutes"
                        , Just "59 minutes"
                        , Just "1 hour"
                        , Just "1 hour"
                        , Just "3 hours"
                        ]
        ]
