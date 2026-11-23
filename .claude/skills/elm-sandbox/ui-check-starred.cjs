#!/usr/bin/env node
// Drives the built Elm app (see serve.cjs) against STUBBED Bluesky responses and reports what the
// Starred nav button's badges / panel do. A worked example of "test federation UI without accounts":
// every non-localhost request is intercepted, and a fake Bluesky account is seeded into localStorage.
//
//   node ui-check-starred.cjs            # screenshots land in /tmp/ui-check-*.png
//
// Scenarios:
//   A  star a post while Bluesky's AppView is slow to index the new like (the original bug): the
//      Server tab must keep the post after the refetch, and the badge spinner must show while loading.
//   B  the like write fails (500): the optimistic entry must be rolled back and a reason shown.
const { chromium } = require("playwright");

const APP = process.env.APP || "http://localhost:1234";
const DID = "did:plc:s2esyvxdshsz5t64io6y4kzf";
const TARGET = `at://${DID}/app.bsky.feed.post/3myichbpp522p`;
const OTHER = "at://did:plc:aaaaaaaaaaaaaaaaaaaaaaaa/app.bsky.feed.post/3aaaaaaaaaaaa";

/** A JWT whose `exp` is far in the future (the app reads it to decide whether to refresh before a request). */
const jwt = exp => ["e30", Buffer.from(JSON.stringify({ exp })).toString("base64url"), "sig"].join(".");

const postView = (uri, text, liked) => ({
  uri,
  cid: "bafy" + uri.length,
  author: { did: uri.split("/")[2], handle: uri.includes("aaaa") ? "alice.test" : "bob.test", displayName: uri.includes("aaaa") ? "Alice" : "Bob" },
  record: { $type: "app.bsky.feed.post", text, createdAt: "2026-11-20T12:00:00.000Z" },
  likeCount: 3, replyCount: 0, indexedAt: "2026-11-20T12:00:01.000Z",
  viewer: liked ? { like: "at://did:plc:me/app.bsky.feed.like/xyz" } : {},
});

/**
 * Fake Bluesky. `initialLikes` is what the account has liked; a like (or unlike) only shows up in what the
 * AppView reports (`getActorLikes`, `viewer.like`) after `indexLagMs` -- in BOTH directions, like the real
 * one: right after an unlike the old list still has the post.
 */
