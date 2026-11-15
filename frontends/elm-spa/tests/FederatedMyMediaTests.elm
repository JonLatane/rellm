module FederatedMyMediaTests exposing (suite)

{-| `Components.FederatedMyMedia.itemsOf`: which attachments of a list of posts become tiles.
-}

import Components.FederatedMyMedia as FederatedMyMedia exposing (Kind(..))
import Expect
import Proto.Rellm exposing (MediaReference, Post, defaultMediaReference, defaultMediaSize, defaultPost)
import Test exposing (Test, describe, test)


reference : String -> String -> MediaReference
reference id contentType =
    { defaultMediaReference | id = id, sizes = [ { defaultMediaSize | contentType = contentType } ] }


post : String -> List MediaReference -> Post
post id media =
    { defaultPost | id = id, media = media }


suite : Test
suite =
    describe "Components.FederatedMyMedia.itemsOf"
        [ test "images, video and audio each become a tile, tagged by kind and post-scoped" <|
            \_ ->
                [ post "p1" [ reference "a" "image/*", reference "b" "video/*" ], post "p2" [ reference "c" "audio/*" ] ]
                    |> FederatedMyMedia.itemsOf
                    |> List.map (\item -> ( item.id, item.kind ))
                    |> Expect.equal [ ( "p1/a", ImageKind ), ( "p1/b", VideoKind ), ( "p2/c", AudioKind ) ]
        , test "other attachments and posts without media are skipped" <|
            \_ ->
                [ post "p1" [ reference "a" "application/pdf" ], post "p2" [] ]
                    |> FederatedMyMedia.itemsOf
                    |> Expect.equal []
        ]
