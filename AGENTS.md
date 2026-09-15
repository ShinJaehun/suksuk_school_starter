# AGENTS.md

## 목적

이 문서는 `suksuk_school_starter` 저장소에서 작업하는 에이전트(Codex 등)가
프로젝트의 기본 작업 원칙과 문서 참조 순서를 일관되게 따르도록 하기 위한 안내서다.

---

## 기본 작업 원칙

- Rails 관례(Rails way)를 최우선으로 따른다.
- 꼭 필요하지 않다면 비표준 구조, 과한 추상화, 과한 메타프로그래밍을 피한다.
- 기존 public behavior를 함부로 바꾸지 않는다.
- 작은 단위로 읽고, 작은 단위로 수정하고, 변경 이유를 분명히 남긴다.
- 새로운 코드는 현재 코드베이스의 구조와 스타일에 최대한 맞춘다.
- UI 문구나 마크업만 보고 성급히 수정하지 말고, 관련 도메인/흐름/정책부터 확인한다.
- view에는 가능한 한 로직을 최소화하고, 권한/분기/도메인 판단은 controller, policy, model, helper 등 적절한 계층에 둔다.
- 권한 판단은 view에서 직접 해결하지 말고, controller와 policy를 기준으로 읽기 쉽게 유지한다.
- 사용자에게 표시되는 문자열은 기존 locale key를 우선 재사용하고, 없으면 `config/locales`에 추가한 뒤 `I18n.t` 또는 `t`로 참조한다.
- view, controller, model, helper, service에 제목, 버튼, label, placeholder, flash, validation 안내, Turbo 제출 상태 문구를 새 literal로 직접 추가하지 않는다.
- 기존 하드코딩을 발견해도 현재 작업 범위를 무리하게 넓히지 말고, 새로 추가하거나 수정한 사용자 표시 문자열부터 locale 규칙을 지킨다.

---

## 문서 우선순위

작업 전 아래 문서를 가능한 먼저 확인한다.

1. `AGENTS.md`

2. 현재 시스템/아키텍처 문서
   - `docs/architecture/*.md`

3. 현재 작업과 직접 관련된 spec 문서
   - `docs/specs/*.md`

4. 테스트 전략 문서
   - `docs/testing/*.md`

5. 운영 문서
   - `docs/ops/*.md`

원칙:

- `spec.md`가 없을 수 있으므로, 존재하지 않는 파일을 전제로 작업을 멈추지 않는다.
- 관련 문서가 없거나 부족하면, 먼저 현재 코드 구조를 읽고 작업 계획을 제안한다.
- 문서가 현재 구현과 다르면, 구현을 기준으로 무리하게 추측하지 말고 사용자에게 확인한다.
- `docs/archive/*`, `docs/legacy/*`는 사용자가 요청하거나 현재 문서만으로 맥락을 알 수 없을 때만 참고한다.
- spec만 보지 말고, 해당 spec의 판단 근거가 되는 정책/구조 문서가 있으면 함께 확인한다.

---

## 도메인 원칙

