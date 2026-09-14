# Avatar: Default Asset + Custom Upload Spec

> Historical / superseded: 이 문서는 과거 설계 기록이며 현재 구현 계약이 아니다.
> 현재 preset avatar와 cleanup 계약은 [Final Starter Audit Hardening §7](../specs/final_starter_audit_hardening.md#7-deadstale-artifacts-cleanup),
> 별도 Student 모델의 avatar 계약은 [Student Model Migration](../specs/student_model_migration.md)을 따른다.
> 아래의 학생 User, `default_avatar_index`와 custom upload 요구를 현재 기능으로 해석하지 않는다.

## 1. Background

현재 상태: - User 모델에는 아바타 개념이 존재하지 않음. - 학생 화면 및
교실 화면에서 사용자 식별을 텍스트 기반으로만 처리 중. - 기본 프로필
이미지 시스템이 없음.

문제: - 사용자 시각적 구분이 어려움. - 교실 화면에서 학생 리스트
가독성이 낮음. - 커스텀 프로필 이미지 업로드 기능이 없음.

왜 이 작업이 필요한가: - 사용자 경험 개선 (UX) - 교실 화면 가독성 향상 -
향후 개인화 기능 확장 기반 마련 - Rails way 기반의 일관된 이미지 처리
구조 도입

------------------------------------------------------------------------

## 2. Scope (이번 작업 범위)

### 포함

-   모든 User(teacher, student, admin)에 avatar 개념 추가
-   기본 랜덤 썸네일 자동 할당
-   ActiveStorage 기반 커스텀 업로드 지원
-   user show 화면에서 512px 이미지 표시
-   classrooms show 화면에서 128px 이미지 표시
-   seed 생성 시 기본 썸네일 자동 배정
-   default_avatar_index 컬럼 추가
-   기본 아바타 asset 구조 및 네이밍 규칙 명세화

### 제외 (이번 작업에서 하지 않을 것)

-   이미지 크롭 UI
-   Drag & Drop 업로드 UI
-   CDN 구성
-   Avatar 선택 UI
-   기존 정책/권한 구조 변경
-   썸네일 관리용 Admin UI

------------------------------------------------------------------------

## 3. Constraints (제약 조건)

-   기존 동작 동일 유지
-   Public interface 변경 금지
-   Turbo frame id 유지
-   Pundit 정책 구조 유지
-   기존 테스트 깨지지 않아야 함
-   기본 아바타는 static asset으로 유지 (ActiveStorage에 저장하지 않음)
-   DB에는 index 값만 저장 (파일 경로 직접 저장 금지)
-   파일 네이밍 규칙은 명세와 반드시 일치해야 함

------------------------------------------------------------------------

## 4. Asset Structure & Naming Convention

### 4.1 Directory

기본 아바타 파일은 다음 경로에 위치해야 한다:

app/assets/images/avatars/

### 4.2 File Naming Rule

각 기본 아바타는 두 가지 사이즈를 가진다:

-   512px (User show 용)
-   128px (Classrooms show 용)

파일명 규칙:

user_profile_XX_512.png user_profile_XX_128.png

여기서: - XX는 01 \~ 32까지의 두 자리 숫자 - 총 32 세트 - 전체 파일 수:
64개

예:

user_profile_01_512.png user_profile_01_128.png user_profile_32_512.png
user_profile_32_128.png

### 4.3 Index Mapping

DB에는 다음 값만 저장한다:

default_avatar_index : integer (1 \~ 32)

파일 매핑은 다음 규칙을 따른다:

index = 7

→ user_profile_07_512.png → user_profile_07_128.png

------------------------------------------------------------------------

## 5. Avatar Selection Logic

### 5.1 Creation Rule

User 생성 시:

-   avatar가 attach 되어 있지 않고
-   default_avatar_index가 nil이면
-   1..32 범위에서 랜덤 할당

------------------------------------------------------------------------

## 6. Rendering Logic (Single Source of Truth)

표시 우선순위:

if user.avatar.attached? → ActiveStorage image else → asset avatar
(default_avatar_index 기반)

------------------------------------------------------------------------

## 7. Acceptance Criteria (완료 조건)

-   [ ] users 테이블에 default_avatar_index 컬럼이 존재한다.
-   [ ] app/assets/images/avatars/ 경로에 64개 파일이 존재한다.
-   [ ] 파일 네이밍 규칙이 명세와 일치한다.
-   [ ] User 생성 시 avatar 미첨부 상태이면 1\~32 중 랜덤 index가
    저장된다.
-   [ ] user show 화면에서 512px 기본/커스텀 이미지가 정상 표시된다.
-   [ ] classrooms show 화면에서 128px 기본/커스텀 이미지가 정상
    표시된다.
-   [ ] 커스텀 이미지 업로드 시 기본 썸네일보다 우선 적용된다.
-   [ ] seed 실행 시 각 user가 기본 썸네일을 가진다.
-   [ ] 기존 테스트가 모두 통과한다.

모든 항목이 충족되면 작업 완료로 간주한다.

------------------------------------------------------------------------

## 8. Risks / Open Questions

-   32개 기본 썸네일 개수는 향후 증가 가능한가?
-   teacher/admin도 랜덤 배정이 정책적으로 적절한가?
-   default_avatar_index NULL 허용 여부를 유지할 것인가?
-   asset 파일 누락 시 fallback 전략은 무엇인가?
