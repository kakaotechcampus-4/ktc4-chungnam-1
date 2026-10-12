// DB 스냅숏 보기. 작업대(DB 탭)와 결과 화면(DB 탭)이 같이 쓴다.
// 스냅숏은 [{id, label, visit, tables: {테이블: {key, columns, rows}}}]. 왼쪽에서 시점을 고르면 바로 앞 시점과 비교해 보여 준다.
window.DBView = (() => {
  const NAMES = {
    users: "사용자", profiles: "프로필", photos: "사진", visit_sessions: "면회", speech_analysis_jobs: "음성 분석",
    life_fact_proposals: "이야기 제안", life_facts: "이야기", proto_elements: "요소", proto_element_links: "요소 포함 관계",
    proto_cards: "카드", proto_card_elements: "카드-요소", proto_element_feedback: "요소 결정",
    card_sets: "카드 묶음", conversation_cards: "대화 카드", profile_topics: "주제", topic_proposals: "주제 제안", topic_feedback: "주제 결정",
  };
  const KIND = { period: "시절", place: "장소", person: "사람", activity: "활동" };
  const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

  const style = document.createElement("style");
  style.textContent = `
.dbv { display: grid; grid-template-columns: 220px minmax(0, 1fr); gap: 12px; align-items: start; }
@media (max-width: 860px) { .dbv { grid-template-columns: minmax(0, 1fr); } }
.dbv-points { display: grid; gap: 2px; background: var(--panel); border: 1px solid var(--line); border-radius: 12px; padding: 6px; position: sticky; top: 0; max-height: 80vh; overflow: auto; }
.dbv-points .vh { font-size: 0.72rem; font-weight: 600; color: var(--muted); padding: 8px 10px 2px; }
.dbv-points button { font: inherit; text-align: left; border: 0; background: none; color: var(--fg); border-radius: 8px; padding: 6px 10px; cursor: pointer; display: grid; gap: 1px; }
.dbv-points button:hover { background: var(--sunken); }
.dbv-points button[aria-current="true"] { background: var(--accent-soft); color: var(--accent); font-weight: 600; }
.dbv-points .d { font-size: 0.72rem; color: var(--faint); font-weight: 400; font-family: var(--mono); }
.dbv-main { display: grid; gap: 10px; min-width: 0; background: var(--panel); border: 1px solid var(--line); border-radius: 12px; padding: 14px 16px; }
.dbv-bar { display: flex; flex-wrap: wrap; gap: 8px 16px; align-items: center; justify-content: space-between; }
.dbv-bar h3 { margin: 0; font-size: 0.98rem; }
.dbv-opts { display: flex; flex-wrap: wrap; gap: 4px 14px; font-size: 0.8rem; color: var(--muted); }
.dbv-opts label { display: inline-flex; gap: 5px; align-items: center; }
.dbv-seg { display: flex; flex-wrap: wrap; gap: 2px; background: var(--sunken); border: 1px solid var(--line); border-radius: 9px; padding: 3px; }
.dbv-seg button { font: inherit; font-size: 0.8rem; background: none; border: 0; border-radius: 6px; padding: 4px 9px; color: var(--muted); cursor: pointer; white-space: nowrap; }
.dbv-seg button[aria-selected="true"] { background: var(--panel); color: var(--fg); font-weight: 600; box-shadow: var(--shadow); }
.dbv-seg button.empty { opacity: 0.55; }
.dbv-seg .n { font-family: var(--mono); font-size: 0.7rem; margin-left: 4px; color: var(--faint); }
.dbv-seg .plus { color: var(--warn); font-weight: 600; }
.dbv-meta { font-size: 0.8rem; color: var(--muted); display: flex; flex-wrap: wrap; gap: 4px 14px; }
.dbv-meta code { font-family: var(--mono); font-size: 0.76rem; }
.dbv-scroll { overflow: auto; max-height: 70vh; border: 1px solid var(--line); border-radius: 10px; }
.dbv table { border-collapse: collapse; width: 100%; background: var(--panel); }
.dbv th { position: sticky; top: 0; z-index: 1; text-align: left; font-weight: 600; font-size: 0.72rem; color: var(--muted); background: var(--sunken); padding: 7px 10px; border-bottom: 1px solid var(--line); white-space: nowrap; font-family: var(--mono); }
.dbv td { padding: 6px 10px; border-bottom: 1px solid var(--line); vertical-align: top; font-size: 0.8rem; max-width: 340px; }
.dbv td .v { display: -webkit-box; -webkit-line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden; overflow-wrap: anywhere; }
.dbv td.open .v { display: block; }
.dbv td.long { cursor: pointer; }
.dbv td.short { white-space: nowrap; }
.dbv td.num, .dbv td.id, .dbv td.time { font-family: var(--mono); font-size: 0.74rem; white-space: nowrap; }
.dbv tr.new td { background: var(--mark); }
.dbv tr.new td:first-child { box-shadow: inset 3px 0 0 var(--warn); }
.dbv td.chg { box-shadow: inset 0 0 0 2px var(--warn); }
.dbv tr.gone td { color: var(--faint); text-decoration: line-through; }
.dbv .null { color: var(--faint); font-style: italic; }
.dbv .ref { font-family: var(--sans); font-size: 0.76rem; background: var(--accent-soft); color: var(--accent); padding: 0 6px; border-radius: 4px; white-space: nowrap; }
.dbv .t { color: var(--ok); } .dbv .f { color: var(--faint); }
.dbv-note { font-size: 0.8rem; color: var(--faint); }
`;
  document.head.append(style);

  function h(tag, attrs = {}, ...kids) {
    const e = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) { if (v == null || v === false) continue; if (k === "class") e.className = v; else e.setAttribute(k, v); }
    for (const k of kids.flat()) if (k != null && k !== false) e.append(k instanceof Node ? k : document.createTextNode(String(k)));
    return e;
  }

  // 결과 JSON에서 시점 목록을 꺼낸다. 예전 기록은 회차가 끝난 뒤 한 번만 찍었고 열도 골라 담았다.
  function fromRun(run) {
    if (run.db_snapshots) return run.db_snapshots;
    const out = [];
    if (run.db_after_onboarding) out.push({ id: "onboarding", label: "프로필 입력 직후", visit: 0, tables: run.db_after_onboarding });
    (run.visits || []).forEach(v => { if (v.db_after) out.push({ id: `v${v.no}-applied`, label: "회차가 끝난 뒤", visit: v.no, tables: v.db_after }); });
    return out;
  }

  // 같은 스냅숏의 행으로 ID 이름표를 만든다.
  function labelMap(tables) {
    const m = new Map(), rows = (t) => (tables[t] && tables[t].rows) || [];
    rows("users").forEach(r => m.set(r.user_id, `사용자 ${r.display_name || ""}`.trim()));
    rows("profiles").forEach(r => m.set(r.profile_id, `프로필 ${r.name || ""}`.trim()));
    [...rows("visit_sessions")].sort((a, b) => String(a.started_at).localeCompare(String(b.started_at)))
      .forEach((r, i) => m.set(r.session_id, `${i + 1}회차 면회`));
    rows("photos").forEach((r, i) => m.set(r.photo_id, `사진 ${i + 1}`));
    rows("card_sets").forEach((r, i) => m.set(r.set_id, `카드 묶음 ${i + 1}`));
    rows("proto_elements").forEach(r => m.set(r.element_id, `${KIND[r.kind] || r.kind}:${r.name}`));
    rows("profile_topics").forEach(r => m.set(r.topic_id, `주제: ${r.title}`));
    for (const t of ["proto_cards", "conversation_cards"]) rows(t).forEach(r => {
      const v = m.get(r.session_id); m.set(r.card_id, `${v ? v.replace(" 면회", " ") : ""}#${r.position} ${r.card_title}`); });
    rows("life_fact_proposals").forEach(r => m.set(r.proposal_id, `제안: ${r.title}`));
    rows("life_facts").forEach(r => m.set(r.fact_id, `이야기: ${r.title}`));
    return m;
  }

  // DB에는 UTC로 들어 있다. 면회 일정은 한국 시각으로 잡았으니 한국 시각으로 보여 준다.
  const KST = new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Seoul", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" });
  const kst = (s) => { const d = new Date(s.replace(" ", "T")); return isNaN(d) ? s.slice(0, 16) : KST.format(d); };
  const keyOf = (tb, r) => tb.key.split(",").map(k => r[k]).join("|");
  const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

  function diff(tb, prevTb) {
    if (!prevTb) return { added: new Set(), changed: new Map(), gone: [] };
    const before = new Map(prevTb.rows.map(r => [keyOf(prevTb, r), r]));
    const now = new Set(tb.rows.map(r => keyOf(tb, r)));
    const added = new Set(), changed = new Map();
    tb.rows.forEach(r => { const k = keyOf(tb, r), o = before.get(k);
      if (!o) added.add(k); else { const cols = tb.columns.filter(c => !same(r[c], o[c])); if (cols.length) changed.set(k, new Set(cols)); } });
    const gone = prevTb.rows.filter(r => !now.has(keyOf(prevTb, r)));
    return { added, changed, gone };
  }

  function cell(value, names, readable, own) {
    if (value == null) return [h("span", { class: "null" }, "null"), ""];
    if (typeof value === "boolean") return [h("span", { class: value ? "t" : "f" }, String(value)), "num"];
    if (typeof value === "number") return [String(value), "num"];
    if (typeof value === "object") return [JSON.stringify(value), ""];
    const s = String(value);
    if (UUID.test(s)) {
      if (readable && !own && names.has(s)) return [h("span", { class: "ref", title: s }, names.get(s)), "id"];
      return [h("span", { title: s }, s.slice(0, 8)), "id"];
    }
    if (/^\d{4}-\d\d-\d\d[T ]\d\d:\d\d/.test(s)) return [h("span", { title: s }, kst(s)), "time"];
    return [s, s.length <= 16 ? "short" : ""];
  }

  function mount(root, opts = {}) {
    let snaps = [], current = null, table = null;
    const state = { readable: true, hideEmpty: true, onlyChanged: false };
    const points = h("div", { class: "dbv-points" });
    const main = h("div", { class: "dbv-main" });
    root.replaceChildren(h("div", { class: "dbv" }, points, main));
    points.addEventListener("click", e => { const b = e.target.closest("button"); if (b) { current = b.dataset.id; render(); } });

    function renderPoints() {
      let lastVisit = null;
      const kids = [];
      snaps.forEach((s, i) => {
        if (s.visit !== lastVisit) { kids.push(h("p", { class: "vh" }, s.visit ? `${s.visit}회차` : "처음")); lastVisit = s.visit; }
        const prev = snaps[i - 1];
        let add = 0, chg = 0;
        if (prev) for (const [t, tb] of Object.entries(s.tables)) { const d = diff(tb, prev.tables[t]); add += d.added.size; chg += d.changed.size; }
        kids.push(h("button", { type: "button", "data-id": s.id, "aria-current": String(s.id === current) }, h("span", {}, s.label),
          h("span", { class: "d" }, prev ? `새 행 ${add} · 바뀜 ${chg}` : `처음 상태`)));
      });
      points.replaceChildren(...(kids.length ? kids : [h("p", { class: "dbv-note" }, opts.emptyText || "아직 찍힌 시점이 없습니다.")]));
    }

    function render() {
      renderPoints();
      const i = snaps.findIndex(s => s.id === current);
      if (i < 0) { main.replaceChildren(h("p", { class: "dbv-note" }, "왼쪽에서 시점을 고르세요.")); return; }
      const snap = snaps[i], prev = snaps[i - 1], names = labelMap(snap.tables);
      const all = Object.keys(snap.tables);
      const diffs = Object.fromEntries(all.map(t => [t, diff(snap.tables[t], prev && prev.tables[t])]));
      const touched = (t) => diffs[t].added.size || diffs[t].changed.size || diffs[t].gone.length;
      const shown = all.filter(t => !state.hideEmpty || snap.tables[t].rows.length || touched(t));
      if (!table || !shown.includes(table)) table = shown.find(touched) || shown[0];
      const seg = h("div", { class: "dbv-seg", role: "tablist" }, shown.map(t => { const d = diffs[t], tb = snap.tables[t];
        return h("button", { type: "button", role: "tab", "data-t": t, "aria-selected": String(t === table), class: tb.rows.length ? null : "empty", title: t },
          NAMES[t] || t, h("span", { class: "n" }, tb.rows.length), d.added.size ? h("span", { class: "n plus" }, `+${d.added.size}`) : null,
          d.changed.size ? h("span", { class: "n plus" }, `~${d.changed.size}`) : null); }));
      seg.addEventListener("click", e => { const b = e.target.closest("button"); if (b) { table = b.dataset.t; render(); } });

      const opt = (key, text) => { const box = h("input", { type: "checkbox" }); box.checked = state[key];
        box.addEventListener("change", () => { state[key] = box.checked; render(); }); return h("label", {}, box, text); };
      const hidden = all.length - shown.length;
      const bar = h("div", { class: "dbv-bar" }, h("h3", {}, `${snap.visit ? snap.visit + "회차 · " : ""}${snap.label}`),
        h("div", { class: "dbv-opts" }, opt("readable", "ID를 이름으로"), opt("hideEmpty", `빈 테이블 숨기기${hidden ? ` (${hidden}개)` : ""}`), prev ? opt("onlyChanged", "새·바뀐 행만") : null));

      const tb = snap.tables[table], d = diffs[table];
      const cols = tb.columns.filter(c => !(state.readable && c === "profile_id" && table !== "profiles"));
      const meta = h("div", { class: "dbv-meta" }, h("span", {}, h("code", {}, table), ` · ${tb.rows.length}행`),
        prev ? h("span", {}, `${prev.visit ? prev.visit + "회차 " : ""}${prev.label}과 비교: 새 행 ${d.added.size}, 바뀐 행 ${d.changed.size}, 없어진 행 ${d.gone.length}`) : h("span", {}, "처음 시점이라 비교 없음"),
        cols.length < tb.columns.length ? h("span", {}, "profile_id는 모두 이 프로필이라 숨김") : null);
      const row = (r, cls) => { const k = keyOf(tb, r), ch = d.changed.get(k);
        return h("tr", { class: cls || (d.added.has(k) ? "new" : null) }, cols.map(c => { const [v, kind] = cell(r[c], names, state.readable, tb.key === c);
          const long = typeof v === "string" && v.length > 120;
          return h("td", { class: [kind, ch && ch.has(c) ? "chg" : "", long ? "long" : ""].filter(Boolean).join(" ") || null,
            title: ch && ch.has(c) ? "직전 시점과 값이 다름" : null }, h("span", { class: "v" }, v)); })); };
      const body = tb.rows.length || d.gone.length
        ? h("div", { class: "dbv-scroll" }, h("table", {}, h("thead", {}, h("tr", {}, cols.map(c => h("th", {}, c)))),
            h("tbody", {}, tb.rows.filter(r => !(state.onlyChanged && prev) || d.added.has(keyOf(tb, r)) || d.changed.has(keyOf(tb, r))).map(r => row(r)),
              d.gone.map(r => row(r, "gone")))))
        : h("p", { class: "dbv-note" }, "이 시점에는 행이 없습니다.");
      body.addEventListener?.("click", e => { const td = e.target.closest("td.long"); if (td) td.classList.toggle("open"); });
      main.replaceChildren(bar, seg, meta, body,
        h("p", { class: "dbv-note" }, "노란 줄은 새로 생긴 행, 테두리 칸은 직전 시점과 값이 달라진 칸, 줄 그은 행은 없어진 행입니다. 긴 글은 누르면 펼쳐집니다."));
    }

    return {
      set(list, { follow = false, emptyText } = {}) {
        snaps = list || [];
        if (emptyText) opts.emptyText = emptyText;
        if (!snaps.some(s => s.id === current) || follow) current = snaps.length ? snaps[snaps.length - 1].id : null;
        render();
      },
    };
  }

  return { mount, fromRun };
})();
