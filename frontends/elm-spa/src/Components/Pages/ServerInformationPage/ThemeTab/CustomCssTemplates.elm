module Components.Pages.ServerInformationPage.ThemeTab.CustomCssTemplates exposing (Template, all, grouped, matching, placeholder)

{-| Starter stylesheets for the Theme tab's Custom CSS editor (see `CustomCssConfiguration`'s "Apply
Template" dropdown) -- twenty-four looks (Art Deco, Bauhaus, Serif Fonts, Standard Style, High Contrast, Terminal,
Newspaper, Synthwave, Midcentury Modern, Polaroid, Concert Poster, Calm, Town Square, Blueprint, Disco,
Cinematic, Dyslexia-Friendly, Field Guide, Y2K Aero, Retro Desktop, Zine, Wabi-sabi, Ocean, Forest), each in
a version with no images, one image, and two images. Pure data: no `Msg`, no `Shared`, just `Template`s.

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

**Brand colors**: `--primary-color` and `--nav-color` are the server's configured primary and navigation colors
(`#rrggbb`; defined by `/custom_css.css` and by `UI.CustomCssStylesheet`, always present). A few styles use them
for decoration that should look like *this* server -- Bauhaus (its red and blue), Serif Fonts (drop cap),
Standard Style (page wash), Concert Poster (the hot color), Town Square (bunting, tabs, card tops, masthead edge),
Retro Desktop (title bar, a dark shade of the primary color), Zine (its two riso inks) and Wabi-sabi (the seal). Every use has a fallback
(`var(--primary-color, #e03a2f)`) and is purely decorative: never body text, where a pale brand color could fail
to contrast. Styles whose identity *is* a fixed palette (Art Deco's gold, Terminal's green, Synthwave's neon, ...)
and the accessibility ones (High Contrast, Dyslexia-Friendly, Calm) leave them alone.

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

    -- The style it belongs to (its `name` without the image suffix) -- the dropdown's `<optgroup>`.
    , group : String

    -- How many images (`--custom-media-N`) the CSS uses -- the editor reminds the admin to choose that many.
    , imageCount : Int
    , css : String

    -- Whether applying the template also forces the light / dark theme (`CustomCSSConfiguration.force_light_theme` /
    -- `force_dark_theme`; at most one is ever `True`) -- for styles whose backdrop is always light or always dark,
    -- see `ForcedTheme`.
    , forceLightTheme : Bool
    , forceDarkTheme : Bool
    }


{-| Which theme, if any, a style needs the app locked to. The app derives colors that must contrast with the
page background (the server's `primaryAnchorColor`, `navAnchorColor`, ... -- see `UI.ServerTheme`) from its
effective light/dark mode, so a style whose background is *always* light or *always* dark has to say so, or
those colors get chosen for the wrong one. A style that builds its background from the page's own `--bg` (so it
follows light/dark like the app) forces nothing.
-}
type ForcedTheme
    = FollowsTheme
    | ForcesLight
    | ForcesDark


{-| The dropdown's own top, disabled item.
-}
placeholder : String
placeholder =
    "Apply Template"


{-| In the dropdown's order.
-}
all : List Template
all =
    List.concat
        [ style "Art Deco" "image" FollowsTheme artDeco
        , style "Bauhaus" "image" FollowsTheme bauhaus
        , style "Serif Fonts" "image" FollowsTheme serifFonts
        , style "Standard Style" "background image" FollowsTheme standardStyle
        , style "High Contrast" "image" FollowsTheme highContrast
        , style "Terminal" "image" ForcesDark terminal
        , style "Newspaper" "image" FollowsTheme newspaper
        , style "Synthwave" "image" ForcesDark synthwave
        , style "Midcentury Modern" "image" FollowsTheme midcenturyModern
        , style "Polaroid" "image" ForcesLight polaroid
        , style "Concert Poster" "image" FollowsTheme concertPoster
        , style "Calm" "image" FollowsTheme calm
        , style "Town Square" "image" FollowsTheme townSquare
        , style "Blueprint" "image" ForcesDark blueprint
        , style "Disco" "image" ForcesDark disco
        , style "Cinematic" "image" ForcesDark cinematic
        , style "Dyslexia-Friendly" "image" FollowsTheme dyslexiaFriendly
        , style "Field Guide" "image" FollowsTheme fieldGuide
        , style "Y2K Aero" "image" ForcesLight y2kAero
        , style "Retro Desktop" "image" ForcesLight retroDesktop
        , style "Zine" "image" ForcesLight zine
        , style "Wabi-sabi" "image" FollowsTheme wabiSabi
        , style "Ocean" "image" FollowsTheme ocean
        , style "Forest" "image" FollowsTheme forest
        ]


{-| `all`, one entry per style (in order) with that style's three templates -- the dropdown's `<optgroup>`s.
-}
grouped : List ( String, List Template )
grouped =
    all
        |> List.map .group
        |> List.foldl
            (\group seen ->
                if List.member group seen then
                    seen

                else
                    seen ++ [ group ]
            )
            []
        |> List.map (\group -> ( group, List.filter (\t -> t.group == group) all ))


{-| A style's three templates -- no images, one, two -- named `Style`, `Style (1 image)`, `Style (2 images)`
(`imageNoun` is what the dropdown calls them).
-}
style : String -> String -> ForcedTheme -> (Int -> String) -> List Template
style group imageNoun forced css =
    let
        build : String -> Int -> Template
        build name imageCount =
            { name = name
            , group = group
            , imageCount = imageCount
            , css = css imageCount
            , forceLightTheme = forced == ForcesLight
            , forceDarkTheme = forced == ForcesDark
            }
    in
    [ build group 0
    , build (group ++ " (1 " ++ imageNoun ++ ")") 1
    , build (group ++ " (2 " ++ imageNoun ++ "s)") 2
    ]


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