function makeBluesky({ indexLagMs, likesDelayMs, failWrite, initialLikes = [OTHER], hideViewerLike = false, dropEveryFifth = false, failLikesFromOffset = null, expireTokenOnce = false }) {
  const state = { likes: initialLikes.slice(), ops: [], log: [], deleted: [], likesPages: [], refreshes: 0, tokensSeen: [], expired: false };
  const visible = () => {
    const now = Date.now();
    let likes = state.likes.slice();
    for (const op of state.ops) {
      if (now - op.at < indexLagMs) continue;
      likes = op.add ? (likes.includes(op.uri) ? likes : [op.uri, ...likes]) : likes.filter(x => x !== op.uri);
    }
    return likes;
  };
  return {
    state,
    likesNow: visible,
    async handle(route) {
      const req = route.request(), u = new URL(req.url()), p = u.pathname;
      const json = (body, status = 200) => route.fulfill({ status, contentType: "application/json", headers: { "access-control-allow-origin": "*" }, body: JSON.stringify(body) });
      if (req.method() === "OPTIONS") return route.fulfill({ status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "*" } });
      state.log.push(`${req.method()} ${u.host}${p}`);
      if (p.endsWith("refreshSession")) { state.refreshes++; return json({ accessJwt: jwt(9999999999) + "r" + state.refreshes, refreshJwt: "ref" + state.refreshes, handle: "me.test", did: "did:plc:me" }); }
      if (p.endsWith("getActorLikes")) {
        await new Promise(r => setTimeout(r, likesDelayMs));
        // Paged like the real endpoint: `limit` (<= 100) records per page, `cursor` is where the next page starts.
        // With `dropEveryFifth`, every fifth record is hydrated away (deleted/blocked posts) -- a page then holds
        // FEWER posts than asked for while still handing out a cursor, so a short page is not the last one.
        const all = visible();
        const limit = Math.min(Number(u.searchParams.get("limit") || 50), 100);
        const offset = Number(u.searchParams.get("cursor") || 0);
        state.likesPages.push({ limit, offset });
        // A token that expires between pages: the first request for page 2 is rejected like an expired JWT.
        if (expireTokenOnce && offset >= 100 && !state.expired) { state.expired = true; return json({ error: "ExpiredToken", message: "Token has expired" }, 400); }
        if (failLikesFromOffset !== null && offset >= failLikesFromOffset) return json({ error: "InternalServerError", message: "page failed" }, 500);
        const page = all.slice(offset, offset + limit).filter((_, i) => !dropEveryFifth || (offset + i) % 5 !== 4);
        const next = offset + limit < all.length ? String(offset + limit) : undefined;
        return json({ feed: page.map(uri => ({ post: postView(uri, "liked post", true) })), ...(next ? { cursor: next } : {}) });
      }
      if (p.endsWith("getPosts")) {
        const uri = u.searchParams.get("uris");
        return json({ posts: [postView(uri, uri === TARGET ? "The post being starred" : "liked post", !hideViewerLike && visible().includes(uri))] });
      }
      if (p.endsWith("getPostThread")) {
        const uri = u.searchParams.get("uri");
        return json({ thread: { $type: "app.bsky.feed.defs#threadViewPost", post: postView(uri, "The post being starred", false), replies: [] } });
      }
      if (p.endsWith("createRecord")) {
        if (failWrite) return json({ error: "InternalServerError", message: "boom" }, 500);
        state.ops.push({ add: true, uri: TARGET, at: Date.now() });
        return json({ uri: "at://did:plc:me/app.bsky.feed.like/like1", cid: "bafylike" });
      }
      if (p.endsWith("deleteRecord")) {
        // Like the real server: deleting a record key that isn't one of the account's like records changes nothing.
        const rkey = JSON.parse(req.postData() || "{}").rkey;
        state.deleted.push(rkey);
        if (rkey === "like1" || rkey === "xyz") state.ops.push({ add: false, uri: TARGET, at: Date.now() });
        return json({});
      }
      return json({}, 404);
    },
  };
}

async function newPage(browser, bsky, browserStars = []) {
  const ctx = await browser.newContext({ viewport: { width: 1000, height: 900 }, deviceScaleFactor: Number(process.env.DSF || 1) });
  const token = jwt(9999999999);
  await ctx.addInitScript(([stars, token]) => {
    localStorage.setItem("rellmStarredPosts", JSON.stringify(stars));
    localStorage.setItem("rellmBlueskyAccounts", JSON.stringify([{
      handle: "me.test", accessToken: token, refreshToken: "ref", enabled: true, avatarUrl: null,
      displayName: "Me", sortOrder: 0, needsReauth: false, pdsHost: "bsky.social",
    }]));
  }, [browserStars, token]);
  await ctx.route(url => !/localhost|127\.0\.0\.1/.test(new URL(url).host), r => bsky.handle(r));
  const page = await ctx.newPage();
  page.on("pageerror", e => console.log("PAGE ERROR:", String(e).slice(0, 200)));
  return page;
}

