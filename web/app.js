import { createClient } from "@supabase/supabase-js";
import { SUPABASE_URL, SUPABASE_ANON_KEY } from "./config.js";

const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
});

// ---------- constants and helpers
const CATS = [
  ["electronics", "Electronics"], ["furniture", "Furniture"], ["vehicles", "Vehicles"], ["clothing", "Clothing"],
  ["home", "Home"], ["sports", "Sports"], ["toys", "Toys"], ["other", "Other"],
];
const CONDS = [["new", "New"], ["likeNew", "Like new"], ["good", "Good"], ["fair", "Fair"]];
const REPORT_LISTING = ["Spam or scam", "Prohibited item", "Offensive content", "Something else"];
const REPORT_USER = ["Spam or scam", "Harassment", "Offensive content", "Something else"];

const svg = (d, size = 24, sw = 1.8) =>
  `<svg aria-hidden="true" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${sw}" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;
const P = {
  search: '<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>',
  plus: '<circle cx="12" cy="12" r="9"/><path d="M12 8v8M8 12h8"/>',
  chat: '<path d="M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.6A8 8 0 1 1 21 12z"/>',
  heart: '<path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.5A4 4 0 0 1 19 10c0 5.6-7 10-7 10z"/>',
  user: '<circle cx="12" cy="8" r="4"/><path d="M4 21c0-4 3.6-6 8-6s8 2 8 6"/>',
  filter: '<path d="M4 6h16M7 12h10M10 18h4"/>',
  back: '<path d="M15 5l-7 7 7 7"/>',
  share: '<path d="M12 3v12M8 7l4-4 4 4"/><path d="M5 12v7h14v-7"/>',
  more: '<circle cx="12" cy="12" r="9"/><path d="M8 12h.01M12 12h.01M16 12h.01"/>',
  photo: '<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="9" cy="10" r="1.5"/><path d="M21 16l-5-5-8 8"/>',
  shield: '<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/>',
  send: '<path d="M12 19V6M6 12l6-6 6 6"/>',
};
const GLYPH = {
  furniture: '<path d="M5 12V9a3 3 0 0 1 3-3h8a3 3 0 0 1 3 3v3"/><path d="M3 14a2 2 0 0 1 4 0v2h10v-2a2 2 0 0 1 4 0v4H3z"/><path d="M6 18v2M18 18v2"/>',
  sports: '<circle cx="6" cy="16" r="3.5"/><circle cx="18" cy="16" r="3.5"/><path d="M6 16l4-7h5l3 7M10 9L8 6h-2M15 9l-3 7"/>',
  electronics: '<rect x="7" y="2.5" width="10" height="19" rx="2.5"/><path d="M11 18.5h2"/>',
  toys: '<rect x="3" y="12" width="8" height="6" rx="1"/><rect x="12" y="9" width="9" height="9" rx="1"/><circle cx="7" cy="20" r="1.5"/><circle cx="16.5" cy="20" r="1.5"/>',
  clothing: '<path d="M8 4l-5 3 2 4 3-1v10h8V10l3 1 2-4-5-3a4 4 0 0 1-8 0z"/>',
  vehicles: '<path d="M4 15l1.5-5A2 2 0 0 1 7.4 8.6h9.2a2 2 0 0 1 1.9 1.4L20 15v3H4z"/><circle cx="8" cy="17.5" r="1.5"/><circle cx="16" cy="17.5" r="1.5"/>',
  home: '<path d="M5 9h14v4a6 6 0 0 1-6 6h-2a6 6 0 0 1-6-6z"/><path d="M9 9V6h6v3M19 11h2"/>',
  other: '<path d="M3 12l9-9h8v8l-9 9z"/><circle cx="15.5" cy="8.5" r="1.2"/>',
};

const $ = (s, r = document) => r.querySelector(s);
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const uuid = () => (crypto.randomUUID ? crypto.randomUUID() : "10000000-1000-4000-8000-100000000000".replace(/[018]/g, (c) => (c ^ (crypto.getRandomValues(new Uint8Array(1))[0] & (15 >> (c / 4)))).toString(16)));
const money = (n) => {
  const v = Number(n);
  if (v === 0) return "Free";
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", minimumFractionDigits: Number.isInteger(v) ? 0 : 2, maximumFractionDigits: 2 }).format(v);
};
const ago = (iso) => {
  const s = (new Date(iso) - Date.now()) / 1000;
  const rtf = new Intl.RelativeTimeFormat("en", { numeric: "auto" });
  for (const [u, sec] of [["day", 86400], ["hour", 3600], ["minute", 60]]) {
    if (Math.abs(s) >= sec) return rtf.format(Math.round(s / sec), u);
  }
  return "just now";
};
const label = (list, key) => (list.find((x) => x[0] === key) || [key, key])[1];
const errText = (e) => (e && (e.message || e.error_description)) || "Something went wrong. Please try again.";

let toastTimer;
function toast(msg) {
  const t = $("#toast");
  t.textContent = msg;
  t.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (t.hidden = true), 4000);
}

// ---------- state
const state = {
  user: null,
  profile: null,
  all: [],
  saved: new Set(),
  blocked: new Set(),
  threads: [],
  f: { q: "", cat: null, cond: "", min: "", max: "", sort: "newest" },
  authMode: "create",
};
const visible = () => state.all.filter((l) => !state.blocked.has(l.seller_id));
const me = () => state.user?.id;
const myName = () => state.profile?.name || state.user?.user_metadata?.name || state.user?.user_metadata?.full_name || "";

// ---------- data
async function loadListings() {
  const { data, error } = await sb.from("listings").select("*,profiles!seller_id(name)").order("created_at", { ascending: false }).limit(200);
  if (error) return toast(errText(error));
  state.all = data || [];
}

async function loadAccount() {
  if (!state.user) {
    Object.assign(state, { profile: null, saved: new Set(), blocked: new Set(), threads: [] });
    return;
  }
  const [prof, fav, blk, th] = await Promise.all([
    sb.from("profiles").select("name").eq("id", me()).maybeSingle(),
    sb.from("favorites").select("listing_id"),
    sb.from("blocks").select("blocked_id"),
    sb.from("threads")
      .select("id,listing_id,buyer_id,seller_id,listings!listing_id(title),buyer:profiles!buyer_id(name),seller:profiles!seller_id(name),messages(id,sender_id,body,created_at)")
      .order("created_at", { ascending: false }),
  ]);
  state.profile = prof.data || null;
  state.saved = new Set((fav.data || []).map((r) => r.listing_id));
  state.blocked = new Set((blk.data || []).map((r) => r.blocked_id));
  state.threads = (th.data || []).map(mapThread);
  const firstError = prof.error || fav.error || blk.error || th.error;
  if (firstError) toast(errText(firstError));
}

function mapThread(r) {
  const iAmBuyer = r.buyer_id === me();
  const other = iAmBuyer ? r.seller : r.buyer;
  return {
    id: r.id,
    listing_id: r.listing_id,
    title: r.listings?.title || "Listing",
    otherId: iAmBuyer ? r.seller_id : r.buyer_id,
    otherName: other?.name || "User",
    messages: (r.messages || []).slice().sort((a, b) => new Date(a.created_at) - new Date(b.created_at)),
  };
}

// ---------- routing
const route = () => {
  const [name, arg] = location.hash.replace(/^#\/?/, "").split("/");
  return { name: name || "browse", arg };
};
const TABS = [
  ["browse", "Browse", P.search], ["sell", "Sell", P.plus], ["inbox", "Inbox", P.chat], ["saved", "Saved", P.heart], ["profile", "Profile", P.user],
];
let chatTimer = null;

function drawTabs(active) {
  $("#tabs").innerHTML = TABS.map(([k, name, p]) => `<a href="#/${k === "browse" ? "" : k}" ${k === active ? 'aria-current="page"' : ""}>${svg(p, 26)}<span>${name}</span></a>`).join("");
}

async function render() {
  clearInterval(chatTimer);
  const { name, arg } = route();
  const tab = { item: "browse", chat: "inbox" }[name] || name;
  drawTabs(tab);
  $("#tabs").hidden = name === "item" || name === "chat";
  const views = { browse: browseView, item: itemView, sell: sellView, inbox: inboxView, chat: chatView, saved: savedView, profile: profileView };
  (views[name] || browseView)(arg);
  window.scrollTo(0, 0);
}
window.addEventListener("hashchange", render);

// ---------- shared pieces
const thumb = (l, extra = "") => {
  const url = l.photo_urls?.[0];
  return `<div class="thumb">${url ? `<img loading="lazy" alt="" src="${esc(url)}">` : svg(GLYPH[l.category] || GLYPH.other, 44, 1.4)}${extra}</div>`;
};
const card = (l) => `<a class="card" href="#/item/${esc(l.id)}">${thumb(l,
  (state.saved.has(l.id) ? `<span class="tag" aria-label="Saved">${svg(P.heart, 16).replace('fill="none"', 'fill="currentColor"')}</span>` : "") +
  (l.is_sold ? '<span class="sold">Sold</span>' : ""))}<div class="price">${money(l.price)}</div><div class="t">${esc(l.title)}</div><div class="sub">${esc(l.location_name)}</div></a>`;
const emptyBox = (title, body, action = "") => `<div class="empty">${svg(P.search, 40, 1.4)}<h3>${esc(title)}</h3><p>${esc(body)}</p>${action}</div>`;
const needSignIn = (title, body) => emptyBox(title, body, '<button class="btn" data-act="auth">Sign in or create account</button>');

function filtered() {
  const f = state.f, q = f.q.trim().toLowerCase();
  const min = f.min === "" ? null : Number(f.min), max = f.max === "" ? null : Number(f.max);
  const out = visible().filter((l) => !l.is_sold
    && (!f.cat || l.category === f.cat)
    && (!f.cond || l.condition === f.cond)
    && (min === null || Number(l.price) >= min)
    && (max === null || Number(l.price) <= max)
    && (!q || l.title.toLowerCase().includes(q) || (l.details || "").toLowerCase().includes(q)));
  const by = { newest: (a, b) => new Date(b.created_at) - new Date(a.created_at), low: (a, b) => a.price - b.price, high: (a, b) => b.price - a.price }[f.sort];
  return out.sort(by);
}
const filtersActive = () => { const f = state.f; return !!(f.cat || f.cond || f.min !== "" || f.max !== "" || f.sort !== "newest"); };

// ---------- views
function browseView() {
  const f = state.f;
  $("#app").innerHTML = `
    <div class="top"><h1>Swap</h1><button class="icon" data-act="filters" aria-label="Filters">${svg(P.filter, 22)}</button></div>
    <label class="search">${svg(P.search, 18)}<input id="q" type="search" placeholder="Search items" aria-label="Search items" value="${esc(f.q)}" autocomplete="off"></label>
    <div class="chips" id="chips"></div>
    <div id="results"></div>`;
  drawChips();
  drawResults();
}
function drawChips() {
  const f = state.f;
  const chip = (k, name) => `<button class="chip" data-act="cat" data-cat="${k}" aria-pressed="${(f.cat || "") === k}">${name}</button>`;
  $("#chips").innerHTML = chip("", "All") + CATS.map(([k, n]) => chip(k, n)).join("");
}
function drawResults() {
  const list = filtered();
  $("#results").innerHTML = list.length
    ? `<div class="grid">${list.map(card).join("")}</div>`
    : emptyBox("Nothing here yet", state.f.q ? `No results for "${state.f.q}".` : "Try a different category or clear your filters.",
        filtersActive() || state.f.q ? '<button class="btn ghost" data-act="reset">Clear filters</button>' : "");
}

function itemView(id) {
  const l = state.all.find((x) => x.id === id);
  if (!l) { $("#app").innerHTML = emptyBox("Listing removed", "This item is no longer available.", '<a class="btn" href="#/">Back to browse</a>'); return; }
  const mine = l.seller_user === undefined && me() === l.seller_id;
  const photos = l.photo_urls?.length ? l.photo_urls : [null];
  const seller = l.profiles?.name || "Seller";
  const saved = state.saved.has(l.id);
  $("#app").innerHTML = `
    <div class="hero"><div class="pager">${photos.map((u) => `<div>${u ? `<img alt="" src="${esc(u)}">` : svg(GLYPH[l.category] || GLYPH.other, 72, 1.2)}</div>`).join("")}</div>
      <div class="floating"><a class="icon" href="#/" aria-label="Back" data-act="back">${svg(P.back, 22)}</a>
        <div class="grp"><button class="icon" data-act="share" data-id="${esc(l.id)}" aria-label="Share">${svg(P.share, 20)}</button>
        ${mine ? "" : `<button class="icon" data-act="more-listing" data-id="${esc(l.id)}" aria-label="More">${svg(P.more, 22)}</button>`}</div></div></div>
    <div class="big">${money(l.price)}${l.is_sold ? ' <span class="chip" style="font-size:13px;min-height:0;padding:4px 10px">Sold</span>' : ""}</div>
    <div style="font-size:20px;margin-top:4px">${esc(l.title)}</div>
    <div class="muted" style="margin-top:6px">${esc(label(CONDS, l.condition))} · ${esc(label(CATS, l.category))}</div>
    <div class="muted" style="font-size:13px;margin-top:2px">${esc(l.location_name)} · Posted ${esc(ago(l.created_at))}</div>
    ${l.details ? `<h2>Description</h2><div style="white-space:pre-wrap;overflow-wrap:anywhere">${esc(l.details)}</div>` : ""}
    <div class="row" style="margin-top:18px"><div class="avatar">${esc((seller[0] || "S").toUpperCase())}</div><div><b>${esc(seller)}</b><div class="muted" style="font-size:13px">Seller</div></div></div>
    <div class="note">${svg(P.shield, 18)}<span>Meet in a public place and check the item before you pay.</span></div>
    <div class="bar">${mine
      ? `${l.is_sold ? "" : `<button class="btn" data-act="sold" data-id="${esc(l.id)}">Mark as sold</button>`}<button class="btn danger" data-act="del" data-id="${esc(l.id)}">Delete</button>`
      : `<button class="btn secondary sq" data-act="save" data-id="${esc(l.id)}" aria-label="${saved ? "Remove from saved" : "Save"}">${svg(P.heart, 24).replace('fill="none"', `fill="${saved ? "currentColor" : "none"}"`)}</button>
         <button class="btn" data-act="message" data-id="${esc(l.id)}" ${l.is_sold ? "disabled" : ""}>Message seller</button>`}</div>`;
}

let pickedFiles = [];
function sellView() {
  if (!state.user) { $("#app").innerHTML = `<div class="top"><h1>Sell an item</h1></div>${needSignIn("Sign in to sell", "Create a free account to post items.")}`; return; }
  pickedFiles = [];
  $("#app").innerHTML = `
    <div class="top"><h1>Sell an item</h1></div>
    <form id="sell" class="stack" novalidate>
      <div class="cap">Photos</div>
      <div class="group"><label class="filebtn">${svg(P.photo, 26)}<span id="photoLabel">Add photos (up to 6)</span><input id="photos" type="file" accept="image/*" multiple></label><div class="thumbs" id="previews" hidden></div></div>
      <div class="cap">Details</div>
      <div class="group">
        <div class="field full"><input id="title" placeholder="Title" maxlength="120" aria-label="Title" autocomplete="off"></div>
        <div class="field full"><input id="price" placeholder="Price (0 for free)" inputmode="decimal" aria-label="Price"></div>
        <div class="field"><label for="cat">Category</label><select id="cat">${CATS.map(([k, n]) => `<option value="${k}" ${k === "other" ? "selected" : ""}>${n}</option>`).join("")}</select></div>
        <div class="field"><label for="cond">Condition</label><select id="cond">${CONDS.map(([k, n]) => `<option value="${k}" ${k === "good" ? "selected" : ""}>${n}</option>`).join("")}</select></div>
      </div>
      <div class="cap">Description</div>
      <div class="group"><textarea id="details" maxlength="4000" placeholder="Tell buyers about it" aria-label="Description"></textarea></div>
      <div class="cap">Location</div>
      <div class="group"><div class="field full"><input id="loc" placeholder="Neighborhood or city" maxlength="120" aria-label="Location"></div></div>
      <div id="sellErr" class="err" hidden></div>
      <button class="btn block" id="post" type="submit" style="margin-top:18px">Post listing</button>
    </form>`;
}

async function inboxView() {
  if (!state.user) { $("#app").innerHTML = `<div class="top"><h1>Inbox</h1></div>${needSignIn("Sign in to see messages", "Your conversations with buyers and sellers show up here.")}`; return; }
  $("#app").innerHTML = `<div class="top"><h1>Inbox</h1></div><div id="threads"><div class="empty"><span class="spin"></span></div></div>`;
  await loadAccount();
  if (route().name !== "inbox") return;
  const list = state.threads.filter((t) => !state.blocked.has(t.otherId)).sort((a, b) => lastDate(b) - lastDate(a));
  $("#threads").innerHTML = list.length
    ? `<div class="list">${list.map((t) => {
        const last = t.messages[t.messages.length - 1];
        return `<a href="#/chat/${esc(t.id)}"><div class="avatar">${esc((t.otherName[0] || "?").toUpperCase())}</div><div class="grow"><div class="row" style="justify-content:space-between"><span class="nm">${esc(t.otherName)}</span><span class="muted" style="font-size:12px">${last ? esc(ago(last.created_at)) : ""}</span></div><div class="muted ln">${esc(t.title)}</div><div class="ln">${esc(last ? last.body : "Say hello")}</div></div></a>`;
      }).join("")}</div>`
    : emptyBox("No messages yet", "Message a seller from any listing and it shows up here.");
}
const lastDate = (t) => (t.messages.length ? new Date(t.messages[t.messages.length - 1].created_at) : new Date(0));

function chatView(id) {
  const t = state.threads.find((x) => x.id === id);
  if (!t) { $("#app").innerHTML = emptyBox("Conversation not found", "Open it from your inbox.", '<a class="btn" href="#/inbox">Inbox</a>'); return; }
  const quick = ["Is this still available?", "Can you do a lower price?", "When can I pick it up?"];
  $("#app").innerHTML = `
    <div class="chat-head"><a class="icon plain" href="#/inbox" aria-label="Back">${svg(P.back, 24)}</a><b>${esc(t.otherName)}</b><button class="icon plain" data-act="more-chat" data-id="${esc(t.id)}" aria-label="More">${svg(P.more, 24)}</button></div>
    <div class="msgs" id="msgs"></div>
    <div class="bar"><form id="compose" class="compose" style="width:100%"><input id="msg" placeholder="Message" aria-label="Message" autocomplete="off" maxlength="2000"><button class="icon plain" style="color:var(--accent)" aria-label="Send" type="submit">${svg(P.send, 28, 2.4)}</button></form></div>`;
  drawMsgs(t, quick);
  chatTimer = setInterval(() => pollThread(id), 4000);
}
function drawMsgs(t, quick = []) {
  const box = $("#msgs");
  if (!box) return;
  const atBottom = true;
  box.innerHTML = `<div class="about">About: ${esc(t.title)}</div>` +
    t.messages.map((m) => `<div class="b ${m.sender_id === me() ? "me" : ""}">${esc(m.body)}</div>`).join("") +
    (t.messages.length ? "" : `<div class="quick">${quick.map((q) => `<button class="btn ghost" data-act="quick" data-text="${esc(q)}">${esc(q)}</button>`).join("")}</div>`);
  if (atBottom) window.scrollTo(0, document.body.scrollHeight);
}
async function pollThread(id) {
  const t = state.threads.find((x) => x.id === id);
  if (!t || route().name !== "chat") return;
  const { data } = await sb.from("messages").select("id,sender_id,body,created_at").eq("thread_id", id).order("created_at", { ascending: true });
  if (!data) return;
  const same = data.length === t.messages.length && data.every((m, i) => m.id === t.messages[i].id);
  if (!same) { t.messages = data; drawMsgs(t); }
}
async function sendMessage(id, text) {
  const body = text.trim();
  const t = state.threads.find((x) => x.id === id);
  if (!body || !t) return;
  const m = { id: uuid(), sender_id: me(), body, created_at: new Date().toISOString() };
  t.messages.push(m);
  drawMsgs(t);
  const { error } = await sb.from("messages").insert({ id: m.id, thread_id: id, body });
  if (error) { t.messages = t.messages.filter((x) => x.id !== m.id); drawMsgs(t); toast(errText(error)); }
}

function savedView() {
  const list = visible().filter((l) => state.saved.has(l.id));
  $("#app").innerHTML = `<div class="top"><h1>Saved</h1></div>` + (!state.user
    ? needSignIn("Sign in to save items", "Tap the heart on a listing to keep it here.")
    : list.length ? `<div class="grid">${list.map(card).join("")}</div>` : emptyBox("Nothing saved", "Tap the heart on a listing to keep it here."));
}

function profileView() {
  if (!state.user) { $("#app").innerHTML = `<div class="top"><h1>Profile</h1></div>${needSignIn("Join Swap", "Create a free account to sell items and message sellers.")}`; return; }
  const mine = visible().filter((l) => l.seller_id === me());
  $("#app").innerHTML = `
    <div class="top"><h1>Profile</h1></div>
    <div class="cap">Account</div>
    <div class="group"><div class="field"><span>Name</span><span>${esc(myName() || "Not set")}</span></div><div class="field"><span>Email</span><span>${esc(state.user.email || "")}</span></div></div>
    <div class="cap">My listings</div>
    ${mine.length ? `<div class="list">${mine.map((l) => `<a href="#/item/${esc(l.id)}"><div class="mini">${l.photo_urls?.[0] ? `<img alt="" src="${esc(l.photo_urls[0])}">` : svg(GLYPH[l.category] || GLYPH.other, 24, 1.4)}</div><div class="grow"><div class="ln nm">${esc(l.title)}</div><div class="muted" style="font-size:13px">${l.is_sold ? "Sold" : esc(money(l.price))}</div></div></a>`).join("")}</div>` : '<p class="muted">You haven\'t posted anything yet.</p>'}
    <div style="display:flex;flex-direction:column;gap:10px;margin-top:24px">
      <button class="btn ghost block" data-act="signout">Sign out</button>
      <button class="btn danger block" data-act="deleteAccount">Delete account</button>
      <p class="muted" style="font-size:13px;margin:0">Deleting your account removes your listings, messages, and saved items.</p>
    </div>`;
}

// ---------- sheets
function openSheet(html) { const s = $("#sheet"); s.innerHTML = `<div class="panel" role="dialog" aria-modal="true">${html}</div>`; s.hidden = false; }
function closeSheet() { const s = $("#sheet"); s.hidden = true; s.innerHTML = ""; }
$("#sheet").addEventListener("click", (e) => { if (e.target.id === "sheet") closeSheet(); });

function filterSheet() {
  const f = state.f;
  openSheet(`<h3>Filters</h3><form id="filters">
    <div class="group">
      <div class="field"><label for="fsort">Sort by</label><select id="fsort"><option value="newest">Newest</option><option value="low">Price: low to high</option><option value="high">Price: high to low</option></select></div>
      <div class="field"><label for="fcat">Category</label><select id="fcat"><option value="">Any</option>${CATS.map(([k, n]) => `<option value="${k}">${n}</option>`).join("")}</select></div>
      <div class="field"><label for="fcond">Condition</label><select id="fcond"><option value="">Any</option>${CONDS.map(([k, n]) => `<option value="${k}">${n}</option>`).join("")}</select></div>
      <div class="field"><label for="fmin">Min price</label><input id="fmin" inputmode="decimal" placeholder="Any" value="${esc(f.min)}"></div>
      <div class="field"><label for="fmax">Max price</label><input id="fmax" inputmode="decimal" placeholder="Any" value="${esc(f.max)}"></div>
    </div>
    <div style="display:flex;gap:10px;margin-top:14px"><button type="button" class="btn ghost" style="flex:1" data-act="reset">Reset</button><button class="btn" style="flex:1" type="submit">Show items</button></div></form>`);
  $("#fsort").value = f.sort; $("#fcat").value = f.cat || ""; $("#fcond").value = f.cond;
}

function authSheet() {
  const create = state.authMode === "create";
  openSheet(`<h3>${create ? "Create account" : "Sign in"}</h3>
    <div class="seg"><button data-act="authmode" data-mode="create" aria-pressed="${create}">Create account</button><button data-act="authmode" data-mode="signin" aria-pressed="${!create}">Sign in</button></div>
    <button class="btn ghost block" data-act="google" style="background:#fff;border:1px solid var(--line)">Continue with Google</button>
    <p class="muted" style="margin:10px 4px">Or use your email.</p>
    <form id="auth"><div class="group">
      ${create ? '<div class="field full"><input id="aname" placeholder="Name" autocomplete="name" maxlength="60" aria-label="Name"></div>' : ""}
      <div class="field full"><input id="aemail" type="email" placeholder="Email" autocomplete="email" inputmode="email" autocapitalize="none" aria-label="Email"></div>
      <div class="field full"><input id="apass" type="password" placeholder="Password (8 or more characters)" autocomplete="${create ? "new-password" : "current-password"}" aria-label="Password"></div>
    </div><div id="autherr" class="err" hidden></div>
    <button class="btn block" id="authgo" type="submit" style="margin-top:14px">${create ? "Create account" : "Sign in"}</button>
    <button type="button" class="btn ghost block" data-act="closeSheet" style="margin-top:10px">Cancel</button></form>`);
}
const authError = (m) => { const e = $("#autherr"); if (e) { e.textContent = m; e.hidden = !m; } };

function menuSheet(title, items) {
  openSheet(`<h3>${esc(title)}</h3><div class="menu">${items.map((i) => `<button class="${i.danger ? "danger" : ""}" ${i.attrs}>${esc(i.text)}</button>`).join("")}</div><button class="btn ghost block" data-act="closeSheet">Cancel</button>`);
}

// ---------- actions
const requireUser = () => { if (state.user) return true; state.authMode = "create"; authSheet(); return false; };
const listingById = (id) => state.all.find((l) => l.id === id);

async function compress(file) {
  const url = URL.createObjectURL(file);
  try {
    const img = await new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = () => rej(new Error("Couldn't read that photo.")); i.src = url; });
    const scale = Math.min(1, 1600 / Math.max(img.naturalWidth, img.naturalHeight));
    const c = document.createElement("canvas");
    c.width = Math.round(img.naturalWidth * scale); c.height = Math.round(img.naturalHeight * scale);
    c.getContext("2d").drawImage(img, 0, 0, c.width, c.height);
    return await new Promise((res, rej) => c.toBlob((b) => (b ? res(b) : rej(new Error("Couldn't process that photo."))), "image/jpeg", 0.75));
  } finally { URL.revokeObjectURL(url); }
}
const storagePath = (url) => { const m = String(url).split("/object/public/listing-photos/"); return m[1] || null; };

async function postListing() {
  const err = $("#sellErr"), btn = $("#post");
  const title = $("#title").value.trim(), loc = $("#loc").value.trim();
  const price = Number($("#price").value.replace(/,/g, "").trim());
  const bad = !title ? "Add a title." : $("#price").value.trim() === "" || !Number.isFinite(price) || price < 0 ? "Enter a price. Use 0 for free." : !loc ? "Add a location." : "";
  err.hidden = !bad; err.textContent = bad;
  if (bad) return;
  btn.disabled = true; btn.innerHTML = '<span class="spin"></span>';
  const uploaded = [];
  try {
    for (const f of pickedFiles.slice(0, 6)) {
      const blob = await compress(f);
      const path = `${me()}/${uuid()}.jpg`;
      const up = await sb.storage.from("listing-photos").upload(path, blob, { contentType: "image/jpeg" });
      if (up.error) throw up.error;
      uploaded.push(sb.storage.from("listing-photos").getPublicUrl(path).data.publicUrl);
    }
    const id = uuid();
    const { error } = await sb.from("listings").insert({ id, title, price, category: $("#cat").value, condition: $("#cond").value, details: $("#details").value.trim(), location_name: loc, photo_urls: uploaded });
    if (error) throw error;
    await loadListings();
    toast("Listing posted");
    location.hash = `#/item/${id}`;
  } catch (e) {
    const paths = uploaded.map(storagePath).filter(Boolean);
    if (paths.length) sb.storage.from("listing-photos").remove(paths);
    err.hidden = false; err.textContent = errText(e);
    btn.disabled = false; btn.textContent = "Post listing";
  }
}

