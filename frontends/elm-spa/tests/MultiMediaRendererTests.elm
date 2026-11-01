module MultiMediaRendererTests exposing (suite)

{-| A post's own page shows all of its media at the `Natural` size, whatever layout the post chose for its cards.
-}

import Components.MediaRenderer as MediaRenderer
import Components.MultiMediaRenderer as MultiMediaRenderer
import Html
import Html.Attributes
import Expect
import Proto.Rellm exposing (MediaReference, defaultMediaReference, defaultMediaSize)
import Proto.Rellm.MediaConversion exposing (MediaConversion(..))
import Proto.Rellm.PostMediaLayout exposing (PostMediaLayout(..))
import Support.RellmServerFactory as RellmServerFactory
import Test exposing (Test, describe, test)
import Test.Html.Query as Query
import Test.Html.Selector as Selector


item : String -> MediaReference
item id =
    { defaultMediaReference
        | id = id
        , url = Just ("https://rellm.org/media/" ++ id)
        , sizes = [ { defaultMediaSize | conversion = MEDIACONVERSIONORIGINAL, contentType = "video/mp4" } ]
    }


suite : Test
suite =
    describe "Components.MultiMediaRenderer"
        [ describe "viewNatural"
            [ test "stacks every item at Natural size, ignoring the post's strip layout" <|
                \_ ->
                    let
                        render : List MediaReference -> Query.Single ()
                        render media =
                            Html.div []
                                [ MultiMediaRenderer.viewNatural (RellmServerFactory.connected "rellm.org") Nothing MediaRenderer.init (\_ -> ()) (\_ -> ()) media ]
                                |> Query.fromHtml
                    in
                    Expect.all
                        [ \_ ->
                            render [ item "a", item "b", item "c" ]
                                |> Expect.all
                                    [ Query.has [ Selector.class "multi-media-gallery" ]
                                    , Query.hasNot [ Selector.class "multi-media-strip" ]
                                    , Query.findAll [ Selector.tag "rellm-video" ] >> Query.count (Expect.equal 3)
                                    , Query.findAll [ Selector.attribute (Html.Attributes.attribute "data-media-size" "natural") ] >> Query.count (Expect.equal 3)
                                    ]
                        , \_ ->
                            render [ item "a" ]
                                |> Query.find [ Selector.tag "rellm-video" ]
                                |> Query.has [ Selector.attribute (Html.Attributes.attribute "data-media-size" "natural") ]
                        ]
                        ()
            , test "the post's own layout choice still gives its multi-item view the strip" <|
                \_ ->
                    Html.div []
                        [ MultiMediaRenderer.view MEDIALAYOUTSTANDARD (RellmServerFactory.connected "rellm.org") Nothing MediaRenderer.init (\_ -> ()) (\_ -> ()) [ item "a", item "b" ] ]
                        |> Query.fromHtml
                        |> Query.has [ Selector.class "multi-media-strip" ]
            ]
        ]
