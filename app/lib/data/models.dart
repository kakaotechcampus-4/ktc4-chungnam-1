/// `docs/architecture/data-contracts.md` 의 객체를 옮긴 것이다.
///
/// 필드 이름과 enum 값은 계약을 그대로 따른다. 계약이 바뀌면 이 파일과
/// `assets/mock/` 의 목 데이터를 같은 변경에서 갱신한다.
/// 계약에 없는 필드를 여기서 만들지 않는다.
///
/// **enum 의 `parse` 는 계약에 없는 값을 만나면 `null` 을 돌려준다.** 정상 값으로
/// 바꿔 두면 계약 버전 차이로 들어온 값이 보호자가 고른 답처럼 화면에 나간다.
/// 그래서 값을 담는 필드도 nullable 이며, 화면은 `null` 을 정상 답변으로 보여주지
/// 않는다. `app/CLAUDE.md` 의 실패 표시 규칙과 테크스펙 NFR-005 를 따른다.
library;

// ── 계정 ────────────────────────────────────────────

class ConsentItem {
  const ConsentItem({required this.granted, this.grantedAt});

  factory ConsentItem.fromJson(Map<String, dynamic> json) => ConsentItem(
    granted: json['granted'] as bool,
    grantedAt: json['grantedAt'] as String?,
  );

  final bool granted;
  final String? grantedAt;
}

class Account {
  const Account({
    required this.accountId,
    required this.loginId,
    required this.displayName,
    required this.email,
    required this.consentVersion,
    required this.consent,
    required this.createdAt,
  });

  factory Account.fromJson(Map<String, dynamic> json) {
    final consent = json['consent'] as Map<String, dynamic>;
    return Account(
      accountId: json['accountId'] as String,
      loginId: json['loginId'] as String,
      displayName: json['displayName'] as String,
      email: json['email'] as String,
      consentVersion: consent['consentVersion'] as String,
      consent: {
        for (final entry in consent.entries)
          if (entry.value is Map<String, dynamic>)
            entry.key: ConsentItem.fromJson(entry.value as Map<String, dynamic>),
      },
      createdAt: json['createdAt'] as String,
    );
  }

  final String accountId;
  final String loginId;
  final String displayName;
  final String email;
  final String consentVersion;

  /// `serviceData`, `sensitiveData`, `serviceImprovement`, `pushNotification`.
  final Map<String, ConsentItem> consent;
  final String createdAt;
}

// ── 프로필 ──────────────────────────────────────────

/// `condition.stage` 값. 계약에 정의된 셋뿐이다.
///
/// [unknown] 은 보호자가 직접 고른 "잘 모르겠어요" 다. 계약에 없는 값을 이것으로
/// 바꾸면 둘을 구분할 수 없어 [parse] 는 `null` 을 준다.
enum ConditionStage {
  mildCognitiveImpairment('경도 인지장애'),
  mildDementia('경도 치매'),
  unknown('잘 모르겠어요');

  const ConditionStage(this.label);

  final String label;

  static ConditionStage? parse(String raw) =>
      values.where((v) => v.name == raw).firstOrNull;
}

class Profile {
  const Profile({
    required this.profileId,
    required this.name,
    required this.gender,
    required this.birthDate,
    required this.ageRange,
    required this.stage,
    required this.lifeFactIds,
    required this.photoIds,
    this.symptomNote,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    final localOnly = json['localOnly'] as Map<String, dynamic>;
    final condition = json['condition'] as Map<String, dynamic>;
    return Profile(
      profileId: json['profileId'] as String,
      name: localOnly['name'] as String,
      gender: localOnly['gender'] as String,
      birthDate: localOnly['birthDate'] as String,
      ageRange: json['ageRange'] as String,
      stage: ConditionStage.parse(condition['stage'] as String),
      symptomNote: condition['symptomNote'] as String?,
      lifeFactIds: (json['lifeFactIds'] as List).cast<String>(),
      photoIds: (json['photoIds'] as List).cast<String>(),
    );
  }

  final String profileId;

  /// `localOnly` 에 속한다. 외부 요청에 담지 않는다.
  final String name;
  final String gender;
  final String birthDate;

  final String ageRange;
  final ConditionStage? stage;
  final String? symptomNote;
  final List<String> lifeFactIds;
  final List<String> photoIds;
}

class LifeFact {
  const LifeFact({
    required this.factId,
    required this.category,
    required this.text,
    required this.sourceType,
  });

