"""시뮬레이션 기록의 카드 생성 단계(context → ①조사 → ②연결 판정 → ③선정 → ④문안 → 면회 뒤)를 회차마다 입력과 출력으로 나눠 보여 주는 한 장짜리 HTML.

    uv run python -m simulation.steps_view simulation/runs/persona-topics-...json   # → 같은 이름의 .steps.html
    작업대: http://127.0.0.1:8780/runs/<기록 이름>/steps

단계 기록은 visits[].recommend.steps(backends/steps.py)에서 읽는다. 단계 기록이 없는 예전 기록은 회차마다 비어 있다고 표시한다.
render(..., fragment=True)는 문서 틀(doctype, html, head, body) 없이 내용만 돌려준다(claude.ai 페이지로 올릴 때).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
PROMPT_KEYS = {"research": "추천 ① 조사 에이전트", "match": "추천 ② 연결 판정", "write": "추천 ④ 문안 작성",
               "same_story": "추천 ①② 같은 이야기 기준"}


def slim(run: dict[str, Any]) -> dict[str, Any]:
    """화면에 필요한 것만 남긴다. 대화 전사와 DB 스냅숏은 뺀다."""
    p = run.get("persona", {})
    visits = []
    for v in run.get("visits", []):
        visits.append({
            "no": v["no"], "date": v.get("date"), "mood": v.get("mood"),
            "recommend": {k: v["recommend"].get(k) for k in ("candidates", "refills", "seconds", "prompt_version", "steps")},
            "cards": [{k: c.get(k) for k in ("position", "card_title", "kind", "selected", "added_in_visit", "review", "select_why",
                                             "primary_question")} | {"topic": (c.get("topic") or {}).get("title")}
                      for c in v.get("cards", [])],
            "applied": v.get("applied", {}), "evaluation": v.get("evaluation"), "turns": len(v.get("transcript", []))})
    return {"name": run.get("_name", ""), "seed": run.get("seed"), "llm": run.get("llm"), "blank": run.get("blank_profile", False),
            "failure": run.get("failure"), "started_at": run.get("started_at"),
            "persona": {"id": p.get("id"), "summary": (p.get("patient") or {}).get("summary"),
                        "relation": (p.get("caregiver") or {}).get("relation")},
            "onboarding": {"answers": (run.get("onboarding") or {}).get("answers"),
                           "photo": bool((run.get("onboarding") or {}).get("photo"))},
            "prompts": {k: run.get("prompts", {}).get(name, "") for k, name in PROMPT_KEYS.items()},
            "failed": run.get("failed_recommend"), "visits": visits}


def render(run: dict[str, Any], fragment: bool = False) -> str:
    payload = json.dumps(slim(run), ensure_ascii=False, default=str).replace("</", "<\\/")
    body = TEMPLATE.replace("__DATA__", payload)
    if fragment:
        return body
    return f'<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"></head><body>{body}</body></html>'


def build(path: Path) -> Path:
    run = json.loads(path.read_text(encoding="utf-8"))
    run["_name"] = path.stem
    out = path.with_suffix(".steps.html")
    out.write_text(render(run), encoding="utf-8")
    return out


TEMPLATE = r"""<title>카드 생성 단계 기록</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+KR:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap">
<style>
/* 레이아웃: 회차 탭 → 단계 흐름 띠 → 단계마다 입력(왼쪽)과 출력(오른쪽)을 나란히. 좁으면 위아래로 쌓음 */
:root{
  --bg:#f6f7f5; --surface:#ffffff; --sunken:#eef0ec; --fg:#1d2321; --sub:#5d6662; --faint:#8b938f; --line:#dde1dc;
  --in:#2d6a8f; --in-bg:#eaf2f7; --out:#7a4d16; --out-bg:#f7efe3;
  --personal:#2f6fde; --photo:#9a4fd1; --discover:#1c8358; --general:#9a6c0c;
  --ok:#1c8358; --ok-bg:#e4f3eb; --bad:#b23a32; --bad-bg:#f8e6e4; --warn:#a85a0c; --warn-bg:#f8eedd;
  --display:"IBM Plex Sans KR",system-ui,sans-serif; --body:"IBM Plex Sans KR",system-ui,-apple-system,"Apple SD Gothic Neo",sans-serif;
  --mono:"JetBrains Mono",ui-monospace,SFMono-Regular,Menlo,monospace;
}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){
  --bg:#141716; --surface:#1c201f; --sunken:#232826; --fg:#e4e8e6; --sub:#a2aba7; --faint:#77807c; --line:#2f3533;
  --in:#7fb8dc; --in-bg:#1a2a33; --out:#e0b07a; --out-bg:#2e2419;
  --personal:#86adff; --photo:#cb9af2; --discover:#62d29d; --general:#e0bb5c;
  --ok:#62d29d; --ok-bg:#183126; --bad:#f08a80; --bad-bg:#3a1f1d; --warn:#f0b066; --warn-bg:#352816; color-scheme:dark}}
:root[data-theme="dark"]{
  --bg:#141716; --surface:#1c201f; --sunken:#232826; --fg:#e4e8e6; --sub:#a2aba7; --faint:#77807c; --line:#2f3533;
  --in:#7fb8dc; --in-bg:#1a2a33; --out:#e0b07a; --out-bg:#2e2419;
  --personal:#86adff; --photo:#cb9af2; --discover:#62d29d; --general:#e0bb5c;
  --ok:#62d29d; --ok-bg:#183126; --bad:#f08a80; --bad-bg:#3a1f1d; --warn:#f0b066; --warn-bg:#352816; color-scheme:dark}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.6 var(--body)}
body::before{content:"";position:fixed;inset:0 0 auto;height:env(safe-area-inset-top,0px);z-index:10;background:var(--surface)}
.gut{padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px))}
.wrap{max-width:1280px;margin:0 auto}
header.top{background:var(--surface);border-bottom:1px solid var(--line);padding-block:18px 0}
h1{font:600 20px/1.3 var(--display);margin:0;text-wrap:balance}
.meta{display:flex;flex-wrap:wrap;gap:6px 14px;color:var(--sub);font-size:13px;margin:6px 0 12px}
.meta b{color:var(--fg);font-weight:500}
nav.tabs{display:flex;gap:2px;overflow-x:auto;position:sticky;top:env(safe-area-inset-top,0px);background:var(--surface);z-index:5;border-bottom:1px solid var(--line)}
nav.tabs button{border:0;background:none;color:var(--sub);font:500 14px var(--body);padding:10px 14px;border-bottom:2px solid transparent;cursor:pointer;white-space:nowrap}
nav.tabs button[aria-selected="true"]{color:var(--fg);border-bottom-color:var(--fg)}
button:focus-visible,summary:focus-visible,a:focus-visible{outline:2px solid var(--in);outline-offset:2px}
main{padding-block:18px 60px;display:flex;flex-direction:column;gap:18px}
.flow{display:flex;gap:6px;overflow-x:auto;padding-bottom:4px}
.flow a{flex:1 0 128px;text-decoration:none;color:inherit;background:var(--surface);border:1px solid var(--line);border-radius:8px;padding:8px 10px;display:flex;flex-direction:column;gap:2px}
.flow a:hover{border-color:var(--sub)}
.flow .n{font:500 11px var(--mono);color:var(--faint);letter-spacing:.04em}
.flow .t{font-weight:600;font-size:13px}
.flow .v{font-size:12px;color:var(--sub)}
section.stage{background:var(--surface);border:1px solid var(--line);border-radius:10px;overflow:hidden;scroll-margin-top:56px}
.sh{display:flex;flex-wrap:wrap;align-items:baseline;gap:6px 12px;padding:12px 16px;border-bottom:1px solid var(--line)}
.sh h2{font:600 16px/1.3 var(--display);margin:0}
.sh .what{color:var(--sub);font-size:13px;flex:1 1 280px}
.sh .time{font:12px var(--mono);color:var(--faint)}
.io{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr)}
.io.wide-out{grid-template-columns:minmax(0,2fr) minmax(0,3fr)}
@media (max-width:860px){.io,.io.wide-out{grid-template-columns:minmax(0,1fr)}}
.col{padding:14px 16px;min-width:0;display:flex;flex-direction:column;gap:10px}
.col.in{background:var(--in-bg)}
.col.out{background:var(--out-bg)}
.col.full{grid-column:1/-1;background:var(--surface)}
.lab{font:600 11px var(--mono);letter-spacing:.08em;text-transform:uppercase}
.in .lab{color:var(--in)} .out .lab{color:var(--out)} .full .lab{color:var(--sub)}
.sub{color:var(--sub);font-size:13px} .faint{color:var(--faint)} .mono{font-family:var(--mono);font-size:12px}
.chips{display:flex;flex-wrap:wrap;gap:6px}
.chip{display:inline-flex;gap:6px;align-items:baseline;background:var(--surface);border:1px solid var(--line);border-radius:6px;padding:3px 8px;font-size:13px}
.chip .k{color:var(--faint);font-size:12px}
.chip.empty{border-style:dashed;color:var(--faint)}
.kind{display:inline-block;font:500 11px var(--mono);padding:1px 6px;border-radius:4px;border:1px solid currentColor;white-space:nowrap}
.k-personal{color:var(--personal)} .k-photo{color:var(--photo)} .k-discover{color:var(--discover)} .k-general{color:var(--general)}
.pill{display:inline-block;font-size:12px;padding:1px 8px;border-radius:999px;white-space:nowrap}
.pill.ok{background:var(--ok-bg);color:var(--ok)} .pill.bad{background:var(--bad-bg);color:var(--bad)} .pill.warn{background:var(--warn-bg);color:var(--warn)} .pill.n{background:var(--sunken);color:var(--sub)}
.scroll{overflow-x:auto;background:var(--surface);border:1px solid var(--line);border-radius:6px}
table{border-collapse:collapse;width:100%;font-size:13px}
th,td{text-align:left;vertical-align:top;padding:6px 8px;border-bottom:1px solid var(--line)}
th{font:600 11px var(--mono);letter-spacing:.04em;color:var(--faint);background:var(--sunken);position:sticky;top:0}
tr:last-child td{border-bottom:0}
td.num{font:12px var(--mono);color:var(--faint);white-space:nowrap;font-variant-numeric:tabular-nums}
tr.fate-picked td:first-child{box-shadow:inset 3px 0 var(--ok)}
tr.fate-drop td:first-child{box-shadow:inset 3px 0 var(--bad)}
tr.fate-cut td:first-child{box-shadow:inset 3px 0 var(--faint)}
tr.fate-cut td{color:var(--sub)}
details{background:var(--surface);border:1px solid var(--line);border-radius:6px}
details>summary{cursor:pointer;padding:6px 10px;font-size:13px;list-style-position:inside}
details>summary .mono{color:var(--sub)}
details[open]>summary{border-bottom:1px solid var(--line)}
pre{margin:0;padding:10px;font:12px/1.5 var(--mono);white-space:pre-wrap;word-break:break-word;max-height:420px;overflow:auto}
.calls{display:flex;flex-direction:column;gap:6px}
.req{background:var(--surface);border-left:3px solid var(--in);padding:6px 10px;border-radius:0 6px 6px 0;font-size:13px}
.pair{display:grid;grid-template-columns:minmax(0,1fr) 28px minmax(0,1.3fr);align-items:stretch;gap:0;border-bottom:1px solid var(--line)}
.pair:last-child{border-bottom:0}
.pair>div{padding:12px 16px;min-width:0}
.pair .pi{background:var(--in-bg)} .pair .po{background:var(--out-bg)}
.pair .arrow{display:flex;align-items:center;justify-content:center;color:var(--faint);background:linear-gradient(90deg,var(--in-bg) 50%,var(--out-bg) 50%)}
@media (max-width:860px){.pair{grid-template-columns:minmax(0,1fr)}.pair .arrow{display:none}}
.pair h4{margin:0 0 4px;font-size:14px;display:flex;gap:6px;align-items:center;flex-wrap:wrap}
.q{font-weight:600;margin:6px 0 4px}
ul.fu{margin:0;padding-left:18px;font-size:13px}
.slots{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:8px}
.slot{background:var(--surface);border:1px solid var(--line);border-radius:6px;padding:8px 10px;display:flex;flex-direction:column;gap:4px}
.slot .pos{font:500 11px var(--mono);color:var(--faint)}
.slot.reserve{border-style:dashed}
.bar{display:flex;height:10px;border-radius:3px;overflow:hidden;background:var(--sunken);min-width:120px}
.bar span{display:block}
.legend{display:flex;flex-wrap:wrap;gap:10px;font-size:12px;color:var(--sub)}
.legend i{display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:4px;vertical-align:-1px}
.note{font-size:13px;color:var(--sub);max-width:75ch}
.empty-state{padding:24px;text-align:center;color:var(--sub)}
</style>
<header class="top gut"><div class="wrap">
  <h1 id="title">카드 생성 단계 기록</h1>
  <div class="meta" id="meta"></div>
