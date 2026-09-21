# `UI.Flip` collapse-animation rework proposal

## Context

Jon reported a visual bug while testing the Messages sidebar flattening work
(this session): collapsing a group's messages showed "a gap between elements
that suddenly closes after freezing there for a bit." Precisely characterized
over the course of live debugging as: **"mostly-collapse, then fade, then
suddenly finish collapse."** Also seen (unprompted, once asked to look) on:

- PostsPage / UsersPage, toggling a server off in the Accounts panel
- StarredPanel, unstarring a post
- Messages sidebar *and* two-pane detail view

So this is a bug in the shared `UI.Flip` module itself, not anything
Messages-specific — every caller in the app that removes a list item via
`UI.Flip.remove` is affected.

## Root causes found (both confirmed via live browser instrumentation)

Two independent bugs, both contributing to the same visible symptom:

### 1. `gap` CSS property fighting the collapse axis — FIXED, done

Several containers combine a plain `gap`/`row-gap` with `.flip-animated-column`/
`.flip-animated-row`, on the *same axis* the FLIP item actually collapses
along. `gap` is a fixed spacing value between flex children — it does **not**
shrink away as a child's own box height/width animates to zero. So while an
item is collapsing (and for however long it lingers in the DOM afterward,
see bug 2), its neighbor still sees the item's own `gap` contribution as a
dead, un-animating sliver — which then vanishes in one un-animated snap the
instant the item is actually removed from the DOM (fewer children = fewer
gaps, recomputed instantly, no transition). This is *exactly* what
`flip.css`'s own top-of-file doc comment warns about, and it's exactly why
`servers.css` already has two precedents fixing it
(`.federated-servers-strip.flip-animated-row { gap: 0; }`,
`.custom-tabs-strip.flip-animated-row { gap: 0; }`) — those two containers
were already fixed by someone before this session; the others weren't.

**Why this explains "gap size scales linearly with items expanded":** each
simultaneously-collapsing item contributes its own separate `gap`-width
sliver, so N items collapsing at once (e.g. collapsing a big group, or
turning off a server with many posts) shows N stacked slivers.