/** What the Starred button's bottom-right (server) badge looks like right now. */
const badge = page => page.evaluate(() => {
  const b = document.querySelector(".starred-menu .corner-badge-bottom-right");
  if (!b) return null;
  const spin = b.querySelector(".starred-count-spinner");
  return { text: b.textContent.replace("↻", "").trim(), hidden: b.classList.contains("count-badge-hidden"), spinning: !!spin && spin.classList.contains("loading") };
});
/** The Browser/Server tab counts in the open panel (the Server tab lists every account section's posts). */
const tabCounts = page => page.evaluate(() => Object.fromEntries([...document.querySelectorAll(".starred-panel-tab")].map(t => {
  const n = t.querySelector(".tab-count-badge");
  return [t.textContent.replace(n ? n.textContent : "", "").trim(), n ? Number(n.textContent) : null];
})));
/** Everything a person sees counted: both corner badges and both tab counts (the panel is mounted while closed). */
const counts = async page => {
  const b = await badge(page);
  const tabs = await tabCounts(page);
  const top = await page.evaluate(() => {
    const e = document.querySelector(".starred-menu .corner-badge-top-right");
    return e ? Number(e.textContent.replace("↻", "").trim()) : null;
  });
  const [browserTab, serverTab] = Object.values(tabs);
  return { topBadge: top, bottomBadge: b && !b.hidden ? Number(b.text || 0) : 0, spinning: !!(b && b.spinning), browserTab, serverTab };
};
const fmt = c => `top=${c.topBadge} bottom=${c.bottomBadge}${c.spinning ? "↻" : ""} | tabs: browser=${c.browserTab} server=${c.serverTab}`;
const errorBanner = page => page.evaluate(() => {
  const e = document.querySelector(".starred-panel-error");
  if (!e) return null;
  const r = e.getBoundingClientRect(), cs = getComputedStyle(e);
  return { visible: !e.classList.contains("hidden"), text: e.textContent.replace("✕", "").trim(), box: [r.x, r.y, r.width, r.height].map(Math.round), opacity: cs.opacity };
});
const sleep = ms => new Promise(r => setTimeout(r, ms));
let failures = 0;
const check = (ok, what) => { console.log(`${ok ? "PASS" : "FAIL"}  ${what}`); if (!ok) failures++; };

