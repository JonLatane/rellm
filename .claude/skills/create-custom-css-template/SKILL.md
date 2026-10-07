---
name: create-custom-css-template
description: Add a new Custom CSS template (a style such as "Art Deco" or "Blueprint", in 0/1/2-image versions) to the Elm SPA's Theme tab "Apply Template" dropdown. Use when asked to create, extend, or fix a Custom CSS style template in frontends/elm-spa.
---

Custom CSS templates are starter stylesheets an admin applies from the Theme tab's Custom CSS editor ("Apply Template" dropdown). They are **pure data**, all in one module: `frontends/elm-spa/src/Components/Pages/ServerInformationPage/ThemeTab/CustomCssTemplates.elm`. The dropdown (`CustomCssConfiguration.templateRow`) and its `<optgroup>`s are built from `CustomCssTemplates.grouped`, so adding a style needs no UI change.

## 1. Add the style

A style is a function `Int -> String` (image count 0/1/2 -> CSS), registered in `all` with `style "<Name>" "<image noun>" <ForcedTheme> <fn>`, which yields `Name`, `Name (1 image)`, `Name (2 images)` (the noun is "image" except Standard Style's "background image"). Copy a nearby style (`artDeco`, `terminal`, `polaroid`) and keep its shape:

```elm
myStyle images =
    String.join "\n"
        [ """/* base CSS: fonts, headings, .navbar, .container, cards, buttons */"""
        , eventSurfaces                       -- only if the style forces its own colors (see below)
        , if images == 0 then """/* plain page background */ html { ... } body { background: transparent; }"""
          else pageImage { filter = "...", overlay = "...", note = "Image 1 (--custom-media-1): ..." }
        , if images >= 2 then masthead { note = "...", height = "12rem", filter = "...", overlay = "...", extra = "..." } else ""
        ]
```

- **Images** arrive as `--custom-media-1` / `--custom-media-2` (each a full `url("...")`). **Always** write `var(--custom-media-N, none)` -- the helpers do; a hand-written use must include the `none` fallback (a test enforces it). Image 1 = page background (`pageImage`: fixed `body::before` layer with a scroll-driven drift, `body::after` overlay, `html` keeps `var(--bg)`); image 2 = a band at the top of the column (`masthead`: `main::before`, `background-attachment: fixed` parallax window). `overlay` is any `background` value (layers allowed, last may be a plain color); a masthead `overlay` must be an `<image>`. Each template must use exactly as many `--custom-media-N` as its image count (tested).
- **Brand colors**: `--primary-color` and `--nav-color` (`#rrggbb`) are always defined -- they're the server's configured primary and navigation colors (the app bar and the nav highlight), defined by `/custom_css.css` (`backend/src/logic/custom_css.rs`) and `UI.CustomCssStylesheet`. Use them for **decorative** accents that should look like *this* server (shadows, stripes, bunting, halftone, title bars, seals): always with a fallback, `var(--primary-color, #e03a2f)` (a test enforces it), and **never for body text** -- a pale brand color can fail to contrast. Material Design and Comic Book wear them too. Styles whose identity is a fixed palette (Art Deco gold, Terminal green, Synthwave neon) and the accessibility ones (High Contrast, Dyslexia-Friendly, Calm) deliberately don't use them. If a style should wear them, add it to the "styles meant to wear the server's colors" test.
- **Dropdown arrows are handled for you**: `style` appends `selectChevron` to every template -- the browser's native `<select>` arrow hugs the right edge and can't be moved from CSS (`padding-right` only widens the box), so it's replaced by an inset gradient chevron in `currentColor` (specificity-boosted for the editor's own `.custom-css-template-select`). Don't re-style `select` backgrounds in a template without keeping `background-image`.
- **Layout changes are fair game in pure CSS**: `Standard Side Navigation` rebuilds the nav as a left column on wide screens (`@media (min-width: 1140px)`) using only template CSS -- `.nav-links` becomes a grid, `.nav-links-scroll` gets `display: contents` so the toggles and tab links become grid items, panel `left` offsets are overridden. Keep the bar's own height fixed so overflowing tab pills don't push the page down, and never put `filter`/`backdrop-filter` on `.navbar` (it traps its fixed panels).
- **Helpers**: `forcedRoot` (set `--bg/--fg/--muted/--border/--panel-bg/--chip-bg` in every theme state), `themedRoot light dark` (separate light/dark palettes following the setting), `eventSurfaces`, `noMotion`/`noDrift`, `waveBand`/`pines`/`treeline`/`landscapeLayer`.
- No external anything: no `@import`, no URLs, no data-URI SVG, system font stacks only. No backslashes or `"""` inside the Elm triple-quoted strings (use the literal character, e.g. `█`, not `\2588`).
- Respect `prefers-reduced-motion` for anything that animates.

## 2. Decide the forced theme (important)

