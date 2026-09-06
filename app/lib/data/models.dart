/// `docs/architecture/data-contracts.md` 의 객체를 옮긴 것이다.
///
/// 필드 이름과 enum 값은 계약을 그대로 따른다. 계약이 바뀌면 이 파일과
/// `assets/mock/` 의 목 데이터를 같은 변경에서 갱신한다.
/// 계약에 없는 필드를 여기서 만들지 않는다.
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
enum ConditionStage {
  mildCognitiveImpairment('경도 인지장애'),
  mildDementia('경도 치매'),
  unknown('잘 모르겠어요');

  const ConditionStage(this.label);

  final String label;

  static ConditionStage parse(String raw) => values.firstWhere(
    (v) => v.name == raw,
    orElse: () => ConditionStage.unknown,
  );
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
  final ConditionStage stage;
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

/// 생애 정보 수집 단계의 상태. `collected`, `skipped`, `manualFallback`, `pending`.
enum CollectionStatus {
  pending,
  collected,
  skipped,
  manualFallback;

  static CollectionStatus parse(String raw) => values.firstWhere(
    (v) => v.name == raw,
    orElse: () => CollectionStatus.pending,
  );
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
  final CollectionStatus status;

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

/// `pending`, `accepted`, `rejected`. `ChangeProposal` 과 같은 값을 쓴다.
enum ReviewStatus {
  pending,
  accepted,
  rejected;

  static ReviewStatus parse(String raw) =>
      values.firstWhere((v) => v.name == raw, orElse: () => ReviewStatus.pending);
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
        reviewStatus: ReviewStatus.parse(json['reviewStatus'] as String),
      );

  final String candidateId;
  final String text;
  final ReviewStatus reviewStatus;
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
    sessionStatus: json['sessionStatus'] as String,
    photoId: json['photoId'] as String?,
    startedAt: json['startedAt'] as String,
    endedAt: json['endedAt'] as String?,
  );

  final String sessionId;
  final String profileId;
  final List<String> selectedCardIds;
  final String sessionStatus;
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
    reportStatus: json['reportStatus'] as String,
    title: json['title'] as String,
    visitDate: json['visitDate'] as String,
    mood: json['mood'] as String,
    photoId: json['photoId'] as String?,
    summaryText: json['summaryText'] as String,
    cardSummaries: (json['cardSummaries'] as List)
        .map((e) => CardSummary.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  final String reportId;
  final String sessionId;
  final String reportStatus;
  final String title;
  final String visitDate;
  final String mood;
  final String? photoId;
  final String summaryText;
  final List<CardSummary> cardSummaries;
}

// ── 보호자 평가와 변경 제안 ─────────────────────────

class CardReview {
  const CardReview({
    required this.cardId,
    required this.wasUsed,
    required this.caregiverReaction,
  });

  factory CardReview.fromJson(Map<String, dynamic> json) => CardReview(
    cardId: json['cardId'] as String,
    wasUsed: json['wasUsed'] as bool,
    caregiverReaction: json['caregiverReaction'] as String,
  );

  final String cardId;
  final bool wasUsed;
  final String caregiverReaction;
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
        careRecipientReaction: json['careRecipientReaction'] as String,
        cardReviews: (json['cardReviews'] as List)
            .map((e) => CardReview.fromJson(e as Map<String, dynamic>))
            .toList(),
        freeNote: json['freeNote'] as String?,
      );

  final String reviewId;
  final String sessionId;
  final int conversationSatisfaction;
  final String careRecipientReaction;
  final List<CardReview> cardReviews;
  final String? freeNote;
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
    reviewStatus: ReviewStatus.parse(json['reviewStatus'] as String),
  );

  final String changeId;

  /// `topicPriority` 또는 `lifeFactAdd`.
  final String changeType;
  final String? topicTitle;
  final String? direction;
  final String? text;
  final String reason;
  final ReviewStatus reviewStatus;
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
    proposalStatus: json['proposalStatus'] as String,
    changes: (json['changes'] as List)
        .map((e) => ProposedChange.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  final String proposalId;
  final String reportId;
  final String proposalStatus;
  final List<ProposedChange> changes;
}
