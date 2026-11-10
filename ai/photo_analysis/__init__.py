"""프로필 사진 설명 생성. 별도 태그 확인 화면이나 사진 메타데이터 입력은 없다.

photo-2는 사람별 안경, 옷 색과 행동을 따로 살피고 불분명한 세부는 생략하도록 지시한다.
배경 사물과 사람의 실제 행동을 구분한다. 모델의 시각 판단 정확성을 보장하는 검사는 아니다.
"""
from .generate import PhotoAnalysisError, PhotoDescription, analyze_photo

__all__ = ["PhotoAnalysisError", "PhotoDescription", "analyze_photo"]