</div></header>
<nav class="tabs gut" id="tabs" aria-label="회차"></nav>
<main class="gut"><div class="wrap" id="view" style="display:flex;flex-direction:column;gap:18px"></div></main>
<script type="application/json" id="data">__DATA__</script>
<script>
const D = JSON.parse(document.getElementById("data").textContent);
const KIND_COLOR = { personal: "var(--personal)", photo: "var(--photo)", discover: "var(--discover)", general: "var(--general)" };
const KINDS = ["personal", "photo", "discover", "general"];
const FIELD = { occupation: "하시던 일", hometown: "고향", hobby: "취미", family: "가족" };
const ACTION = { more: "더 자주", less: "덜 자주", exclude: "추천하지 않기" };
const REACT = { positive: "좋았어요", neutral: "보통", negative: "아쉬웠어요", notUsed: "안 씀" };
const TOOL = { get_profile: "프로필", list_topics: "지난 주제 목록", get_topic: "주제 하나", list_life_facts: "쌓아온 이야기 목록",
  get_life_facts: "이야기 원문", list_photos: "사진 설명" };

function h(tag, attrs = {}, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v == null || v === false) continue;
    if (k === "class") e.className = v; else if (k === "text") e.textContent = v; else if (k === "style") e.setAttribute("style", v); else e.setAttribute(k, v);
  }
  for (const k of kids.flat(Infinity)) if (k != null && k !== false) e.append(k instanceof Node ? k : document.createTextNode(String(k)));
  return e;
}
const kind = (k) => h("span", { class: `kind k-${k}` }, k);
const pill = (cls, t) => h("span", { class: `pill ${cls}` }, t);
const lab = (t) => h("div", { class: "lab" }, t);
const js = (x) => JSON.stringify(x, null, 2);
const pre = (x) => h("pre", {}, typeof x === "string" ? x : js(x));
const det = (summary, body, open) => h("details", open ? { open: "" } : {}, h("summary", {}, summary), body);
const table = (head, rows) => h("div", { class: "scroll" }, h("table", {}, h("thead", {}, h("tr", {}, head.map(t => h("th", {}, t)))), h("tbody", {}, rows)));
const short = (id) => id ? String(id).slice(0, 8) : "";
const evText = (ev) => (ev || []).map(e => e.factId ? `이야기 ${short(e.factId)}` : e.photoId ? `사진 ${short(e.photoId)}` : e.profileField ? FIELD[e.profileField] || e.profileField : Object.values(e)[0]).join(", ");

