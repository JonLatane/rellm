module Federation.ActionsTests exposing (suite)

import Components.Posts as Posts
import Expect
import Json.Encode as Encode
import Proto.Rellm exposing (defaultAuthor, defaultMediaReference, defaultPost)
import Shared.AccountsPanel.MastodonAccounts exposing (MastodonAccount)
import Shared.Federation.Actions as Actions exposing (ServerAccount(..))
import Json.Decode as Decode
import Shared.Federation.Bluesky as Bluesky
import Shared.Federation.Mastodon as Mastodon
import Test exposing (Test, describe, test)


mastodonAccount : MastodonAccount
mastodonAccount =
    { instanceHost = "mastodon.social"
    , accessToken = "t"
    , refreshToken = Nothing
    , clientId = "c"
    , username = "alice"
    , sortOrder = 0
    , needsReauth = False
    , avatarUrl = Nothing
    }


postBy : String -> Proto.Rellm.Post
postBy username =
    { defaultPost | author = Just { defaultAuthor | username = Just username } }


authorOf : String -> String -> Result Decode.Error (Maybe String)
authorOf instanceHost json =
    Decode.decodeString Mastodon.decoder json
        |> Result.map (\status -> (Mastodon.toPost instanceHost status).author |> Maybe.andThen .username)


facetsJson : String -> String
facetsJson markdown =
    Encode.encode 0 (Encode.list identity (Bluesky.richText markdown).facets)


suite : Test
suite =
    describe "Federation write support"
        [ describe "Actions.isOwnPost"
            [ test "a Mastodon status by the account on its own instance is own" <|
                \_ ->
                    Actions.isOwnPost (MastodonServerAccount mastodonAccount) "mastodon:mastodon.social" (postBy "alice@mastodon.social")
                        |> Expect.equal True
            , test "the same username seen through another instance isn't (its id means nothing here)" <|
                \_ ->
                    Actions.isOwnPost (MastodonServerAccount mastodonAccount) "mastodon:other.example" (postBy "alice@other.example")
                        |> Expect.equal False
            , test "someone else's status isn't" <|
                \_ ->
                    Actions.isOwnPost (MastodonServerAccount mastodonAccount) "mastodon:mastodon.social" (postBy "bob@mastodon.social")
                        |> Expect.equal False
            ]
        , describe "Mastodon author address"
            [ test "a remote author keeps their own address, not the viewing instance's" <|
                \_ ->
                    authorOf "a.example" """{"id":"1","content":"x","created_at":"2023-04-05T12:00:00.000Z","account":{"username":"bob","display_name":"","avatar":"","acct":"bob@b.example"}}"""
                        |> Expect.equal (Ok (Just "bob@b.example"))
            , test "a local author gets the viewing instance appended" <|
                \_ ->
                    authorOf "a.example" """{"id":"1","content":"x","created_at":"2023-04-05T12:00:00.000Z","account":{"username":"bob","display_name":"","avatar":"","acct":"bob"}}"""
                        |> Expect.equal (Ok (Just "bob@a.example"))
            ]
        , describe "Posts.isDeleted"
            [ test "a post with no author, content, title, link or media is deleted" <|
                \_ -> Posts.isDeleted defaultPost |> Expect.equal True
            , test "a post with an author isn't" <|
                \_ -> Posts.isDeleted (postBy "alice") |> Expect.equal False
            , test "a post with only content isn't" <|
                \_ -> Posts.isDeleted { defaultPost | content = Just "hi" } |> Expect.equal False
            , test "a post with only media isn't" <|
                \_ -> Posts.isDeleted { defaultPost | media = [ defaultMediaReference ] } |> Expect.equal False
            ]
        , describe "Bluesky.richText"
            [ test "plain text has no facets" <|
                \_ ->
                    Expect.equal { text = "hello world", facets = "[]" }
                        { text = (Bluesky.richText "hello world").text, facets = facetsJson "hello world" }
            , test "a Markdown link becomes its label with a link facet over it" <|
                \_ ->
                    Expect.equal
                        ( "see this now"
                        , """[{"index":{"byteStart":4,"byteEnd":8},"features":[{"$type":"app.bsky.richtext.facet#link","uri":"https://example.com/a"}]}]"""
                        )
                        ( (Bluesky.richText "see [this](https://example.com/a) now").text
                        , facetsJson "see [this](https://example.com/a) now"
                        )
            , test "a bare URL gets a facet over itself, without trailing punctuation" <|
                \_ ->
                    Expect.equal
                        ( "go https://example.com/a."
                        , """[{"index":{"byteStart":3,"byteEnd":24},"features":[{"$type":"app.bsky.richtext.facet#link","uri":"https://example.com/a"}]}]"""
                        )
                        ( (Bluesky.richText "go https://example.com/a.").text
                        , facetsJson "go https://example.com/a."
                        )
            , test "offsets count UTF-8 bytes, not characters" <|
                \_ ->
                    -- "é" is 2 bytes, so the link starts at byte 3
                    facetsJson "é [x](https://a.example)"
                        |> Expect.equal """[{"index":{"byteStart":3,"byteEnd":4},"features":[{"$type":"app.bsky.richtext.facet#link","uri":"https://a.example"}]}]"""
            , test "a hashtag link turns back into a tag facet" <|
                \_ ->
                    facetsJson "[#music](https://bsky.app/hashtag/music)"
                        |> Expect.equal """[{"index":{"byteStart":0,"byteEnd":6},"features":[{"$type":"app.bsky.richtext.facet#tag","tag":"music"}]}]"""
            , test "brackets that aren't a link are left alone" <|
                \_ ->
                    (Bluesky.richText "a [b] (c)").text |> Expect.equal "a [b] (c)"
            ]
        ]