- 서비스의 사용자 역할 개념은 `admin`, `teacher`, `student`를 기준으로 하되, 인증 모델은 admin/teacher `User`와 별도 `Student`로 구분한다.
- 현재 runtime authority는 admin/teacher `User`와 Classroom에 직접 속한 `Student`로 분리된다. 학생용 `User`와 student `ClassroomMembership`은 runtime/schema에 존재하지 않는다.
- `Student`는 Devise User가 아니며 Rails session + PIN으로 인증한다. 이는 일반적인 인증 모델 확대가 아니라 승인된 Student cutover 예외이며 그 밖의 role을 성급히 별도 인증 모델로 분리하지 않는다.
- 권한 판단은 controller/policy 중심으로 유지한다.
- view에서 직접 복잡한 권한 조건을 늘리지 않는다.
- Teacher와 Classroom의 현재·과거 담임 관계는 `HomeroomAssignment`를 canonical source로 사용한다. `ended_on IS NULL`인 row가 현재 담임이다.
- Classroom의 학교와 학년도는 `Classroom.school_year.school`, `Classroom.school_year`를 기준으로 하고 반 식별자는 `Classroom.class_label`을 사용한다.
- SchoolYear-aware 기능을 추가하기 전에 데이터의 귀속 SchoolYear와 active/planning/archived별 read/write authority를 명시한다. SchoolYear에 귀속되지 않는 데이터는 School-level 또는 global ownership인 이유를 명확히 하며, 이 판단 없이 active year에 묶거나 현재 User의 SchoolYear를 암묵적으로 재사용하지 않는다.
- 교사의 현재 학교, 학교 역할과 학년은 각각 `User.school_year.school`, `User.school_role`, `User.grade`를 기준으로 한다.
- teacher의 학교 소속과 권한에는 별도 membership model을 두지 않는다.
- 현재 runtime의 학생 소속과 lifecycle source는 `Student.classroom_id`와 `Student.active`다.
- Teacher, Student, Classroom lifecycle은 각각의 canonical spec과 상태 source를 따른다.
- Student에는 `StudentEnrollment`를 두지 않는다.
- 학생 관련 기능은 교실 사용 맥락을 먼저 고려한다.
- 공유 태블릿 환경에서는 학생 세션, 로그아웃, PIN, 권한 노출에 특히 주의한다.
- Turbo 응답과 HTML 응답은 둘 다 깨지지 않도록 주의한다.

---

## 아키텍처/구현 원칙

- 새 기능을 추가할 때는 먼저 현재 구조와 naming, partial 분리 방식, controller 책임 범위를 확인하고 그 흐름을 따른다.
- 불필요한 새 객체, 새 패턴, 새 계층을 성급히 늘리지 않는다.
- controller는 인증/권한/흐름 제어를 담당하되, 과도한 도메인 로직을 밀어 넣지 않는다.
- model에는 데이터 불변식과 단순 도메인 규칙을 둔다.
- helper는 view 표현을 단순하게 만들기 위한 용도로 사용한다.
- view에는 가능한 한 계산/권한/도메인 판단을 직접 넣지 않는다.
- 기존 route, controller, view 구조가 있다면 먼저 그 흐름을 따른다.
- 새 구조가 필요하면 Rails 관례에 맞는 가장 단순한 형태부터 제안한다.

---

## 변경 승인 원칙

- 기본적으로 파일을 바로 수정하지 말고, 먼저 변경 목적, 수정 대상 파일 목록, 핵심 변경 요약, 위험/주의점을 제시한다.
- 사용자가 승인하기 전에는 실제 파일 수정(write)을 하지 않는다.
- 사용자가 승인한 뒤에는 별도 요청이 없는 한 전체 diff를 다시 제시하지 말고 작업을 진행한다.
- 전체 diff나 unified diff는 사용자가 명시적으로 요청한 경우에만 제시한다.
- 문서 작업도 동일하게 적용한다.
- 사용자가 “바로 반영해도 된다”고 명시한 경우에만 즉시 수정한다.
- 변경 범위가 클 경우, 파일별 수정 계획을 먼저 요약한다.
- 작업 도중 예상보다 범위가 커지면 멈추고 사용자에게 범위 재확인을 요청한다.

---

## 토큰 절약 작업 원칙