function kindBar(items) {
  const n = items.length || 1, c = Object.fromEntries(KINDS.map(k => [k, items.filter(i => i === k).length]));
  return h("div", { style: "display:flex;gap:8px;align-items:center;flex-wrap:wrap" },
    h("div", { class: "bar", title: KINDS.map(k => `${k} ${c[k]}`).join(", ") }, KINDS.filter(k => c[k]).map(k => h("span", { style: `width:${c[k] / n * 100}%;background:${KIND_COLOR[k]}` }))),
    h("span", { class: "sub" }, KINDS.filter(k => c[k]).map(k => `${k} ${c[k]}`).join(" · ") || "-"));
}

function stage(id, no, title, what, time, ...body) {
  return h("section", { class: "stage", id },
    h("div", { class: "sh" }, h("h2", {}, no ? `${no} ${title}` : title), h("span", { class: "what" }, what), time ? h("span", { class: "time" }, time) : null), ...body);
}
const io = (inKids, outKids, cls = "") => h("div", { class: `io ${cls}` }, h("div", { class: "col in" }, lab("입력"), inKids), h("div", { class: "col out" }, lab("출력"), outKids));
const promptBox = (key, label) => D.prompts[key] ? det(h("span", {}, "시스템 프롬프트 ", h("span", { class: "mono" }, label)), pre(D.prompts[key])) : null;

