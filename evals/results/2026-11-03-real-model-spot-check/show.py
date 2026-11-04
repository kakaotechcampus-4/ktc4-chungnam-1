"""카드 출력의 UUID를 합성 입력의 원래 ID(f-anchovy 등)로 되돌려 사람이 읽기 쉽게 보여 준다.

    python <이 폴더>/show.py card-rich-uuid

2026-11-03 실행 때와 다른 점은 경로뿐이다.
"""
import json, os, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
OUT = Path(os.environ.get("SPOT_CHECK_OUT") or HERE / "outputs")
import inputs
name = sys.argv[1]
rev = {v: k for k, v in {**inputs.RICH_ID_MAP, **inputs.SPARSE_ID_MAP}.items()}
def r(x): return json.loads(json.dumps(x).replace('"', '"')) if False else json.loads(_sub(json.dumps(x, ensure_ascii=False)))
def _sub(t):
    for u, k in rev.items(): t = t.replace(u, k)
    return t
d = json.loads(_sub(open(OUT / f'{name}.json', encoding='utf-8').read()))
for c in d['cards']:
    t = c['topic']; e = c['extra']
    print(c['position'], '|', t.get('topicId') or ('NEW:' + str(t.get('title')) + ' / ' + str(t.get('evidence'))), '|', c['cardTitle'], '|', e['kind'], e['bucket'], '|', c['evidenceSource'], c['evidence'])
    print('   angle:', e['angle'])
    print('   D:', c['description']); print('   Q:', c['primaryQuestion']); print('   F:', c['followUpQuestions'])
print(json.dumps(d['log'], ensure_ascii=False, indent=1))
