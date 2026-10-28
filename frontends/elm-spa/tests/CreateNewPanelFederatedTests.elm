module CreateNewPanelFederatedTests exposing (suite)

{-| What `Shared.CreateNewPanel` sends when the draft is posted to a Mastodon/Bluesky account: a title, the
Markdown content and the link/quote folded into the one text those services have room for.
-}

import Expect
import Shared.CreateNewPanel as CreateNewPanel
import Shared.Federation.Actions as Actions
import Shared.Federation.Bluesky as Bluesky
import Support.PostFactory as PostFactory
import Test exposing (Test, describe, test)


draft : String -> String -> String -> CreateNewPanel.Model
draft title content link =
    let
        init : CreateNewPanel.Model
        init =
            CreateNewPanel.init
    in
    { init | title = title, content = content, link = link }


suite : Test
suite =
    describe "federated posts from the New Post panel"
        [ describe "federatedText"
            [ test "title, content and link become paragraphs, in that order" <|
                \_ ->
                    CreateNewPanel.federatedText (draft "Hello" "Some *body* text" "https://example.com/a")
                        |> Expect.equal "Hello\n\nSome *body* text\n\nhttps://example.com/a"
            , test "blank parts are left out, and the rest trimmed" <|
                \_ ->
                    CreateNewPanel.federatedText (draft "  " "  just this  " "")
                        |> Expect.equal "just this"
            , test "an empty draft says nothing" <|
                \_ -> CreateNewPanel.federatedText (draft "" "" "") |> Expect.equal ""
            , test "a quote stands in for the typed link" <|
                \_ ->
                    let
                        text : String
                        text =
                            CreateNewPanel.openQuoting "rellm.org" (PostFactory.post { id = "abc", createdAtMillis = 0 }) (draft "T" "" "https://typed.example")
                                |> CreateNewPanel.federatedText
                    in
                    ( String.contains "https://typed.example" text, String.contains "rellm.org" text )
                        |> Expect.equal ( False, True )
            ]
        , describe "Actions.postWebUrl"
            [ test "builds the bsky.app URL from the handle and the record key" <|
                \_ ->
                    Actions.postWebUrl "alice.bsky.social" "at://did:plc:abc/app.bsky.feed.post/3kxyz"
                        |> Expect.equal "https://bsky.app/profile/alice.bsky.social/post/3kxyz"
            ]
        , describe "Bluesky.graphemeCount"
            [ test "plain text counts its characters" <|
                \_ -> Bluesky.graphemeCount "hello" |> Expect.equal 5
            , test "an emoji outside the BMP is one, not two UTF-16 units" <|
                \_ -> Bluesky.graphemeCount (String.repeat 200 "😀") |> Expect.equal 200
            , test "a ZWJ sequence (a family) is one" <|
                \_ -> Bluesky.graphemeCount "👨\u{200D}👩\u{200D}👧" |> Expect.equal 1
            , test "a skin-tone modifier and a variation selector add nothing" <|
                \_ -> Bluesky.graphemeCount "👍\u{1F3FD}❤\u{FE0F}" |> Expect.equal 2
            , test "a combining accent joins its letter" <|
                \_ -> Bluesky.graphemeCount "e\u{0301}" |> Expect.equal 1
            , test "a very long draft counts without overflowing the stack" <|
                \_ -> Bluesky.graphemeCount (String.repeat 300000 "ab") |> Expect.equal 600000
            , test "a flag (two regional indicators) is one" <|
                \_ -> Bluesky.graphemeCount "\u{1F1FA}\u{1F1F8}!" |> Expect.equal 2
            ]
        ]