  factory LifeFact.fromJson(Map<String, dynamic> json) => LifeFact(
    factId: json['factId'] as String,
    category: json['category'] as String,
    text: json['text'] as String,
    sourceType: json['sourceType'] as String,
  );

  final String factId;
  final String category;
  final String text;
  final String sourceType;
}

/// 생애 정보 수집 단계의 상태. `pending`, `collected`, `skipped`, `manualFallback`.
enum CollectionStatus {
  pending,
  collected,
  skipped,
  manualFallback;

  static CollectionStatus? parse(String raw) =>
      values.where((v) => v.name == raw).firstOrNull;
}

class CategoryCollectionState {
  const CategoryCollectionState({
    required this.category,
    required this.status,
    required this.attemptCount,
  });

  factory CategoryCollectionState.fromJson(Map<String, dynamic> json) =>
      CategoryCollectionState(
        category: json['category'] as String,
        status: CollectionStatus.parse(json['status'] as String),
        attemptCount: json['attemptCount'] as int,
      );

  final String category;
  final CollectionStatus? status;

  /// 음성 인식을 시도한 횟수. 2회 실패하면 직접 입력으로 넘어간다.
  final int attemptCount;
}

class ProfilePhoto {
  const ProfilePhoto({
    required this.photoId,
    required this.localUri,
    required this.acceptedTags,
  });

  factory ProfilePhoto.fromJson(Map<String, dynamic> json) => ProfilePhoto(
    photoId: json['photoId'] as String,
    localUri: json['localUri'] as String,
    acceptedTags: (json['acceptedTags'] as List? ?? const []).cast<String>(),
  );

  final String photoId;
  final String localUri;
  final List<String> acceptedTags;
}

/// 이미지 분석 후보 하나의 검토 상태. 계약에 정의된 셋이다.
///
/// 변경 제안의 [ChangeReviewStatus] 와 값 이름은 겹치지만 같은 타입이 아니다.
/// 후보는 되돌릴 대상이 없어 `reverted` 를 갖지 않는다.
enum TagReviewStatus {
  pending,
  accepted,
  rejected;

  static TagReviewStatus? parse(String raw) =>
      values.where((v) => v.name == raw).firstOrNull;
}

class ImageTagCandidate {
  const ImageTagCandidate({
    required this.candidateId,
    required this.text,
    required this.reviewStatus,
  });

  factory ImageTagCandidate.fromJson(Map<String, dynamic> json) =>
      ImageTagCandidate(
        candidateId: json['candidateId'] as String,
        text: json['text'] as String,
        reviewStatus: TagReviewStatus.parse(json['reviewStatus'] as String),
      );

  final String candidateId;
  final String text;
  final TagReviewStatus? reviewStatus;
}

/// 프로필 화면이 한 번에 쓰는 묶음이다. `assets/mock/profile.json` 한 파일에 해당한다.
class ProfileBundle {
  const ProfileBundle({
    required this.profile,
    required this.lifeFacts,
    required this.collectionStates,
    required this.photo,
    required this.tagCandidates,
  });

