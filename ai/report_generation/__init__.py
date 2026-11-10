"""면회 리포트 생성. 면회가 끝난 뒤 녹음 전사, 보호자 소감, 고른 카드로 리포트 제목, 본문, 카드별 요약을 만듦.

입력은 #106 내부 API(8-3) 요청(common.visit_report.VisitReportRequest)과 같음. DB를 읽거나 쓰지 않음.

    from common.visit_report import combine
    from proposal_generation import generate_proposals
    from report_generation import generate_report

    report = generate_report(request, model=settings.report_model, api_key=settings.ml_api_key)
    proposals = generate_proposals(request, model=settings.report_model, api_key=settings.ml_api_key)
    result = combine(request.analysis_id, report, proposals)     # #106 응답 하나

#106이 응답 전체를 거절하는 규칙은 코드로 미리 거름. 카드 요약은 반응이 positive·neutral·negative인 카드에만, 카드당 하나.
report-3은 라벨 누락과 인원 차이에도 대화 맥락으로 화자를 추론하되, 근거가 부족한 귀속은 단정하지 않도록 지시함.
report-5는 보호자에게 보이는 글에 전사, 화자, 보호자 소감 같은 처리 과정의 말을 쓰지 않게 하고, 근거가 부족한 사정을 설명하는 대신 말한 사람을 정하지 않는 표현을 쓰게 함(11/8 운영 시험). report-4는 배포 전에 되돌렸고(#269) 쓰지 않음.
report-6은 본문을 나눈 화제마다 짧은 문단으로 이야기한 순서대로 쓰고 분량을 대화 길이에 맞추게 함. 녹음 길이(분)를 입력에 넣음(PM 결정, 2026-11-09).
결과의 token_usage는 처리 기록용 숫자이고 combine()은 #106 응답에 넣지 않음.
"""

__all__ = ["generate_report", "PROMPT", "PROMPT_VERSION"]

from report_generation.generate import PROMPT, PROMPT_VERSION, generate_report