async function openChat(id) {
  const l = listingById(id);
  if (!l || !requireUser()) return;
  let t = state.threads.find((x) => x.listing_id === l.id && x.otherId === l.seller_id);
  if (!t) {
    const tid = uuid();
    const { error } = await sb.from("threads").insert({ id: tid, listing_id: l.id, seller_id: l.seller_id });
    if (error) return toast(errText(error));
    t = { id: tid, listing_id: l.id, title: l.title, otherId: l.seller_id, otherName: l.profiles?.name || "Seller", messages: [] };
    state.threads.push(t);
  }
  location.hash = `#/chat/${t.id}`;
}

async function toggleSave(id) {
  if (!requireUser()) return;
  const on = !state.saved.has(id);
  on ? state.saved.add(id) : state.saved.delete(id);
  render();
  const { error } = on ? await sb.from("favorites").insert({ listing_id: id }) : await sb.from("favorites").delete().eq("listing_id", id).eq("user_id", me());
  if (error) { on ? state.saved.delete(id) : state.saved.add(id); render(); toast(errText(error)); }
}

async function fileReport(listingId, userId, reason) {
  if (!requireUser()) return;
  closeSheet();
  const row = { reason };
  if (listingId) row.listing_id = listingId;
  if (userId) row.reported_user_id = userId;
  const { error } = await sb.from("reports").insert(row);
  toast(error ? errText(error) : "Thanks. We'll review this.");
}
async function blockUser(userId) {
  if (!requireUser()) return;
  closeSheet();
  const { error } = await sb.from("blocks").insert({ blocked_id: userId });
  if (error && error.code !== "23505") return toast(errText(error));
  state.blocked.add(userId);
  toast("Blocked. You won't see their listings or messages.");
  location.hash = "#/";
}