function fateOf(st) {
  const f = {};
  const last = st.match[st.match.length - 1];
  if (last) last.dropped.forEach(d => f[d.no] = ["drop", pill("bad", "② 판정에서 빠짐")]);
  if (st.select) {
    st.select.dropped.forEach(d => f[d.no] = ["cut", pill("n", "③ 선정 탈락")]);
    st.select.picked.forEach(p => f[p.no] = ["picked", pill("ok", `③ ${p.position}번 카드`)]);
  }
  return f;
}

// ── 단계별 ───────────────────────────────────────
function contextStage(c) {
  const pf = c.profileFacts || {};
  const topics = c.topics || [];
  return stage("s-context", "", "context", "backend 역할이 DB에서 모아 카드 생성에 넘긴 것. 에이전트 도구는 이것만 읽는다.", null,
    h("div", { class: "io" }, h("div", { class: "col full" },
      lab("넘긴 것"),
      h("div", { class: "chips" }, h("span", { class: "chip" }, h("span", { class: "k" }, "연령대"), c.ageRange),
        Object.entries(FIELD).map(([k, t]) => h("span", { class: "chip" + (pf[k] ? "" : " empty") }, h("span", { class: "k" }, t), pf[k] || "비어 있음"))),
      h("div", { class: "chips" }, [["쌓아온 이야기", (c.lifeFacts || []).length], ["사진", (c.photos || []).length], ["지난 주제", topics.length],
        ["평가 끝난 면회", (c.visits || []).length], ["지난 카드", (c.pastCards || []).length]].map(([t, n]) => h("span", { class: "chip" + (n ? "" : " empty") }, h("span", { class: "k" }, t), n))),
      (c.lifeFacts || []).length ? det(`쌓아온 이야기 ${c.lifeFacts.length}개`, table(["제목", "내용", "출처", ""], c.lifeFacts.map(f =>
        h("tr", {}, h("td", {}, f.title), h("td", {}, f.content), h("td", { class: "num" }, f.source), h("td", {}, f.sensitive ? pill("bad", "아픈 기억") : null))))) : null,
      topics.length ? det(`지난 주제 ${topics.length}개`, table(["주제", "설명", "근거", "보호자 결정"], topics.map(t =>
        h("tr", {}, h("td", {}, t.title), h("td", { class: "sub" }, t.description), h("td", { class: "mono" }, evText(t.evidence)),
          h("td", {}, (t.feedback || []).map(f => pill(f.action === "exclude" ? "bad" : f.action === "less" ? "warn" : "ok", ACTION[f.action]))))))) : null,
      det("context 원문(JSON)", pre(c)))));
}