`CustomCSSConfiguration.force_light_theme` / `force_dark_theme` lock the whole app (Elm's `Shared.effectiveDarkMode`) to one theme and disable both theme toggles (`UI.themeToggle`). The app derives colors that must **contrast with the page background** (`primaryAnchorColor`, `navAnchorColor`, ...) from that mode, so:

- Background **always dark** (forced dark palette, night looks) -> `ForcesDark`. Currently Terminal, Synthwave, Blueprint, Disco, Psychedelic Poster, Cinematic, Haunted Mansion, Neuro Zoogle, Deep Space.
- Background **always light** (cream paper, glossy aqua, gray window) -> `ForcesLight`. Currently Polaroid, Fiesta, Pirate Map, Y2K Aero, Mac Classic, OS X (Original), Candy Shop, Retro Desktop, Zine, Comic Book.
- Background built from the page's own `--bg` (`color-mix(in srgb, var(--bg) ..., ...)`, or `themedRoot`) so it follows light/dark -> `FollowsTheme`.

Applying a template sets the editor's flags to the template's (cancelling the edit throws the draft away). The dropdown shows a template as selected exactly while the CSS box still equals that template's CSS (`CustomCssTemplates.matching`), and goes back to "Apply Template" as soon as the text is edited. At most one flag, ever (server validates; Elm toggles are mutually exclusive). A style that forces colors in CSS but is not marked forced will get wrong-contrast brand colors -- check this every time.

## 3. Rules learned the hard way

- **Brand utility classes win**: cards carry per-server classes that set `border-color` and `background-color` (specificity beats `.post-card`), so use `border-color: ... !important` / `background: ... !important` when the style must own them; set a *shorthand* border first, then the `-color` override. A `background` shorthand's image layers still show over a brand `background-color`.
- **Forced palettes break the calendar**: `UI.EmittedStylesheet` gives `.events-list`/`.events-strip`/`.events-calendar` a translucent background from the *app's* light/dark mode -- include `eventSurfaces` in any style that forces its own `--bg`.
- `--calendar-accent` is the server's accent color (set by the app) -- use it for "brand" decoration (Town Square).
- **`filter` on a pseudo-element also filters its box-shadow/overlays** (a yellow shadow turned gray). For grayscale/duotone use `background-color` + `background-blend-mode: normal, luminosity` instead. Never put `filter` on `.navbar` (it becomes the containing block for the fixed panels inside it).
- Cards sit in `.flip-animated-item` wrappers, one card per wrapper -- alternate styling with `.flip-animated-item:nth-child(even) .post-card`, not `.post-card:nth-child`.
- **Never cover the top edge of the screen with a fixed overlay**: iOS Safari then treats it, not `.navbar`, as the top bar, so the nav stops reading as solid and the page shows through above it (Terminal's scanlines and Cinematic's vignette did this). Start full-screen fixed overlays below the nav: `top: calc(env(safe-area-inset-top, 0px) + 69px)` (69px = nav height), and give the nav its own scanlines/texture as an extra `background` layer over its solid color.
- Layering: `html::before` < `body::before/::after` (pageImage) < `html::after`, all `z-index: -1` (tree order); `html::after` with a high z-index is a click-through overlay (Terminal's scanlines). `.container::before` is the strip right under the nav.
- `max-width`/layout: `.container` is the 800px column; `main` has the padding; `.navbar` is sticky and *outside* `.container`; the events grid/calendar deliberately break out wider than the column.
- A section label `.section-title` and the "Recent Posts" pill are different elements; headings (`h2`) are often brand-colored pills -- don't assume text sits on `--bg`.

## 4. Tests

In `frontends/elm-spa/tests/CustomCssTemplatesTests.elm`: add the style to the expected names list, bump the style-count test, and add it to the forced-dark / forced-light expectation if it forces a theme. The suite also checks every template for balanced braces/parens, `--custom-media-N` count and `none` fallbacks, no external URLs, size < 64 KiB, and that a style forces the same theme in all three versions. Then:

```
cd frontends/elm-spa && make test    # elm-review + elm-test-rs
make build                            # tests don't compile the page modules
```

## 5. Look at it in a browser (do not skip -- CSS passes tests and still looks wrong)

Needs the backend running (`run-backend` skill) and `.claude/skills/run-elm`'s driver. Test against the Rust-served pages (`http://localhost/posts`, `/events`), since `/custom_css.css` only exists there (the Elm dev server on :1234 instead renders it via `GetCustomCSS`).

1. Dump the template strings with a throwaway Elm worker (delete it afterwards): a `Platform.worker` in `src/` that sends `List.map (\t -> { name, css }) Templates.all` through a port; `elm make` it to JS in the scratchpad and `node -e` it to JSON.
2. Put one on the dev site without an admin session by updating the active row: `UPDATE server_configurations SET custom_css_configuration = '{"media_ids":["<id1>","<id2>"],"force_dark_theme":false}'::jsonb, custom_css = $css$...$css$ WHERE active;` (use two `GLOBAL_PUBLIC` image media ids from `grpcurl -plaintext -d '{}' localhost:27707 rellm.Rellm/GetMedia`).
3. Screenshot with the driver (`nav`, `sleep 3500`, `screenshot`) and **read the PNGs**: the 2-image version on `/posts` (cards + masthead + page image), the plain version on `/events` (calendar must be readable), and light + dark (`eval document.documentElement.setAttribute('data-theme','dark')`) for `FollowsTheme` styles.
4. **Reset the DB when done**: `UPDATE server_configurations SET custom_css_configuration = NULL, custom_css = NULL WHERE active;`.

**Test a returning visit, not just a first one**: a browser that has visited before has the server persisted, so startup takes a different path (`GotReconnectResult`, not `GotMainServerResult`) -- the dev-server CSS fallback once only worked on the first path. Load the page twice in one driver run (`nav`, `sleep`, `nav`, `sleep`, then `eval`) and check the Elm-rendered `#custom-css-stylesheet` is longer than the bare variable block, on both `http://localhost:1234` (Elm dev server) and `http://localhost` (Rust-served).

zsh gotcha when scripting the loop: don't name a shell variable `path` (it is tied to `$PATH`).

## 6. Wrap-up

Commit nothing unless asked. Mention which templates you actually viewed, that animation (parallax, drifting waves, beams) was only seen as static frames, and anything that needs an admin account to confirm (the dropdown/Preview/toggles in the editor itself).
