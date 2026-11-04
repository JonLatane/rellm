module CountabilibarTests exposing (suite)

{-| `Shared.Countabilibar`'s pure core: counting (idempotent, sorted highest-first), removing, hiding and
showing servers/users (with their cached counts), and `syncMsg` -- the diff pages send after every update
to keep the counts in step with what they show.
-}

import Dict
import Expect
import Proto.Rellm exposing (Author, defaultAuthor)
import Set
import Shared.Countabilibar as Countabilibar exposing (Kind(..), Model, Msg(..))
import Test exposing (Test, describe, test)


author : String -> Author
author userId =
    { defaultAuthor | userId = userId, username = Just ("user-" ++ userId) }


alice : Author
alice =
    author "alice"


bob : Author
bob =
    author "bob"


apply : List Msg -> Model -> Model
apply msgs model =
    List.foldl (\msg acc -> Countabilibar.update msg acc |> Tuple.first) model msgs


counted : List Msg -> Model
counted msgs =
    apply msgs Countabilibar.init


{-| Every server's host with its `( posts, events )`, in the order they're listed.
-}
servers : Model -> List ( String, ( Int, Int ) )
servers model =
    List.map (\server -> ( server.host, ( server.postCount, server.eventCount ) )) model.serverCounts


{-| Every user on `host` with their `( posts, events )`, in the order they're listed.
-}
authorsOn : String -> Model -> List ( String, ( Int, Int ) )
authorsOn host model =
    model.serverCounts
        |> List.filter (\server -> server.host == host)
        |> List.concatMap .authorCounts
        |> List.map (\counts -> ( counts.author.userId, ( counts.postCount, counts.eventCount ) ))


