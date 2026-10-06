module Components.Pages.ServerInformationPage.ThemeTab.CustomCssTemplates exposing (Template, all, matching, placeholder)

{-| Starter stylesheets for the Theme tab's Custom CSS editor (see `CustomCssConfiguration`'s "Apply
Template" dropdown) -- four looks (Art Deco, Bauhaus, Serif Fonts, Standard Style), each in a version with
no images, one image, and two images. Pure data: no `Msg`, no `Shared`, just `Template`s.

Every template is plain CSS appended after the app's own, written against the app's real structure (`html`,
`body`, the `.container > main` content column, the sticky `.navbar`, `.post-card`/`.event-card`/`.user-card`,
`.section-title`) and its theme variables (`--bg`, `--fg`, `--muted`, `--border`, `--chip-bg`), so each one
follows light/dark mode on its own. Per-server brand colors (nav, links) still come from the server's own
colors -- a template decorates around them rather than replacing them.

**Images** are the admin's `CustomCSSConfiguration.media_ids`, exposed as `--custom-media-1`,
`--custom-media-2` (each a full `url("...")`, so `background: var(--custom-media-1) ...` works as-is).
Image 1 is always the page background; image 2 is a "masthead" band across the top of the content column
(or, in `Standard Style (2 background images)`, a second background that fades in as you scroll). Every use
has a `none` fallback, so a template applied before its images are picked still renders (just without them).

Two effects are shared by the image templates, both progressive enhancement:

  - **Drift parallax** (`pageImage`): the background image sits in a fixed layer a little taller than the
    viewport and, where the browser supports scroll-driven animations (`animation-timeline: scroll()`), slides
    slowly against the page as it scrolls. Elsewhere it's simply a fixed background.
  - **Window parallax** (`masthead`): the masthead uses `background-attachment: fixed`, so the picture stays
    put while the band scrolls over it. (iOS ignores `fixed`; there it scrolls with the page.)

Both switch off under `prefers-reduced-motion: reduce`. Nothing here loads external fonts or files --
typefaces are system font stacks, so a template never makes visitors' browsers call out to a third party.

-}


type alias Template =
    { name : String

    -- How many images (`--custom-media-N`) the CSS uses -- the editor reminds the admin to choose that many.
    , imageCount : Int
    , css : String
    }


{-| The dropdown's own top, disabled item.
-}
placeholder : String
placeholder =
    "Apply Template"


{-| In the dropdown's order.
-}
all : List Template
all =
    [ template "Art Deco" 0 (artDeco 0)
    , template "Art Deco (1 image)" 1 (artDeco 1)
    , template "Art Deco (2 images)" 2 (artDeco 2)
    , template "Bauhaus" 0 (bauhaus 0)
    , template "Bauhaus (1 image)" 1 (bauhaus 1)
    , template "Bauhaus (2 images)" 2 (bauhaus 2)
    , template "Serif Fonts" 0 (serifFonts 0)
    , template "Serif Fonts (1 image)" 1 (serifFonts 1)
    , template "Serif Fonts (2 images)" 2 (serifFonts 2)
    , template "Standard Style" 0 (standardStyle 0)
    , template "Standard Style (1 background image)" 1 (standardStyle 1)
    , template "Standard Style (2 background images)" 2 (standardStyle 2)
    ]


template : String -> Int -> String -> Template
template name imageCount css =
    { name = name, imageCount = imageCount, css = css }


{-| The template whose CSS is exactly `css` -- i.e. one that was just applied and not yet edited. Lets the
editor keep nudging the admin about images until the template's own CSS is changed.
-}
matching : String -> Maybe Template
matching css =
    all |> List.filter (\t -> t.css == css) |> List.head



-- ART DECO