- 기본적으로 토큰 절약 모드로 작업한다.
- 관련 파일만 읽고, 관련 파일만 수정한다.
- 전체 `git diff` 출력은 피한다.
- 전체 코드베이스 검색은 꼭 필요할 때만 한다.
- 긴 계획, 긴 최종 요약, 전체 테스트 로그 출력을 피한다.
- 한 번의 Codex run에서는 하나의 좁고 명확한 구현 책임만 처리한다.
- migration/model, service/domain behavior, controller/policy/UI, 광범위한 spec 정리, 문서 갱신을 한 run에 모두 몰아넣지 않는다.
- canonical spec 작성과 product implementation은 반드시 별도 run으로 처리한다.
- 구현 범위가 여러 계층에 걸치면 migration/model → service/domain → controller/policy/runtime → spec/docs처럼 필요한 단위로 나누어 진행한다.
- 이전 run에서 dependency inventory가 이미 끝났다면 다음 run에서 같은 범위를 다시 광범위하게 탐색하지 않는다.
- 작업 중 추가 정리나 후속 책임을 발견해도 현재 책임의 정확성에 필수적이지 않다면 현재 run에 추가하지 않는다.
- context compaction이 발생했거나 context가 크게 누적된 session에서는 새로운 대규모 작업을 시작하지 않는다.
- usage-limit 경고가 나타난 뒤에는 현재 run의 범위를 확장하지 않는다.
- 큰 context를 유지하기 위해 기존 Codex session을 계속 재사용하지 않는다. 다음의 의미 있는 구현 단위는 새 session에서 시작하는 것을 우선한다.
- "토큰을 절약하라"는 지시만으로 충분하다고 보지 않는다. 실제 읽는 파일 수와 수정 계층, 구현 책임 자체를 줄인다.
- 작업 완료 후에는 변경 파일 목록과 사용자가 실행할 테스트 명령만 짧게 제시한다.
- 전체 테스트, 전체 diff 확인, 커밋, push, merge는 기본적으로 사용자가 직접 수행한다.
- 사용자가 명시적으로 요청하지 않는 한 Codex가 직접 커밋하지 않는다.
- `git add .`, `git add -A`는 사용하지 않는다.
- 커밋이 필요한 경우에도 사용자가 명시한 파일만 `git add <file>` 형식으로 스테이징한다.
- 한 세션에서 하나의 큰 기능 전체를 끝내려 하지 않는다. 같은 feature branch라도 여러 개의 작은 Codex run/session으로 나눌 수 있다.

---

## 브랜치 운영 원칙

- 브랜치는 너무 잘게 쪼개지 않는다.
- 하나의 기능 흐름이나 정책 검토 흐름이 이어지는 동안에는 같은 의미 있는 브랜치에서 작업을 계속한다.
- 브랜치는 “작업 단위”가 아니라 “의미 있는 변경 묶음” 기준으로 만든다.
- 단, `main`에는 직접 작업하지 않는다.
- 이미 관련 브랜치가 열려 있다면, 새 브랜치를 만들기보다 그 브랜치에서 이어서 작업할 수 있는지 먼저 확인한다.
- 브랜치 분리가 필요한 경우는 기능 방향이 명확히 달라지거나, 위험도가 높은 변경을 기존 작업과 분리해야 할 때로 제한한다.

---

## 정리/복구 원칙

- 구현 방향이 바뀌어 더 이상 필요 없어졌다면, 관련 파일과 코드도 함께 정리 대상으로 본다.
- 새 구조를 넣으면서 불필요해진 controller, view, helper, route, 테스트, 문서가 남지 않도록 정리한다.
- 단, 테스트의 삭제·통합·축소에는 아래 `기존 테스트 보존 원칙`이 우선하며, 구현 구조가 사라졌다는 이유만으로 관련 spec을 함께 삭제하지 않는다.
- 무언가를 추가했다가 방향을 바꿔 되돌리는 경우, 남겨둘 이유가 분명하지 않다면 최대한 작업 전 상태에 가깝게 복구한다.
- 다만 사용자가 직접 만든 변경이나, 현재 작업과 무관한 기존 변경은 임의로 되돌리지 않는다.
- 삭제/복구가 필요한 파일이 있다면, 반영 전에 정리 대상 파일 목록을 먼저 요약한다.

---

## 테스트 원칙

- 테스트의 목적은 coverage 수치가 아니라 confidence 확보이다.
- 핵심 도메인 규칙, 권한, 멱등성, request 흐름을 우선 테스트한다.
- brittle한 HTML 구조 테스트는 지양한다.
- system spec은 핵심 happy path 중심으로 최소화한다.
- RSpec 스타일은 readable > clever 원칙을 따른다.
- 과도한 shared context, helper, abstraction을 피한다.
- 기존 테스트와 중복되는 저가치 테스트를 늘리지 않는다.
- 전체 테스트는 사용자가 직접 실행하는 것을 기본으로 한다.
- Codex는 필요한 경우 관련 request/model/helper spec만 제안하거나, 사용자가 승인한 경우에만 targeted spec을 실행한다.