suite : Test
suite =
    describe "Shared.Countabilibar"
        [ describe "counting"
            [ test "counts posts and events separately, per user and per server" <|
                \_ ->
                    counted
                        [ CountPost "a.example" alice "p1"
                        , CountPost "a.example" alice "p2"
                        , CountEvent "a.example" alice "e1"
                        , CountPost "a.example" bob "p3"
                        ]
                        |> (\model -> ( servers model, authorsOn "a.example" model ))
                        |> Expect.equal
                            ( [ ( "a.example", ( 3, 1 ) ) ]
                            , [ ( "alice", ( 2, 1 ) ), ( "bob", ( 1, 0 ) ) ]
                            )
            , test "counting the same id twice changes nothing" <|
                \_ ->
                    counted [ CountPost "a.example" alice "p1", CountPost "a.example" alice "p1", CountPosts "a.example" [ ( alice, "p1" ) ] ]
                        |> servers
                        |> Expect.equal [ ( "a.example", ( 1, 0 ) ) ]
            , test "a batch counts like the same messages one at a time" <|
                \_ ->
                    counted [ CountPosts "a.example" [ ( alice, "p1" ), ( bob, "p2" ) ], CountEvents "b.example" [ ( alice, "e1" ) ] ]
                        |> Expect.equal
                            (counted
                                [ CountPost "a.example" alice "p1"
                                , CountPost "a.example" bob "p2"
                                , CountEvent "b.example" alice "e1"
                                ]
                            )
            , test "servers and users are listed highest-first, whatever order they were counted in" <|
                \_ ->
                    counted
                        [ CountPost "small.example" alice "p1"
                        , CountPosts "big.example" [ ( alice, "p2" ), ( bob, "p3" ), ( bob, "p4" ), ( bob, "p5" ) ]
                        , CountEvents "mid.example" [ ( alice, "e1" ), ( alice, "e2" ) ]
                        ]
                        |> (\model -> ( List.map Tuple.first (servers model), List.map Tuple.first (authorsOn "big.example" model) ))
                        |> Expect.equal ( [ "big.example", "mid.example", "small.example" ], [ "bob", "alice" ] )
            , test "a batch in one message is the same as a Batch of single ones" <|
                \_ ->
                    counted [ Batch [ CountPost "a.example" alice "p1", CountPost "a.example" bob "p2" ] ]
                        |> servers
                        |> Expect.equal [ ( "a.example", ( 2, 0 ) ) ]
            ]
        , describe "removing"
            [ test "RemovePost takes one id off; a user (then server) with nothing left disappears" <|
                \_ ->
                    counted [ CountPosts "a.example" [ ( alice, "p1" ), ( alice, "p2" ) ], RemovePost "a.example" alice "p1" ]
                        |> servers
                        |> Expect.equal [ ( "a.example", ( 1, 0 ) ) ]
            , test "removing the last one takes the server off the list" <|
                \_ ->
                    counted [ CountPost "a.example" alice "p1", RemovePost "a.example" alice "p1" ]
                        |> .serverCounts
                        |> Expect.equal []
            , test "RemovePost leaves events alone, and RemoveEvent leaves posts alone" <|
                \_ ->
                    counted [ CountPost "a.example" alice "x", CountEvent "a.example" alice "y", RemovePost "a.example" alice "y", RemoveEvent "a.example" alice "x" ]
                        |> servers
                        |> Expect.equal [ ( "a.example", ( 1, 1 ) ) ]
            , test "RemoveAuthor and RemoveHost drop everything counted for them" <|
                \_ ->
                    counted
                        [ CountPost "a.example" alice "p1"
                        , CountPost "a.example" bob "p2"
                        , CountPost "b.example" alice "p3"
                        , RemoveAuthor "a.example" alice
                        , RemoveHost "b.example"
                        ]
                        |> (\model -> ( servers model, authorsOn "a.example" model ))
                        |> Expect.equal ( [ ( "a.example", ( 1, 0 ) ) ], [ ( "bob", ( 1, 0 ) ) ] )
            , test "Reset forgets everything, hidden or not" <|
                \_ ->
                    counted [ CountPost "a.example" alice "p1", CountPost "b.example" bob "p2", HideHost "b.example", HideAuthor "a.example" alice, Reset ]
                        |> (\model -> ( ( model.serverCounts, model.hiddenHosts ), ( model.hiddenAuthors, Countabilibar.hidden model ) ))
                        |> Expect.equal ( ( [], [] ), ( [], Countabilibar.noneHidden ) )
            ]
        , describe "hiding hosts"
            [ test "HideHost moves a server's counts into the hidden cache" <|
                \_ ->
                    counted [ CountPosts "a.example" [ ( alice, "p1" ), ( bob, "p2" ) ], CountEvent "b.example" alice "e1", HideHost "a.example" ]
                        |> (\model -> ( servers model, List.map (\server -> ( server.host, server.postCount )) model.hiddenHosts ))
                        |> Expect.equal ( [ ( "b.example", ( 0, 1 ) ) ], [ ( "a.example", 2 ) ] )
            , test "counts for a hidden host are ignored" <|
                \_ ->
                    counted [ CountPost "a.example" alice "p1", HideHost "a.example", CountPost "a.example" alice "p2" ]
                        |> servers
                        |> Expect.equal []
            , test "ShowHost restores the cached counts" <|
                \_ ->
                    counted [ CountPosts "a.example" [ ( alice, "p1" ), ( bob, "p2" ) ], HideHost "a.example", ShowHost "a.example" ]
                        |> (\model -> ( servers model, model.hiddenHosts ))
                        |> Expect.equal ( [ ( "a.example", ( 2, 0 ) ) ], [] )
            , test "ToggleHostVisibility hides, then shows" <|
                \_ ->
                    let
                        hiddenOnce : Model
                        hiddenOnce =
                            counted [ CountPost "a.example" alice "p1", ToggleHostVisibility "a.example" ]
                    in
                    ( Countabilibar.isHostHidden (Countabilibar.hidden hiddenOnce) "a.example"
                    , Countabilibar.isHostHidden (Countabilibar.hidden (apply [ ToggleHostVisibility "a.example" ] hiddenOnce)) "a.example"
                    )
                        |> Expect.equal ( True, False )
            , test "hiding a host twice keeps the first cache" <|
                \_ ->
                    counted [ CountPost "a.example" alice "p1", HideHost "a.example", HideHost "a.example" ]
                        |> .hiddenHosts
                        |> List.map .postCount
                        |> Expect.equal [ 1 ]
            ]
        , describe "hiding users"
            [ test "HideAuthor caches the user's counts and takes them out of the server's" <|
                \_ ->
                    counted [ CountPosts "a.example" [ ( alice, "p1" ), ( alice, "p2" ), ( bob, "p3" ) ], HideAuthor "a.example" alice ]
                        |> (\model ->
                                ( servers model
                                , List.map (\( host, counts ) -> ( host, counts.author.userId, counts.postCount )) model.hiddenAuthors
                                )
                           )
                        |> Expect.equal ( [ ( "a.example", ( 1, 0 ) ) ], [ ( "a.example", "alice", 2 ) ] )
            , test "counts for a hidden user are ignored, others' aren't" <|
                \_ ->
                    counted [ CountPost "a.example" alice "p1", HideAuthor "a.example" alice, CountPost "a.example" alice "p2", CountPost "a.example" bob "p3" ]
                        |> (\model -> authorsOn "a.example" model)
                        |> Expect.equal [ ( "bob", ( 1, 0 ) ) ]
            , test "ShowAuthor restores them" <|
                \_ ->
                    counted [ CountPosts "a.example" [ ( alice, "p1" ), ( alice, "p2" ), ( bob, "p3" ) ], HideAuthor "a.example" alice, ShowAuthor "a.example" alice ]
                        |> (\model -> ( authorsOn "a.example" model, model.hiddenAuthors ))
                        |> Expect.equal ( [ ( "alice", ( 2, 0 ) ), ( "bob", ( 1, 0 ) ) ], [] )
            , test "ToggleAuthorVisibility hides, then shows" <|
                \_ ->
                    let
                        hiddenOnce : Model
                        hiddenOnce =
                            counted [ CountPost "a.example" alice "p1", ToggleAuthorVisibility "a.example" alice ]
                    in
                    ( Countabilibar.isAuthorHidden (Countabilibar.hidden hiddenOnce) "a.example" "alice"
                    , Countabilibar.isAuthorHidden (Countabilibar.hidden (apply [ ToggleAuthorVisibility "a.example" alice ] hiddenOnce)) "a.example" "alice"
                    )
                        |> Expect.equal ( True, False )
            , test "the same user on another server is a different user" <|
                \_ ->
                    counted [ CountPost "a.example" alice "p1", CountPost "b.example" alice "p2", HideAuthor "a.example" alice ]
                        |> (\model ->
                                ( Countabilibar.isAuthorHidden (Countabilibar.hidden model) "a.example" "alice"
                                , Countabilibar.isAuthorHidden (Countabilibar.hidden model) "b.example" "alice"
                                )
                           )
                        |> Expect.equal ( True, False )
            , test "hiddenAuthorIds lists a server's hidden users in a stable order" <|
                \_ ->
                    counted
                        [ CountPosts "a.example" [ ( bob, "p1" ), ( alice, "p2" ) ]
                        , HideAuthor "a.example" bob
                        , HideAuthor "a.example" alice
                        ]
                        |> (\model -> Countabilibar.hiddenAuthorIds (Countabilibar.hidden model) "a.example")
                        |> Expect.equal [ "alice", "bob" ]
            ]
        , describe "going back to a page"
            [ test "what a page had unchecked comes back when the reader returns to it" <|
                \_ ->
                    counted [ CountPosts "a.example" [ ( alice, "p1" ), ( bob, "p2" ) ], CountEvent "b.example" alice "e1", HideAuthor "a.example" bob, HideHost "b.example" ]
                        |> Countabilibar.remember "/posts"
                        |> Countabilibar.reset
                        |> Countabilibar.restore (\_ -> True) "/posts"
                        |> (\model ->
                                ( Countabilibar.hidden model
                                , List.map (\server -> ( server.host, server.eventCount )) model.hiddenHosts
                                , List.map (\( host, counts ) -> ( host, counts.author.userId, counts.postCount )) model.hiddenAuthors
                                )
                           )
                        |> Expect.equal
                            ( { hosts = Set.singleton "b.example", authors = Dict.singleton "a.example" (Set.singleton "bob") }
                            , [ ( "b.example", 1 ) ]
                            , [ ( "a.example", "bob", 1 ) ]
                            )
            , test "arriving any other way (no restore) starts with nothing unchecked" <|
                \_ ->
                    counted [ CountPost "a.example" alice "p1", HideHost "a.example" ]
                        |> Countabilibar.remember "/posts"
                        |> Countabilibar.reset
                        |> Countabilibar.hidden
                        |> Expect.equal Countabilibar.noneHidden
            , test "only the page that was left gets it back" <|
                \_ ->
                    counted [ CountPost "a.example" alice "p1", HideHost "a.example" ]
                        |> Countabilibar.remember "/posts"
                        |> Countabilibar.reset
                        |> Countabilibar.restore (\_ -> True) "/"
                        |> Countabilibar.hidden
                        |> Expect.equal Countabilibar.noneHidden
            , test "a page left with nothing unchecked forgets what it had before" <|
                \_ ->
                    let
                        left : Model
                        left =
                            counted [ CountPost "a.example" alice "p1", HideHost "a.example" ]
                                |> Countabilibar.remember "/posts"
                                |> Countabilibar.reset
                                -- Back on it, the reader checks everything again, then leaves once more.
                                |> Countabilibar.restore (\_ -> True) "/posts"
                                |> apply [ ShowHost "a.example" ]
                                |> Countabilibar.remember "/posts"
                    in
                    left
                        |> Countabilibar.reset
                        |> Countabilibar.restore (\_ -> True) "/posts"
                        |> Countabilibar.hidden
                        |> Expect.equal Countabilibar.noneHidden
            , test "a server that no longer exists is not brought back" <|
                \_ ->
                    counted [ CountPosts "a.example" [ ( alice, "p1" ) ], CountPost "gone.example" bob "p2", HideHost "gone.example", HideAuthor "a.example" alice ]
                        |> Countabilibar.remember "/posts"
                        |> Countabilibar.reset
                        |> Countabilibar.restore (\host -> host /= "gone.example") "/posts"
                        |> Countabilibar.hidden
                        |> Expect.equal { hosts = Set.empty, authors = Dict.singleton "a.example" (Set.singleton "alice") }
            ]
        , describe "what pages are told about"
            [ test "only changes to what's hidden concern pages" <|
                \_ ->
                    [ HideHost "a", ShowHost "a", HideAuthor "a" alice, ShowAuthor "a" alice, Reset, Batch [ CountPost "a" alice "p", HideHost "a" ] ]
                        |> List.map Countabilibar.affectsPages
                        |> Expect.equal (List.repeat 6 True)
            , test "counts, panel toggles and animation plumbing don't" <|
                \_ ->
                    [ CountPost "a" alice "p", CountPosts "a" [], RemovePost "a" alice "p", TogglePanel "a", ClosePanel, EntryRemoved "s:a", MoveSettled "s:a" ]
                        |> List.map Countabilibar.affectsPages
                        |> Expect.equal (List.repeat 7 False)
            ]
        , describe "the popover"
            [ test "opens for a server and closes again" <|
                \_ ->
                    counted [ CountPost "a.example" alice "p1", TogglePanel "a.example" ]
                        |> (\model -> ( model.openHost, (apply [ TogglePanel "a.example" ] model).openHost ))
                        |> Expect.equal ( Just "a.example", Nothing )
            , test "a hidden server's popover still lists its users, all hidden" <|
                \_ ->
                    counted [ CountPosts "a.example" [ ( alice, "p1" ), ( bob, "p2" ), ( bob, "p3" ) ], HideHost "a.example" ]
                        |> Countabilibar.popoverUsers "a.example"
                        |> Expect.equal [ ( "bob", False, 2 ), ( "alice", False, 1 ) ]
            , test "closes by itself once its server has nothing left" <|
                \_ ->
                    counted [ CountPost "a.example" alice "p1", TogglePanel "a.example", RemovePost "a.example" alice "p1" ]
                        |> .openHost
                        |> Expect.equal Nothing
            ]
        , describe "entries"
            [ test "one per server with several; one per user with a single one" <|
                \_ ->
                    ( counted [ CountPost "a.example" alice "p1", CountPost "b.example" bob "p2" ]
                    , counted [ CountPost "a.example" alice "p1", CountPost "a.example" bob "p2" ]
                    )
                        |> Tuple.mapBoth entryKeys entryKeys
                        |> Expect.equal ( [ "s:a.example", "s:b.example" ], [ "u:a.example|alice", "u:a.example|bob" ] )
            , test "a hidden server stays listed (to be shown again), even if it's the only one" <|
                \_ ->
                    counted [ CountPost "a.example" alice "p1", HideHost "a.example" ]
                        |> entryKeys
                        |> Expect.equal [ "s:a.example" ]
            , test "a server whose users are all hidden stays listed, with no counts" <|
                \_ ->
                    counted [ CountPost "a.example" alice "p1", CountPost "b.example" bob "p2", HideAuthor "a.example" alice ]
                        |> entryKeys
                        |> Expect.equal [ "s:b.example", "s:a.example" ]
            , test "when the last entry goes, none is left to show" <|
                \_ ->
                    counted [ CountPost "a.example" alice "p1", RemovePost "a.example" alice "p1" ]
                        |> (\model -> List.filter (\entry -> not entry.flip.removing) (Dict.values model.entries))
                        |> List.length
                        |> Expect.equal 0
            ]
        , describe "syncMsg"
            [ test "counts what's shown and isn't counted yet" <|
                \_ ->
                    Countabilibar.syncMsg PostsKind Set.empty (Dict.fromList [ ( "a.example", [ ( alice, "p1" ), ( bob, "p2" ) ] ) ]) Countabilibar.init
                        |> Expect.equal (Just (Batch [ CountPosts "a.example" [ ( alice, "p1" ), ( bob, "p2" ) ] ]))
            , test "says nothing once they agree -- applying its message makes the next call Nothing" <|
                \_ ->
                    let
                        shown : Dict.Dict String (List ( Author, String ))
                        shown =
                            Dict.fromList [ ( "a.example", [ ( alice, "p1" ), ( bob, "p2" ) ] ), ( "b.example", [ ( alice, "p3" ) ] ) ]
                    in
                    Countabilibar.syncMsg PostsKind Set.empty shown Countabilibar.init
                        |> Maybe.map (\msg -> apply [ msg ] Countabilibar.init)
                        |> Maybe.andThen (Countabilibar.syncMsg PostsKind Set.empty shown)
                        |> Expect.equal Nothing
            , test "removes what's counted but no longer shown" <|
                \_ ->
                    counted [ CountPosts "a.example" [ ( alice, "p1" ), ( bob, "p2" ) ] ]
                        |> Countabilibar.syncMsg PostsKind Set.empty (Dict.fromList [ ( "a.example", [ ( alice, "p1" ) ] ) ])
                        |> Expect.equal (Just (Batch [ RemovePost "a.example" bob "p2" ]))
            , test "a server shown nothing of loses all its counts" <|
                \_ ->
                    counted [ CountPosts "a.example" [ ( alice, "p1" ) ] ]
                        |> Countabilibar.syncMsg PostsKind Set.empty Dict.empty
                        |> Expect.equal (Just (Batch [ RemovePost "a.example" alice "p1" ]))
            , test "only touches its own kind: events counted stay when posts are synced" <|
                \_ ->
                    counted [ CountEvent "a.example" alice "e1" ]
                        |> Countabilibar.syncMsg PostsKind Set.empty Dict.empty
                        |> Expect.equal Nothing
            , test "events are synced against events only" <|
                \_ ->
                    counted [ CountPost "a.example" alice "p1" ]
                        |> Countabilibar.syncMsg EventsKind Set.empty (Dict.fromList [ ( "a.example", [ ( alice, "e1" ) ] ) ])
                        |> Expect.equal (Just (Batch [ CountEvents "a.example" [ ( alice, "e1" ) ] ]))
            , test "leaves a pending host alone, in both directions" <|
                \_ ->
                    counted [ CountPost "a.example" alice "p1" ]
                        |> Countabilibar.syncMsg PostsKind (Set.fromList [ "a.example", "b.example" ]) (Dict.fromList [ ( "b.example", [ ( bob, "p2" ) ] ) ])
                        |> Expect.equal Nothing
            , test "never counts what's hidden, even if a page still shows it" <|
                \_ ->
                    counted [ CountPosts "a.example" [ ( alice, "p1" ), ( bob, "p2" ) ], HideAuthor "a.example" alice, HideHost "b.example" ]
                        |> Countabilibar.syncMsg PostsKind
                            Set.empty
                            (Dict.fromList [ ( "a.example", [ ( alice, "p1" ), ( bob, "p2" ) ] ), ( "b.example", [ ( bob, "p9" ) ] ) ])
                        |> Expect.equal Nothing
            , test "an id moving to another user is a removal and an addition" <|
                \_ ->
                    counted [ CountPost "a.example" alice "p1" ]
                        |> Countabilibar.syncMsg PostsKind Set.empty (Dict.fromList [ ( "a.example", [ ( bob, "p1" ) ] ) ])
                        |> Expect.equal (Just (Batch [ CountPosts "a.example" [ ( bob, "p1" ) ], RemovePost "a.example" alice "p1" ]))
            ]
        ]


entryKeys : Model -> List String
entryKeys model =
    model.entries
        |> Dict.values
        |> List.filter (\entry -> not entry.flip.removing)
        |> List.sortBy (\entry -> ( negate (entry.data.posts + entry.data.events), entry.data.key ))
        |> List.map (.data >> .key)
