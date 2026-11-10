/// 생년월일을 고르고, 나이로 바꾸고, 보여주는 규칙을 한곳에 둔다.
///
/// 서버는 만 10세가 안 된 날짜와 미래 날짜를 받지 않는다
/// (`backend/app/schemas/profiles.py` 의 `latest_birth_date`, API 2-2, 2-4).
/// 앱도 같은 기준으로 고를 수 있는 날짜를 줄여 보낸 뒤에 거절당하지 않게 한다.
///
/// 나이로 입력한 분은 오늘에서 그 나이만큼 뺀 날(오늘과 같은 월, 일)을
/// `birthDate` 로 보낸다. 그러면 오늘 나이가 입력한 나이와 같고 해마다 한 살씩
/// 는다. 이 날짜는 지어낸 것이라 화면에는 날짜 대신 `82세(나이로 입력)` 로
/// 보여준다. 나이로 입력했다는 표시는 서버 계약에 없어 단말에만 둔다
/// (`profile_birth_input_store.dart`).
library;

/// 서버의 `MIN_AGE_YEARS` 와 같다.
const minBirthAge = 10;

/// 나이로 입력할 때 받는 범위. 서버 기준(만 10세)보다 좁다. 돌보는 분의 나이를
/// 적는 칸이라 두 자리를 잘못 친 값(예: 81 을 18 로)을 막는다. 정확한 날짜로
/// 입력하면 만 10세까지 고를 수 있다.
const minAgeInput = 50;
const maxAgeInput = 110;

/// 서버가 날짜를 셀 때 쓰는 오늘. 서버는 UTC 날짜로 센다. 한국 시간 자정부터
/// 아침 9시까지는 휴대폰의 날짜가 하루 빨라, 휴대폰 날짜로 상한을 잡으면 서버가
/// 거절하는 날을 고를 수 있다. 둘 중 이른 날을 쓴다.
DateTime serverToday(DateTime now) {
  final local = DateTime(now.year, now.month, now.day);
  final utcNow = now.toUtc();
  final utc = DateTime(utcNow.year, utcNow.month, utcNow.day);
  return utc.isBefore(local) ? utc : local;
}

/// 그달의 날 수. 윤년의 2월은 29일이다.
int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// [year] 년 [month] 월 [day] 일이 달력에 있는 날인지.
bool isRealDate(int year, int month, int day) =>
    month >= 1 && month <= 12 && day >= 1 && day <= daysInMonth(year, month);

/// [today] 에 만 [age] 세가 되는 가장 늦은 생년월일. 그해에 없는 2월 29일은
/// 2월 28일이다. 서버의 `latest_birth_date` 와 같은 계산이다.
DateTime birthDateForAge(int age, DateTime today) {
  final year = today.year - age;
  final day = today.month == 2 && today.day == 29 && daysInMonth(year, 2) == 28
      ? 28
      : today.day;
  return DateTime(year, today.month, day);
}

/// 고를 수 있는 가장 늦은 생년월일. 오늘 만 10세가 되는 날이다.
DateTime latestBirthDate(DateTime now) =>
    birthDateForAge(minBirthAge, serverToday(now));

/// 년 목록의 첫 해. 나이로 받는 가장 많은 나이까지 고를 수 있다.
int earliestBirthYear(DateTime now) => now.year - maxAgeInput - 1;

/// [today] 의 만 나이. 생일이 지나지 않았으면 한 살 뺀다.
int ageOn(DateTime birth, DateTime today) {
  var age = today.year - birth.year;
  if (today.month < birth.month ||
      (today.month == birth.month && today.day < birth.day)) {
    age--;
  }
  return age;
}

/// `YYYY-MM-DD` 로 쓴다.
String isoDate(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-${two(date.month)}-'
      '${two(date.day)}';
}

/// 생년월일을 보여줄 글자. 나이로 입력한 분은 `82세(나이로 입력)`, 아니면
/// `1943년 3월 12일` 이다. 읽지 못하는 값은 그대로 보여준다.
String birthDateText(String birthDate, {required bool byAge, DateTime? today}) {
  final date = DateTime.tryParse(birthDate);
  if (date == null) return birthDate;
  if (byAge) {
    final now = today ?? DateTime.now();
    return '${ageOn(date, now)}세(나이로 입력)';
  }
  return '${date.year}년 ${date.month}월 ${date.day}일';
}
