module EventsCacheTests exposing (suite)

{-| Tests for `Shared.EventsCache` -- when a saved events feed may be shown again (only on back-navigation, for
the same settings), and what drops one (accounts changing, an event deleted or changed, one created).
-}

import Dict
import Expect
import Proto.Rellm exposing (defaultEvent, defaultOccasion, defaultPost)
import Shared.EventsCache as EventsCache exposing (CachedFeed, Settings, Snapshot)
import Test exposing (Test, describe, test)
import Time


settings : Settings
settings =
    { searchText = "", upcoming = True, endsAfter = Nothing }


feed : String -> Maybe String -> List String -> CachedFeed
feed host accountId eventIds =
    { events =
        List.map
            (\id -> ( { defaultEvent | post = Just { defaultPost | id = id } }, defaultOccasion ))
            eventIds
    , accountId = accountId
    , host = host
    , excludedAuthorIds = []
    , fetchedAt = Just (Time.millisToPosix 1000)
    }


snapshot : Settings -> List CachedFeed -> Snapshot
snapshot snapshotSettings feeds =
    { feeds = feeds |> List.map (\f -> ( f.host, f )) |> Dict.fromList
    , settings = snapshotSettings
    , endsAfter = Just (Time.millisToPosix 2000)
    }


stored : List ( String, Snapshot ) -> EventsCache.Model
stored entries =
    List.foldl (\( key, s ) model -> EventsCache.update (EventsCache.Store key s) model) EventsCache.empty entries


keysOf : EventsCache.Model -> List String
keysOf model =
    model.snapshots |> List.map Tuple.first


suite : Test
suite =
    describe "Shared.EventsCache"
        [ restoring
        , reconciling
        , evicting
        , storing
        ]


restoring : Test
restoring =
    let
        withSnapshot : EventsCache.Model
        withSnapshot =
            stored [ ( "/events", snapshot settings [ feed "a.example" Nothing [ "1" ] ] ) ]
    in
    describe "restorable"
        [ test "never unless the navigation was a browser back" <|
            \_ ->
                EventsCache.restorable "/events" settings withSnapshot
                    |> Expect.equal Nothing
        , test "on a back-navigation, the snapshot saved for that page" <|
            \_ ->
                EventsCache.restorable "/events" settings (EventsCache.setRestoring True withSnapshot)
                    |> Maybe.map (.feeds >> Dict.keys)
                    |> Expect.equal (Just [ "a.example" ])
        , test "not another page's" <|
            \_ ->
                EventsCache.restorable "/people" settings (EventsCache.setRestoring True withSnapshot)
                    |> Expect.equal Nothing
        , test "not under other settings: another search, the other tab, another cutoff" <|
            \_ ->
                let
                    restoring_ : Settings -> Maybe Snapshot
                    restoring_ other =
                        EventsCache.restorable "/events" other (EventsCache.setRestoring True withSnapshot)
                in
                ( restoring_ { settings | searchText = "jazz" }
                , restoring_ { settings | upcoming = False, endsAfter = Just 5 }
                )
                    |> Expect.equal ( Nothing, Nothing )
        , test "the restore flag is spent by ConsumeRestore" <|
            \_ ->
                withSnapshot
                    |> EventsCache.setRestoring True
                    |> EventsCache.update EventsCache.ConsumeRestore
                    |> EventsCache.restorable "/events" settings
                    |> Expect.equal Nothing
        ]


reconciling : Test
reconciling =
    let
        accountIdFor : String -> Maybe String
        accountIdFor host =
            if host == "a.example" then
                Just "alice"

            else
                Nothing

        cache : EventsCache.Model
        cache =
            stored
                [ ( "/events", snapshot settings [ feed "a.example" (Just "alice") [ "1" ], feed "b.example" Nothing [ "2" ] ] )
                , ( "/bob/events", snapshot settings [ feed "a.example" (Just "bob") [ "3" ] ] )
                ]
    in
    describe "reconcile"
        [ test "keeps what was fetched as the account now acting, drops the rest, and empty snapshots go" <|
            \_ ->
                let
                    reconciled : EventsCache.Model
                    reconciled =
                        EventsCache.reconcile accountIdFor cache
                in
                ( keysOf reconciled
                , reconciled.snapshots |> List.concatMap (Tuple.second >> .feeds >> Dict.keys)
                )
                    |> Expect.equal ( [ "/events" ], [ "a.example", "b.example" ] )
        , test "signing out of a server forgets its events" <|
            \_ ->
                EventsCache.reconcile (\_ -> Nothing) cache
                    |> keysOf
                    |> Expect.equal [ "/events" ]
        ]


evicting : Test
evicting =
    let
        cache : EventsCache.Model
        cache =
            stored
                [ ( "/events", snapshot settings [ feed "a.example" Nothing [ "1", "2" ] ] )
                , ( "/bob/events", snapshot settings [ feed "b.example" Nothing [ "3" ] ] )
                ]
    in
    describe "evicting"
        [ test "a deleted event drops the snapshots showing it" <|
            \_ ->
                EventsCache.evictEvent "a.example" "2" cache
                    |> keysOf
                    |> Expect.equal [ "/bob/events" ]
        , test "...only on its own server" <|
            \_ ->
                EventsCache.evictEvent "b.example" "2" cache
                    |> keysOf
                    |> Expect.equal [ "/bob/events", "/events" ]
        , test "an event created on a server drops the snapshots with its events" <|
            \_ ->
                EventsCache.evictHost "b.example" cache
                    |> keysOf
                    |> Expect.equal [ "/events" ]
        , test "EvictAll forgets everything" <|
            \_ ->
                EventsCache.update EventsCache.EvictAll cache
                    |> keysOf
                    |> Expect.equal []
        , test "Evict forgets one page's" <|
            \_ ->
                EventsCache.update (EventsCache.Evict "/events") cache
                    |> keysOf
                    |> Expect.equal [ "/bob/events" ]
        ]


storing : Test
storing =
    describe "Store"
        [ test "replaces the page's snapshot and keeps the most recent first, a bounded number" <|
            \_ ->
                let
                    many : EventsCache.Model
                    many =
                        List.range 1 12
                            |> List.map (\i -> ( "/p" ++ String.fromInt i, snapshot settings [ feed "a.example" Nothing [ "1" ] ] ))
                            |> stored
                in
                ( List.length many.snapshots
                , List.head (keysOf (EventsCache.update (EventsCache.Store "/p9" (snapshot settings [])) many))
                )
                    |> Expect.equal ( 8, Just "/p9" )
        , test "a feed is cacheable only when it is the host's own and not being replaced" <|
            \_ ->
                ( EventsCache.isCacheable "a" { host = "a", refreshing = False }
                , EventsCache.isCacheable "a" { host = "a", refreshing = True }
                , EventsCache.isCacheable "a/user/1" { host = "a", refreshing = False }
                )
                    |> Expect.equal ( True, False, False )
        ]