  factory ProfileBundle.fromJson(Map<String, dynamic> json) {
    final candidate = json['imageAnalysisCandidate'] as Map<String, dynamic>;
    final collection = json['lifeFactCollectionState'] as Map<String, dynamic>;
    return ProfileBundle(
      profile: Profile.fromJson(json['profile'] as Map<String, dynamic>),
      lifeFacts: (json['lifeFacts'] as List)
          .map((e) => LifeFact.fromJson(e as Map<String, dynamic>))
          .toList(),
      collectionStates: (collection['categories'] as List)
          .map((e) => CategoryCollectionState.fromJson(e as Map<String, dynamic>))
          .toList(),
      photo: ProfilePhoto.fromJson(json['profilePhoto'] as Map<String, dynamic>),
      tagCandidates: (candidate['candidates'] as List)
          .map((e) => ImageTagCandidate.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final Profile profile;
  final List<LifeFact> lifeFacts;
  final List<CategoryCollectionState> collectionStates;
  final ProfilePhoto photo;
  final List<ImageTagCandidate> tagCandidates;

  LifeFact? factOf(String category) =>
      lifeFacts.where((f) => f.category == category).firstOrNull;

  CategoryCollectionState? stateOf(String category) =>
      collectionStates.where((s) => s.category == category).firstOrNull;
}

// ── 대화 카드 ───────────────────────────────────────

class ConversationCard {
  const ConversationCard({
    required this.cardId,
    required this.topicKey,
    required this.topicTitle,
    required this.topicDescription,
    required this.primaryQuestion,
    required this.followUpQuestions,
    required this.selected,
  });

  factory ConversationCard.fromJson(Map<String, dynamic> json) =>
      ConversationCard(
        cardId: json['cardId'] as String,
        topicKey: json['topicKey'] as String,
        topicTitle: json['topicTitle'] as String,
        topicDescription: json['topicDescription'] as String,
        primaryQuestion: json['primaryQuestion'] as String,
        followUpQuestions:
            (json['followUpQuestions'] as List).cast<String>(),
        selected: json['selectionStatus'] == 'selected',
      );

  final String cardId;
  final String topicKey;
  final String topicTitle;

  /// 이 카드가 어떤 주제인지 보호자에게 알려주는 설명이다.
  /// 어르신에게 그대로 여쭙는 문장은 [primaryQuestion] 이다.
  final String topicDescription;
  final String primaryQuestion;
  final List<String> followUpQuestions;
  final bool selected;

  ConversationCard copyWith({bool? selected}) => ConversationCard(
    cardId: cardId,
    topicKey: topicKey,
    topicTitle: topicTitle,
    topicDescription: topicDescription,
    primaryQuestion: primaryQuestion,
    followUpQuestions: followUpQuestions,
    selected: selected ?? this.selected,
  );
}

// ── 면회 회차 ───────────────────────────────────────

/// `sessionStatus` 값. 계약에 정의된 일곱이다.
enum SessionStatus {
  ready,
  recording,
  paused,
  ended,
  processing,
  completed,
  failed;

  static SessionStatus? parse(String raw) =>
      values.where((v) => v.name == raw).firstOrNull;
}

class VisitSession {
  const VisitSession({
    required this.sessionId,
    required this.profileId,
    required this.selectedCardIds,
    required this.sessionStatus,
    required this.startedAt,
    this.photoId,
    this.endedAt,
  });

  factory VisitSession.fromJson(Map<String, dynamic> json) => VisitSession(
    sessionId: json['sessionId'] as String,
    profileId: json['profileId'] as String,
    selectedCardIds: (json['selectedCardIds'] as List).cast<String>(),
    sessionStatus: SessionStatus.parse(json['sessionStatus'] as String),
    photoId: json['photoId'] as String?,
    startedAt: json['startedAt'] as String,
    endedAt: json['endedAt'] as String?,
  );

  final String sessionId;
  final String profileId;
  final List<String> selectedCardIds;
  final SessionStatus? sessionStatus;
  final String? photoId;
  final String startedAt;
  final String? endedAt;
}

// ── 리포트 ──────────────────────────────────────────

class CardSummary {
  const CardSummary({
    required this.cardId,
    required this.topicTitle,
    required this.summary,
  });

  factory CardSummary.fromJson(Map<String, dynamic> json) => CardSummary(
    cardId: json['cardId'] as String,
    topicTitle: json['topicTitle'] as String,
    summary: json['summary'] as String,
  );

  final String cardId;
  final String topicTitle;
  final String summary;
}

/// `reportStatus` 값. 계약에 정의된 넷이다.
enum ReportStatus {
  generating,
  ready,
  reviewed,
  acknowledged;

  static ReportStatus? parse(String raw) =>
      values.where((v) => v.name == raw).firstOrNull;
}

class VisitReport {
  const VisitReport({
    required this.reportId,
    required this.sessionId,
    required this.reportStatus,
    required this.title,
    required this.visitDate,
    required this.mood,
    required this.summaryText,
    required this.cardSummaries,
    this.photoId,
  });

  factory VisitReport.fromJson(Map<String, dynamic> json) => VisitReport(
    reportId: json['reportId'] as String,
    sessionId: json['sessionId'] as String,
    reportStatus: ReportStatus.parse(json['reportStatus'] as String),
    title: json['title'] as String,
    visitDate: json['visitDate'] as String,
    mood: VisitMood.parse(json['mood'] as String),
    photoId: json['photoId'] as String?,
    summaryText: json['summaryText'] as String,
    cardSummaries: (json['cardSummaries'] as List)
        .map((e) => CardSummary.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  final String reportId;
  final String sessionId;
  final ReportStatus? reportStatus;
  final String title;
  final String visitDate;
  final VisitMood? mood;
  final String? photoId;
  final String summaryText;
  final List<CardSummary> cardSummaries;
}

// ── 보호자 평가와 변경 제안 ─────────────────────────

/// `careRecipientReaction` 값. 계약에 정의된 다섯이다.
///
/// [ConditionStage] 와 같은 이유로, 보호자가 고른 [unknown] 과 알 수 없는 값을
/// 구분한다.
enum CareRecipientReaction {
  pleased('기뻐하셨어요'),
  calm('차분하셨어요'),
  angry('언짢아하셨어요'),
  lowEnergy('기운이 없으셨어요'),
  unknown('잘 모르겠어요');

  const CareRecipientReaction(this.label);

  final String label;

  static CareRecipientReaction? parse(String raw) =>
      values.where((v) => v.name == raw).firstOrNull;
}

/// `caregiverReaction` 값. 카드 한 장에 대한 보호자의 평가다.
///
/// 계약에 "모르겠다" 에 해당하는 값이 없다. 알 수 없는 값을 [neutral] 로 바꾸면
/// 보호자가 하지 않은 평가가 "보통이에요" 로 화면에 나가므로 `null` 을 준다.
enum CaregiverReaction {
  positive('좋았어요'),
  neutral('보통이에요'),
  negative('아쉬웠어요');

  const CaregiverReaction(this.label);

  final String label;

  static CaregiverReaction? parse(String raw) =>
      values.where((v) => v.name == raw).firstOrNull;
}

/// `VisitReport.mood`. 보호자가 따로 입력하지 않고 대화 만족도에서 계산한다.
enum VisitMood {
  hard('힘든 만남'),
  normal('잔잔한 만남'),
  good('좋은 만남');

  const VisitMood(this.label);

  final String label;

  static VisitMood? parse(String raw) =>
      values.where((v) => v.name == raw).firstOrNull;

  /// 1이면 `hard`, 2~4는 `normal`, 5면 `good` 이다.
  static VisitMood fromSatisfaction(int satisfaction) => switch (satisfaction) {
    <= 1 => VisitMood.hard,
    >= 5 => VisitMood.good,
    _ => VisitMood.normal,
  };
}

class CardReview {
  const CardReview({
    required this.cardId,
    required this.wasUsed,
    required this.caregiverReaction,
  });

  factory CardReview.fromJson(Map<String, dynamic> json) => CardReview(
    cardId: json['cardId'] as String,
    wasUsed: json['wasUsed'] as bool,
    caregiverReaction:
        CaregiverReaction.parse(json['caregiverReaction'] as String),
  );

  final String cardId;
  final bool wasUsed;
  final CaregiverReaction? caregiverReaction;
}

class CaregiverEvaluation {
  const CaregiverEvaluation({
    required this.reviewId,
    required this.sessionId,
    required this.conversationSatisfaction,
    required this.careRecipientReaction,
    required this.cardReviews,
    this.freeNote,
  });

  factory CaregiverEvaluation.fromJson(Map<String, dynamic> json) =>
      CaregiverEvaluation(
        reviewId: json['reviewId'] as String,
        sessionId: json['sessionId'] as String,
        conversationSatisfaction: json['conversationSatisfaction'] as int,
        careRecipientReaction: CareRecipientReaction.parse(
          json['careRecipientReaction'] as String,
        ),
        cardReviews: (json['cardReviews'] as List)
            .map((e) => CardReview.fromJson(e as Map<String, dynamic>))
            .toList(),
        freeNote: json['freeNote'] as String?,
      );

  final String reviewId;
  final String sessionId;
  /// 1 이상 5 이하의 정수다.
  final int conversationSatisfaction;

  final CareRecipientReaction? careRecipientReaction;
  final List<CardReview> cardReviews;
  final String? freeNote;
}

/// 변경 제안 하나의 검토 상태. 계약에 정의된 넷이다.
///
/// [reverted] 는 보호자가 승인해 프로필에 반영한 변경을 나중에 되돌린 정상
/// 상태이며, 값을 읽지 못한 경우가 아니다. 이미지 분석 후보의
/// [TagReviewStatus] 에는 이 값이 없다.
enum ChangeReviewStatus {
  pending,
  accepted,
  rejected,
  reverted;

  static ChangeReviewStatus? parse(String raw) =>
      values.where((v) => v.name == raw).firstOrNull;
}

class ProposedChange {
  const ProposedChange({
    required this.changeId,
    required this.changeType,
    required this.reason,
    required this.reviewStatus,
    this.topicTitle,
    this.direction,
    this.text,
  });

  factory ProposedChange.fromJson(Map<String, dynamic> json) => ProposedChange(
    changeId: json['changeId'] as String,
    changeType: json['changeType'] as String,
    topicTitle: json['topicTitle'] as String?,
    direction: json['direction'] as String?,
    text: json['text'] as String?,
    reason: json['reason'] as String,
    reviewStatus: ChangeReviewStatus.parse(json['reviewStatus'] as String),
  );

  final String changeId;

  /// `topicPriority` 또는 `lifeFactAdd`.
  final String changeType;
  final String? topicTitle;
  final String? direction;
  final String? text;
  final String reason;

  final ChangeReviewStatus? reviewStatus;
}

/// `proposalStatus` 값. 계약에 정의된 둘이다.
enum ProposalStatus {
  pendingReview,
  reviewed;

  static ProposalStatus? parse(String raw) =>
      values.where((v) => v.name == raw).firstOrNull;
}

class ChangeProposal {
  const ChangeProposal({
    required this.proposalId,
    required this.reportId,
    required this.proposalStatus,
    required this.changes,
  });

  factory ChangeProposal.fromJson(Map<String, dynamic> json) => ChangeProposal(
    proposalId: json['proposalId'] as String,
    reportId: json['reportId'] as String,
    proposalStatus: ProposalStatus.parse(json['proposalStatus'] as String),
    changes: (json['changes'] as List)
        .map((e) => ProposedChange.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  final String proposalId;
  final String reportId;
  final ProposalStatus? proposalStatus;
  final List<ProposedChange> changes;
}
