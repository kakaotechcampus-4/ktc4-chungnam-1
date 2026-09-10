# [리포트] 새록 평가 이미지 17종 메타데이터 전수 추출 결과

> **문서 목적**: VLM 추론에 의존하지 않고 사진 파일 자체에서 얻을 수 있는 정보가 실제로 얼마나 남아 있는지를, 이미지 태깅 벤치마크에 쓴 평가 이미지 17종 전수 추출과 실기기 촬영본 대조로 확인한 결과 기록
> **관련 이슈**: #27 (사진 메타데이터 추출 가능 범위), #24, #19
> **관련 문서**: [VLM 벤치마크 리포트](vlm-benchmark-report.md), [이미지 출처와 라이선스](target-image/SOURCES.md), [ADR-001 동의 구조와 원본 자료의 임시 처리 경계](../../../docs/architecture/decisions/ADR-001-consent-and-temporary-processing.md)

---

## 1. 전제 및 범위

- 측정 대상은 **17종의 고해상도 원본 파일** 및 **실기기 대조 촬영 원본 2장**이다. 저장소의 `target-image/` 내 17종은 문서 열람용 리사이즈본이며 메타데이터가 남아 있지 않다(5장 참조, 고해상도 원본은 [SOURCES.md](target-image/SOURCES.md) 참조). 실기기 대조군 2장은 메타데이터가 보존된 원본 그대로 `target-image/`에 수록되었다.
- 17종만으로는 값이 없는 이유가 "원래 없어서"인지 "배포 과정에서 지워져서"인지 가릴 수 없어, **실기기 촬영본 2장을 대조군으로 따로 측정**했다(4장). 표본이 2장뿐이므로 3장의 충족률 통계에는 넣지 않았다.

## 2. 추출 방법

| 항목 | 내용 |
| --- | --- |
| 도구 | Python 3, Pillow (`Image.getexif()`, Exif IFD `0x8769`, GPS IFD `0x8825`) |
| 읽은 영역 | IFD0 기본 태그, Exif 상세 태그, GPS IFD, XP 계열 태그, XMP·IPTC·ICC 존재 여부 |
| 원자료 | [`metadata-extraction-results.json`](metadata-extraction-results.json) (평가 이미지 17종 전수 + 실기기 대조 2종) |

SOURCES.md의 출처 링크에서 받은 고해상도 원본 17종을 대상으로, 위 영역을 파일에서 직접 읽어 값을 그대로 옮겼다. 기기명에 `ScanJet`, `Scanner`, `Epson`, `CanoScan`, `VueScan` 같은 문자열이 있으면 스캔본으로 판정했다.

## 3. 17종 전수 결과

기록된 값을 그대로 옮긴 것이며, 값의 사실 여부를 판정한 것이 아니다.

| 파일명 | EXIF | 기기 (Make/Model) | 촬영일시 | 파일 수정일시 | GPS 좌표 | 설명 필드 | 촬영자 | 편집 소프트웨어 |
| --- | :---: | --- | --- | --- | :---: | :---: | --- | --- |
| `1970s_01_bus_conductor.png` | 없음 | - | - | - | 없음 | 없음 | - | - |
| `1970s_02_medicine_hawker.png` | 없음 | - | - | - | 없음 | 없음 | - | - |
| `1970s_03_saemaul_roof.jpg` | 있음 | - | - | 2011:09:26 11:22:13 | 없음 | 없음 | - | Adobe Photoshop CS4 Windows |
| `1980s_01_olympics_opening.jpg` | 없음 | - | - | - | 없음 | 없음 | - | - |
| `1980s_02_rice_harvest.jpg` | 있음 | - | - | - | 없음 | **있음** | SRA Jeffrey Allen | - |
| `1980s_03_olympics_fireworks.jpg` | 없음 | - | - | - | 없음 | 없음 | - | - |
| `1990s_01_jagalchi_market.jpg` | 있음 | - | - | 2018:11:13 15:04:06 | 없음 | 없음 | - | Adobe Photoshop CS6 (Macintosh) |
| `1990s_02_seoul_fire_safety.jpg` | 있음 | **HP / HP ScanJet 5590** | 1990:01:01 20:52:19 | - | 없음 | 있음 | - | - |
| `2000s_01_worldcup_cheering.jpg` | 있음 | - | - | 2019:02:01 10:11:25 | 없음 | 없음 | - | MS Windows Photo Viewer |
| `2000s_02_worldcup_flag.jpg` | 있음 | - | - | 2009:01:23 00:25:31 | 없음 | 없음 | - | Adobe Photoshop CS2 Windows |
| `2000s_03_chuseok_table.jpg` | 있음 | NIKON / COOLPIX P7100 | 2012:09:30 02:35:12 | 2012:10:20 18:44:14 | 없음 | 없음 | - | MS Windows Photo Viewer |
| `2010s_01_kimchi_festival.jpg` | 있음 | Canon / EOS 5D Mark III | 2014:11:14 14:24:05 | 2014:11:14 17:50:40 | 없음 | 있음 | Jeon Han | Adobe Photoshop CS6 (Windows) |
| `2010s_02_gwangjang_market.jpg` | 있음 | Canon / EOS-1D X | 2014:04:10 16:49:46 | 2014:04:16 09:49:45 | 없음 | 있음 | Jeon Han | Adobe Photoshop CS6 (Windows) |
| `2010s_03_jeongseon_market.jpg` | 있음 | Canon / EOS-1D X | 2014:06:07 13:35:52 | 2014:06:10 14:50:53 | 없음 | 있음 | Jeon Han | Adobe Photoshop CS6 (Windows) |
| `2020s_01_lantern_festival.jpg` | 있음 | Canon / EOS R3 | 2023:05:20 19:39:56 | 2023:05:20 22:29:14 | 없음 | 있음 | KIM SUN JOO | Lightroom Classic 12.3 (Mac) |
| `2020s_02_lantern_crowd.jpg` | 있음 | Canon / EOS R3 | 2022:04:30 19:50:18 | 2022:04:30 20:38:30 | 없음 | 있음 | JEON HAN | Adobe Photoshop 21.2 (Mac) |
| `2020s_03_hiking_outing.jpg` | 있음 | Panasonic / DC-S5M2 | 2023:04:22 14:36:46 | 2023:04:25 00:18:14 | 없음 | 없음 | - | Lightroom Classic 12.3 (Mac) |