function toolResult(m) {
  const r = m.result;
  if (r && typeof r === "object") {
    if (Array.isArray(r.facts) || Array.isArray(r.topics) || Array.isArray(r.photos)) {
      const list = r.facts || r.topics || r.photos;
      return list.length ? pre(r) : h("div", { class: "sub", style: "padding:6px 10px" }, `비어 있음 (total ${r.total ?? 0})`);
    }
  }
  return pre(r);
}

function researchStage(r, i, fate, isLast) {
  const tools = r.messages.filter(m => m.kind === "tool" && m.name !== "CardCandidateSubmission");
  const reqs = r.messages.filter(m => m.kind === "request");
  const inKids = [promptBox("research", "agent.md"),
    reqs.map(m => h("div", { class: "req" }, h("span", { class: "lab" }, "요청 "), m.text)),
    h("div", { class: "sub" }, `도구 호출 ${tools.length}번 · 결과는 모델이 받은 그대로`),
    h("div", { class: "calls" }, tools.map(m => det(
      h("span", {}, h("span", { class: "mono" }, `턴 ${m.turn} · ${m.name}(${Object.entries(m.args || {}).map(([k, v]) => `${k}=${JSON.stringify(v)}`).join(", ")})`), " ", h("span", { class: "faint" }, TOOL[m.name] || "")),
      toolResult(m), tools.length <= 6)))];
  const rows = r.candidates.map(c => {
    const f = isLast ? (fate[c.no] || ["", null]) : ["", pill("n", "다시 찾기 전 제출")];
    return h("tr", { class: f[0] ? `fate-${f[0]}` : "" }, h("td", { class: "num" }, c.no), h("td", {}, kind(c.kind), c.sensitive ? [" ", pill("bad", "sensitive")] : null),
      h("td", {}, h("b", {}, c.card_title), h("div", { class: "sub" }, c.angle)),
      h("td", { class: "sub" }, c.linked_topic_id ? `기존 ${short(c.linked_topic_id)}` : c.new_topic_title),
      h("td", { class: "mono" }, evText(c.evidence.map(e => e.fact_id ? { factId: e.fact_id } : e.photo_id ? { photoId: e.photo_id } : { profileField: e.field })) || (c.discover_field ? `빈 칸: ${FIELD[c.discover_field]}` : "")),
      h("td", { class: "sub" }, c.reason), h("td", {}, f[1]));
  });
  const outKids = [kindBar(r.candidates.map(c => c.kind)),
    r.rejected.length ? det(h("span", {}, pill("warn", `거부된 제출 ${r.rejected.length}번`), " 제출 검사가 돌려보낸 오류"), r.rejected.map(pre)) : null,
    table(["#", "종류", "카드 제목 / angle", "주제", "근거", "reason", "결과"], rows)];
  return stage(`s-research-${i}`, "①", i ? `조사 · 다시 찾기 ${i}` : "조사", "에이전트가 도구로 context를 살펴보고 카드 후보를 낸 순서대로 제출한다.", `${r.seconds}초`,
    io(inKids, outKids, "wide-out"));
}