async function signOut() { await sb.auth.signOut(); location.hash = "#/"; }
async function deleteAccount() {
  if (!confirm("Delete your account? This removes your listings, messages, and saved items. It can't be undone.")) return;
  const paths = visible().filter((l) => l.seller_id === me()).flatMap((l) => l.photo_urls || []).map(storagePath).filter(Boolean);
  if (paths.length) await sb.storage.from("listing-photos").remove(paths);
  const { error } = await sb.rpc("delete_my_account");
  if (error) return toast(errText(error));
  await sb.auth.signOut();
  location.hash = "#/";
  await loadListings();
  toast("Account deleted");
}

// ---------- events
const A = {
  filters: () => filterSheet(),
  reset: () => { state.f = { q: "", cat: null, cond: "", min: "", max: "", sort: "newest" }; closeSheet(); if (route().name === "browse") browseView(); },
  cat: (t) => { state.f.cat = t.dataset.cat || null; drawChips(); drawResults(); },
  auth: () => { state.authMode = "create"; authSheet(); },
  authmode: (t) => { state.authMode = t.dataset.mode; authSheet(); },
  closeSheet: () => closeSheet(),
  back: (t, e) => { if (history.length > 1) { e.preventDefault(); history.back(); } },
  save: (t) => toggleSave(t.dataset.id),
  message: (t) => openChat(t.dataset.id),
  sold: async (t) => { const { error } = await sb.from("listings").update({ is_sold: true }).eq("id", t.dataset.id); if (error) return toast(errText(error)); await loadListings(); render(); },
  del: async (t) => {
    if (!confirm("Delete this listing?")) return;
    const l = listingById(t.dataset.id);
    const { error } = await sb.from("listings").delete().eq("id", t.dataset.id);
    if (error) return toast(errText(error));
    const paths = (l?.photo_urls || []).map(storagePath).filter(Boolean);
    if (paths.length) sb.storage.from("listing-photos").remove(paths);
    await loadListings();
    location.hash = "#/";
  },
  share: async (t) => {
    const l = listingById(t.dataset.id);
    const data = { title: l?.title || "Swap", text: `${l?.title} for ${money(l?.price)} on Swap`, url: location.href };
    try { if (navigator.share) await navigator.share(data); else { await navigator.clipboard.writeText(location.href); toast("Link copied"); } } catch { /* cancelled */ }
  },
  "more-listing": (t) => {
    const l = listingById(t.dataset.id);
    menuSheet("More", [
      { text: "Report listing", attrs: `data-act="report-menu" data-id="${esc(l.id)}"` },
      { text: `Block ${l.profiles?.name || "seller"}`, danger: true, attrs: `data-act="block" data-user="${esc(l.seller_id)}"` },
    ]);
  },
  "report-menu": (t) => menuSheet("Why are you reporting this?", REPORT_LISTING.map((r) => ({ text: r, attrs: `data-act="report" data-listing="${esc(t.dataset.id)}" data-reason="${esc(r)}"` }))),
  "more-chat": (t) => {
    const th = state.threads.find((x) => x.id === t.dataset.id);
    menuSheet("More", [
      { text: "Report", attrs: `data-act="report-user-menu" data-user="${esc(th.otherId)}"` },
      { text: `Block ${th.otherName}`, danger: true, attrs: `data-act="block" data-user="${esc(th.otherId)}"` },
    ]);
  },
  "report-user-menu": (t) => menuSheet("Why are you reporting them?", REPORT_USER.map((r) => ({ text: r, attrs: `data-act="report" data-user="${esc(t.dataset.user)}" data-reason="${esc(r)}"` }))),
  report: (t) => fileReport(t.dataset.listing || null, t.dataset.user || null, t.dataset.reason),
  block: (t) => blockUser(t.dataset.user),
  quick: (t) => sendMessage(route().arg, t.dataset.text),
  google: async () => { const { error } = await sb.auth.signInWithOAuth({ provider: "google", options: { redirectTo: location.origin + location.pathname } }); if (error) authError(errText(error)); },
  signout: () => signOut(),
  deleteAccount: () => deleteAccount(),
};
document.addEventListener("click", (e) => {
  const t = e.target.closest("[data-act]");
  if (t && A[t.dataset.act]) A[t.dataset.act](t, e);
});
document.addEventListener("input", (e) => {
  if (e.target.id === "q") { state.f.q = e.target.value; drawResults(); }
});
document.addEventListener("change", (e) => {
  if (e.target.id !== "photos") return;
  pickedFiles = [...e.target.files].slice(0, 6);
  const box = $("#previews");
  box.hidden = !pickedFiles.length;
  box.innerHTML = pickedFiles.map((f) => `<img alt="" src="${URL.createObjectURL(f)}">`).join("");
  $("#photoLabel").textContent = pickedFiles.length ? `${pickedFiles.length} photo${pickedFiles.length > 1 ? "s" : ""} selected` : "Add photos (up to 6)";
});
document.addEventListener("submit", async (e) => {
  e.preventDefault();
  const id = e.target.id;
  if (id === "filters") {
    state.f = { ...state.f, sort: $("#fsort").value, cat: $("#fcat").value || null, cond: $("#fcond").value, min: $("#fmin").value.trim(), max: $("#fmax").value.trim() };
    closeSheet(); if (route().name === "browse") browseView();
  } else if (id === "sell") {
    postListing();
  } else if (id === "compose") {
    const input = $("#msg"); const text = input.value; input.value = ""; sendMessage(route().arg, text);
  } else if (id === "auth") {
    await submitAuth();
  }
});

