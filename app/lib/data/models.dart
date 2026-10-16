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
    required this.authProvider,
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
      authProvider: json['authProvider'] as String,
      displayName: json['displayName'] as String,
      email: json['email'] as String?,
      consentVersion: consent['consentVersion'] as String,
      consent: {
        for (final entry in consent.entries)
          if (entry.value is Map<String, dynamic>)
            entry.key: ConsentItem.fromJson(
              entry.value as Map<String, dynamic>,
            ),
      },
      createdAt: json['createdAt'] as String,
    );
  }

  final String accountId;

  /// `google` 하나뿐이다. 계약에 다른 제공자를 더하는 것은 계약 변경으로 본다.
  final String authProvider;
  final String displayName;

  /// 서버가 이메일을 보관하지 않거나 제공하지 않으면 `null`이다.
  final String? email;
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
    this.occupation,
    this.hometown,
    this.hobby,
    this.family,
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
      occupation: json['occupation'] as String?,
      hometown: json['hometown'] as String?,
      hobby: json['hobby'] as String?,
      family: json['family'] as String?,
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

  /// 세부 정보 네 항목(`docs/architecture/api-spec.md` 의 Profile). 건너뛰었으면
  /// `null` 이고 빈 문자열은 두지 않는다.
  final String? occupation;
  final String? hometown;
  final String? hobby;
  final String? family;

  /// [category] 는 `occupation`, `hometown`, `hobby`, `family` 중 하나다.
  String? detailOf(String category) => switch (category) {
    'occupation' => occupation,
    'hometown' => hometown,
    'hobby' => hobby,
    'family' => family,
    _ => null,
  };
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

/// 프로필 사진의 이미지 분석 상태. 계약에 정의된 넷이다.
enum PhotoAnalysisStatus {
  pending,
  processing,
  completed,
  failed;

  static PhotoAnalysisStatus? parse(String raw) =>
      values.where((v) => v.name == raw).firstOrNull;
}

/// 프로필 사진 한 장이다(`docs/architecture/data-contracts.md` 의 ProfilePhoto).
///
/// [description] 은 AI 가 만든 후보이며 확인된 사실이 아니다. 보호자가 확인하는
/// 방식(API 3-3)은 아직 정해지지 않았다.
class ProfilePhoto {
  const ProfilePhoto({
    required this.photoId,
    required this.profileId,
    required this.imageUrl,
    required this.analysisStatus,
    required this.createdAt,
    this.imageUrlExpiresAt,
    this.description,
    this.errorCode,
  });

  factory ProfilePhoto.fromJson(Map<String, dynamic> json) {
    final error = json['error'] as Map<String, dynamic>?;
    return ProfilePhoto(
      photoId: json['photoId'] as String,
      profileId: json['profileId'] as String,
      imageUrl: json['imageUrl'] as String,
      imageUrlExpiresAt: json['imageUrlExpiresAt'] as String?,
      analysisStatus: PhotoAnalysisStatus.parse(
        json['analysisStatus'] as String,
      ),
      description: json['description'] as String?,
      errorCode: error?['errorCode'] as String?,
      createdAt: json['createdAt'] as String,
    );
  }

  final String photoId;
  final String profileId;

  /// 수명이 짧은 조회용 URL 이다. 목 데이터는 `asset:` 으로 앱 안의 이미지를 가리킨다.
  final String imageUrl;
  final String? imageUrlExpiresAt;

  /// 모르는 값이면 `null` 이다. 화면은 분석이 끝나지 않은 것으로 다룬다.
  final PhotoAnalysisStatus? analysisStatus;

  /// [PhotoAnalysisStatus.completed] 일 때만 있다.
  final String? description;

  /// [PhotoAnalysisStatus.failed] 일 때의 `error.errorCode` 다.
  final String? errorCode;

  final String createdAt;