function matchStage(m, i) {
  const inp = m.input || { existing_topics: [], candidates: [] }, out = m.output || { assignments: [], new_topics: [] };
  const byC = Object.fromEntries((inp.candidates || []).map(c => [c.candidate_id, c]));
  const nt = Object.fromEntries((out.new_topics || []).map(t => [t.new_key, t]));
  const groups = {};
  (out.assignments || []).forEach(a => { const k = a.topic_id || a.new_key; groups[k] = (groups[k] || 0) + 1; });
  const inKids = [promptBox("match", "match.md + same_story.md"),
    h("div", { class: "sub" }, `기존 주제 ${(inp.existing_topics || []).length}개 · 후보 ${(inp.candidates || []).length}개. 에이전트가 적은 연결은 보여 주지 않는다.`),
    (inp.existing_topics || []).length ? table(["번호표", "주제", "설명"], inp.existing_topics.map(t => h("tr", {}, h("td", { class: "num" }, t.topic_id), h("td", {}, t.title), h("td", { class: "sub" }, t.description)))) : h("div", { class: "chip empty" }, "기존 주제 없음"),
    det(`후보 ${(inp.candidates || []).length}개`, table(["id", "종류", "카드 제목 / angle", "근거 글"], (inp.candidates || []).map(c => h("tr", {}, h("td", { class: "num" }, c.candidate_id), h("td", {}, kind(c.kind)),
      h("td", {}, h("b", {}, c.card_title), h("div", { class: "sub" }, c.angle)), h("td", { class: "sub" }, (c.evidence_texts || []).join(" / ")))))),
    det("판정 LLM 입력 원문(JSON)", pre(inp))];
  const outKids = [h("div", { class: "chips" }, h("span", { class: "chip" }, h("span", { class: "k" }, "남음"), m.kept.length), h("span", { class: "chip" + (m.dropped.length ? "" : " empty") }, h("span", { class: "k" }, "빠짐"), m.dropped.length),
      h("span", { class: "chip" }, h("span", { class: "k" }, "서로 다른 주제"), Object.keys(groups).length)),
    table(["id", "후보", "연결", "판정 이유"], [...(out.assignments || []).map(a => { const c = byC[a.candidate_id] || {}, k = a.topic_id || a.new_key;
      return h("tr", {}, h("td", { class: "num" }, a.candidate_id), h("td", {}, c.card_title),
        h("td", {}, a.topic_id ? `기존 ${a.topic_id}` : h("span", {}, h("span", { class: "mono" }, a.new_key), " ", (nt[a.new_key] || {}).title || ""), groups[k] > 1 ? [" ", pill("warn", `${groups[k]}개가 한 주제`)] : null),
        h("td", { class: "sub" }, a.reason)); }),
      ...m.dropped.map(d => h("tr", { class: "fate-drop" }, h("td", { class: "num" }, `#${d.no}`), h("td", {}, d.card_title), h("td", {}, pill("bad", "빠짐")), h("td", { class: "sub" }, d.reason)))]),
    det("판정 LLM 출력 원문(JSON)", pre(out))];
  return stage(`s-match-${i}`, "②", i ? `연결 판정 · 다시 찾기 ${i}` : "연결 판정", "후보마다 기존 주제와 같은 이야기인지 판정하고, 새 이야기끼리도 같으면 묶는다. 추천하지 않기 주제에 걸린 후보는 뺀다.", `${m.seconds}초`, io(inKids, outKids));
}

function selectStage(s) {
  const r = s.rules || {};
  const inKids = [h("div", { class: "chips" }, [["카드", r.card_count], ["새 이야기 먼저", `${r.min_new}장`], ["temperature", r.temperature]].map(([k, v]) => h("span", { class: "chip" }, h("span", { class: "k" }, k), v))),
    s.topics.length ? table(["기존 주제", "점수", ""], s.topics.map(t => h("tr", {}, h("td", {}, t.title), h("td", { class: "num" }, t.score.toFixed(2)), h("td", {}, t.excluded ? pill("bad", "추천하지 않기") : null))))
      : h("div", { class: "note" }, "기존 주제가 없다. 점수 추첨 없이 새 이야기 후보를 에이전트가 낸 순서대로 앞에서부터 채운다.")];
  const slot = (p) => h("div", { class: "slot" + (p.position > 9 ? " reserve" : "") }, h("span", { class: "pos" }, `${p.position}번 ${p.position > 9 ? "· 면회 중 보충" : ""} · 후보 #${p.no}`),
    h("div", {}, kind(p.kind), " ", h("b", {}, p.cardTitle)), h("span", { class: "sub" }, `${p.bucket === "new" ? "새 이야기" : "기존 주제"} · ${p.reason}`));
  const outKids = [kindBar(s.picked.map(p => p.kind)), h("div", { class: "slots" }, s.picked.map(slot)),
    s.dropped.length ? det(`탈락 ${s.dropped.length}개`, table(["후보", "제목", "이유"], s.dropped.map(d => h("tr", { class: "fate-cut" }, h("td", { class: "num" }, `#${d.no}`), h("td", {}, d.card_title), h("td", { class: "sub" }, d.reason)))), true) : null];
  return stage("s-select", "③", "선정", "코드가 12장을 고른다. 1~9번은 보호자가 고르는 카드, 10~12번은 면회 중 보충용이다.", null, io(inKids, outKids, "wide-out"));
}