async function submitAuth() {
  const create = state.authMode === "create";
  const email = $("#aemail").value.trim(), password = $("#apass").value, name = create ? $("#aname").value.trim() : "";
  if (create && !name) return authError("Add your name.");
  if (!email.includes("@")) return authError("Enter a valid email.");
  if (password.length < 8) return authError("Use at least 8 characters for the password.");
  const btn = $("#authgo"); btn.disabled = true; authError("");
  const { data, error } = create
    ? await sb.auth.signUp({ email, password, options: { data: { name }, emailRedirectTo: location.origin + location.pathname } })
    : await sb.auth.signInWithPassword({ email, password });
  btn.disabled = false;
  if (error) return authError(errText(error));
  if (create && !data.session) { closeSheet(); toast("Check your email to confirm your account, then sign in."); return; }
  closeSheet();
}

// ---------- start
(async function start() {
  $("#app").innerHTML = '<div class="empty"><span class="spin"></span></div>';
  const { data } = await sb.auth.getSession();
  state.user = data?.session?.user ?? null;
  sb.auth.onAuthStateChange((_event, session) => {
    const prev = state.user?.id;
    state.user = session?.user ?? null;
    if ((state.user?.id ?? null) !== (prev ?? null)) {
      setTimeout(async () => { await Promise.all([loadListings(), loadAccount()]); render(); }, 0);
    }
  });
  await Promise.all([loadListings(), loadAccount()]);
  render();
})();