{-| Gold filigree on the page's own light/dark ground: a sunburst fanning from the top of the page, double-ruled
gold frames around the column and every card, wide-tracked uppercase headings in a geometric sans (Futura and
friends -- the Deco typeface), and a doubled gold rule under the nav.
-}
artDeco : Int -> String
artDeco images =
    String.join "\n"
        [ """/* Art Deco -- gold filigree, double rules, geometric capitals. */
:root {
  --deco-gold: #c9a227;
  --deco-gold-soft: color-mix(in srgb, #c9a227 24%, transparent);
}

body {
  font-family: "Futura", "Avenir Next", "Century Gothic", "Trebuchet MS", "Segoe UI", sans-serif;
}

h1, h2, h3, .section-title, .post-card-title {
  text-transform: uppercase;
  letter-spacing: 0.14em;
  font-weight: 600;
}

.section-title {
  color: var(--deco-gold);
  border-bottom: 1px solid var(--deco-gold);
  padding-bottom: 0.25rem;
}

/* A doubled gold rule under the nav (its own colors still come from the server's theme). */
.navbar {
  border-bottom: 4px double var(--deco-gold);
}

/* The content column: a double gold frame, floating slightly off the page. */
.container {
  margin-top: 10px;
  margin-bottom: 10px;
  background: color-mix(in srgb, var(--bg) 90%, transparent);
  box-shadow: 0 0 0 1px var(--deco-gold), 0 0 0 5px var(--bg), 0 0 0 6px var(--deco-gold);
}

/* Cards: a gold keyline, a gap, and a second keyline -- the classic Deco double frame. */
.post-card, .event-card, .user-card {
  border: none;
  border-radius: 0;
  padding: 0.9rem 1.1rem;
  box-shadow: inset 0 0 0 1px var(--deco-gold), inset 0 0 0 4px var(--bg), inset 0 0 0 5px var(--deco-gold);
}

main button:not(.remove-btn) {
  border-radius: 0;
  border-color: var(--deco-gold);
}
"""
        , if images == 0 then
            """
/* Page background: a sunburst fanning down from the top-center, fading out over the first screenful. */
html {
  background:
    linear-gradient(to bottom, transparent 0, var(--bg) 85vh),
    repeating-conic-gradient(from 0deg at 50% 0%, var(--deco-gold-soft) 0deg 3deg, transparent 3deg 9deg),
    var(--bg);
  background-attachment: fixed;
}
body { background: transparent; }
"""

          else
            pageImage
                { filter = "sepia(0.25) saturate(1.1)"
                , overlay = "linear-gradient(135deg, color-mix(in srgb, #c9a227 20%, transparent), transparent 55%), color-mix(in srgb, var(--bg) 78%, transparent)"
                , note = "Image 1 (--custom-media-1): the page background, warmed with a gold wash."
                }
        , if images >= 2 then
            masthead
                { note = "Image 2 (--custom-media-2): a framed gold masthead above the content."
                , height = "13rem"
                , filter = "sepia(0.2) contrast(1.05)"
                , overlay = "linear-gradient(transparent 60%, color-mix(in srgb, var(--bg) 70%, transparent))"
                , extra = "border: 1px solid var(--deco-gold); outline: 1px solid var(--deco-gold); outline-offset: 4px; margin: 6px 6px 1.4rem;"
                }

          else
            ""
        ]



-- BAUHAUS