function writeStage(w) {
  const out = Object.fromEntries((w.output.cards || []).map(c => [c.position, c]));
  return stage("s-write", "④", "문안", "고른 12장에만 설명, 첫 질문, 꼬리 질문 3개를 쓴다. 문안 모델은 아래 왼쪽만 본다.", `${w.seconds}초`,
    h("div", { class: "io" }, h("div", { class: "col full" },
      h("div", { class: "chips" }, h("span", { class: "chip" }, h("span", { class: "k" }, "공통 입력 profile"), h("span", { class: "mono" }, JSON.stringify(w.input.profile))),
        h("span", { class: "chip" + (w.firstProblems.length ? "" : " empty") }, h("span", { class: "k" }, "첫 검사에서 걸린 것"), `${w.firstProblems.length}건`)),
      w.firstProblems.length ? h("ul", { class: "sub" }, w.firstProblems.map(p => h("li", {}, p))) : null,
      promptBox("write", "writing_topics.md")),
      h("div", { style: "grid-column:1/-1" }, w.input.cards.map(c => { const o = out[c.position] || {};
        return h("div", { class: "pair" },
          h("div", { class: "pi" }, lab("입력"), h("h4", {}, h("span", { class: "mono faint" }, `${c.position}`), kind(c.kind), c.sensitive ? pill("bad", "sensitive") : null, c.card_title),
            h("div", { class: "sub" }, h("b", {}, "angle "), c.angle), h("div", { class: "sub" }, h("b", {}, "주제 "), `${c.topic.title} — ${c.topic.description}`),
            h("div", { class: "sub" }, h("b", {}, "근거 글 "), c.evidence_texts.length ? c.evidence_texts.join(" / ") : h("span", { class: "faint" }, "없음"))),
          h("div", { class: "arrow", "aria-hidden": "true" }, "→"),
          h("div", { class: "po" }, lab("출력"), h("div", { class: "sub" }, o.description), h("div", { class: "q" }, o.primary_question), h("ul", { class: "fu" }, (o.follow_up_questions || []).map(q => h("li", {}, q))))); }))));
}

function afterStage(v) {
  const used = v.cards.filter(c => c.selected);
  const ap = v.applied || {};
  return stage("s-after", "", "면회 뒤", "보호자가 고른 카드와 평가, 승인한 이야기와 주제 결정. 다음 회차 context로 이어진다.", v.turns ? `대화 ${v.turns}턴` : null,
    h("div", { class: "io" }, h("div", { class: "col full" },
      table(["카드", "종류", "제목", "주제", "보호자", "평가"], v.cards.map(c => h("tr", { class: c.selected ? "fate-picked" : "" }, h("td", { class: "num" }, c.position), h("td", {}, c.kind ? kind(c.kind) : null),
        h("td", {}, c.card_title, h("div", { class: "sub" }, c.primary_question)), h("td", { class: "sub" }, c.topic),
        h("td", {}, c.added_in_visit ? pill("ok", "면회 중 추가") : c.selected ? pill("ok", "고름") : pill("n", c.position > 9 ? "안 씀" : "안 고름"), c.select_why ? h("div", { class: "sub" }, c.select_why) : null),
        h("td", {}, c.review ? pill(c.review === "positive" ? "ok" : c.review === "negative" ? "bad" : "n", REACT[c.review]) : null)))),
      h("div", { class: "chips" }, h("span", { class: "chip" }, h("span", { class: "k" }, "고른 카드"), used.length),
        h("span", { class: "chip" }, h("span", { class: "k" }, "저장된 이야기"), (ap.facts || []).length + (ap.manual || []).length),
        (ap.feedback || []).map(f => h("span", { class: "chip" }, h("span", { class: "k" }, ACTION[f.action]), f.name))),
      (ap.facts || []).length || (ap.manual || []).length ? det(`저장된 이야기 ${(ap.facts || []).length + (ap.manual || []).length}개`,
        table(["제목", "내용", ""], [...(ap.facts || []), ...(ap.manual || []).map(m => ({ ...m, manual: true }))].map(f => h("tr", {}, h("td", {}, f.title), h("td", { class: "sub" }, f.content),
          h("td", {}, f.manual ? pill("n", "직접 추가") : f.edited ? pill("warn", "고쳐서 승인") : null, f.fabricated ? pill("bad", "생애에 없음") : null))))) : null)));
}

