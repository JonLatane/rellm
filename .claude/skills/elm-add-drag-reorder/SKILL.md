---
name: elm-add-drag-reorder
description: Add touch/mouse drag-to-reorder (on top of the existing ▲/▼ or ◀/▶ FLIP reorder arrows) to a reorderable list in the Elm SPA (frontends/elm-spa), or debug/extend the shared UI.Drag module. Use when a list already uses UI.Flip.reorderButtons/reorderButtonPair and should also drag, or when drag feels laggy/wrong.
---

Drag-to-reorder lives in one shared module, `frontends/elm-spa/src/UI/Drag.elm` (read its module doc first), layered on `UI.Flip`'s FLIP animations. Lists already using it: Starred panel (`Shared/StarredPanel.elm`), Accounts + Servers strip (`Shared/AccountsPanel.elm`, rendered in `UI.elm`), custom nav tabs (`ThemeTab/CustomTabsConfiguration.elm`), Federated + Mastodon server editors (`FederationTab.elm`), My Media selected-media strip (`Shared/MyMediaPanel.elm`). Copy one of them — `CustomTabsConfiguration.elm` is the smallest horizontal example, `StarredPanel.elm` the smallest vertical one.

The list must already have: a keyed `.flip-animated-row`/`-column` container, a stable string key per item, a DOM `id` per item (the element carrying `UI.Flip.moveAttributes`), and a per-item `UI.Flip.MoveState` dict + settle msg (what the tap-an-arrow path uses).

## Wiring (7 places)

1. **Model**: `drag : UI.Drag.State` (= `UI.Drag.init`), next to the list's `moveAnimations`. Msg: `DragMsg UI.Drag.Msg`.
2. **Subscription**: `Sub.map DragMsg (UI.Drag.subscriptions model.drag)` (only live while a measurement is in flight).
3. **Config** (rebuild from the model on every call): `{ axis, owner (unique string), domId, keys (current order, as strings), groupOf }`. `groupOf = \_ -> ""` for a free list; give a pinned item its own group id, or split groups where items can't cross (AccountsPanel: main-server accounts vs. rest; pinned main server).
4. **Update branch** `DragMsg m`: call `UI.Drag.update config m model.drag`, then fold the `Output`s in order:
   - `Reordered newKeys` → write the order back where it really lives (`UI.Drag.reorderByKeys keyOf newKeys list`, or for `sortOrder`-backed lists AccountsPanel's `applyDraggedOrder`) **and persist** exactly like the tap path does.
   - `Slide slides` → `moveAnimations = UI.Drag.applySlides SettledMsg slides moveAnimations`.
   - `Cmd.map DragMsg dragCmd`.
5. **Arrows**: pass `dragAttrs = UI.Drag.handleAttrs DragMsg axis key model.drag` to `UI.Flip.reorderButtons`/`reorderButtonPair`, and wrap each arrow's click with `UI.Drag.onClick drag msg` (or `onClickStoppingPropagation` where the arrows sit inside another clickable) so the click after a drag is swallowed. Skip `handleAttrs` (pass `[]`) wherever the arrows are hidden.
6. **Overlay**: add `UI.Drag.overlay DragMsg axis model.drag` once in the list's view — as an extra *keyed child* (`|> List.map (Tuple.pair "drag-overlay")`) of the keyed container, so no wrapper `div` disturbs the flex layout (it's `position: fixed`).
7. Optional: add class `reorder-dragging` to the item while `UI.Drag.isDragging drag key`.

CSS is in `public/style/ui/drag.css` (already linked from `index.html`); nothing per-list needed.

## How it works / gotchas (all learned the hard way)

- **Pointer events, not mouse/touch.** `touch-action: none` on the handle (drag.css) stops touch scrolling; touch events keep targeting the starting element, mouse drags escape the small arrow, so `overlay` (full-screen, only mounted once the drag passes a 4px threshold) catches those.
- **Handlers are attached from the start**, filtered by `buttons > 0`. Attaching them only after the press re-renders loses a fast first move that leaves a 20px arrow before the frame lands (found by a headless drag test that did nothing).
- **Multi-slot jumps**: each pointer move measures *all* items in one `Ports.measureElements` round trip, picks the slot (`targetOrder`: pointer vs neighbors' midpoints along the axis), emits `Reordered`, waits one frame (`Dom.getViewport`), measures again, emits `Slide`s. Same measure/reorder/measure recipe as `UI.Flip.measureElementsCmd` documents — one-frame wait is mandatory or the second measure sees the old layout.
- **Interrupting running slides** works because the port also reports `layoutX/layoutY` (position with the in-flight translate removed, via `DOMMatrixReadOnly`): targets are judged against layout positions, and slide deltas are old *visible* position minus new *layout* position.
- **Linger/lag gotcha**: never re-measure after a "nothing to change" round trip — that looped a full measurement every frame while holding and janked the slide (and scaled with item count). `State.slot` caches the pointer range `( low, high ]` where the target can't change (`slotRange`); inside it the pointermove decoder fails (no Elm message at all) and `checkPointer` is a no-op. If drag still feels eager, the next lever is hysteresis around midpoints.
- **Keys vs. DOM ids**: `keys` are the list's own keys; `domId key` must give the id of the element the measurement should read (the one that carries the move transform).
- **Horizontal lists assume a single row** (only x is compared); no auto-scroll while dragging a scrolling strip (Servers strip clips at the panel edge).
- A `.flip-moving` item turns `display: grid` into `display: flex`, which shrinks short-content rows (Bluesky account) while sliding — `flip.css` has a `.flip-animated-column ... > * { flex: 1 1 auto }` fix; keep it in mind for any new vertical FLIP list.
- `Ports.elementsMeasured` is one shared untargeted port: `UI.Drag` tags its requests `"drag:" ++ owner` and ignores everyone else's results, so `owner` must be unique per list.

## Testing

- Pure logic: `tests/DragTests.elm` (`targetOrder`, `slotRange`, `reorderByKeys`) — extend when changing it. `make test` = elm-review + elm-test-rs.
- Real behavior needs a browser; use the `run-elm` driver / a throwaway Playwright script (import from `.claude/skills/run-elm/node_modules`): seed `localStorage.rellmStarredPosts` with fake keys (`["a@h1.test", ...]`), open the Starred panel (narrow viewport shows the ⭐ toggle in the nav), `mouse.down` on an arrow, step `mouse.move` in ~15px steps with 16ms waits, assert row order/`localStorage` after `mouse.up`. Count `getBoundingClientRect` calls (monkeypatch) over a few seconds of jiggling inside one slot to check the linger fix: should be ~one measurement pass, not hundreds.
