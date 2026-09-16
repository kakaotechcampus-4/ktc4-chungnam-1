/// 회원가입 화면에서 받는 동의 항목이다.
///
/// 항목의 키는 `docs/architecture/data-contracts.md` 의 `Account.consent` 를,
/// 문구는 `docs/legal/consent-draft.md` 를 그대로 따른다. **여기서 문구를 새로
/// 쓰지 않는다.** 법률 문서가 바뀌면 이 파일을 같은 변경에서 갱신한다.
///
/// 계약에 없는 동의 항목은 이 화면에서 받지 않는다.
/// - 피보호자 동의 확인은 `VisitSession.consent.careRecipientConfirmation` 이라
///   면회를 시작할 때 받는다.
/// - 이미지 분석 동의는 기능을 이용하는 시점에 따로 받는다.
library;

class ConsentTerm {
  const ConsentTerm({
    required this.key,
    required this.required,
    required this.label,
    required this.statement,
    required this.details,
  });

  /// `Account.consent` 의 필드 이름.
  final String key;

  final bool required;

  /// 목록에 보이는 짧은 이름.
  final String label;

  /// 동의문 본문. `docs/legal/consent-draft.md` 에서 옮겼다.
  final String statement;

  /// 목적, 항목, 보유 기간 등. 각 줄도 법률 문서에서 옮긴 것이다.
  final List<String> details;
}

const consentTerms = <ConsentTerm>[
  ConsentTerm(
    key: 'serviceData',
    required: true,
    label: '개인정보 처리 동의',
    statement: '맞춤형 대화 카드와 면회 리포트 제공을 위한 개인정보 처리에 동의합니다.',
    details: [
      '목적: 회원 관리, 피보호자 프로필 관리, 맞춤형 대화 카드 생성, 음성 분석과 회차별 리포트 제공',
      '항목: 보호자의 이름 또는 별칭, 연락처와 로그인 정보, 피보호자의 별칭, 연령대, 보호자와의 관계, 취향, 생애정보, 면회 기록, 보호자와 피보호자의 음성, 전사 결과와 발화 지표',
      '보유 기간: 계정과 프로필 정보는 회원 탈퇴 또는 삭제 요청 시까지, 녹음 원본은 분석 완료 후 즉시 삭제하며 최대 24시간',
      '동의하지 않으면 맞춤형 대화 카드, 녹음 분석과 자동 리포트를 이용할 수 없습니다.',
    ],
  ),
  ConsentTerm(
    key: 'sensitiveData',
    required: true,
    label: '건강 관련 민감정보 처리 동의',
    statement: '건강 관련 민감정보 처리에 동의합니다.',
    details: [
      '목적: 피보호자에게 적합한 질문 구성, 부적절한 질문 방지',
      '항목: 인지 상태, 대화 시 주의사항, 발화 분석 결과',
      '보유 기간: 회원 탈퇴 또는 피보호자 프로필 삭제 시까지',
      '동의하지 않으면 맞춤형 대화 카드와 리포트를 이용할 수 없습니다.',
    ],
  ),
  ConsentTerm(
    key: 'pushNotification',
    required: true,
    label: '알림 수신 동의',
    statement: '면회 준비와 리포트 완료 알림을 받는 것에 동의합니다.',
    details: [
      '목적: 면회 준비와 리포트 처리 완료 알림 제공',
      '항목: 앱 기기 토큰, 알림 설정, 알림 발송 기록',
      '알림 내용: 환자 이름, 건강정보, 전사 내용과 리포트 세부내용을 포함하지 않음',
      '보유 기간: 알림 동의 철회, 로그아웃 또는 회원 탈퇴 시까지',
    ],
  ),
  ConsentTerm(
    key: 'serviceImprovement',
    required: false,
    label: '서비스 품질 개선 활용 동의',
    statement:
        '새록이 더 나은 대화 카드와 리포트를 제공할 수 있도록, 가명처리된 정보를 서비스 품질 개선에 활용하는 것에 동의합니다.',
    details: [
      '목적: 대화 카드와 리포트 품질 평가, AI 모델 개선',
      '항목: 가명처리된 프로필 소재, 전사 일부, 발화 지표, 카드 반응과 보호자 평가',
      '제외 항목: 이름, 연락처, 시설명, 상세 주소, 원본 음성',
      '보유 기간: 수집일로부터 최대 90일',
      '동의하지 않아도 기본 서비스를 이용할 수 있습니다.',
    ],
  ),
];