{-| The server's two colors and hard geometry (its primary color where Bauhaus would use red, its navigation color
where it would use blue; yellow stays): a circle, square and triangle fixed in the page corners, thick black
rules, zero-radius cards with offset hard shadows, lowercase heavy headings (Bayer's "universal alphabet" was all
lowercase), and a primary / yellow / navigation stripe under the nav.
-}
bauhaus : Int -> String
bauhaus images =
    String.join "\n"
        [ """/* Bauhaus -- primary colors, hard edges, lowercase sans. */
:root {
  --bauhaus-red: var(--primary-color, #e03a2f);
  --bauhaus-yellow: #f4c20d;
  --bauhaus-blue: var(--nav-color, #1d4ed8);
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

/* A drop cap on the first paragraph of a post, tinted toward the server's primary color. */
.post-detail-content p:first-of-type::first-letter {
  float: left;
  font-size: 3.2em;
  line-height: 0.85;
  padding: 0.08em 0.1em 0 0;
  color: color-mix(in srgb, var(--primary-color, var(--fg)) 75%, var(--fg));
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
/* Page background: a soft wash from the server's primary color into the page color. */
html {
  background: linear-gradient(180deg, color-mix(in srgb, var(--primary-color, var(--chip-bg)) 14%, var(--bg)), var(--bg) 45vh) fixed, var(--bg);
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
/* The content column becomes frosted glass over the background, with a hairline edge tinted by the server's primary color. */
.container {
  margin-top: 12px;
  margin-bottom: 12px;
  border-radius: 18px;
  border: 1px solid color-mix(in srgb, var(--primary-color, var(--border)) 35%, var(--border));
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



-- HIGH CONTRAST


{-| For readability first: large type, maximum-contrast colors (black on white, white on black -- following the
light/dark setting), thick outlines, always-underlined links, big touch targets, a loud focus ring, and every
animation off. Images are strictly decorative here: the page one is nearly washed out and static, and the
masthead is a plain bordered band -- no text ever sits on either.
-}
highContrast : Int -> String
highContrast images =
    String.join "\n"
        [ """/* High Contrast -- large type, maximum contrast, strong focus rings, no motion. */
:root {
  --fg: #000;
  --bg: #fff;
  --muted: #1a1a1a;
  --border: #000;
  --panel-bg: #fff;
  --chip-bg: #eee;
  --danger: #a00000;
}
@media (prefers-color-scheme: dark) {
  :root {
    --fg: #fff;
    --bg: #000;
    --muted: #f0f0f0;
    --border: #fff;
    --panel-bg: #000;
    --chip-bg: #1a1a1a;
    --danger: #ff8080;
  }
}
:root[data-theme="light"] {
  --fg: #000;
  --bg: #fff;
  --muted: #1a1a1a;
  --border: #000;
  --panel-bg: #fff;
  --chip-bg: #eee;
  --danger: #a00000;
}
:root[data-theme="dark"] {
  --fg: #fff;
  --bg: #000;
  --muted: #f0f0f0;
  --border: #fff;
  --panel-bg: #000;
  --chip-bg: #1a1a1a;
  --danger: #ff8080;
}

body {
  font-size: 1.2rem;
  line-height: 1.7;
  font-weight: 500;
  letter-spacing: 0.01em;
}

h1, h2, h3, .section-title, .post-card-title {
  font-weight: 800;
}

.section-title {
  color: var(--fg);
  font-size: 1.05rem;
  letter-spacing: 0.06em;
}

/* Links are always underlined and bold, never color alone. */
main a {
  text-decoration: underline;
  text-decoration-thickness: 2px;
  text-underline-offset: 0.22em;
  font-weight: 700;
}

/* A loud, consistent focus ring. */
:focus-visible {
  outline: 4px solid #ffbf00;
  outline-offset: 3px;
}

/* Big touch targets, solid outlines. */
main button:not(.remove-btn), main select, main input:not([type="checkbox"]):not([type="radio"]) {
  min-height: 44px;
  border: 2px solid var(--fg);
}

.post-card, .event-card, .user-card {
  border: 3px solid var(--fg) !important;
  border-radius: 6px;
}

.container {
  background: var(--bg);
}

/* No animation or smooth scrolling anywhere. */
*, *::before, *::after {
  animation-duration: 0.001ms !important;
  animation-iteration-count: 1 !important;
  transition-duration: 0.001ms !important;
  scroll-behavior: auto !important;
}
"""
        , if images == 0 then
            """
html { background: var(--bg); }
body { background: transparent; }
"""

          else
            pageImage
                { filter = "grayscale(1)"
                , overlay = "color-mix(in srgb, var(--bg) 94%, transparent)"
                , note = "Image 1 (--custom-media-1): a nearly washed-out, grayscale, motionless page background -- decorative only."
                }
                ++ """
body::before { animation: none !important; transform: none !important; }
"""
        , if images >= 2 then
            masthead
                { note = "Image 2 (--custom-media-2): a plain bordered band above the content -- decorative only, no text on it."
                , height = "9rem"
                , filter = "grayscale(1) contrast(1.1)"
                , overlay = "linear-gradient(transparent, transparent)"
                , extra = "border: 3px solid var(--fg); border-radius: 6px; background-attachment: scroll;"
                }

          else
            ""
        ]



-- TERMINAL


{-| Phosphor-green monospace on black -- always dark, whatever the theme setting. `> ` prompts and a blinking
cursor on headings, outlined zero-radius cards, a faint text glow, and CRT scanlines and vignette over the whole
screen (`html::after`, click-through). Images are rendered as green monochrome.
-}
terminal : Int -> String
terminal images =
    String.join "\n"
        [ """/* Terminal -- phosphor green on black, monospace, scanlines. Always dark. */
:root, :root[data-theme="light"], :root[data-theme="dark"] {
  --bg: #050a06;
  --fg: #33ff66;
  --muted: #1fae45;
  --border: #1f6f3a;
  --panel-bg: #0a140c;
  --chip-bg: #0d1a10;
  color-scheme: dark;
}

body {
  font-family: ui-monospace, "SF Mono", Menlo, Consolas, "Courier New", monospace;
  text-shadow: 0 0 6px color-mix(in srgb, var(--fg) 45%, transparent);
}

h1, h2, h3, .section-title {
  text-transform: uppercase;
  letter-spacing: 0.08em;
}
h2::before, h3::before, .section-title::before {
  content: "> ";
}
h2::after {
  content: "█";
  margin-left: 0.3em;
  animation: custom-css-blink 1.1s steps(1) infinite;
}
@keyframes custom-css-blink {
  50% { opacity: 0; }
}
@media (prefers-reduced-motion: reduce) {
  h2::after { animation: none; }
}

.navbar {
  background: var(--panel-bg) !important;
  color: var(--fg) !important;
  border-bottom: 1px solid var(--fg);
}

.container {
  background: color-mix(in srgb, var(--bg) 82%, transparent);
}

.post-card, .event-card, .user-card {
  background: transparent;
  border: 1px solid var(--fg) !important;
  border-radius: 0;
  box-shadow: 0 0 10px color-mix(in srgb, var(--fg) 25%, transparent);
}
.post-card:hover, .event-card:hover, .user-card:hover {
  background: color-mix(in srgb, var(--fg) 7%, transparent);
}

main button:not(.remove-btn) {
  border-radius: 0;
  border: 1px solid var(--fg);
}

/* CRT: scanlines plus a darkened vignette over everything, never intercepting clicks. */
html::after {
  content: "";
  position: fixed;
  inset: 0;
  z-index: 9999;
  pointer-events: none;
  background:
    repeating-linear-gradient(to bottom, transparent 0 2px, rgba(0, 0, 0, 0.22) 2px 3px),
    radial-gradient(ellipse at center, transparent 60%, rgba(0, 0, 0, 0.45));
}
"""
        , eventSurfaces
        , if images == 0 then
            """
html { background: radial-gradient(ellipse at 50% -10%, #0f2f19, var(--bg) 65%) fixed, var(--bg); }
body { background: transparent; }
"""

          else
            pageImage
                { filter = terminalGreen
                , overlay = "color-mix(in srgb, var(--bg) 80%, transparent)"
                , note = "Image 1 (--custom-media-1): the page background, turned into green monochrome."
                }
        , if images >= 2 then
            masthead
                { note = "Image 2 (--custom-media-2): a green-monochrome 'monitor' band with scanlines and a phosphor glow."
                , height = "12rem"
                , filter = terminalGreen
                , overlay = "repeating-linear-gradient(to bottom, transparent 0 2px, rgba(0, 0, 0, 0.3) 2px 3px)"
                , extra = "border: 1px solid var(--fg); box-shadow: 0 0 18px color-mix(in srgb, var(--fg) 40%, transparent);"
                }

          else
            ""
        ]


{-| The events list, strip and calendar are given a translucent background computed from the *app's* light/dark
mode (see `UI.EmittedStylesheet`), not from the page's CSS variables -- so a template that forces its own
colors (Terminal and Synthwave are always dark, Polaroid's paper is always light) has to re-point that surface at
its own `--bg`, or the calendar ends up light-on-light or dark-on-dark.
-}
eventSurfaces : String
eventSurfaces =
    """
/* Events list / strip / calendar: follow this template's page color, not the app's light/dark mode. */
.events-list:not(:has(>* .events-calendar)), .events-strip, .events-calendar {
  background-color: color-mix(in srgb, var(--bg) 73%, transparent) !important;
}
"""


terminalGreen : String
terminalGreen =
    "grayscale(1) sepia(1) hue-rotate(65deg) saturate(2.2) brightness(0.8) contrast(1.1)"



-- NEWSPAPER


{-| A broadsheet: ink on newsprint, Didot-style headlines over justified book-face text, a double rule under the
nav, hairline-ruled stories instead of boxes, a drop cap on posts, and black-and-white photos. The masthead's
photo gets a halftone screen -- tiny dots over a high-contrast grayscale, like newsprint.
-}
newspaper : Int -> String
newspaper images =
    String.join "\n"
        [ """/* Newspaper -- ink on newsprint, ruled columns, justified serif text, halftone photos. */
body {
  font-family: Georgia, "Times New Roman", Times, serif;
  font-size: 1.02rem;
  line-height: 1.55;
}

h1, h2, h3, .post-card-title {
  font-family: "Didot", "Bodoni 72", "Bodoni MT", "Playfair Display", Georgia, "Times New Roman", serif;
  font-weight: 800;
  line-height: 1.1;
  letter-spacing: -0.01em;
}

/* Section labels become a classic ruled kicker line. */
.section-title {
  color: var(--fg);
  font-size: 0.8rem;
  text-transform: uppercase;
  letter-spacing: 0.22em;
  text-align: center;
  border-top: 3px double var(--fg);
  border-bottom: 1px solid var(--fg);
  padding: 0.35rem 0;
}

.navbar {
  border-bottom: 3px double var(--fg);
}

.container {
  background: color-mix(in srgb, var(--bg) 92%, #e6dcc3);
  border-left: 1px solid var(--fg);
  border-right: 1px solid var(--fg);
}

/* Stories, ruled apart -- no boxes. */
.post-card, .event-card, .user-card {
  border: none;
  border-bottom: 1px solid var(--fg);
  border-bottom-color: var(--fg) !important;
  border-radius: 0;
  padding: 0.8rem 0;
}

/* Full post bodies are justified; card previews aren't -- a long URL on the line after a short first line
   would stretch that line's word gaps absurdly. */
.post-detail-content {
  text-align: justify;
  hyphens: auto;
}

/* A drop cap on the first paragraph of a post. */
.post-detail-content p:first-of-type::first-letter {
  float: left;
  font-family: "Didot", "Bodoni 72", "Bodoni MT", "Playfair Display", Georgia, serif;
  font-weight: 800;
  font-size: 3.6em;
  line-height: 0.8;
  padding: 0.06em 0.08em 0 0;
}
"""
        , if images == 0 then
            """
/* Page background: newsprint with a faint grain. */
html {
  background:
    radial-gradient(color-mix(in srgb, var(--fg) 5%, transparent) 1px, transparent 1px) 0 0 / 3px 3px,
    color-mix(in srgb, var(--bg) 90%, #e6dcc3);
}
body { background: transparent; }
"""

          else
            pageImage
                { filter = "grayscale(1) contrast(1.2)"
                , overlay = "color-mix(in srgb, color-mix(in srgb, var(--bg) 90%, #e6dcc3) 86%, transparent)"
                , note = "Image 1 (--custom-media-1): the page background, in black and white, washed into the newsprint."
                }
        , if images >= 2 then
            masthead
                { note = "Image 2 (--custom-media-2): the front-page photo -- high-contrast black and white under a halftone screen."
                , height = "11rem"
                , filter = "grayscale(1) contrast(1.3)"
                , overlay = "radial-gradient(circle, rgba(0, 0, 0, 0.45) 0 0.9px, transparent 1.3px) 0 0 / 4px 4px"
                , extra = "border-top: 3px double var(--fg); border-bottom: 3px double var(--fg); margin-bottom: 1.2rem;"
                }

          else
            ""
        ]



-- SYNTHWAVE


{-| Neon on deep purple -- always dark. With no images: a striped sun on a purple-to-pink sky above a perspective
grid floor that scrolls toward you (switched off for `prefers-reduced-motion`). Headings glow, cards are
neon-outlined glass over a blurred column. With images, the photo takes the sky's place under a purple-to-pink
wash (page) or a pink/cyan duotone (masthead, via a `luminosity` blend so the glow isn't desaturated).
-}
synthwave : Int -> String
synthwave images =
    String.join "\n"
        [ """/* Synthwave -- neon on deep purple, a sun and a grid. Always dark. */
:root, :root[data-theme="light"], :root[data-theme="dark"] {
  --synth-pink: #ff2bd6;
  --synth-cyan: #00e5ff;
  --synth-sun: #ffe45e;
  --bg: #0d0221;
  --fg: #f4eaff;
  --muted: #b9a3d9;
  --border: #5b2a9a;
  --panel-bg: #170536;
  --chip-bg: #1f0a45;
  color-scheme: dark;
}

body {
  font-family: "Avenir Next Condensed", "Futura", "Trebuchet MS", "Segoe UI", sans-serif;
}

h1, h2, h3, .section-title {
  text-transform: uppercase;
  font-style: italic;
  letter-spacing: 0.12em;
  text-shadow: 0 0 6px var(--synth-pink), 0 0 16px color-mix(in srgb, var(--synth-pink) 60%, transparent);
}

.navbar {
  border-bottom: 2px solid var(--synth-cyan);
  box-shadow: 0 0 18px var(--synth-pink);
}

.container {
  background: color-mix(in srgb, var(--bg) 72%, transparent);
  -webkit-backdrop-filter: blur(6px);
  backdrop-filter: blur(6px);
}

.post-card, .event-card, .user-card {
  background: color-mix(in srgb, var(--panel-bg) 85%, transparent);
  border: 1px solid var(--synth-cyan) !important;
  border-radius: 4px;
  box-shadow: 0 0 10px color-mix(in srgb, var(--synth-cyan) 45%, transparent), inset 0 0 14px color-mix(in srgb, var(--synth-pink) 18%, transparent);
}

main button:not(.remove-btn) {
  border-color: var(--synth-cyan);
}
"""
        , eventSurfaces
        , if images == 0 then
            """
/* Sky, then (html::before) a striped sun on the horizon, then (html::after) the grid floor over its lower half. */
html {
  background: linear-gradient(180deg, #0d0221 0, #2b0a4d 40%, #7a1fa2 58%, var(--synth-pink) 70%, #0d0221 70.2%) fixed;
}
body { background: transparent; }

html::before {
  content: "";
  position: fixed;
  left: 50%;
  bottom: 30%;
  z-index: -1;
  width: 30vmin;
  height: 30vmin;
  transform: translate(-50%, 50%);
  border-radius: 50%;
  pointer-events: none;
  background: linear-gradient(180deg, var(--synth-sun) 10%, var(--synth-pink) 85%);
  -webkit-mask-image: repeating-linear-gradient(180deg, #000 0 0.7rem, transparent 0.7rem 0.95rem);
  mask-image: repeating-linear-gradient(180deg, #000 0 0.7rem, transparent 0.7rem 0.95rem);
}

html::after {
  content: "";
  position: fixed;
  left: -50%;
  right: -50%;
  bottom: 0;
  z-index: -1;
  height: 30%;
  pointer-events: none;
  background:
    linear-gradient(transparent calc(100% - 2px), var(--synth-pink) 0) 0 0 / 100% 48px,
    linear-gradient(90deg, transparent calc(100% - 2px), var(--synth-pink) 0) 0 0 / 64px 100%,
    #0d0221;
  transform: perspective(320px) rotateX(58deg);
  transform-origin: 50% 0;
  -webkit-mask-image: linear-gradient(transparent, #000 45%);
  mask-image: linear-gradient(transparent, #000 45%);
  animation: custom-css-grid 2.4s linear infinite;
}
@keyframes custom-css-grid {
  to { background-position: 0 48px, 0 0, 0 0; }
}
@media (prefers-reduced-motion: reduce) {
  html::after { animation: none; }
}
"""

          else
            pageImage
                { filter = "grayscale(1) contrast(1.15)"
                , overlay = "linear-gradient(180deg, rgba(43, 10, 77, 0.82), rgba(255, 43, 214, 0.38)), rgba(13, 2, 33, 0.35)"
                , note = "Image 1 (--custom-media-1): the page background, under a purple-to-pink neon wash."
                }
        , if images >= 2 then
            masthead
                { note = "Image 2 (--custom-media-2): a pink duotone masthead (a luminosity blend over pink), cyan-washed to one side, in a neon frame."
                , height = "12rem"
                , filter = "none"
                , overlay = "linear-gradient(135deg, transparent 25%, rgba(0, 229, 255, 0.5))"
                , extra = "background-color: var(--synth-pink); background-blend-mode: normal, luminosity; border: 2px solid var(--synth-cyan); box-shadow: 0 0 0 2px var(--synth-pink), 0 0 26px var(--synth-pink); margin: 6px 6px 1.6rem;"
                }

          else
            ""
        ]



-- MIDCENTURY MODERN


{-| Atomic-age warmth: teal, orange and mustard on cream, a geometric humanist sans, asymmetric "leaf"
cards with a mustard spine and an offset teal shadow, pill buttons. With no images the background is scattered
kidney/circle shapes over a dot grid; with images, a Saul Bass-style flat two-color treatment (grayscale under a
teal-to-orange wash), and the masthead a teal-toned leaf shape.
-}
midcenturyModern : Int -> String
midcenturyModern images =
    String.join "\n"
        [ """/* Midcentury Modern -- teal, orange and mustard on cream; leaf shapes and flat color. */
:root {
  --mcm-teal: #1f8a8a;
  --mcm-orange: #e8702a;
  --mcm-mustard: #e3a826;
  --mcm-brown: #5a3a22;
}

body {
  font-family: "Avenir Next", "Gill Sans", "Optima", "Futura", "Trebuchet MS", sans-serif;
}

h1, h2, h3, .section-title, .post-card-title {
  font-weight: 700;
  letter-spacing: 0.01em;
}

.section-title {
  color: var(--mcm-teal);
}

.navbar {
  border-bottom: 5px solid var(--mcm-mustard);
}

.container {
  background: color-mix(in srgb, var(--bg) 88%, #f1e2c1);
  border-radius: 0 0 28px 28px;
}

/* Leaf-shaped cards: a mustard spine, opposite corners rounded, a flat offset teal shadow. */
.post-card, .event-card, .user-card {
  border: none;
  border-left: 8px solid var(--mcm-mustard);
  border-left-color: var(--mcm-mustard) !important;
  border-radius: 22px 4px 22px 4px;
  background: color-mix(in srgb, var(--chip-bg) 55%, var(--bg));
  box-shadow: 4px 4px 0 color-mix(in srgb, var(--mcm-teal) 55%, transparent);
}

main button:not(.remove-btn) {
  border-radius: 999px;
}
"""
        , if images == 0 then
            """
/* Page background: cream with scattered mustard, orange and teal shapes (they show around the column on wide screens) over a dot grid. */
html {
  background-color: color-mix(in srgb, var(--bg) 88%, #f1e2c1);
  background-image:
    radial-gradient(ellipse 18vmin 11vmin at 8% 22%, var(--mcm-mustard) 0 98%, transparent 100%),
    radial-gradient(circle at 94% 40%, var(--mcm-orange) 0 9vmin, transparent calc(9vmin + 1px)),
    radial-gradient(ellipse 14vmin 22vmin at 90% 88%, var(--mcm-teal) 0 98%, transparent 100%),
    radial-gradient(color-mix(in srgb, var(--mcm-brown) 18%, transparent) 1.5px, transparent 2px);
  background-size: auto, auto, auto, 22px 22px;
  background-repeat: no-repeat, no-repeat, no-repeat, repeat;
  background-attachment: fixed;
}
body { background: transparent; }
"""

          else
            pageImage
                { filter = "grayscale(1) contrast(1.5)"
                , overlay = "linear-gradient(135deg, color-mix(in srgb, var(--mcm-teal) 62%, transparent), color-mix(in srgb, var(--mcm-orange) 52%, transparent)), color-mix(in srgb, var(--bg) 30%, transparent)"
                , note = "Image 1 (--custom-media-1): the page background, flattened to two colors -- grayscale under a teal-to-orange wash."
                }
        , if images >= 2 then
            masthead
                { note = "Image 2 (--custom-media-2): a teal-toned leaf-shaped masthead with a mustard offset shadow."
                , height = "13rem"
                , filter = "none"
                , overlay = "linear-gradient(transparent, transparent)"
                , extra = "background-color: var(--mcm-teal); background-blend-mode: normal, luminosity; border-radius: 120px 14px 120px 14px; box-shadow: 8px 8px 0 var(--mcm-mustard); margin: 4px 10px 1.6rem 4px;"
                }

          else
            ""
        ]



-- POLAROID


{-| A scrapbook page: snapshots taped to a corkboard. The content column is a sheet of cream paper (light
inside regardless of the theme setting, so the dark text always has its ground), cards are white polaroid-style
prints at alternating slight tilts with a strip of tape on top (the tilt selects on each card's list-item
wrapper, `.flip-animated-item`, since a card is always its wrapper's only child), headings are handwriting
faces, and section labels are yellow tape. With no images the board is cork; with one image the photo is the
wall behind the paper; with two, the second is a big tilted polaroid at the top.
-}
polaroid : Int -> String
polaroid images =
    String.join "\n"
        [ """/* Polaroid -- snapshots taped to a corkboard. */
h1, h2, h3, .section-title, .post-card-title {
  font-family: "Bradley Hand", "Segoe Print", "Marker Felt", "Chalkboard SE", "Comic Sans MS", cursive;
  font-weight: 700;
}

/* The page: cream paper, light inside whatever the theme setting. */
.container {
  --fg: #2b2620;
  --bg: #fffdf7;
  --muted: #6b6354;
  --border: #d8cfb8;
  --panel-bg: #fffdf7;
  --chip-bg: #f0e8d6;
  color: var(--fg);
  background: var(--bg);
  margin-top: 14px;
  margin-bottom: 14px;
  box-shadow: 0 6px 24px rgba(0, 0, 0, 0.35);
}

/* Section labels as a strip of yellow tape. */
.section-title {
  display: inline-block;
  background: #ffe27a;
  color: #2b2620;
  padding: 0.15rem 0.7rem;
  transform: rotate(-1.5deg);
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.3);
}

/* Cards: white prints with a thick bottom margin, tilted, taped on. */
.post-card, .event-card, .user-card {
  background: #fff;
  border: none;
  border-radius: 3px;
  padding: 1rem 1rem 1.4rem;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.25), 0 10px 22px rgba(0, 0, 0, 0.18);
  margin: 12px 0;
  transform: rotate(-0.7deg);
  transition: transform 0.2s ease, box-shadow 0.2s ease;
}
.flip-animated-item:nth-child(even) .post-card,
.flip-animated-item:nth-child(even) .event-card,
.flip-animated-item:nth-child(even) .user-card {
  transform: rotate(0.8deg);
}
.flip-animated-item .post-card:hover,
.flip-animated-item .event-card:hover,
.flip-animated-item .user-card:hover {
  transform: rotate(0) scale(1.01);
  box-shadow: 0 4px 8px rgba(0, 0, 0, 0.3), 0 16px 30px rgba(0, 0, 0, 0.22);
}

/* The tape. */
.post-card::before, .event-card::before, .user-card::before {
  content: "";
  position: absolute;
  top: -10px;
  left: 50%;
  width: 84px;
  height: 22px;
  transform: translateX(-50%) rotate(-3deg);
  background: color-mix(in srgb, #ffe27a 70%, transparent);
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.2);
  pointer-events: none;
}
@media (prefers-reduced-motion: reduce) {
  .post-card, .event-card, .user-card { transition: none; }
}
"""
        , eventSurfaces
        , if images == 0 then
            """
/* The board: cork, from three layers of speckle. */
html {
  background:
    radial-gradient(circle at 20% 30%, rgba(0, 0, 0, 0.18) 0 1px, transparent 2px) 0 0 / 7px 7px,
    radial-gradient(circle at 70% 60%, rgba(255, 255, 255, 0.18) 0 1px, transparent 2px) 0 0 / 11px 11px,
    radial-gradient(circle at 40% 80%, rgba(0, 0, 0, 0.14) 0 1.5px, transparent 2.5px) 0 0 / 13px 13px,
    color-mix(in srgb, #b98b5a 85%, var(--bg));
  background-attachment: fixed;
}
body { background: transparent; }
"""

          else
            pageImage
                { filter = "sepia(0.35) saturate(0.9)"
                , overlay = "rgba(60, 40, 20, 0.35)"
                , note = "Image 1 (--custom-media-1): the 'wall' behind the paper, warmed and darkened."
                }
        , if images >= 2 then
            masthead
                { note = "Image 2 (--custom-media-2): a big tilted polaroid at the top of the page."
                , height = "15rem"
                , filter = "sepia(0.2)"
                , overlay = "linear-gradient(transparent, transparent)"
                , extra = "width: 88%; margin: 14px auto 2.2rem; border: 12px solid #fff; border-bottom-width: 48px; box-shadow: 0 8px 22px rgba(0, 0, 0, 0.35); transform: rotate(-1.2deg); background-attachment: scroll;"
                }

          else
            ""
        ]



-- CONCERT POSTER


{-| A gig poster: condensed Impact-style capitals, a yellow "sticker" for each section label, a hazard-stripe
under the nav, hard-edged cards with a hot-pink offset shadow, and halftone everywhere -- dots on the plain
background, a halftone duotone over the page photo, and a big skewed, halftoned masthead with a yellow shadow.
-}
concertPoster : Int -> String
concertPoster images =
    String.join "\n"
        [ """/* Concert Poster -- loud, condensed, halftone, hard color blocks. */
:root {
  --poster-hot: var(--primary-color, #ff3b5c);
  --poster-yellow: #ffd400;
}

body {
  font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
  font-weight: 600;
}

h1, h2, h3, .post-card-title {
  font-family: Impact, Haettenschweiler, "Franklin Gothic Condensed", "Arial Narrow", sans-serif;
  font-weight: 900;
  text-transform: uppercase;
  letter-spacing: 0.02em;
  line-height: 0.95;
}

/* Section labels as a stuck-on yellow sticker. */
.section-title {
  display: inline-block;
  background: var(--poster-yellow);
  color: #111;
  padding: 0.15rem 0.6rem;
  transform: rotate(-2deg);
  font-family: Impact, Haettenschweiler, "Franklin Gothic Condensed", "Arial Narrow", sans-serif;
  font-size: 1rem;
  letter-spacing: 0.08em;
}

/* A hazard stripe under the nav. */
.navbar {
  border-bottom: 8px solid;
  border-image: repeating-linear-gradient(135deg, #111 0 10px, var(--poster-yellow) 10px 20px) 1;
}

.container {
  background: color-mix(in srgb, var(--bg) 88%, transparent);
}

.post-card, .event-card, .user-card {
  border: 3px solid var(--fg);
  border-color: var(--fg) !important;
  border-radius: 0;
  box-shadow: 5px 5px 0 var(--poster-hot);
  transition: transform 0.12s ease, box-shadow 0.12s ease;
}
.post-card:hover, .event-card:hover, .user-card:hover {
  transform: translate(-2px, -2px);
  box-shadow: 7px 7px 0 var(--poster-hot);
}

main button:not(.remove-btn) {
  border-radius: 0;
  border: 2px solid var(--fg);
  font-weight: 800;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}
"""
        , if images == 0 then
            """
/* Page background: a field of hot-pink halftone dots. */
html {
  background:
    radial-gradient(circle, color-mix(in srgb, var(--poster-hot) 28%, transparent) 2px, transparent 2.6px) 0 0 / 14px 14px,
    var(--bg);
  background-attachment: fixed;
}
body { background: transparent; }
"""

          else
            pageImage
                { filter = "grayscale(1) contrast(1.4)"
                , overlay = "radial-gradient(circle, rgba(0, 0, 0, 0.35) 1px, transparent 1.6px) 0 0 / 5px 5px, linear-gradient(135deg, color-mix(in srgb, var(--poster-hot) 50%, transparent), color-mix(in srgb, var(--poster-yellow) 35%, transparent)), color-mix(in srgb, var(--bg) 40%, transparent)"
                , note = "Image 1 (--custom-media-1): the page background -- high-contrast black and white under a pink-to-yellow wash and a halftone screen."
                }
        , if images >= 2 then
            masthead
                { note = "Image 2 (--custom-media-2): a big skewed halftone masthead with a yellow offset shadow."
                , height = "15rem"
                , filter = "grayscale(1) contrast(1.5)"
                , overlay = "radial-gradient(circle, color-mix(in srgb, var(--poster-hot) 70%, transparent) 0 1.2px, transparent 1.8px) 0 0 / 6px 6px"
                , extra = "border: 4px solid var(--fg); box-shadow: 10px 10px 0 var(--poster-yellow); transform: skewY(-2deg); margin: 14px 12px 2.2rem 4px; background-attachment: scroll;"
                }

          else
            ""
        ]



-- CALM


{-| Low stimulation: soft, muted colors (a warm off-white / a soft slate, following the light/dark setting),
no motion at all, generous spacing and line height, a comfortable line length, borderless rounded cards, quiet
focus rings, and no all-caps. Images are strictly optional and subdued: the page one is desaturated and
blurred, the masthead a soft rounded band.
-}
calm : Int -> String
calm images =
    String.join "\n"
        [ "/* Calm -- low stimulation: soft colors, generous space, no motion. */\n"
            ++ themedRoot
                """  --bg: #f6f4ef;
  --fg: #2f3437;
  --muted: #5d676b;
  --border: #dcd8cf;
  --panel-bg: #faf8f3;
  --chip-bg: #ece8df;
"""
                """  --bg: #1d2125;
  --fg: #d9dde0;
  --muted: #9aa4a9;
  --border: #343b41;
  --panel-bg: #22272c;
  --chip-bg: #272d33;
"""
            ++ """
body {
  font-size: 1.08rem;
  line-height: 1.75;
  letter-spacing: 0.01em;
}

h1, h2, h3, .section-title, .post-card-title {
  text-transform: none;
  font-weight: 600;
  letter-spacing: 0.01em;
}

.section-title {
  font-size: 0.95rem;
  color: var(--muted);
}

.container {
  background: var(--bg);
}

/* Soft, borderless, rounded cards with room to breathe; nothing moves on hover. */
.post-card, .event-card, .user-card {
  border: none;
  border-radius: 16px;
  background: var(--chip-bg);
  padding: 1.1rem 1.25rem;
  margin-bottom: 0.6rem;
  box-shadow: none;
  transition: none;
}

.post-card-content-preview, .post-detail-content {
  max-width: 68ch;
}

main a {
  text-decoration: underline;
  text-underline-offset: 0.2em;
}

/* A quiet but visible focus ring. */
:focus-visible {
  outline: 3px solid color-mix(in srgb, var(--fg) 55%, transparent);
  outline-offset: 3px;
}

"""
            ++ noMotion
        , eventSurfaces
        , if images == 0 then
            """
html { background: var(--bg); }
body { background: transparent; }
"""

          else
            pageImage
                { filter = "saturate(0.5) blur(2px)"
                , overlay = "color-mix(in srgb, var(--bg) 92%, transparent)"
                , note = "Image 1 (--custom-media-1): a very quiet page background -- desaturated, blurred, barely there, and still."
                }
                ++ noDrift
        , if images >= 2 then
            masthead
                { note = "Image 2 (--custom-media-2): a soft, rounded, muted band above the content."
                , height = "9rem"
                , filter = "saturate(0.6)"
                , overlay = "linear-gradient(transparent 60%, color-mix(in srgb, var(--bg) 55%, transparent))"
                , extra = "border-radius: 16px; background-attachment: scroll;"
                }

          else
            ""
        ]


{-| Everything's animation and smooth scrolling off.
-}
noMotion : String
noMotion =
    """/* No animation or smooth scrolling anywhere. */
*, *::before, *::after {
  animation-duration: 0.001ms !important;
  animation-iteration-count: 1 !important;
  transition-duration: 0.001ms !important;
  scroll-behavior: auto !important;
}
"""


{-| Switches `pageImage`'s drift parallax off.
-}
noDrift : String
noDrift =
    """
body::before { animation: none !important; transform: none !important; }
"""



-- TOWN SQUARE


{-| Civic and friendly, wearing the server's own brand color: `--calendar-accent` is that color (the app sets
it from the server's theme), so the section labels' tab, the card tops, the bunting hung under the nav and the
masthead's edge all follow whatever the server's colors are. A plain humanist sans, tidy shadowed cards, and a
landmark photo for the masthead.
-}
townSquare : Int -> String
townSquare images =
    String.join "\n"
        [ """/* Town Square -- civic and friendly, in the server's own brand colors. */
:root {
  --civic-main: var(--primary-color, var(--calendar-accent));
  --civic-accent: var(--nav-color, var(--calendar-accent));
}

body {
  font-family: "Franklin Gothic Medium", "Gill Sans", "Trebuchet MS", "Segoe UI", sans-serif;
}

h1, h2, h3, .post-card-title {
  font-weight: 700;
  letter-spacing: 0.01em;
}

/* Section labels: a brand-colored tab. */
.section-title {
  color: var(--fg);
  font-size: 0.8rem;
  letter-spacing: 0.14em;
  border-left: 6px solid var(--civic-main);
  padding-left: 0.55rem;
}

.navbar {
  border-bottom: 4px solid rgba(255, 255, 255, 0.55);
}

/* Bunting strung under the nav, in the server's navigation color. */
.container::before {
  content: "";
  display: block;
  height: 14px;
  background: linear-gradient(135deg, var(--civic-accent) 50%, transparent 50%) 0 0 / 22px 14px repeat-x;
  opacity: 0.9;
}

.container {
  background: color-mix(in srgb, var(--bg) 92%, transparent);
  box-shadow: 0 0 0 1px var(--border);
}

.post-card, .event-card, .user-card {
  border: 1px solid var(--border);
  border-top: 5px solid var(--civic-main);
  border-top-color: var(--civic-main) !important;
  border-radius: 6px;
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.08);
}

main button:not(.remove-btn) {
  border-radius: 6px;
}
"""
        , if images == 0 then
            """
/* Page background: a gentle wash of the brand color from the top. */
html {
  background: linear-gradient(180deg, color-mix(in srgb, var(--civic-main) 14%, var(--bg)), var(--bg) 50vh) fixed, var(--bg);
}
body { background: transparent; }
"""

          else
            pageImage
                { filter = "saturate(0.9)"
                , overlay = "color-mix(in srgb, var(--bg) 62%, transparent)"
                , note = "Image 1 (--custom-media-1): a landmark photo as the page background, softened toward the page color."
                }
        , if images >= 2 then
            masthead
                { note = "Image 2 (--custom-media-2): a wide landmark banner with a brand-colored scrim and bottom edge."
                , height = "12rem"
                , filter = "none"
                , overlay = "linear-gradient(transparent 55%, color-mix(in srgb, var(--civic-main) 55%, transparent))"
                , extra = "border-bottom: 6px solid var(--civic-main); border-radius: 6px 6px 0 0;"
                }

          else
            ""
        ]



-- BLUEPRINT


{-| A technical drawing: white-blue linework on blueprint blue (always dark), a major/minor grid, monospaced
uppercase labels, hairline-outlined square cards with a dashed offset outline, and photos turned into blue
monochrome under the grid. The masthead is "a figure" -- gridded, with a ruled border.
-}
blueprint : Int -> String
blueprint images =
    String.join "\n"
        [ "/* Blueprint -- white linework on blueprint blue, a drafting grid, monospaced labels. Always dark. */\n"
            ++ forcedRoot
                """  --bp-line: rgba(190, 225, 255, 0.16);
  --bp-line-minor: rgba(190, 225, 255, 0.07);
  --bg: #0b2a4a;
  --fg: #e8f4ff;
  --muted: #8fb6dc;
  --border: #2f6aa3;
  --panel-bg: #0e335c;
  --chip-bg: #123d6b;
  color-scheme: dark;
"""
            ++ """
body {
  font-family: ui-monospace, "SF Mono", Menlo, Consolas, "Courier New", monospace;
}

h1, h2, h3, .section-title {
  text-transform: uppercase;
  letter-spacing: 0.12em;
}
.section-title {
  color: var(--fg);
  border-bottom: 1px dashed var(--fg);
  padding-bottom: 0.2rem;
}

.navbar {
  border-bottom: 2px dashed var(--fg);
}

.container {
  background: color-mix(in srgb, var(--bg) 80%, transparent);
}

/* Square, hairline-outlined cards with a dashed offset outline, like a drawing frame. */
.post-card, .event-card, .user-card {
  border: 1px solid var(--fg) !important;
  border-radius: 0;
  background: color-mix(in srgb, var(--panel-bg) 78%, transparent);
  outline: 1px dashed color-mix(in srgb, var(--fg) 45%, transparent);
  outline-offset: 4px;
  margin: 6px 4px;
}

main button:not(.remove-btn) {
  border-radius: 0;
  border: 1px solid var(--fg);
}
"""
        , eventSurfaces
        , if images == 0 then
            """
/* Page background: a drafting grid -- major lines every 120px, minor every 24px. */
html {
  background:
    linear-gradient(var(--bp-line) 1px, transparent 1px) 0 0 / 120px 120px,
    linear-gradient(90deg, var(--bp-line) 1px, transparent 1px) 0 0 / 120px 120px,
    linear-gradient(var(--bp-line-minor) 1px, transparent 1px) 0 0 / 24px 24px,
    linear-gradient(90deg, var(--bp-line-minor) 1px, transparent 1px) 0 0 / 24px 24px,
    var(--bg);
  background-attachment: fixed;
}
body { background: transparent; }
"""

          else
            pageImage
                { filter = blueprintBlue
                , overlay = "linear-gradient(var(--bp-line) 1px, transparent 1px) 0 0 / 24px 24px, linear-gradient(90deg, var(--bp-line) 1px, transparent 1px) 0 0 / 24px 24px, color-mix(in srgb, var(--bg) 78%, transparent)"
                , note = "Image 1 (--custom-media-1): the page background, in blue monochrome under the drafting grid."
                }
        , if images >= 2 then
            masthead
                { note = "Image 2 (--custom-media-2): 'a figure' -- a blue-monochrome plate with a grid overlay and a ruled border."
                , height = "12rem"
                , filter = blueprintBlue
                , overlay = "linear-gradient(rgba(255, 255, 255, 0.15) 1px, transparent 1px) 0 0 / 20px 20px, linear-gradient(90deg, rgba(255, 255, 255, 0.15) 1px, transparent 1px) 0 0 / 20px 20px"
                , extra = "border: 1px solid var(--fg); outline: 1px dashed color-mix(in srgb, var(--fg) 45%, transparent); outline-offset: 4px; margin: 6px 6px 1.6rem;"
                }

          else
            ""
        ]


blueprintBlue : String
blueprintBlue =
    "grayscale(1) sepia(1) hue-rotate(180deg) saturate(3) brightness(0.7) contrast(1.1)"



-- DISCO


{-| A mirror-ball night (always dark, deep purple): a field of tiny sparkles, slowly rotating pink / cyan /
gold light beams from above (off for `prefers-reduced-motion`), cards edged in a shifting prismatic border, and
glowing white headings. The masthead is spotlit and glittered.
-}
disco : Int -> String
disco images =
    String.join "\n"
        [ "/* Disco -- a mirror-ball night: sparkle, light beams, prismatic edges. Always dark. */\n"
            ++ forcedRoot
                """  --bg: #14061f;
  --fg: #fdf4ff;
  --muted: #d6b3e8;
  --border: #6b2d8f;
  --panel-bg: #1c0a2b;
  --chip-bg: #2a1040;
  color-scheme: dark;
"""
            ++ """
body {
  font-family: "ITC Avant Garde Gothic", "Century Gothic", "Futura", "Trebuchet MS", sans-serif;
  letter-spacing: 0.02em;
}

h1, h2, h3, .section-title {
  font-weight: 700;
  letter-spacing: 0.05em;
  text-shadow: 0 0 10px rgba(255, 255, 255, 0.55), 0 0 22px rgba(255, 79, 216, 0.5);
}

.navbar {
  box-shadow: 0 0 22px rgba(255, 79, 216, 0.55);
}

.container {
  background: color-mix(in srgb, var(--bg) 70%, transparent);
  -webkit-backdrop-filter: blur(5px);
  backdrop-filter: blur(5px);
}

/* A prismatic gradient border: the card's own panel color over a pink / cyan / gold gradient edge. */
.post-card, .event-card, .user-card {
  border: 2px solid transparent !important;
  border-radius: 12px;
  background:
    linear-gradient(color-mix(in srgb, var(--panel-bg) 88%, transparent), color-mix(in srgb, var(--panel-bg) 88%, transparent)) padding-box,
    linear-gradient(135deg, #ff4fd8, #4fd8ff, #ffe66b, #ff4fd8) border-box;
}

main button:not(.remove-btn) {
  border-color: #ff4fd8;
}
"""
        , eventSurfaces
        , if images == 0 then
            """
/* Page background: a sparkle field (two offset layers of tiny glints) ... */
html {
  background:
    radial-gradient(circle, rgba(255, 255, 255, 0.55) 0 1px, transparent 1.6px) 0 0 / 53px 47px,
    radial-gradient(circle, rgba(255, 230, 255, 0.4) 0 1px, transparent 1.8px) 19px 23px / 71px 67px,
    var(--bg);
  background-attachment: fixed;
}
body { background: transparent; }

/* ... under slowly turning pink / cyan / gold beams from above. */
html::before {
  content: "";
  position: fixed;
  left: 50%;
  top: -30vmax;
  width: 160vmax;
  height: 160vmax;
  margin-left: -80vmax;
  z-index: -1;
  pointer-events: none;
  background: conic-gradient(from 0deg, transparent 0 10deg, rgba(255, 79, 216, 0.22) 10deg 16deg, transparent 16deg 50deg, rgba(79, 216, 255, 0.22) 50deg 56deg, transparent 56deg 100deg, rgba(255, 230, 107, 0.2) 100deg 106deg, transparent 106deg 150deg, rgba(255, 79, 216, 0.22) 150deg 156deg, transparent 156deg 200deg, rgba(79, 216, 255, 0.22) 200deg 206deg, transparent 206deg 250deg, rgba(255, 230, 107, 0.2) 250deg 256deg, transparent 256deg 300deg, rgba(255, 79, 216, 0.22) 300deg 306deg, transparent 306deg);
  -webkit-mask-image: radial-gradient(circle, #000 0, transparent 60%);
  mask-image: radial-gradient(circle, #000 0, transparent 60%);
  animation: custom-css-beams 60s linear infinite;
}
@keyframes custom-css-beams {
  to { transform: rotate(360deg); }
}
@media (prefers-reduced-motion: reduce) {
  html::before { animation: none; }
}
"""

          else
            pageImage
                { filter = "saturate(1.3) contrast(1.1)"
                , overlay = "radial-gradient(circle, rgba(255, 255, 255, 0.5) 0 1px, transparent 1.6px) 0 0 / 53px 47px, radial-gradient(circle at 50% 0%, rgba(255, 79, 216, 0.35), transparent 60%), rgba(20, 6, 31, 0.72)"
                , note = "Image 1 (--custom-media-1): the page background, darkened under a pink spotlight and a sparkle field."
                }
        , if images >= 2 then
            masthead
                { note = "Image 2 (--custom-media-2): a spotlit, glittered masthead in a gold frame with a pink glow."
                , height = "13rem"
                , filter = "saturate(1.2)"
                , overlay = "radial-gradient(circle, rgba(255, 255, 255, 0.85) 0 1px, transparent 1.6px) 7px 9px / 41px 43px, radial-gradient(ellipse at 50% 0%, rgba(255, 255, 255, 0.3), transparent 65%)"
                , extra = "border: 2px solid #ffe66b; box-shadow: 0 0 30px rgba(255, 79, 216, 0.6); margin: 6px 6px 1.6rem;"
                }

          else
            ""
        ]



-- CINEMATIC


{-| A night at the movies (always dark, warm black): Baskerville-style small-caps headings with a gold hairline
running out from each label, gold-spined cards, a gentle vignette over the whole screen (click-through), and a
teal-and-orange color grade on the photos. The masthead is a true 2.39:1 letterboxed frame.
-}
cinematic : Int -> String
cinematic images =
    String.join "\n"
        [ "/* Cinematic -- warm black, gold hairlines, letterboxed frames, a color grade. Always dark. */\n"
            ++ forcedRoot
                """  --cine-gold: #c8a96a;
  --bg: #0b0b0d;
  --fg: #e9e4d8;
  --muted: #a29b8c;
  --border: #2b2a2e;
  --panel-bg: #121216;
  --chip-bg: #18181d;
  color-scheme: dark;
"""
            ++ """
body {
  font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
}

h1, h2, h3, .post-card-title {
  font-family: "Baskerville", "Hoefler Text", "Iowan Old Style", Georgia, serif;
  font-weight: 400;
  font-variant: small-caps;
  letter-spacing: 0.12em;
}

/* Each section label is followed by a gold hairline running out to the edge. */
.section-title {
  display: flex;
  align-items: center;
  gap: 0.8rem;
  color: var(--cine-gold);
  font-family: "Baskerville", "Hoefler Text", "Iowan Old Style", Georgia, serif;
  font-variant: small-caps;
  text-transform: none;
  letter-spacing: 0.18em;
}
.section-title::after {
  content: "";
  flex: 1;
  height: 1px;
  background: var(--cine-gold);
}

.container {
  background: color-mix(in srgb, var(--bg) 80%, transparent);
}

.post-card, .event-card, .user-card {
  border: none;
  border-left: 2px solid var(--cine-gold);
  border-radius: 0;
  background: linear-gradient(180deg, color-mix(in srgb, var(--panel-bg) 90%, transparent), transparent);
}

main button:not(.remove-btn) {
  border-radius: 2px;
  border-color: var(--cine-gold);
}

/* A gentle vignette over everything, never intercepting clicks. */
html::after {
  content: "";
  position: fixed;
  inset: 0;
  z-index: 9999;
  pointer-events: none;
  background: radial-gradient(ellipse at center, transparent 55%, rgba(0, 0, 0, 0.5));
}
"""
        , eventSurfaces
        , if images == 0 then
            """
html { background: radial-gradient(ellipse at 50% -20%, #1d1a14, var(--bg) 70%) fixed, var(--bg); }
body { background: transparent; }
"""

          else
            pageImage
                { filter = "saturate(0.7) contrast(1.15) brightness(0.85)"
                , overlay = "linear-gradient(180deg, rgba(0, 90, 110, 0.25), rgba(255, 140, 40, 0.18)), rgba(8, 8, 10, 0.7)"
                , note = "Image 1 (--custom-media-1): the page background, darkened and graded teal-and-orange."
                }
        , if images >= 2 then
            masthead
                { note = "Image 2 (--custom-media-2): a letterboxed 2.39:1 frame, teal-and-orange graded."
                , height = "auto"
                , filter = "saturate(0.85) contrast(1.1)"
                , overlay = "linear-gradient(180deg, rgba(0, 90, 110, 0.22), rgba(255, 140, 40, 0.16))"
                , extra = "aspect-ratio: 2.39 / 1; border-top: 14px solid #000; border-bottom: 14px solid #000; margin: 4px 0 1.6rem; background-attachment: scroll;"
                }

          else
            ""
        ]



-- DYSLEXIA-FRIENDLY


{-| Built around what tends to help dyslexic readers: a soft cream (or soft charcoal in dark mode, never
stark black on white), a wide-set sans (Verdana / Trebuchet -- system fonts, so nothing external loads), extra
letter and word spacing, tall line height, ragged-right text with a short measure, bold instead of italics, no
all-caps, underlined links and no motion. Images are decorative only, as in `High Contrast`.
-}
dyslexiaFriendly : Int -> String
dyslexiaFriendly images =
    String.join "\n"
        [ "/* Dyslexia-Friendly -- soft colors, wide-set type, extra spacing, no italics or all-caps, no motion. */\n"
            ++ themedRoot
                """  --bg: #fbf5e6;
  --fg: #222222;
  --muted: #4a4a4a;
  --border: #cfc6ad;
  --panel-bg: #fffaf0;
  --chip-bg: #f1e9d2;
"""
                """  --bg: #262626;
  --fg: #f2ecd9;
  --muted: #cfc8b4;
  --border: #4a4a4a;
  --panel-bg: #2d2d2d;
  --chip-bg: #333333;
"""
            ++ """
body {
  font-family: Verdana, "Trebuchet MS", "Segoe UI", Tahoma, sans-serif;
  font-size: 1.1rem;
  line-height: 1.9;
  letter-spacing: 0.05em;
  word-spacing: 0.16em;
  text-align: left;
}

h1, h2, h3, .section-title, .post-card-title {
  text-transform: none;
  letter-spacing: 0.04em;
  font-weight: 700;
  line-height: 1.4;
}

.section-title {
  color: var(--fg);
  font-size: 1rem;
}

/* Bold, not italic -- italics are harder to read. */
em, i, cite, address {
  font-style: normal;
  font-weight: 700;
}

p {
  margin-block: 1.2em;
}

.post-card-content-preview, .post-detail-content {
  max-width: 62ch;
  text-align: left !important;
}

main a {
  text-decoration: underline;
  text-decoration-thickness: 2px;
  text-underline-offset: 0.22em;
}

.container {
  background: var(--bg);
}

.post-card, .event-card, .user-card {
  border: 2px solid var(--border) !important;
  border-radius: 10px;
  background: var(--panel-bg);
  padding: 1.1rem 1.25rem;
  margin-bottom: 0.8rem;
}

main button:not(.remove-btn), main select, main input:not([type="checkbox"]):not([type="radio"]) {
  min-height: 44px;
}

:focus-visible {
  outline: 3px solid var(--fg);
  outline-offset: 3px;
}

"""
            ++ noMotion
        , eventSurfaces
        , if images == 0 then
            """
html { background: var(--bg); }
body { background: transparent; }
"""

          else
            pageImage
                { filter = "grayscale(1)"
                , overlay = "color-mix(in srgb, var(--bg) 94%, transparent)"
                , note = "Image 1 (--custom-media-1): a nearly invisible, still, grayscale page background -- decorative only."
                }
                ++ noDrift
        , if images >= 2 then
            masthead
                { note = "Image 2 (--custom-media-2): a plain rounded band above the content -- decorative only, no text on it."
                , height = "9rem"
                , filter = "none"
                , overlay = "linear-gradient(transparent, transparent)"
                , extra = "border: 2px solid var(--border); border-radius: 10px; background-attachment: scroll;"
                }

          else
            ""
        ]



-- FIELD GUIDE


{-| A naturalist's plate book: foxed cream paper, serif type, a "❦" flourish either side of each section
label, and every card numbered as a plate ("Plate I.", "Plate II.", ... -- a CSS counter) under a hairline
rule. Photos inside cards get a mounted-specimen frame. The masthead is a framed plate.
-}
fieldGuide : Int -> String
fieldGuide images =
    String.join "\n"
        [ """/* Field Guide -- foxed paper, serif type, numbered plates. */
body {
  font-family: "Iowan Old Style", "Palatino Linotype", Palatino, Georgia, "Times New Roman", serif;
  line-height: 1.55;
}

h1, h2, h3, .post-card-title {
  font-weight: 600;
  font-style: italic;
  letter-spacing: 0.01em;
}

.section-title {
  text-align: center;
  text-transform: none;
  font-style: italic;
  font-size: 1.05rem;
  color: var(--fg);
}
.section-title::before { content: "❦  "; }
.section-title::after { content: "  ❦"; }

.container {
  counter-reset: plate;
  background: color-mix(in srgb, var(--bg) 86%, #e9dcbc);
}

/* Each card is numbered like a plate in the book. */
.post-card, .event-card {
  counter-increment: plate;
}
.post-card::before, .event-card::before {
  content: "Plate " counter(plate, upper-roman) ".";
  display: block;
  font-size: 0.72rem;
  font-variant: small-caps;
  letter-spacing: 0.14em;
  color: var(--muted);
  border-bottom: 1px solid var(--border);
  padding-bottom: 0.25rem;
  margin-bottom: 0.5rem;
}

.post-card, .event-card, .user-card {
  border: 1px solid var(--border);
  border-color: var(--border) !important;
  border-radius: 2px;
  background: color-mix(in srgb, var(--bg) 70%, #fffdf6);
  padding: 0.9rem 1rem;
}

/* Pictures in cards are mounted like specimens. */
.post-card img, .event-card img {
  border: 1px solid var(--border);
  padding: 4px;
  background: #fffdf6;
}

main button:not(.remove-btn) {
  border-radius: 2px;
  font-variant: small-caps;
  letter-spacing: 0.05em;
}
"""
        , if images == 0 then
            """
/* Page background: cream paper with foxing -- a few faint brown blotches. */
html {
  background:
    radial-gradient(circle at 12% 18%, rgba(150, 110, 60, 0.1), transparent 18%),
    radial-gradient(circle at 88% 64%, rgba(150, 110, 60, 0.09), transparent 22%),
    radial-gradient(circle at 40% 92%, rgba(150, 110, 60, 0.08), transparent 16%),
    color-mix(in srgb, var(--bg) 90%, #e9dcbc);
  background-attachment: fixed;
}
body { background: transparent; }
"""

          else
            pageImage
                { filter = "grayscale(0.3) sepia(0.4)"
                , overlay = "color-mix(in srgb, color-mix(in srgb, var(--bg) 90%, #e9dcbc) 90%, transparent)"
                , note = "Image 1 (--custom-media-1): the page background, aged and washed far back like an endpaper illustration."
                }
        , if images >= 2 then
            masthead
                { note = "Image 2 (--custom-media-2): a framed plate -- a sepia print in a white mount with a hairline rule."
                , height = "12rem"
                , filter = "sepia(0.45) contrast(1.05)"
                , overlay = "linear-gradient(transparent, transparent)"
                , extra = "border: 10px solid #fffdf6; box-shadow: 0 0 0 1px var(--border); margin: 8px 8px 1.6rem;"
                }

          else
            ""
        ]



-- Y2K AERO


{-| Early-2000s glassy optimism (always light): an aqua sky over grass with translucent bubbles, glossy
pill buttons with a hard highlight, frosted-glass cards, and a gloss highlight across the nav (laid over the
server's own color) and the masthead.
-}
y2kAero : Int -> String
y2kAero images =
    String.join "\n"
        [ "/* Y2K Aero -- aqua glass, gloss, bubbles. Always light. */\n"
            ++ forcedRoot
                """  --bg: #e9f7ff;
  --fg: #0b3a55;
  --muted: #4b7a94;
  --border: #9fd3ea;
  --panel-bg: #f4fbff;
  --chip-bg: #d6f0fb;
  color-scheme: light;
"""
            ++ """
body {
  font-family: "Segoe UI", "Frutiger", "Lucida Grande", "Trebuchet MS", sans-serif;
}

h1, h2, h3, .section-title, .post-card-title {
  font-weight: 600;
  text-shadow: 0 1px 0 rgba(255, 255, 255, 0.9);
}

/* A glossy highlight across the nav, over whatever color the server gave it. */
.navbar {
  background-image: linear-gradient(180deg, rgba(255, 255, 255, 0.5), rgba(255, 255, 255, 0) 55%);
  box-shadow: 0 3px 10px rgba(0, 90, 140, 0.3);
}

.container {
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.75), rgba(255, 255, 255, 0.5));
  -webkit-backdrop-filter: blur(8px);
  backdrop-filter: blur(8px);
}

.post-card, .event-card, .user-card {
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.9), rgba(255, 255, 255, 0.6));
  border: 1px solid rgba(255, 255, 255, 0.95) !important;
  border-radius: 18px;
  box-shadow: 0 6px 18px rgba(0, 100, 160, 0.2), inset 0 1px 0 #ffffff;
}

/* Glossy pill buttons: a hard highlight across the top half. */
main button:not(.remove-btn) {
  background: linear-gradient(180deg, #ffffff 0%, #bfe9ff 49%, #8fd6ff 50%, #c9f0ff 100%);
  border: 1px solid #5db9e6;
  border-radius: 999px;
  color: #05476b;
  text-shadow: 0 1px 0 rgba(255, 255, 255, 0.8);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.9), 0 2px 4px rgba(0, 80, 130, 0.25);
}
"""
        , eventSurfaces
        , if images == 0 then
            """
/* Page background: an aqua sky down to grass, with a few translucent bubbles. */
html {
  background:
    radial-gradient(circle at 30% 30%, rgba(255, 255, 255, 0.9) 0 6%, rgba(255, 255, 255, 0.25) 7% 60%, rgba(255, 255, 255, 0.08) 61%, transparent 62%) 12% 22% / 14vmin 14vmin no-repeat,
    radial-gradient(circle at 30% 30%, rgba(255, 255, 255, 0.9) 0 6%, rgba(255, 255, 255, 0.25) 7% 60%, rgba(255, 255, 255, 0.08) 61%, transparent 62%) 90% 38% / 9vmin 9vmin no-repeat,
    radial-gradient(circle at 30% 30%, rgba(255, 255, 255, 0.9) 0 6%, rgba(255, 255, 255, 0.25) 7% 60%, rgba(255, 255, 255, 0.08) 61%, transparent 62%) 5% 70% / 18vmin 18vmin no-repeat,
    linear-gradient(180deg, #5bbcff 0%, #bfe9ff 45%, #e9f7ff 62%, #9fe08a 88%, #5bbf3b 100%);
  background-attachment: fixed;
}
body { background: transparent; }
"""

          else
            pageImage
                { filter = "saturate(1.2) brightness(1.05)"
                , overlay = "linear-gradient(180deg, rgba(91, 188, 255, 0.35), rgba(255, 255, 255, 0.15))"
                , note = "Image 1 (--custom-media-1): the page background, brightened under a sky-blue wash."
                }
        , if images >= 2 then
            masthead
                { note = "Image 2 (--custom-media-2): a glossy glass masthead -- a highlight across its top half, white rim, soft blue shadow."
                , height = "13rem"
                , filter = "saturate(1.15)"
                , overlay = "linear-gradient(180deg, rgba(255, 255, 255, 0.55) 0, rgba(255, 255, 255, 0.1) 50%, transparent 50%)"
                , extra = "border: 2px solid rgba(255, 255, 255, 0.9); border-radius: 24px; box-shadow: 0 8px 24px rgba(0, 100, 160, 0.35); margin: 6px 6px 1.6rem;"
                }

          else
            ""
        ]



-- RETRO DESKTOP


{-| A 1995 desktop (always light): a teal desktop, the content column as a gray window with a raised bevel and
a navy title bar, sunken white "fields" for cards, and chunky raised buttons that press in. Images become the
wallpaper (tinted teal) and a bevelled picture window with its own title bar.
-}
retroDesktop : Int -> String
retroDesktop images =
    String.join "\n"
        [ "/* Retro Desktop -- gray bevels, a navy title bar, a teal desktop. Always light. */\n"
            ++ forcedRoot
                """  --bg: #c0c0c0;
  --fg: #000000;
  --muted: #404040;
  --border: #808080;
  --panel-bg: #c0c0c0;
  --chip-bg: #dfdfdf;
  color-scheme: light;
"""
            ++ """
body {
  font-family: "MS Sans Serif", Tahoma, "Segoe UI", Geneva, sans-serif;
  font-size: 0.95rem;
}

h1, h2, h3, .section-title, .post-card-title {
  font-weight: 700;
}
.section-title {
  color: #000;
}

.navbar {
  border-bottom: 2px solid #000;
}

/* The content column is a window: a raised bevel and a navy title bar. */
.container {
  background: #c0c0c0;
  border: 2px solid;
  border-color: #fff #404040 #404040 #fff;
  box-shadow: 1px 1px 0 #000;
  margin: 12px auto;
}
.container::before {
  content: "▣  Rellm";
  display: block;
  padding: 3px 6px;
  background: linear-gradient(90deg, color-mix(in srgb, var(--primary-color, #000080) 45%, #000), color-mix(in srgb, var(--primary-color, #1084d0) 80%, #000));
  color: #fff;
  font-weight: 700;
  font-size: 0.85rem;
  letter-spacing: 0.02em;
}

/* Cards are sunken white fields. */
.post-card, .event-card, .user-card {
  background: #fff !important;
  color: #000;
  border: 2px solid;
  border-color: #808080 #fff #fff #808080 !important;
  border-radius: 0;
  box-shadow: inset 1px 1px 0 #000;
}

/* Buttons are raised, and press in. */
main button:not(.remove-btn) {
  background: #c0c0c0 !important;
  color: #000;
  border: 2px solid;
  border-color: #fff #404040 #404040 #fff;
  border-radius: 0;
  box-shadow: 1px 1px 0 #000;
}
main button:not(.remove-btn):active {
  border-color: #404040 #fff #fff #404040;
}
"""
        , eventSurfaces
        , if images == 0 then
            """
/* The desktop. */
html { background: #008080; }
body { background: transparent; }
"""

          else
            pageImage
                { filter = "contrast(1.1) saturate(0.85)"
                , overlay = "rgba(0, 128, 128, 0.3)"
                , note = "Image 1 (--custom-media-1): the desktop wallpaper, tinted teal."
                }
        , if images >= 2 then
            masthead
                { note = "Image 2 (--custom-media-2): a picture window -- bevelled, with a navy title bar."
                , height = "13rem"
                , filter = "none"
                , overlay = "linear-gradient(transparent, transparent)"
                , extra = "border: 2px solid; border-color: #fff #404040 #404040 #fff; border-top: 22px solid color-mix(in srgb, var(--primary-color, #000080) 45%, #000); margin: 6px 6px 1.4rem;"
                }

          else
            ""
        ]



-- ZINE


{-| A photocopied zine, risograph-printed (always light): typewriter type with a marker-highlighted label,
headings printed slightly out of register (pink and blue offset shadows), dashed "cut here" card outlines with
misregistered offset shadows, and halftone in two offset colors. The masthead is a pink duotone under a blue
halftone, pasted on at a slight angle.
-}
zine : Int -> String
zine images =
    String.join "\n"
        [ "/* Zine -- photocopy and riso: halftone, out-of-register color, dashed cut lines. Always light. */\n"
            ++ forcedRoot
                """  --riso-pink: var(--primary-color, #ff48b0);
  --riso-blue: var(--nav-color, #0078bf);
  --riso-yellow: #ffe800;
  --bg: #f4efe2;
  --fg: #151515;
  --muted: #555555;
  --border: #151515;
  --panel-bg: #fbf7ec;
  --chip-bg: #ebe4d2;
  color-scheme: light;
"""
            ++ """
body {
  font-family: "American Typewriter", "Courier New", Courier, monospace;
}

h1, h2, h3, .section-title, .post-card-title {
  font-family: "American Typewriter", "Courier New", Courier, monospace;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  /* Printed a little out of register. */
  text-shadow: 2px 1px 0 var(--riso-pink), -1px 0 0 var(--riso-blue);
}

/* Section labels are highlighted with a yellow marker. */
.section-title {
  display: inline-block;
  background: linear-gradient(transparent 55%, var(--riso-yellow) 55%);
  color: var(--fg);
}

.navbar {
  border-bottom: 3px dashed #151515;
}

.container {
  background: color-mix(in srgb, var(--bg) 90%, transparent);
}

.post-card, .event-card, .user-card {
  background: #fff;
  border: 2px dashed #151515 !important;
  border-radius: 0;
  box-shadow: 4px 4px 0 var(--riso-pink), -3px -3px 0 color-mix(in srgb, var(--riso-blue) 55%, transparent);
}

main button:not(.remove-btn) {
  border-radius: 0;
  border: 2px solid #151515;
  background: var(--riso-yellow);
  color: #151515;
  font-weight: 700;
}
"""
        , eventSurfaces
        , if images == 0 then
            """
/* Page background: two offset halftone screens, pink and blue, on newsprint. */
html {
  background:
    radial-gradient(circle, color-mix(in srgb, var(--riso-pink) 35%, transparent) 1.5px, transparent 2px) 0 0 / 9px 9px,
    radial-gradient(circle, color-mix(in srgb, var(--riso-blue) 28%, transparent) 1.5px, transparent 2px) 4px 4px / 9px 9px,
    var(--bg);
  background-attachment: fixed;
}
body { background: transparent; }
"""

          else
            pageImage
                { filter = "grayscale(1) contrast(1.4)"
                , overlay = "radial-gradient(circle, color-mix(in srgb, var(--riso-blue) 45%, transparent) 1.2px, transparent 1.8px) 0 0 / 6px 6px, rgba(244, 239, 226, 0.72)"
                , note = "Image 1 (--custom-media-1): the page background, photocopied -- high-contrast gray under a blue halftone."
                }
        , if images >= 2 then
            masthead
                { note = "Image 2 (--custom-media-2): a pink duotone under a blue halftone, pasted on at a slight angle with a dashed edge."
                , height = "13rem"
                , filter = "none"
                , overlay = "radial-gradient(circle, color-mix(in srgb, var(--riso-blue) 60%, transparent) 0 1.2px, transparent 1.8px) 0 0 / 6px 6px"
                , extra = "background-color: var(--riso-pink); background-blend-mode: normal, luminosity; border: 2px dashed #151515; box-shadow: 6px 6px 0 var(--riso-blue); transform: rotate(0.6deg); margin: 8px 8px 1.8rem 4px; background-attachment: scroll;"
                }

          else
            ""
        ]



-- WABI-SABI


{-| Quiet imperfection: a warm paper (or warm charcoal in dark mode), thin light-weight type with wide
tracking, lots of empty space, hairline-ruled entries instead of cards, a small vermilion seal beside each
section label, and a single faint ink ring ("ensō") near the corner of the plain page. The seal is the server's primary color. Photos are ink-wash:
grayscale, softened, and -- for the masthead -- faded out at the sides.
-}
wabiSabi : Int -> String
wabiSabi images =
    String.join "\n"
        [ "/* Wabi-sabi -- quiet, spare, imperfect. */\n"
            ++ themedRoot
                """  --bg: #f3efe7;
  --fg: #33302b;
  --muted: #7a746a;
  --border: #d9d3c7;
  --panel-bg: #f7f3eb;
  --chip-bg: #ebe6db;
"""
                """  --bg: #1f1d1a;
  --fg: #e4dfd3;
  --muted: #9c968a;
  --border: #38342f;
  --panel-bg: #25221e;
  --chip-bg: #2b2823;
"""
            ++ """
body {
  font-family: "Hiragino Sans", "Hiragino Kaku Gothic ProN", "Helvetica Neue", "Avenir Next", sans-serif;
  font-weight: 300;
  letter-spacing: 0.04em;
  line-height: 1.9;
}

h1, h2, h3, .post-card-title {
  font-weight: 300;
  letter-spacing: 0.06em;
}

/* Section labels: small, widely spaced, with a vermilion seal. */
.section-title {
  font-size: 0.72rem;
  letter-spacing: 0.35em;
  text-transform: uppercase;
  color: var(--muted);
}
.section-title::before {
  content: "";
  display: inline-block;
  width: 0.55em;
  height: 0.55em;
  margin-right: 0.8em;
  background: var(--primary-color, #b5382b);
  border-radius: 1px;
}

.container {
  background: color-mix(in srgb, var(--bg) 88%, transparent);
}
main {
  padding: 2rem 1rem;
}

/* Entries, not cards: just a hairline between them. */
.post-card, .event-card, .user-card {
  border: none;
  border-bottom: 1px solid var(--border);
  border-bottom-color: var(--border) !important;
  border-radius: 0;
  padding: 1.6rem 0;
}

main button:not(.remove-btn) {
  border-radius: 2px;
  font-weight: 300;
  letter-spacing: 0.08em;
}
"""
        , eventSurfaces
        , if images == 0 then
            """
/* Page background: plain paper with one faint ink ring (ensō) near the top-right corner. */
html {
  background:
    radial-gradient(circle at 86% 16%, transparent 0 10.5vmin, color-mix(in srgb, var(--fg) 7%, transparent) 10.5vmin calc(10.5vmin + 3px), transparent calc(10.5vmin + 4px)) fixed,
    var(--bg);
}
body { background: transparent; }
"""

          else
            pageImage
                { filter = "grayscale(1) blur(3px) contrast(0.9)"
                , overlay = "color-mix(in srgb, var(--bg) 88%, transparent)"
                , note = "Image 1 (--custom-media-1): the page background as an ink wash -- gray, softened, barely there."
                }
        , if images >= 2 then
            masthead
                { note = "Image 2 (--custom-media-2): an ink-wash band, faded out at both sides."
                , height = "10rem"
                , filter = "grayscale(1) blur(1px)"
                , overlay = "linear-gradient(transparent, transparent)"
                , extra = "-webkit-mask-image: linear-gradient(90deg, transparent, #000 15%, #000 85%, transparent); mask-image: linear-gradient(90deg, transparent, #000 15%, #000 85%, transparent); background-attachment: scroll;"
                }

          else
            ""
        ]



-- OCEAN


{-| Layers of sea: a sky that fades into the page color, then two bands of scalloped waves along the bottom of
the screen (far and near) drifting at different speeds -- still, under `prefers-reduced-motion`. The colors are
mixed with the page's own, so it holds up in light and dark. With a page photo, only the near waves are kept, laid
over the picture; the masthead's lower edge is a waterline.
-}
ocean : Int -> String
ocean images =
    String.join "\n"
        [ """/* Ocean -- layered waves under a clear sky. */
body {
  font-family: "Avenir Next", "Trebuchet MS", "Segoe UI", sans-serif;
}

.section-title {
  color: color-mix(in srgb, #1f7fc4 80%, var(--fg));
}

.navbar {
  border-bottom: 3px solid color-mix(in srgb, #3b9be0 70%, transparent);
}

.container {
  margin-top: 12px;
  margin-bottom: 12px;
  border-radius: 16px;
  background: color-mix(in srgb, var(--bg) 84%, transparent);
  -webkit-backdrop-filter: blur(5px);
  backdrop-filter: blur(5px);
}

.post-card, .event-card, .user-card {
  border-radius: 14px;
  border-color: color-mix(in srgb, #3b9be0 55%, transparent) !important;
  box-shadow: 0 2px 10px color-mix(in srgb, #1d6fb3 18%, transparent);
}
"""
        , if images == 0 then
            """
/* The sky, then (html::before) the far waves and (html::after) the near waves, each drifting sideways. */
html {
  background: linear-gradient(180deg, color-mix(in srgb, #5bb8f0 45%, var(--bg)), var(--bg) 62%) fixed, var(--bg);
}
body { background: transparent; }

"""
                ++ landscapeLayer "before" "34vh" (waveBand "color-mix(in srgb, #3b9be0 62%, var(--bg))" 180 26)
                ++ landscapeLayer "after" "20vh" (waveBand "color-mix(in srgb, #1d6fb3 78%, var(--bg))" 120 18)
                ++ """
html::before { animation: custom-css-wave-far 24s linear infinite; }
html::after { animation: custom-css-wave-near 14s linear infinite; }
@keyframes custom-css-wave-far {
  to { background-position: 180px 0, 0 100%; }
}
@keyframes custom-css-wave-near {
  to { background-position: -120px 0, 0 100%; }
}
@media (prefers-reduced-motion: reduce) {
  html::before, html::after { animation: none; }
}
"""

          else
            pageImage
                { filter = "saturate(1.1)"
                , overlay = "linear-gradient(180deg, color-mix(in srgb, #5bb8f0 30%, transparent), transparent 50%), color-mix(in srgb, var(--bg) 30%, transparent)"
                , note = "Image 1 (--custom-media-1): the page background, under a faint sky wash -- with the near waves lapping over it along the bottom."
                }
                ++ "\n"
                ++ landscapeLayer "after" "20vh" (waveBand "color-mix(in srgb, #1d6fb3 78%, var(--bg))" 120 18)
                ++ """
html::after { animation: custom-css-wave-near 14s linear infinite; }
@keyframes custom-css-wave-near {
  to { background-position: -120px 0, 0 100%; }
}
@media (prefers-reduced-motion: reduce) {
  html::after { animation: none; }
}
"""
        , if images >= 2 then
            masthead
                { note = "Image 2 (--custom-media-2): a seascape masthead whose lower edge is a scalloped waterline."
                , height = "12rem"
                , filter = "saturate(1.1)"
                , overlay = "radial-gradient(ellipse 22px 14px at 50% 100%, var(--bg) 0 98%, transparent 100%) 0 100% / 44px 14px repeat-x"
                , extra = "border-radius: 16px 16px 0 0; background-attachment: scroll;"
                }

          else
            ""
        ]



-- FOREST


{-| Layers of woodland: a sky that fades into the page color, rolling hills (far) and a row of pines (near)
along the bottom of the screen, which shift against the page as it scrolls where scroll-driven animations
exist. Greens are mixed with the page's own colors. With a page photo only the pines are kept, over the picture;
the masthead's lower edge is a treeline.
-}
forest : Int -> String
forest images =
    String.join "\n"
        [ """/* Forest -- hills and pines under a pale sky. */
body {
  font-family: "Avenir Next", "Gill Sans", "Trebuchet MS", "Segoe UI", sans-serif;
}

.section-title {
  color: color-mix(in srgb, #2f7a4a 80%, var(--fg));
}

.navbar {
  border-bottom: 3px solid color-mix(in srgb, #2f7a4a 70%, transparent);
}

.container {
  margin-top: 12px;
  margin-bottom: 12px;
  border-radius: 10px;
  background: color-mix(in srgb, var(--bg) 86%, transparent);
  -webkit-backdrop-filter: blur(4px);
  backdrop-filter: blur(4px);
}

.post-card, .event-card, .user-card {
  border-radius: 10px;
  border-color: color-mix(in srgb, #2f7a4a 55%, transparent) !important;
  box-shadow: 0 2px 10px color-mix(in srgb, #1f5a3a 16%, transparent);
}
"""
        , if images == 0 then
            """
/* The sky, then (html::before) far hills and (html::after) a row of pines. */
html {
  background: linear-gradient(180deg, color-mix(in srgb, #bfe3b8 40%, var(--bg)), var(--bg) 62%) fixed, var(--bg);
}
body { background: transparent; }

"""
                ++ landscapeLayer "before" "34vh" (waveBand "color-mix(in srgb, #5d9a62 55%, var(--bg))" 320 46)
                ++ landscapeLayer "after" "22vh" (pines "color-mix(in srgb, #1f5a3a 80%, var(--bg))")
                ++ """
/* Parallax: the hills and pines shift against the page as it scrolls. */
@supports (animation-timeline: scroll()) {
  html::before { animation: custom-css-hills linear both; animation-timeline: scroll(root); }
  html::after { animation: custom-css-trees linear both; animation-timeline: scroll(root); }
}
@keyframes custom-css-hills {
  from { transform: translateY(0); }
  to { transform: translateY(-3vh); }
}
@keyframes custom-css-trees {
  from { transform: translateY(0); }
  to { transform: translateY(4vh); }
}
@media (prefers-reduced-motion: reduce) {
  html::before, html::after { animation: none; }
}
"""

          else
            pageImage
                { filter = "saturate(1.05)"
                , overlay = "linear-gradient(180deg, color-mix(in srgb, #bfe3b8 30%, transparent), transparent 50%), color-mix(in srgb, var(--bg) 30%, transparent)"
                , note = "Image 1 (--custom-media-1): the page background, under a faint green wash -- with a row of pines standing over it along the bottom."
                }
                ++ "\n"
                ++ landscapeLayer "after" "22vh" (pines "color-mix(in srgb, #1f5a3a 80%, var(--bg))")
        , if images >= 2 then
            masthead
                { note = "Image 2 (--custom-media-2): a woodland masthead whose lower edge is a treeline of pines."
                , height = "12rem"
                , filter = "saturate(1.05)"
                , overlay = treeline "#1f5a3a"
                , extra = "border-radius: 10px 10px 0 0; background-attachment: scroll;"
                }

          else
            ""
        ]


{-| One fixed layer along the bottom of the screen, behind the content (`html::before` / `html::after`).
-}
landscapeLayer : String -> String -> String -> String
landscapeLayer pseudo height background =
    "html::"
        ++ pseudo
        ++ " {\n  content: \"\";\n  position: fixed;\n  left: 0;\n  right: 0;\n  bottom: 0;\n  height: "
        ++ height
        ++ ";\n  z-index: -1;\n  pointer-events: none;\n  background: "
        ++ background
        ++ ";\n}\n"


{-| A band of scalloped waves / rolling hills as a two-layer `background` value: a repeating row of
`width` x `height` arcs along the top, over a solid fill of `color` below them.
-}
waveBand : String -> Int -> Int -> String
waveBand color width height =
    "radial-gradient(ellipse "
        ++ String.fromInt (width // 2)
        ++ "px "
        ++ String.fromInt height
        ++ "px at 50% 100%, "
        ++ color
        ++ " 0 98%, transparent 100%) 0 0 / "
        ++ String.fromInt width
        ++ "px "
        ++ String.fromInt height
        ++ "px repeat-x, linear-gradient("
        ++ color
        ++ ", "
        ++ color
        ++ ") 0 100% / 100% calc(100% - "
        ++ String.fromInt (height - 1)
        ++ "px) no-repeat"


{-| A row of pine trees along the top of a solid band, as a two-layer `background` value: each tree is a
40x60 triangle drawn with a `conic-gradient` whose apex is at the top-center (half-angle 18.4 degrees, so
its base meets the tile's edges), over a solid fill of `color` below.
-}
pines : String -> String
pines color =
    treeRow "0 0" color
        ++ ", linear-gradient("
        ++ color
        ++ ", "
        ++ color
        ++ ") 0 100% / 100% calc(100% - 59px) no-repeat"


{-| Just the row of pine triangles, sitting on the bottom edge of whatever it's a layer of.
-}
treeline : String -> String
treeline color =
    treeRow "0 100%" color


{-| The row of pine triangles at a given `background-position`.
-}
treeRow : String -> String -> String
treeRow position color =
    "conic-gradient(from 161.6deg at 50% 0, " ++ color ++ " 0 36.8deg, transparent 36.8deg) " ++ position ++ " / 40px 60px repeat-x"


{-| `declarations` as the `:root` custom properties in every theme state -- for a template that forces its own
colors whatever the light/dark setting.
-}
forcedRoot : String -> String
forcedRoot declarations =
    ":root, :root[data-theme=\"light\"], :root[data-theme=\"dark\"] {\n" ++ declarations ++ "}\n"


{-| Separate `light` and `dark` custom-property declarations that follow the light/dark setting: the OS
preference (the `@media` rule) unless an explicit Light/Dark selection (`data-theme`) overrides it -- the same
precedence the app's own theme variables use.
-}
themedRoot : String -> String -> String
themedRoot light dark =
    ":root {\n"
        ++ light
        ++ "}\n@media (prefers-color-scheme: dark) {\n  :root {\n"
        ++ dark
        ++ "  }\n}\n:root[data-theme=\"light\"] {\n"
        ++ light
        ++ "}\n:root[data-theme=\"dark\"] {\n"
        ++ dark
        ++ "}\n"



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