### 기존 테스트 보존 원칙

* 기존 테스트는 단순한 구현 부속물이 아니라 현재 public behavior, 권한 경계, 오류 처리, lifecycle과 회귀 방지 계약으로 취급한다.
* 구현 변경 때문에 기존 테스트가 실패하더라도, 테스트가 낡았다고 추정하여 삭제하거나 assertion을 약화하지 않는다.
* 모델 전환이나 구조 refactor에서는 기존 테스트의 fixture와 대상 모델을 새 구조에 맞게 이식하되, 기존 example이 검증하던 의미와 안전망은 가능한 그대로 보존한다.
* 테스트를 통과시키기 위한 목적으로 example 삭제, spec 파일 삭제, `skip`/`pending` 추가, 세부 assertion 제거, 단순 status assertion으로의 축소를 하지 않는다.
* 기존 spec 파일을 삭제하거나 여러 example을 제거·통합하려면 먼저 기준 브랜치의 기존 example을 확인하고 각 항목을 `유지`, `새 테스트로 대체`, `승인된 정책 변경으로 폐기` 중 하나로 분류한다.
* `승인된 정책 변경으로 폐기`는 canonical spec에서 해당 기존 behavior의 제거 또는 변경이 명시적으로 승인된 경우에만 사용할 수 있다.
* 기존 spec 파일 삭제, 의미 있는 example 수 감소, 권한·보안·lifecycle·오류 처리 assertion의 약화가 필요해지면 실제 변경 전에 작업을 멈추고 사용자 승인을 받는다.
* 새 구현과 기존 테스트가 충돌하는데 어느 쪽이 옳은지 명확하지 않으면 구현에 맞춰 테스트를 고치지 말고 정책 충돌로 보고 사용자에게 확인한다.
* 광범위한 실패가 발생해도 spec 파일 전체를 다시 작성하지 않는다. 실패 원인을 분류하고 fixture, setup, assertion을 필요한 범위에서 순차적으로 이식한다.
* 작업 완료 시 수정한 주요 spec에 대해 기존 scenario가 사라지지 않았는지 확인한다. 삭제하거나 대체한 scenario가 있다면 그 이유와 대체 위치를 사용자에게 명시한다.
* 구조 refactor 전후로 관련 spec의 example 수가 크게 줄었다면 회귀 신호로 취급한다. 단, 동일 example 수 유지는 목표가 아니며 중복 제거가 필요한 경우에도 기존 scenario의 대체 위치를 먼저 확인하고 사용자 승인을 받는다.

---

## 커밋 원칙

- 커밋은 기본적으로 사용자가 직접 수행한다.
- Codex는 사용자가 명시적으로 요청한 경우에만 커밋한다.
- Codex가 커밋을 수행해야 하는 경우, 먼저 커밋 대상 파일 목록을 짧게 제시한다.
- `git add .`, `git add -A`는 사용하지 않고, 필요한 파일만 명시적으로 스테이징한다.
- 커밋 메시지는 가능하면 간결하게 작성한다.
- 커밋 메시지에는 변경 의도와 검증 방법이 드러나면 충분하다.
- 과도하게 긴 커밋 메시지를 기본값으로 요구하지 않는다.
- commit message는 한국어 우선으로 작성한다.

---

## 작업 완료 후 기대사항

- 변경 이유를 짧게 설명할 수 있어야 한다.
- 가능하면 관련 테스트를 함께 추가/수정한다.
- 새 규칙이 생겼다면 관련 문서 반영 여부를 검토한다.
- 사용자 표시 문자열을 다룬 경우 locale key 재사용·추가 여부와 새 하드코딩 literal이 없는지 확인한다.
- 변경 범위가 크면 후속 작업 포인트를 짧게 남긴다.
- 사용자가 실행할 확인 명령이나 테스트 명령을 짧게 제시한다.