(async () => {
  const browser = await chromium.launch();
  const postUrl = `${APP}/post/${DID}~3myichbpp522p@bluesky`;

  const only = process.env.ONLY; // e.g. ONLY=counts runs just the count-consistency scenarios
  const KEY = `${TARGET}@bluesky:`; // how the browser persists a star on TARGET
  // A browser star on some unrelated post, so the Browser/Server tab strip is always rendered (as for anyone
  // with both kinds of star) and the Server tab's count can be read at every step.
  const FILLER = "at://did:plc:zzzzzzzzzzzzzzzzzzzzzzzz/app.bsky.feed.post/3zzzzzzzzzzzz@bluesky:";

  /** Counts as they change over `ms`, right after `action` -- so both the instant and the post-refetch values show. */
  async function timeline(page, label, action, expect, ms = 8000) {
    const first = await counts(page);
    await action();
    const samples = [{ t: 0, ...(await counts(page)) }];
    for (let t = 300; t <= ms; t += 300) { await sleep(300); samples.push({ t, ...(await counts(page)) }); }
    const lines = [];
    for (const smp of samples) if (!lines.length || fmt(lines[lines.length - 1].c) !== fmt(smp)) lines.push({ t: smp.t, c: smp });
    console.log(`   ${label}\n     before: ${fmt(first)}`);
    for (const l of lines) console.log(`     +${String(l.t).padStart(4)}ms: ${fmt(l.c)}`);
    const last = samples[samples.length - 1];
    check(samples.every(x => x.topBadge === x.browserTab && x.bottomBadge === x.serverTab),
      `${label}: the badges show the same numbers as the Browser/Server tabs at every step`);
    check(last.serverTab === first.serverTab + expect.server && last.browserTab === first.browserTab + expect.browser,
      `${label}: settles at Server ${first.serverTab + expect.server}, Browser ${first.browserTab + expect.browser} (was ${first.serverTab} / ${first.browserTab})`);
    check(samples.every(x => x.serverTab === samples[0].serverTab && x.browserTab === samples[0].browserTab),
      `${label}: no flip-flop after the optimistic change -- the refetch doesn't undo it`);
    return { first, last, samples };
  }
  const clickStar = page => page.locator(".post-star >> visible=true").first().click();
  const manyLikes = n => Array.from({ length: n }, (_, i) => `at://did:plc:aaaaaaaaaaaaaaaaaaaaaaaa/app.bsky.feed.post/3x${String(i).padStart(4, "0")}`);
  const open = async (initialLikes, stars, opts = {}) => {
    const bsky = makeBluesky({ indexLagMs: 3000, likesDelayMs: 600, failWrite: false, initialLikes, ...opts });
    const page = await newPage(browser, bsky, stars);
    await page.goto(postUrl, { waitUntil: "load" });
    await page.waitForSelector(".post-star >> visible=true", { timeout: 20000 });
    await page.waitForSelector(".starred-menu:not(.hidden)", { timeout: 20000 });
    await sleep(2000);
    page.bsky = bsky;
    return page;
  };

  // ---- C/D/E: do the counts agree with each other, and move the right way on star / unstar? ---------
  if (!only || only === "counts") {
    console.log("\nC  liked on Bluesky, not starred here (server-only)");
    let page = await open([OTHER, TARGET], [FILLER]);
    await timeline(page, "click the (filled) star -> unstar", () => clickStar(page), { server: -1, browser: 0 });
    await timeline(page, "click again -> star", () => clickStar(page), { server: +1, browser: +1 });
    await page.close();

    console.log("\nD  starred here AND liked on Bluesky (overlap)");
    page = await open([OTHER, TARGET], [FILLER, KEY]);
    await timeline(page, "click -> unstar", () => clickStar(page), { server: -1, browser: -1 });
    await timeline(page, "click again -> star", () => clickStar(page), { server: +1, browser: +1 });
    await page.close();

    console.log("\nE  not starred, not liked");
    page = await open([OTHER], [FILLER]);
    await timeline(page, "click -> star", () => clickStar(page), { server: +1, browser: +1 });
    await timeline(page, "click again -> unstar", () => clickStar(page), { server: -1, browser: -1 });
    await page.close();
  }

  // ---- H/I/J: a list longer than one page ----------------------------------------------------------------
  // What a person reads: the Server tab's label and the bottom-right badge.
  const shownCounts = page => page.evaluate(() => {
    const tab = [...document.querySelectorAll(".starred-panel-tab")].find(t => t.textContent.includes("Server"));
    const b = document.querySelector(".starred-menu .corner-badge-bottom-right");
    return {
      serverTab: tab ? tab.querySelector(".tab-count-badge").textContent.trim() : null,
      badge: b ? b.textContent.replace("↻", "").trim() : null,
    };
  });
  if (!only || only === "pages") {
    console.log("\nH  251 likes (3 pages of 100): all loaded, count is exact");
    let page = await open([OTHER, ...manyLikes(250)], [FILLER]);
    await sleep(2500);
    let shown = await shownCounts(page);
    console.log(`   Server tab "${shown.serverTab}", badge "${shown.badge}", pages requested: ${JSON.stringify(page.bsky.state.likesPages)}`);
    check(shown.serverTab === "251" && shown.badge === "251", "H  the Server tab and badge show all 251 likes (not stuck at the first page)");
    check(page.bsky.state.likesPages.every(p => p.limit === 100), "H  likes are requested 100 at a time (the endpoint's maximum)");
    await page.close();

    console.log("\nI  351 likes: loads up to the cap and says there are more");
    page = await open([OTHER, ...manyLikes(350)], [FILLER]);
    await sleep(3000);
    shown = await shownCounts(page);
    console.log(`   Server tab "${shown.serverTab}", badge "${shown.badge}", pages requested: ${page.bsky.state.likesPages.length}`);
    check(shown.serverTab === "300+" && shown.badge === "300+", "I  shows \"300+\", not a count that looks complete");
    check(page.bsky.state.likesPages.length === 3, "I  stops after 3 pages instead of fetching all 4");
    await page.close();

    console.log("\nK  the second page fails: keep the first page and say there is more");
    page = await open([OTHER, ...manyLikes(250)], [FILLER], { failLikesFromOffset: 100 });
    await sleep(3000);
    shown = await shownCounts(page);
    console.log(`   Server tab "${shown.serverTab}", badge "${shown.badge}", pages requested: ${JSON.stringify(page.bsky.state.likesPages)}`);
    check(shown.serverTab === "100+" && shown.badge === "100+", "K  the 100 likes already loaded are kept and shown as \"100+\" (not an error / an empty tab)");
    await page.close();

    console.log("\nL  the access token expires between pages: refresh it and load everything");
    page = await open([OTHER, ...manyLikes(250)], [FILLER], { expireTokenOnce: true });
    await sleep(3500);
    shown = await shownCounts(page);
    console.log(`   Server tab "${shown.serverTab}", badge "${shown.badge}", session refreshes: ${page.bsky.state.refreshes}, pages requested: ${JSON.stringify(page.bsky.state.likesPages)}`);
    check(page.bsky.state.refreshes === 1, "L  the rejected token made the app refresh the session (once)");
    check(shown.serverTab === "251" && shown.badge === "251", "L  after the refresh all 251 likes are loaded, not a partial \"100+\"");
    await page.close();

    console.log("\nJ  a page with posts dropped (deleted/blocked) still has a cursor: keep going");
    page = await open(manyLikes(250), [FILLER], { dropEveryFifth: true });
    await sleep(3000);
    shown = await shownCounts(page);
    console.log(`   Server tab "${shown.serverTab}", badge "${shown.badge}", pages requested: ${page.bsky.state.likesPages.length} (each page returns 80 of 100)`);
    check(shown.serverTab === "200" && shown.badge === "200", "J  all 200 surviving likes are loaded (a short page is not the last page)");
    await page.close();
  }

  // ---- F/G: Bluesky hasn't told us about the like yet -----------------------------------------------
  if (!only || only === "counts") {
    console.log("\nF  star, then unstar before the AppView has indexed the like (viewer.like still empty)");
    let bsky = makeBluesky({ indexLagMs: 3000, likesDelayMs: 600, failWrite: false, initialLikes: [OTHER] });
    let page = await newPage(browser, bsky, [FILLER]);
    await page.goto(postUrl, { waitUntil: "load" });
    await page.waitForSelector(".post-star >> visible=true", { timeout: 20000 });
    await page.waitForSelector(".starred-menu:not(.hidden)", { timeout: 20000 });
    await sleep(2000);
    const start = await counts(page);
    await clickStar(page);          // like
    await sleep(900);               // well inside the 3s lag
    await clickStar(page);          // unlike, while viewer.like is still empty
    await sleep(9000);              // the AppView catches up, a few refetches happen
    const end = await counts(page);
    console.log(`   start: ${fmt(start)}\n   end:   ${fmt(end)}\n   deleteRecord keys sent: ${JSON.stringify(bsky.state.deleted)}`);
    check(bsky.state.deleted.includes("like1"), "F  the unlike deleted the like it had just created (via the remembered record URI)");
    check(!bsky.likesNow().includes(TARGET), "F  once the AppView has caught up, Bluesky really no longer has the like (nothing left hidden by Rellm)");
    await page.close();

    check(end.serverTab === start.serverTab && end.bottomBadge === end.serverTab, "F  the Server tab/badge end where they started, not hiding or inventing a like");

    console.log("\nG  unlike when no like record can be found (nothing remembered, viewer.like empty)");
    bsky = makeBluesky({ indexLagMs: 3000, likesDelayMs: 600, failWrite: false, initialLikes: [OTHER, TARGET], hideViewerLike: true });
    page = await newPage(browser, bsky, [FILLER]);
    await page.goto(postUrl, { waitUntil: "load" });
    await page.waitForSelector(".post-star >> visible=true", { timeout: 20000 });
    await page.waitForSelector(".starred-menu:not(.hidden)", { timeout: 20000 });
    await sleep(2000);
    const gStart = await counts(page);
    await clickStar(page);
    await sleep(3000);
    const gEnd = await counts(page);
    const err = await errorBanner(page);
    console.log(`   start: ${fmt(gStart)}\n   end:   ${fmt(gEnd)}\n   banner: ${JSON.stringify(err && err.text)}`);
    check(err && err.visible && /Couldn't unlike on Bluesky/.test(err.text), "G  says it couldn't unlike, instead of pretending it worked");
    check(gEnd.serverTab === gStart.serverTab, "G  the still-liked post stays in the Server tab (not hidden)");
    check(bsky.state.deleted.length === 0, "G  no deleteRecord was sent (there was nothing to delete)");
    await page.close();
  }

  if (only) {
    await browser.close();
    console.log(failures ? `\n${failures} check(s) FAILED` : "\nall checks passed");
    process.exit(failures ? 1 : 0);
  }

  // ---- A: slow AppView indexing --------------------------------------------------------------
  {
    const bsky = makeBluesky({ indexLagMs: 6000, likesDelayMs: 1200, failWrite: false });
    const page = await newPage(browser, bsky);
    await page.goto(postUrl, { waitUntil: "load" });
    await page.waitForSelector(".post-star", { timeout: 20000 });
    await page.waitForSelector(".starred-menu:not(.hidden)", { timeout: 20000 });
    await sleep(1500);
    console.log("A  before starring, badge:", JSON.stringify(await badge(page)));
    await page.screenshot({ path: "/tmp/ui-check-a-before.png" });
    await page.locator(".post-star >> visible=true").first().click();
    const seen = [];
    for (let i = 0; i < 24; i++) { seen.push({ t: i * 250, ...(await badge(page)) }); if (i > 0 && seen[i].spinning && !seen.snapped) { seen.snapped = true; await page.screenshot({ path: "/tmp/ui-check-a-loading.png", clip: { x: 100, y: 0, width: 160, height: 70 }, scale: "device" }); } await sleep(250); }
    console.log("A  badge over time:", seen.map(s => `${s.t}ms:${s.text || "-"}${s.spinning ? "↻" : ""}${s.hidden ? "(hidden)" : ""}`).join("  "));
    const last = seen[seen.length - 1];
    check(seen.some(s => s.spinning), "A  spinner shows while the server list is refetching");
    check(!last.spinning, "A  the spinner is gone once the refetch finished");
    await page.click(".starred-menu .nav-menu-toggle");
    await sleep(600);
    const tabs = await tabCounts(page);
    console.log("A  panel tabs:", JSON.stringify(tabs));
    check(tabs.Server === 2, "A  the Server tab still lists the new like (2) after the refetch, despite the AppView lag");
    await page.screenshot({ path: "/tmp/ui-check-a-after.png" });
    await page.close();
  }

  // ---- B: the write fails ----------------------------------------------------------------------
  {
    const bsky = makeBluesky({ indexLagMs: 0, likesDelayMs: 200, failWrite: true });
    const page = await newPage(browser, bsky);
    await page.goto(postUrl, { waitUntil: "load" });
    await page.waitForSelector(".post-star", { timeout: 20000 });
    await page.waitForSelector(".starred-menu:not(.hidden)", { timeout: 20000 });
    await sleep(1000);
    await page.locator(".post-star >> visible=true").first().click();
    await sleep(2500);
    const b = await badge(page);
    console.log("B  badge:", JSON.stringify(b));
    // Open the panel to see the message.
    await page.click(".starred-menu .nav-menu-toggle");
    await sleep(600);
    const err = await errorBanner(page);
    console.log("B  banner:", JSON.stringify(err));
    await page.screenshot({ path: "/tmp/ui-check-b-panel.png" });
    check(err && err.visible && /Couldn't like on Bluesky/.test(err.text), "B  a failed like shows a reason in the Starred panel");
    const tabsB = await tabCounts(page);
    console.log("B  panel tabs:", JSON.stringify(tabsB));
    check(tabsB.Server === 1, "B  the failed like is rolled back (Server tab back to the 1 existing like)");
    await page.close();
  }

  await browser.close();
  console.log(failures ? `\n${failures} check(s) FAILED` : "\nall checks passed");
  process.exit(failures ? 1 : 0);
})();