### 3.1 항목별 충족률

| 정보 항목 | 17종 중 존재 | 비고 |
| --- | :---: | --- |
| EXIF 블록 자체 | 13 | PNG 2종과 JPEG 2종은 태그가 하나도 없음 |
| 촬영일시 `DateTimeOriginal` | 8 | 이 중 1건은 스캐너 기록값 |
| 파일 수정일시 `DateTime` | 11 | 편집·내보내기 시각 |
| 날짜가 하나라도 있는 파일 | 12 | 촬영일시 또는 수정일시 |
| 기기 제조사·모델 | 8 | 이 중 1건은 스캐너 |
| 촬영 설정(조리개·ISO·초점거리 등) | 7 | 디지털카메라 직촬본에만 존재 |
| 편집 소프트웨어 | 11 | |
| 설명 필드(`ImageDescription`/`XPComment`) | 7 | |
| 촬영자(`Artist`/`XPAuthor`) | 6 | 실명 |
| **GPS 좌표** | **0** | 4건은 GPS 블록이 있으나 `GPSVersionID`만 들어 있음 |
| XMP / IPTC 부가 블록 | 13 / 13 | |
| 미리보기(썸네일) | 0 | |
| 폭·높이·형식·용량 | 17 | 파일을 열면 항상 얻을 수 있음 |

## 4. 실기기 원본 대조 측정 결과

스마트폰 카메라 설정에 따른 메타데이터 차이를 측정한 결과임. 원본 파일은 [`target-image/`](target-image/)에 수록됨.

| 항목 | 꺼짐 대조군 (`20260909_205724.jpg`) | 켜짐 대조군 (`20260911_003035.jpg`) |
| --- | --- | --- |
| 단말 / 펌웨어 | Galaxy S21+ (SM-G996N) / `G996NKSSCHZA9` | 동일 |
| 촬영일시 (`DateTimeOriginal`) | 2026:09:09 20:57:24 | 2026:09:11 00:30:36 |
| 촬영 설정 | f/1.8, 1/10s, ISO 2000, 5.4mm | f/1.8, 1/120s, ISO 100, 5.4mm |
| **GPS 블록 유무** | **없음** (태그 0개) | **있음** (태그 10개) |
| `GPSLatitude` / Ref | 없음 | 36° 22′ 30.819″ N (`36.375228`) |
| `GPSLongitude` / Ref | 없음 | 127° 20′ 50.936″ E (`127.347482`) |
| `GPSAltitude` | 없음 | 141.0 m |
| `GPSProcessingMethod` | 없음 | `CELLID` (기지국 측위) |
| `GPSTimeStamp` / `GPSDateStamp` | 없음 | 15:30:34 / 2026:09:10 (UTC) |

## 5. 핵심 발견

- **GPS 좌표 부재**: 17종 전수 유효 좌표 없음 (4건은 버전 ID만 존재).
- **실기기 GPS 특성**: 위치 태그 ON 시에만 좌표 생성, 실내 측위는 `CELLID`(기지국) 방식, GPS 일시는 UTC 기준.
- **기록 날짜 불일치**: 스캔·수정본은 실제 촬영 시점과 최대 40년 차이 발생 (`DateTimeOriginal` 명칭만으로 시점 보증 불가). 과거 사진을 스마트폰으로 재촬영한 경우도 마찬가지.
- **스캔본 기기명**: `ScanJet` 등 스캐너 모델명으로 스캔 여부 식별 가능.
- **리사이즈 시 메타데이터 소실**: 웹 열람용 800px 리사이즈 시 EXIF·XMP·IPTC 100% 소실.