function visitView(v) {
  const st = v.recommend.steps;
  const root = h("div", { style: "display:flex;flex-direction:column;gap:18px" });
  if (!st) { root.append(h("div", { class: "stage empty-state" }, "이 회차에는 단계 기록이 없습니다. 단계 기록을 넣기 전에 돌린 실행입니다.")); return root; }
  const fate = fateOf(st), lastR = st.research[st.research.length - 1], lastM = st.match[st.match.length - 1];
  const c = st.context, pf = c.profileFacts || {};
  root.append(h("nav", { class: "flow", "aria-label": "단계" },
    [["s-context", "context", "입력", `초기 정보 ${Object.keys(FIELD).filter(k => pf[k]).length}/4 · 이야기 ${(c.lifeFacts || []).length} · 주제 ${(c.topics || []).length}`],
     ["s-research-0", "①", "조사", `후보 ${lastR.candidates.length}개${st.research.length > 1 ? ` · 다시 찾기 ${st.research.length - 1}` : ""}`],
     ["s-match-0", "②", "연결 판정", `남음 ${lastM.kept.length} · 빠짐 ${lastM.dropped.length}`],
     ["s-select", "③", "선정", st.select ? `${st.select.picked.length}장 · 탈락 ${st.select.dropped.length}` : "실패"],
     ["s-write", "④", "문안", st.write ? `첫 검사 ${st.write.firstProblems.length}건` : "실패"],
     ["s-after", "", "면회 뒤", `고름 ${v.cards.filter(x => x.selected).length}장`]].map(([id, n, t, val]) =>
      h("a", { href: `#${id}` }, h("span", { class: "n" }, n || "·"), h("span", { class: "t" }, t), h("span", { class: "v" }, val)))));
  root.append(contextStage(c));
  st.research.forEach((r, i) => root.append(researchStage(r, i, fate, i === st.research.length - 1)));
  st.match.forEach((m, i) => root.append(matchStage(m, i)));
  if (st.select) root.append(selectStage(st.select));
  if (st.write) root.append(writeStage(st.write));
  root.append(afterStage(v));
  root.querySelectorAll(".flow a").forEach(a => a.addEventListener("click", e => { e.preventDefault(); const t = document.getElementById(a.getAttribute("href").slice(1)); if (t) t.scrollIntoView({ behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" }); }));
  return root;
}

function compareView() {
  const rows = D.visits.map(v => { const st = v.recommend.steps; if (!st) return h("tr", {}, h("td", { class: "num" }, `${v.no}회`), h("td", { colspan: "6", class: "sub" }, "단계 기록 없음"));
    const c = st.context, r = st.research[st.research.length - 1];
    return h("tr", {}, h("td", { class: "num" }, `${v.no}회`),
      h("td", { class: "sub" }, `이야기 ${(c.lifeFacts || []).length} · 주제 ${(c.topics || []).length} · 결정 ${(c.topics || []).reduce((n, t) => n + (t.feedback || []).length, 0)}`),
      h("td", {}, kindBar(r.candidates.map(x => x.kind))), h("td", {}, st.select ? kindBar(st.select.picked.map(p => p.kind)) : "-"),
      h("td", { class: "num" }, st.research.length - 1), h("td", { class: "num" }, st.write ? st.write.firstProblems.length : "-"),
      h("td", { class: "num" }, v.cards.filter(x => x.selected).length)); });
  return h("div", { style: "display:flex;flex-direction:column;gap:18px" },
    stage("s-compare", "", "회차 비교", "회차가 지나며 context가 쌓이고 카드 구성이 어떻게 바뀌는지 본다.", null,
      h("div", { class: "io" }, h("div", { class: "col full" },
        h("div", { class: "legend" }, KINDS.map(k => h("span", {}, h("i", { style: `background:${KIND_COLOR[k]}` }), k))),
        table(["회차", "context", "① 후보 종류", "③ 선정 12장 종류", "다시 찾기", "④ 첫 검사", "보호자가 고름"], rows)))));
}

function render() {
  const ob = D.onboarding || {}, ans = ob.answers || {};
  document.getElementById("title").textContent = `카드 생성 단계 기록 · ${D.persona.id || ""}${D.blank ? " (초기 정보 없음)" : ""}`;
  const meta = document.getElementById("meta");
  meta.append(h("span", {}, D.persona.summary || ""), h("span", {}, "초기 정보 ", h("b", {}, `${Object.keys(FIELD).filter(k => ans[k]).length}/4칸`), ob.photo ? " · 사진 있음" : " · 사진 없음"),
    h("span", {}, "모델 ", h("b", {}, D.llm || "-"), " · 버전 ", h("b", {}, (D.visits[0] && D.visits[0].recommend.prompt_version) || "-"), " · seed ", h("b", {}, D.seed)),
    h("span", { class: "mono faint" }, D.name), D.failure ? pill("warn", D.failure) : null);
  const tabs = [...D.visits.map(v => ({ id: `v${v.no}`, label: `${v.no}회차`, render: () => visitView(v) })), ...(D.visits.length > 1 ? [{ id: "compare", label: "회차 비교", render: compareView }] : [])];
  if (!tabs.length) { document.getElementById("view").append(h("div", { class: "stage empty-state" }, "끝난 회차가 없습니다.")); return; }
  const nav = document.getElementById("tabs");
  const show = (id) => { const t = tabs.find(x => x.id === id) || tabs[0];
    nav.querySelectorAll("button").forEach(b => b.setAttribute("aria-selected", String(b.dataset.id === t.id)));
    document.getElementById("view").replaceChildren(t.render()); try { history.replaceState(null, "", "#" + t.id); } catch (e) {} };
  tabs.forEach(t => nav.append(h("button", { type: "button", "data-id": t.id, "aria-selected": "false" }, t.label)));
  nav.addEventListener("click", e => { const b = e.target.closest("button"); if (b) show(b.dataset.id); });
  const hash = (location.hash || "").slice(1);
  show(tabs.some(t => t.id === hash) ? hash : tabs[0].id);
}
render();
</script>
"""


if __name__ == "__main__":
    for arg in sys.argv[1:]:
        print(build(Path(arg)))
