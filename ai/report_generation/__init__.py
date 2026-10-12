"""면회 리포트 생성. 면회가 끝난 뒤 녹음 전사, 보호자 소감, 고른 카드로 리포트 제목, 본문, 카드별 요약을 만듦.

입력은 #106 내부 API(8-3) 요청(common.visit_report.VisitReportRequest)과 같음. DB를 읽거나 쓰지 않음.

    from common.visit_report import combine
    from proposal_generation import generate_proposals
    from report_generation import generate_report

    report = generate_report(request, model=settings.report_model, api_key=settings.ml_api_key)
    proposals = generate_proposals(request, model=settings.report_model, api_key=settings.ml_api_key)
    result = combine(request.analysis_id, report, proposals)     # #106 응답 하나

#106이 응답 전체를 거절하는 규칙은 코드로 미리 거름. 카드 요약은 반응이 positive·neutral·negative인 카드에만, 카드당 하나.
화자 라벨은 1~8명이고 null 구간은 누구의 말로도 단정하지 않게 프롬프트에 적어 둠.
"""

__all__ = ["generate_report", "PROMPT", "PROMPT_VERSION"]

from report_generation.generate import PROMPT, PROMPT_VERSION, generate_report