{-| Primary colors and hard geometry: a red circle, blue square and yellow triangle fixed in the page corners,
thick black rules, zero-radius cards with offset hard shadows, lowercase heavy headings (Bayer's "universal
alphabet" was all lowercase), and a red/yellow/blue stripe under the nav.
-}
bauhaus : Int -> String
bauhaus images =
    String.join "\n"
        [ """/* Bauhaus -- primary colors, hard edges, lowercase sans. */
:root {
  --bauhaus-red: #e03a2f;
  --bauhaus-yellow: #f4c20d;
  --bauhaus-blue: #1d4ed8;
}

body {
  font-family: "Futura", "Century Gothic", "Helvetica Neue", Helvetica, Arial, sans-serif;
}

h1, h2, h3, .section-title, .post-card-title {
  text-transform: lowercase;
  font-weight: 800;
  letter-spacing: -0.01em;
}

.section-title {
  color: var(--fg);
  border-left: 0.6rem solid var(--bauhaus-red);
  padding-left: 0.5rem;
}

/* The nav gets a red / yellow / blue stripe along its bottom edge. */
.navbar {
  border-bottom: 6px solid;
  border-image: linear-gradient(90deg, var(--bauhaus-red) 0 33.4%, var(--bauhaus-yellow) 33.4% 66.7%, var(--bauhaus-blue) 66.7%) 1;
}

.container {
  background: var(--bg);
  border-left: 4px solid var(--fg);
  border-right: 4px solid var(--fg);
}

/* Cards: a thick black outline with a hard offset shadow that "lifts" on hover. (`!important`: the server's
   brand-color utility classes would otherwise tint the outline.) */
.post-card, .event-card, .user-card {
  border: 3px solid var(--fg);
  border-color: var(--fg) !important;
  border-radius: 0;
  box-shadow: 6px 6px 0 var(--bauhaus-red);
  transition: transform 0.12s ease, box-shadow 0.12s ease;
}
.post-card:hover, .event-card:hover, .user-card:hover {
  transform: translate(-2px, -2px);
  box-shadow: 8px 8px 0 var(--bauhaus-red);
}

main button:not(.remove-btn) {
  border-radius: 0;
  border: 2px solid var(--fg);
  font-weight: 700;
}
"""
        , if images == 0 then
            """
/* Page background: a red circle, blue square and yellow triangle fixed in the corners (the column covers
   them on narrow screens -- they show around it on wide ones). */
html {
  background-color: var(--bg);
  background-image:
    radial-gradient(circle, var(--bauhaus-red) 0 69%, transparent 70%),
    linear-gradient(var(--bauhaus-blue), var(--bauhaus-blue)),
    linear-gradient(to top right, var(--bauhaus-yellow) 49.5%, transparent 50%);
  background-size: 22vmin 22vmin, 14vmin 14vmin, 26vmin 26vmin;
  background-position: 96% 14%, 3% 82%, 98% 98%;
  background-repeat: no-repeat;
  background-attachment: fixed;
}
body { background: transparent; }
"""

          else
            pageImage
                { filter = "grayscale(1) contrast(1.25)"
                , overlay = "linear-gradient(135deg, color-mix(in srgb, var(--bauhaus-red) 30%, transparent), color-mix(in srgb, var(--bauhaus-blue) 26%, transparent)), color-mix(in srgb, var(--bg) 55%, transparent)"
                , note = "Image 1 (--custom-media-1): the page background, in hard black-and-white under a red-to-blue wash."
                }
        , if images >= 2 then
            masthead
                { note = "Image 2 (--custom-media-2): a black-and-white masthead with a hard yellow shadow."
                , height = "12rem"
                , filter = "none"
                , overlay = "linear-gradient(transparent, transparent)"

                -- Grayscale via a `luminosity` blend over white rather than `filter: grayscale()`, which
                -- would also drain the color out of the yellow shadow.
                , extra = "background-color: #fff; background-blend-mode: normal, luminosity; border: 3px solid var(--fg); box-shadow: 8px 8px 0 var(--bauhaus-yellow); margin: 4px 8px 1.6rem 4px;"
                }

          else
            ""
        ]



-- SERIF FONTS


{-| A bookish page: old-style serif faces (Iowan Old Style / Palatino / Georgia -- all system fonts), a slightly
larger measure with generous leading, small-caps section labels, hairline-ruled card lists instead of boxes,
underlined links, a drop cap on post bodies, and a soft paper tone. Images are treated like old photographs
(sepia, vignette).
-}
serifFonts : Int -> String
serifFonts images =
    String.join "\n"
        [ """/* Serif Fonts -- a quiet, bookish page. */
body {
  font-family: "Iowan Old Style", "Palatino Linotype", Palatino, "Book Antiqua", Georgia, "Times New Roman", serif;
  font-size: 1.06rem;
  line-height: 1.6;
}

h1, h2, h3, .post-card-title {
  font-weight: 600;
  letter-spacing: 0.005em;
  line-height: 1.25;
}

.section-title {
  text-transform: none;
  font-variant: all-small-caps;
  letter-spacing: 0.1em;
  font-size: 1rem;
}

/* Underlined links read as links in running text; the nav keeps its own look. */
main a {
  text-decoration: underline;
  text-decoration-thickness: 1px;
  text-underline-offset: 0.2em;
}

/* A page-like column: warm paper, a soft shadow. */
.container {
  background: color-mix(in srgb, var(--bg) 88%, #d9b779);
  box-shadow: 0 0 40px rgba(0, 0, 0, 0.18);
}

/* Cards become hairline-ruled list entries, like a table of contents. */
.post-card, .event-card, .user-card {
  border: none;
  border-top: 1px solid var(--border);
  border-radius: 0;
  padding: 1rem 0.25rem;
}

/* A drop cap on the first paragraph of a post. */
.post-detail-content p:first-of-type::first-letter {
  float: left;
  font-size: 3.2em;
  line-height: 0.85;
  padding: 0.08em 0.1em 0 0;
}

main button:not(.remove-btn) {
  font-variant: small-caps;
  letter-spacing: 0.04em;
}
"""
        , if images == 0 then
            """
/* Page background: warm paper with a faint grain. */
html {
  background:
    radial-gradient(color-mix(in srgb, var(--fg) 6%, transparent) 1px, transparent 1px) 0 0 / 4px 4px,
    color-mix(in srgb, var(--bg) 93%, #d9b779);
}
body { background: transparent; }
"""

          else
            pageImage
                { filter = "sepia(0.7) saturate(0.8) blur(1px)"
                , overlay = "color-mix(in srgb, color-mix(in srgb, var(--bg) 88%, #d9b779) 80%, transparent)"
                , note = "Image 1 (--custom-media-1): the page background, aged to sepia and washed out like an endpaper."
                }
        , if images >= 2 then
            masthead
                { note = "Image 2 (--custom-media-2): a frontispiece -- a sepia plate with a vignette and a ruled frame."
                , height = "11rem"
                , filter = "sepia(0.55) contrast(1.05)"
                , overlay = "radial-gradient(ellipse at center, transparent 45%, rgba(0, 0, 0, 0.35))"
                , extra = "border: 1px solid var(--border); outline: 1px solid var(--border); outline-offset: 4px; margin: 6px 6px 1.4rem;"
                }

          else
            ""
        ]



-- STANDARD STYLE


{-| The app's own look, polished: the default type, rounded cards with soft shadows that lift on hover, and a
frosted-glass column when there's an image behind it. With two background images, the second one
crossfades in over the first as you scroll (see `standardCrossfade`).
-}
standardStyle : Int -> String
standardStyle images =
    String.join "\n"
        [ """/* Standard Style -- the default look, with softer surfaces. */
.post-card, .event-card, .user-card {
  border-radius: 14px;
  border-color: transparent;
  background: color-mix(in srgb, var(--chip-bg) 55%, var(--bg));
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.06), 0 4px 14px rgba(0, 0, 0, 0.05);
  transition: transform 0.15s ease, box-shadow 0.15s ease;
}
.post-card:hover, .event-card:hover, .user-card:hover {
  transform: translateY(-1px);
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.08), 0 8px 22px rgba(0, 0, 0, 0.08);
}

main button:not(.remove-btn) {
  border-radius: 999px;
}
"""
        , case images of
            0 ->
                """
/* Page background: a soft wash from the chip color into the page color. */
html {
  background: linear-gradient(180deg, color-mix(in srgb, var(--chip-bg) 70%, var(--bg)), var(--bg) 45vh) fixed, var(--bg);
}
body { background: transparent; }
"""

            1 ->
                pageImage
                    { filter = "none"
                    , overlay = "color-mix(in srgb, var(--bg) 35%, transparent)"
                    , note = "Image 1 (--custom-media-1): the page background, barely tinted, behind a frosted column."
                    }
                    ++ standardFrostedColumn

            _ ->
                standardCrossfade ++ standardFrostedColumn
        ]


standardFrostedColumn : String
standardFrostedColumn =
    """
/* The content column becomes frosted glass over the background. */
.container {
  margin-top: 12px;
  margin-bottom: 12px;
  border-radius: 18px;
  background: color-mix(in srgb, var(--bg) 72%, transparent);
  -webkit-backdrop-filter: blur(14px) saturate(1.2);
  backdrop-filter: blur(14px) saturate(1.2);
}
"""


{-| `Standard Style (2 background images)`: both are page backgrounds -- image 1 fixed behind everything, image 2
layered over it and fading in as you scroll (needs scroll-driven animations; without them image 2 stays hidden
and this reads as the one-image version).
-}
standardCrossfade : String
standardCrossfade =
    """
/* Image 1 (--custom-media-1): the page background. Image 2 (--custom-media-2): a second background that
   fades in over it as you scroll down the page. */
html { background: var(--bg); }
body { background: transparent; }

html::before,
body::before {
  content: "";
  position: fixed;
  inset: 0;
  z-index: -1;
  pointer-events: none;
  background-position: center;
  background-size: cover;
  background-repeat: no-repeat;
}
html::before { background-image: var(--custom-media-1, none); }
body::before {
  background-image: var(--custom-media-2, none);
  opacity: 0;
}
/* A light wash over both so text stays readable. */
body::after {
  content: "";
  position: fixed;
  inset: 0;
  z-index: -1;
  pointer-events: none;
  background: color-mix(in srgb, var(--bg) 35%, transparent);
}

@supports (animation-timeline: scroll()) {
  body::before {
    animation: custom-css-crossfade linear both;
    animation-timeline: scroll(root);
  }
}
@keyframes custom-css-crossfade {
  from { opacity: 0; }
  to { opacity: 1; }
}
@media (prefers-reduced-motion: reduce) {
  body::before { animation: none; }
}
"""



-- SHARED EFFECTS


{-| Image 1 as the page background (see the module doc's "Drift parallax"): `body::before` is a fixed layer
`filter`ed as given and 6% taller than the viewport top and bottom (room to drift), `body::after` a fixed
`overlay` (any `background` value) on top of it, so the filter never touches the tint. `html` keeps the
page color underneath, since `body` goes transparent.
-}
pageImage : { filter : String, overlay : String, note : String } -> String
pageImage options =
    """
/* {note} */
html { background: var(--bg); }
body { background: transparent; }

body::before {
  content: "";
  position: fixed;
  inset: -6% 0;
  z-index: -1;
  pointer-events: none;
  background: var(--custom-media-1, none) center / cover no-repeat;
  filter: {filter};
}
body::after {
  content: "";
  position: fixed;
  inset: 0;
  z-index: -1;
  pointer-events: none;
  background: {overlay};
}

/* Parallax: where scroll-driven animations exist, the image drifts against the page as it scrolls. */
@supports (animation-timeline: scroll()) {
  body::before {
    animation: custom-css-drift linear both;
    animation-timeline: scroll(root);
  }
}
@keyframes custom-css-drift {
  from { transform: translateY(4%) scale(1.04); }
  to { transform: translateY(-4%) scale(1.04); }
}
@media (prefers-reduced-motion: reduce) {
  body::before { animation: none; }
}
"""
        |> String.replace "{note}" options.note
        |> String.replace "{filter}" options.filter
        |> String.replace "{overlay}" options.overlay


{-| Image 2 as a band across the top of the content column (`main::before`; see the module doc's "Window
parallax"). `overlay` is a full `<image>` (e.g. a `linear-gradient`) painted over the picture; `extra` is any
further declarations for the band (borders, margins, shadows).
-}
masthead : { note : String, height : String, filter : String, overlay : String, extra : String } -> String
masthead options =
    """
/* {note} */
main::before {
  content: "";
  display: block;
  height: {height};
  margin-bottom: 1rem;
  background: {overlay}, var(--custom-media-2, none) center / cover no-repeat fixed;
  filter: {filter};
  {extra}
}
@media (prefers-reduced-motion: reduce) {
  main::before { background-attachment: scroll; }
}
"""
        |> String.replace "{note}" options.note
        |> String.replace "{height}" options.height
        |> String.replace "{filter}" options.filter
        |> String.replace "{overlay}" options.overlay
        |> String.replace "{extra}" options.extra