Fixed in this session (`gap`/`row-gap` removed, container now relies on
`flip.css`'s own `.flip-animated-item` `padding-bottom`/`-right` instead,
exactly as that file's own doc prescribes):

- `messages.css` — `.messages-group-list` (was `gap: 0.4rem`)
- `users.css` — `.user-picker-list` (was `gap: 0.3rem`)
- `shared/my_media_panel.css` — `.my-media-panel-selected-strip` (was `gap: 0.5rem`)

**Checked and confirmed *not* buggy** (left alone, don't touch these):

- `shared/my_media_panel.css` — `.my-media-panel-grid`'s `row-gap: 0.75rem`
- `events.css` — `.occasion-grid`'s `row-gap: 0.4rem`

Both use `.flip-animated-grid`, whose *active* collapse rule in `flip.css`
(`.flip-animated-grid .flip-animated-item.flip-collapsed`) only animates
`grid-template-columns` (width) — the `grid-template-rows: 0fr` line is
present but commented out. So `row-gap` (vertical, between wrapped rows) is
orthogonal to the actual (horizontal) collapse axis and doesn't conflict.
`my_media_panel.css` even has a comment explaining this exact reasoning
already — it's correct, don't "fix" it.

**If reworking per this doc:** once opacity/scale move to CSS transitions too
(see below), re-audit whether the `gap` conflict still applies the same way —
it should, since it's about the *grid-template-rows/columns* collapse
specifically, which isn't changing.

### 2. Opacity/scale fade duration not synced to the CSS collapse — PARTIALLY FIXED

`UI.Flip.enter`/`remove`/`reappear` fade opacity/scale via
`elm-style-animation`'s **default interpolation** for a plain numeric
property, which is a lightly-damped **spring** (`stiffness = 170, damping =
26`, see `Animation.Model.defaultInterpolationByProperty` in the installed
package source, `~/.elm/0.19.2/packages/mdgriffith/elm-style-animation/4.0.0/`).
Springs have no fixed duration — they settle once position+velocity both
drop under a small tolerance, which for these constants took ~400-550ms
empirically (physics estimate: damping ratio ζ ≈ 0.997, ω₀ ≈ 13 rad/s, τ ≈
77ms, ~5-7τ to settle ≈ 385-540ms). Meanwhile `flip.css`'s own
`.flip-animated-item` CSS transition (`grid-template-rows`/`-columns`, the
thing that actually shrinks the box) is a **fixed 250ms**. So the CSS side
visibly finishes well before the JS-driven opacity fade does, and the DOM
node — still present, since only `Animation.Messenger.send onRemoved`
(fired once the spring settles) actually deletes it from the caller's model
— lingers for that gap. That's the "freeze" (nothing moving because the box
is already visually collapsed) before the "sudden finish" (the lingering
node finally gets deleted, snapping whatever was still depending on its
presence, e.g. bug #1's `gap`).

**Fix applied** (`UI/Flip.elm`): added `flipDurationMs = 250` (matching
`flip.css`'s own transition duration) and `cssEase`, a from-scratch
Newton-Raphson solver for CSS's `ease` timing function
(`cubic-bezier(0.25, 0.1, 0.25, 1.0)`, verified numerically correct against
known reference points in isolation — see "Verification methodology"
below). `enter`/`remove`/`reappear` now use
`Animation.toWith (Animation.easing { duration = flipDurationMs, ease = cssEase }) [...]`
instead of `Animation.to [...]` (which used the default spring).

**Measured improvement** (see methodology below): lingering-gap-after-CSS-end
dropped from **399ms → 148ms**, a ~63% reduction. Real and verified, not
theoretical.

**Residual ~100-150ms not yet closed.** Root-caused (not just guessed) to
`Animation.subscription`'s own design:

```elm
subscription msg states =
    if List.any isRunning states then
        Sub.map msg (Browser.Events.onAnimationFrame Tick)
    else
        Sub.none
```

Whenever *nothing* is currently animating, this returns `Sub.none` — no
`requestAnimationFrame` is registered with the browser at all. The instant
`remove` is called (setting `running = True`), Elm's runtime has to notice
the `Sub` changed and register a *fresh* `Browser.Events.onAnimationFrame`
subscription — a "cold start" that appears to take on the order of 100-150ms
before the interpolation's internal clock starts making visible progress,
consistently, regardless of configured duration. **Confirmed this does NOT
scale with item count** — collapsing 1 item vs. 24 items simultaneously
(same page, same test) showed nearly identical total completion time. That
directly rules out a rendering-cost / virtual-DOM-diffing explanation (no
`Html.Lazy` needed here) and points specifically at the Sub
activation/cold-start itself.

Options considered for closing this residual, discussed with Jon:

1. Ship as-is (399→148ms is a big win, residual is small and constant).
2. Tune `flipDurationMs` down to empirically compensate — rejected as a
   fragile magic number tied to this test environment's timing, may not
   generalize to real user hardware/browsers.
3. **Chosen: move opacity/scale off the JS/elm-style-animation path onto
   plain CSS transitions**, riding alongside the existing
   `grid-template-rows`/`-columns` transition. CSS transitions have no
   "cold start" tax — they're purely declarative and start exactly when the
   triggering class change is painted, same as the grid collapse already
   does today. This is the actual ask of this doc.

## The rework: CSS-driven opacity/scale instead of `Animation.render`

### Goal

Eliminate the JS animation-frame subscription entirely for the plain
enter/leave fade (`UI.Flip.State`/`enter`/`remove`/`reappear`/`animate`/
`subscription`), replacing it with a CSS class toggle + `transition:
opacity, transform` declared in `flip.css`, using the *same* 250ms duration
and easing the grid-collapse already uses (so they're inherently synced —
no more possibility of drift between two independently-timed systems).

### What can be deleted/simplified

- `UI.Flip.State`'s `style : Animation.Messenger.State msg` field — replaced
  by nothing (state becomes just `{ removing : Bool, entering : Bool }`, or
  folded away entirely if `itemAttributes` can derive everything from
  `removing`/`entering` alone).
- `animate`, `subscription` (the enter/remove-specific ones) — no more
  per-frame JS stepping needed for opacity/scale.
- `flipDurationMs`, `flipEasing`, `cssEase` (this session's own fix) —
  ironically, once this rework lands, these become unnecessary: CSS drives
  both transitions directly, no JS-side duration/easing value needs to
  match anything by hand anymore (only `flip.css`'s own `transition`
  declarations need to state the duration once).
- Every caller's own `Animate`-equivalent `Msg`/`update` case for enter/leave
  animation stepping (e.g. `MessagesPage.Animate`/`animateSidebarDict`,
  `MessagesPage.DetailMessageAnimate`/`animateMessageDict`, `PostsPage.Animate`,
  `UsersPage.Animate`, `StarredPanel`'s equivalent, etc.) — no longer needed
  for the fade itself.

### What must stay JS-driven (do NOT touch)

`UI.Flip.MoveState`/`startMove`/`startMoveScaled`/`moveAttributes`/
`moveAnimate`/`moveSubscription`/`beginReorder`/`applyReorder`/
`measureElementsCmd` — the drag-reorder slide animation. This measures real
pixel offsets via `Browser.Dom` (from-position to-position deltas) and
animates a CSS `transform` by that measured amount — CSS alone can't know
those offsets without JS measurement first. This is a *genuinely* different
animation (reorder slide, not enter/leave fade) and is out of scope for this
rework. Don't conflate the two `State` types when editing.

### Removal timing (`onRemoved`)

Currently `Animation.Messenger.send onRemoved` fires once the spring/easing
settles. Without a JS animation to "settle," the natural replacement is
listening for the CSS transition's own `transitionend` event on the
collapsing element and firing `onRemoved` from that — which is *already*
exactly what drives the grid collapse today, so this needs no new timing
concept, just wiring a `Html.Events.on "transitionend"` handler (filtered by
`event.propertyName` so multiple transitioning properties on one element —
`grid-template-rows`, `opacity`, `transform` — don't fire it multiple times;
pick one canonical property per axis, e.g. `grid-template-rows` for
`Vertical`, `grid-template-columns` for `Horizontal`, to key off of) onto
`itemAttributes`'s returned div.

Concretely: `itemAttributes` currently returns `msg`-free attributes (see its
own doc comment on why — `Animation.render` never produces a `msg`). Once
`onRemoved` is wired via a native DOM event instead of an animation-library
callback, `itemAttributes` will need to *become* `msg`-producing for the
`removing` case, changing its type signature — audit every call site (see
list below) for the `Html.map`/type-variable implications the current doc
comment explicitly calls out avoiding.

### Class/CSS design sketch (not final, just a starting point)

`flip.css`, alongside the existing `.flip-collapsed` grid-track rule:

```css
.flip-animated-item {
  /* existing grid-template-rows/columns transition, unchanged */
  transition: grid-template-rows 0.25s ease, grid-template-columns 0.25s ease,
    opacity 0.25s ease, transform 0.25s ease;
  opacity: 1;
  transform: scale(1);
}

.flip-animated-item.flip-collapsed {
  opacity: 0;
  transform: scale(0.92);
}
```

`itemAttributes` then just needs to toggle the *same* `flip-collapsed` class
it already toggles for `entering || removing` — no separate class needed,
since opacity/scale and grid-track collapse can share one trigger and one
`transition` declaration. This is actually simpler than today's two-system
approach, not just equivalent.

Watch out for: `reappear` (interrupting a removing item back to entering)
needs the class removed *before* the transition would have finished — browser
transition-reversal from a mid-flight state is well-supported for simple
opacity/transform, should "just work" by toggling the class back, but verify
live (this is exactly the kind of thing to verify live, not just reason
about — see methodology below).

### Every caller to touch

Search `grep -rln "UI.Flip\." src` for the full list; as of this session:

- `src/Components/Pages/MessagesPage.elm` — both `sidebarAnimations`
  (this session's own new flattened list) and `detailThreadAnimations`
- `src/Components/Pages/PostsPage.elm`
- `src/Components/Pages/UsersPage.elm`
- `src/Components/Pages/EventsPage.elm`
- `src/Components/Pages/ServerInformationPage/FederationTab.elm`
- `src/Components/Pages/ServerInformationPage/SettingsTab.elm`
- `src/Components/PostReplies.elm`
- `src/Components/UserPicker.elm`
- `src/Shared/StarredPanel.elm`
- `src/Shared/MyMediaPanel.elm`
- `src/Pages/Event/EventId_.elm`
- `src/UI.elm` (servers strip, accounts)
- Presumably `src/Pages/Home_.elm` too (`UI.Flip`'s own module doc says this
  is where the pattern was originally extracted from) — confirm.

Each has its own `Animate`-style `Msg`/subscription/update-fold for the
enter/remove state that becomes dead code once this lands. This is a wide
blast radius — plan for a careful, one-caller-at-a-time migration with live
verification (screenshot or instrumented `transitionend` check) after each,
rather than a single big-bang rewrite across all ~13 files at once.

## Verification methodology (reuse this, don't re-derive it)

Everything above was confirmed live, not just reasoned about from reading
code — per standing practice for this kind of bug, static reading alone
was actively misleading at a couple of points during this investigation
(see "Dead ends" below). Use the `run-elm` skill's `driver.mjs` (Playwright).
Key techniques that worked:

**Measuring the lingering-DOM-node gap** (CSS `transitionend` vs. actual
removal): attach a `transitionend` listener to the collapsing
`.flip-animated-item` and a `MutationObserver({childList: true})` on its
parent list, both timestamped against a shared `performance.now()` origin.
Trigger the collapse (e.g. toggle a server checkbox off in the Accounts
panel on the home feed — no login required, `.posts-list` always has
~30 items). Compare `transitionend`'s timestamp to the `MutationObserver`'s
`removedNodes` timestamp.

**Measuring the real interpolation curve cleanly**: do NOT use a tight
`setTimeout`-based polling loop for this — it competes with the page's own
`requestAnimationFrame`-driven animation subscription for the JS event
loop and throttles/distorts the measured curve (this cost real time to
figure out this session — the first "before/after" numbers, while directionally
correct, had inflated absolute values from this interference). Use a
`requestAnimationFrame`-driven sampling loop instead (same rendering
pipeline the animation itself uses, no artificial throttling), reading the
element's own `style` attribute (`el.getAttribute('style')`, parsed for
`opacity:`) each frame.

**Testing whether a delay scales with item count**: toggle a
server/account with many affected items (this session: `jonline.io`, 24
posts) vs. one with a single item, same measurement, compare total
completion time. Nearly-identical timing across very different item counts
is strong evidence against a rendering-cost explanation.

**Testing a specific numeric claim in isolation**: for verifying the
`cssEase` bezier solver was mathematically correct independent of the
browser/Elm runtime, a plain Node.js reimplementation of the same
Newton-Raphson math (copy the algorithm, run `node -e "..."`) was faster
and more conclusive than compiling Elm and threading debug output through
the app.

**Creating live test data (Messages specifically)**: creating a fresh local
account (see `run-elm` skill's own "log in as a fresh test account" recipe)
and composing messages between two test accounts is slow/fiddly (several
failed attempts this session — flaky post-account-creation navigation,
wrong-button mis-clicks). If you just need *some* animated list to test
against, prefer PostsPage's server-toggle or StarredPanel's star/unstar —
both need no data setup, work on an anonymous session, and reproduce the
exact same shared `UI.Flip` bug.

### Dead ends worth knowing about (so you don't re-walk them)

- Initially suspected the sidebar flattening from this session's OTHER work
  (folding Messages' sidebar into one big `Html.Keyed.node`) caused a
  rendering-cost problem needing `Html.Lazy`. Ruled out once Jon reported
  the *same* bug on PostsPage/UsersPage/StarredPanel (small, unrelated
  lists, no flattening involved) — it was never a Messages-specific or
  list-size-specific bug at the `Html.Lazy` level.
- Checking `getComputedStyle` on the collapsing item's *child* element for
  the opacity value returns nothing useful — `Animation.render`'s inline
  style attributes land on the `.flip-animated-item` wrapper itself (what
  `itemAttributes` returns attributes for), not on the content nested
  inside it. Check `target.getAttribute('style')` on the wrapper.
- The very first duration-matched build looked like it wasn't taking effect
  at all (the observed decay curve looked exactly like the old spring).
  Turned out to be the tight-polling-loop measurement-interference problem
  above, not a code bug — confirmed by setting `flipDurationMs` to an
  absurd, unmistakable value (3000ms) and seeing the fade visibly slow to
  match, which proved the code path *was* live and working; the
  measurement methodology was just wrong.

## Current repo state (as of writing this doc)

- `UI/Flip.elm`: `flipDurationMs = 250`, `flipEasing`, `cssEase` added;
  `enter`/`remove`/`reappear` use `Animation.toWith flipEasing` instead of
  the default-spring `Animation.to`. This is a real, verified improvement
  and should stay regardless of whether the CSS-transition rework above
  ever happens — don't revert it as part of that rework's own cleanup
  until the CSS replacement is actually landed and verified end-to-end.
- `messages.css`, `users.css`, `shared/my_media_panel.css`: `gap`/`row-gap`
  removed from the three conflicting containers (see bug #1 above). This
  fix stands independently and isn't affected by whether the CSS-transition
  rework happens.
- Both fixes are committed (an automated checkpoint captured them mid-session
  under commit `79a99672`, "Claude asked: Keep tuning? LESSSSGO" — Jon has
  some auto-commit tooling tied to `AskUserQuestion` calls in this
  environment; not something either fix depended on, just noting where to
  find them in `git log` if needed).
- This session's *other* major change (unrelated to the animation bug, but
  touched the same files) was flattening Messages' sidebar into one
  FLIP-animated list (`MessagesPage.elm`'s `sidebarAnimations`) and a
  `Conversation`/`ConversationSummary` type consolidation in
  `Components/Messages.elm` — both already complete, compiled, and
  elm-review-clean as of this doc. Not blocking for this rework, just
  context if `MessagesPage.elm` looks unfamiliar.