  /// 같은 사진을 다른 어르신의 것으로 붙인다. 목 사진을 어르신마다 나눠 쓸 때만
  /// 쓴다. 서버가 붙으면 사진은 처음부터 어르신마다 따로 온다.
  ProfilePhoto forProfile(String profileId) => ProfilePhoto(
    photoId: photoId,
    profileId: profileId,
    imageUrl: imageUrl,
    imageUrlExpiresAt: imageUrlExpiresAt,
    analysisStatus: analysisStatus,
    description: description,
    errorCode: errorCode,
    createdAt: createdAt,
  );
}

/// 프로필 화면이 한 번에 쓰는 묶음이다. `assets/mock/profile.json` 한 파일에 해당한다.
class ProfileBundle {
  const ProfileBundle({
    required this.profile,
    required this.lifeFacts,
    required this.collectionStates,
    required this.photos,
  });

  factory ProfileBundle.fromJson(Map<String, dynamic> json) {
    final collection = json['lifeFactCollectionState'] as Map<String, dynamic>;
    return ProfileBundle(
      profile: Profile.fromJson(json['profile'] as Map<String, dynamic>),
      lifeFacts: (json['lifeFacts'] as List)
          .map((e) => LifeFact.fromJson(e as Map<String, dynamic>))
          .toList(),
      collectionStates: (collection['categories'] as List)
          .map(
            (e) => CategoryCollectionState.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      photos: (json['photos'] as List? ?? const [])
          .map((e) => ProfilePhoto.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final Profile profile;
  final List<LifeFact> lifeFacts;
  final List<CategoryCollectionState> collectionStates;

  /// 올린 순서대로다. 최대 5장이다.
  final List<ProfilePhoto> photos;

  LifeFact? factOf(String category) =>
      lifeFacts.where((f) => f.category == category).firstOrNull;

  CategoryCollectionState? stateOf(String category) =>
      collectionStates.where((s) => s.category == category).firstOrNull;
}

// ── 대화 카드 ───────────────────────────────────────

/// 지금 쓸 카드 묶음이다. 계약의 `CardSet` 이며 API 4-3 의 응답이다.
class CardSet {
  const CardSet({
    required this.setId,
    required this.usedBySessionId,
    required this.cards,
  });

  factory CardSet.fromJson(Map<String, dynamic> json) => CardSet(
    setId: json['setId'] as String,
    usedBySessionId: json['usedBySessionId'] as String?,
    cards:
        (json['cards'] as List)
            .map((e) => ConversationCard.fromJson(e as Map<String, dynamic>))
            .toList()
          // `position` 1~9 가 선택 화면, 10~12 가 보충용이다. 배열 순서에
          // 기대지 않고 순서 값으로 줄 세운다.
          ..sort((a, b) => a.position.compareTo(b.position)),
  );

  /// 녹음을 시작할 때 API 5-1 에 보낸다.
  final String setId;

  /// 이 묶음을 쓰는 평가 전 회차. 고르기 전이면 `null` 이다.
  final String? usedBySessionId;

  /// 12장. [ConversationCard.position] 순서다.
  final List<ConversationCard> cards;
}

/// 카드가 다루는 주제. 회차가 바뀌어도 `topicId` 로 같은 주제를 잇는다.
class CardTopic {
  const CardTopic({
    required this.topicId,
    required this.title,
    required this.description,
  });

  factory CardTopic.fromJson(Map<String, dynamic> json) => CardTopic(
    topicId: json['topicId'] as String,
    title: json['title'] as String,
    description: json['description'] as String,
  );

  final String topicId;
  final String title;

  /// 이 주제가 무엇인지 보호자에게 알려주는 설명이다.
  final String description;
}

class ConversationCard {
  const ConversationCard({
    required this.cardId,
    required this.position,
    required this.topic,
    required this.cardTitle,
    required this.description,
    required this.primaryQuestion,
    required this.followUpQuestions,
    required this.evidenceSource,
    required this.evidence,
    required this.selected,
  });

  factory ConversationCard.fromJson(Map<String, dynamic> json) =>
      ConversationCard(
        cardId: json['cardId'] as String,
        position: json['position'] as int,
        topic: CardTopic.fromJson(json['topic'] as Map<String, dynamic>),
        cardTitle: json['cardTitle'] as String,
        description: json['description'] as String,
        primaryQuestion: json['primaryQuestion'] as String,
        followUpQuestions: (json['followUpQuestions'] as List).cast<String>(),
        evidenceSource: json['evidenceSource'] as String,
        evidence: (json['evidence'] as List)
            .cast<Map<String, dynamic>>()
            .toList(),
        selected: json['selected'] as bool,
      );

  final String cardId;

  /// 1~12. 1~9 가 선택 화면 대상이고 10~12 가 면회 중 보충용이다.
  final int position;

  final CardTopic topic;
  final String cardTitle;

  /// 이 카드가 무엇을 나누는지 보호자에게 알려주는 설명이다.
  /// 어르신에게 그대로 여쭙는 문장은 [primaryQuestion] 이다.
  final String description;
  final String primaryQuestion;
  final List<String> followUpQuestions;

  /// `lifeFact`, `photo`, `profile`, `none`.
  final String evidenceSource;

  /// `{"factId"}`, `{"photoId"}`, `{"profileField"}` 중 하나의 목록이다.
  /// [evidenceSource] 가 `none` 이면 비어 있다.
  final List<Map<String, dynamic>> evidence;

  /// 회차를 만들 때 고른 카드와 면회 중 보충한 카드가 `true` 다.
  final bool selected;
}

// ── 면회 회차 ───────────────────────────────────────

/// `sessionStatus` 값. 서버가 평가, 음성 분석 작업과 리포트로 계산한다.
///
/// 녹음 일시정지와 종료는 단말에서 처리하고 서버에 알리지 않으므로 녹음 중
/// 상태는 없다.
enum SessionStatus {
  /// 보호자 평가 전.
  evaluationPending,

  /// 평가 후 음성 접수 전. 업로드 단계에서 실패한 작업만 있어도 여기다.
  audioPending,

  /// 음성 분석 작업이 진행 중이다.
  processing,

  /// 리포트를 저장했다.
  completed,

  /// 접수된 음성 분석 작업이 실패했다.
  failed;

  static SessionStatus? parse(String raw) =>
      values.where((v) => v.name == raw).firstOrNull;
}

/// 면회 한 회차. 계약의 `VisitSession` 이며 API 5-1, 5-3 의 응답이다.
class VisitSession {
  const VisitSession({
    required this.sessionId,
    required this.profileId,
    required this.setId,
    required this.selectedCardIds,
    required this.sessionStatus,
    required this.startedAt,
    this.photoId,
    this.participantCount,
    this.analysisId,
  });

  factory VisitSession.fromJson(Map<String, dynamic> json) => VisitSession(
    sessionId: json['sessionId'] as String,
    profileId: json['profileId'] as String,
    setId: json['setId'] as String,
    selectedCardIds: (json['selectedCardIds'] as List).cast<String>(),
    sessionStatus: SessionStatus.parse(json['sessionStatus'] as String),
    photoId: json['photoId'] as String?,
    startedAt: json['startedAt'] as String,
    participantCount: json['participantCount'] as int?,
    analysisId: json['analysisId'] as String?,
  );

  final String sessionId;
  final String profileId;

  /// 이 회차가 쓰는 카드 묶음.
  final String setId;

  /// 회차를 만들 때 고른 카드와 면회 중 더한 보충 카드.
  final List<String> selectedCardIds;

  /// 읽지 못한 값이면 `null` 이다. 다른 상태로 짐작하지 않는다.
  final SessionStatus? sessionStatus;

  /// 면회 사진을 올리지 않았으면 `null` 이다.
  final String? photoId;

  /// 서버가 회차 생성 요청을 받은 시각.
  final String startedAt;

  /// 대화에 함께한 사람 수. 어르신과 보호자를 포함한다.
  ///
  /// 녹음을 끝낼 때 보호자에게 확인받는다. 앱이 목소리를 세어 짐작하지 않는다.
  /// 음성을 제출할 때 함께 보내며, 그 전에는 `null` 이다.
  final int? participantCount;

  /// 가장 최근 음성 분석 작업. 음성을 제출하기 전에는 `null` 이다.
  final String? analysisId;
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
  hard('아쉬운 만남'),
  normal('평범한 만남'),
  good('즐거운 만남');

  const VisitMood(this.label);

  final String label;

  static VisitMood? parse(String raw) =>
      values.where((v) => v.name == raw).firstOrNull;

  /// 1~2는 `hard`, 3은 `normal`, 4~5는 `good` 이다.
  ///
  /// 보호자가 고른 말과 리포트에 적히는 말이 이어지게 나눈다. 예전에는 2~4를
  /// 모두 `normal` 로 묶어, `아쉬웠어요` 를 고른 사람에게도 `평범한 만남` 이라고
  /// 적었다.
  static VisitMood fromSatisfaction(int satisfaction) => switch (satisfaction) {
    <= 2 => VisitMood.hard,
    >= 4 => VisitMood.good,
    _ => VisitMood.normal,
  };
}

/// 카드 한 장에 보호자가 남긴 답이다.
///
/// 답하지 않은 카드는 이 목록에 담지 않는다. 담지 않는 것이 미응답이고,
/// [wasUsed] 가 `false` 인 것이 미사용이다. 둘은 다음 회차 우선순위에 다르게
/// 쓰이므로 뭉개지 않는다(`docs/architecture/data-contracts.md`).
class CardReview {
  const CardReview({
    required this.cardId,
    required this.wasUsed,
    this.caregiverReaction,
  });

  factory CardReview.fromJson(Map<String, dynamic> json) {
    // 쓰지 않은 카드에는 평가가 없다. 계약의 없어도 되는 값이다.
    final reaction = json['caregiverReaction'] as String?;
    return CardReview(
      cardId: json['cardId'] as String,
      wasUsed: json['wasUsed'] as bool,
      caregiverReaction: reaction == null
          ? null
          : CaregiverReaction.parse(reaction),
    );
  }

  final String cardId;
  final bool wasUsed;

  /// 쓰지 않은 카드에는 없다.
  final CaregiverReaction? caregiverReaction;

  Map<String, Object?> toJson() => {
    'cardId': cardId,
    'wasUsed': wasUsed,
    'caregiverReaction': caregiverReaction?.name,
  };
}

/// 보호자 평가를 저장하는 요청. API 6-1 의 본문이다.
class EvaluationSubmission {
  const EvaluationSubmission({
    required this.conversationSatisfaction,
    required this.careRecipientReaction,
    required this.cardReviews,
    this.freeNote,
  });

  /// 1 이상 5 이하의 정수다.
  final int conversationSatisfaction;

  final CareRecipientReaction careRecipientReaction;

  /// 답한 카드만 담는다. 담지 않은 카드가 미응답이다.
  final List<CardReview> cardReviews;

  /// 비었으면 `null` 이다.
  final String? freeNote;

  Map<String, Object?> toJson() => {
    'conversationSatisfaction': conversationSatisfaction,
    'careRecipientReaction': careRecipientReaction.name,
    'cardReviews': [for (final review in cardReviews) review.toJson()],
    'freeNote': freeNote,
  };
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

/// 변경 제안 하나의 검토 상태. 계약에 정의된 셋이다.
///
/// 승인한 제안을 되돌리는 기능은 없다. 승인으로 만든 생애 사실은 일대기에서
/// 직접 고친다.
enum ChangeReviewStatus {
  pending,
  accepted,
  rejected;

  static ChangeReviewStatus? parse(String raw) =>
      values.where((v) => v.name == raw).firstOrNull;
}

/// 주제 제안의 행동. AI 가 제안한 값(`suggestedAction`)과 보호자가 고른 값에
/// 함께 쓴다.
enum TopicAction {
  more,
  less,
  exclude;

  static TopicAction? parse(String raw) =>
      values.where((v) => v.name == raw).firstOrNull;
}

/// 일대기에 더할 생애 정보 제안. `life_fact_proposals` 에 대응한다.
///
/// [reason] 은 AI 가 제안한 이유다. 보호자가 고치는 값은 [title] 과
/// [content] 뿐이며, 고친 값은 승인할 때 따로 보낸다. 이 객체는 원래 제안을
/// 그대로 들고 있다.
class LifeFactProposal {
  const LifeFactProposal({
    required this.proposalId,
    required this.title,
    required this.content,
    required this.reason,
    required this.reviewStatus,
  });

  factory LifeFactProposal.fromJson(Map<String, dynamic> json) =>
      LifeFactProposal(
        proposalId: json['proposalId'] as String,
        title: json['title'] as String,
        content: json['content'] as String,
        reason: json['reason'] as String,
        reviewStatus: ChangeReviewStatus.parse(json['reviewStatus'] as String),
      );

  final String proposalId;

  /// 100자 이하.
  final String title;
  final String content;
  final String reason;
  final ChangeReviewStatus? reviewStatus;
}

/// 주제 제안이 가리키는 주제. `profile_topics` 에 대응한다.
class ProposalTopic {
  const ProposalTopic({
    required this.topicId,
    required this.title,
    this.description,
  });

  factory ProposalTopic.fromJson(Map<String, dynamic> json) => ProposalTopic(
    topicId: json['topicId'] as String,
    title: json['title'] as String,
    description: json['description'] as String?,
  );

  final String topicId;
  final String title;

  /// 제목만으로는 무슨 이야기였는지 떠올리기 어려워 함께 보여준다. 이 화면을
  /// 위해 계약에 더한 값이다. 아직 서버가 보내지 않을 수 있어 없으면 제목만
  /// 보여준다.
  final String? description;
}

/// 다음 카드 생성에서 주제를 더 다룰지, 덜 다룰지, 제외할지에 대한 제안.
/// `topic_proposals` 에 대응한다.
///
/// [suggestedAction] 과 [reason] 은 AI 의 제안이다. 보호자는 다른 행동을 고를
/// 수 있고, 고른 값은 승인할 때 따로 보낸다.
class TopicProposal {
  const TopicProposal({
    required this.proposalId,
    required this.cardId,
    required this.topic,
    required this.suggestedAction,
    required this.reason,
    required this.reviewStatus,
  });

  factory TopicProposal.fromJson(Map<String, dynamic> json) => TopicProposal(
    proposalId: json['proposalId'] as String,
    cardId: json['cardId'] as String,
    topic: ProposalTopic.fromJson(json['topic'] as Map<String, dynamic>),
    suggestedAction: TopicAction.parse(json['suggestedAction'] as String),
    reason: json['reason'] as String,
    reviewStatus: ChangeReviewStatus.parse(json['reviewStatus'] as String),
  );

  final String proposalId;
  final String cardId;
  final ProposalTopic topic;
  final TopicAction? suggestedAction;
  final String reason;
  final ChangeReviewStatus? reviewStatus;
}

/// 한 회차의 변경 제안. API 7-3 의 응답이다.
class ChangeProposal {
  const ChangeProposal({
    required this.sessionId,
    required this.lifeFactProposals,
    required this.topicProposals,
  });

  factory ChangeProposal.fromJson(Map<String, dynamic> json) => ChangeProposal(
    sessionId: json['sessionId'] as String,
    lifeFactProposals: (json['lifeFactProposals'] as List)
        .map((e) => LifeFactProposal.fromJson(e as Map<String, dynamic>))
        .toList(),
    topicProposals: (json['topicProposals'] as List)
        .map((e) => TopicProposal.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  final String sessionId;
  final List<LifeFactProposal> lifeFactProposals;
  final List<TopicProposal> topicProposals;

  bool get isEmpty => lifeFactProposals.isEmpty && topicProposals.isEmpty;

  /// 아직 검토하지 않은(`pending`) 생애 정보 제안. 검토는 이것만 보낸다.
  /// 이미 승인하거나 거절한 제안과 상태를 읽지 못한 제안은 다시 보내지 않는다.
  List<LifeFactProposal> get pendingLifeFacts => [
    for (final p in lifeFactProposals)
      if (p.reviewStatus == ChangeReviewStatus.pending) p,
  ];

  /// 아직 검토하지 않은(`pending`) 주제 제안. [pendingLifeFacts] 와 같은 규칙이다.
  List<TopicProposal> get pendingTopics => [
    for (final p in topicProposals)
      if (p.reviewStatus == ChangeReviewStatus.pending) p,
  ];

  /// 검토할 제안이 하나도 없다. 이미 반영한 회차를 다시 열었을 때다.
  bool get nothingPending => pendingLifeFacts.isEmpty && pendingTopics.isEmpty;
}

/// 주제 제안 하나의 검토 결과. API 7-4 요청의 `topics[]` 한 항목이다.
///
/// [action] 은 보호자가 최종으로 고른 행동이다. AI 제안을 그대로 둔 경우도
/// 담는다. `accepted` 일 때만 보낸다. 이 값은 이 화면을 위해 계약에 더한 것이다.
class TopicReview {
  const TopicReview.accepted({required this.proposalId, required this.action})
    : reviewStatus = ChangeReviewStatus.accepted;

  const TopicReview.rejected({required this.proposalId})
    : reviewStatus = ChangeReviewStatus.rejected,
      action = null;

  final String proposalId;
  final ChangeReviewStatus reviewStatus;
  final TopicAction? action;

  Map<String, dynamic> toJson() => {
    'proposalId': proposalId,
    'reviewStatus': reviewStatus.name,
    if (action != null) 'action': action!.name,
  };
}

/// 생애 정보 제안 하나의 검토 결과. API 7-4 요청의 `lifeFacts[]` 한 항목이다.
///
/// [title] 과 [content] 는 일대기에 저장할 최종 값이다. 보호자가 고치지 않았으면
/// 제안 그대로다. `accepted` 일 때만 보낸다. 이 값은 이 화면을 위해 계약에
/// 더한 것이다.
class LifeFactReview {
  const LifeFactReview.accepted({
    required this.proposalId,
    required this.title,
    required this.content,
  }) : reviewStatus = ChangeReviewStatus.accepted;

  const LifeFactReview.rejected({required this.proposalId})
    : reviewStatus = ChangeReviewStatus.rejected,
      title = null,
      content = null;

  final String proposalId;
  final ChangeReviewStatus reviewStatus;
  final String? title;
  final String? content;

  Map<String, dynamic> toJson() => {
    'proposalId': proposalId,
    'reviewStatus': reviewStatus.name,
    if (title != null) 'title': title,
    if (content != null) 'content': content,
  };
}

/// 한 회차의 변경 제안 검토. API 7-4 요청이다.
///
/// 회차의 `pending` 제안만 모두 담는다. 화면에 남긴 항목은 `accepted`, 뺀
/// 항목은 `rejected` 다.
class ProposalReview {
  const ProposalReview({required this.lifeFacts, required this.topics});

  final List<LifeFactReview> lifeFacts;
  final List<TopicReview> topics;

  Map<String, dynamic> toJson() => {
    'lifeFacts': [for (final r in lifeFacts) r.toJson()],
    'topics': [for (final r in topics) r.toJson()],
  };
}
