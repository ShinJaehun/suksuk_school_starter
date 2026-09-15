# Final Starter Audit Hardening

## 상태와 범위

- 현재 상태: 아래 7개 항목은 후속 implementation에서 완료됐다. Full baseline 문서 현행화 기준은 `main` / `7093d38`이다.
- Audit 당시 검토 기준: `main` / `79b194bc48fbfc8a077586a8bd8243aab5b36945`.
- Audit 당시 작업 브랜치: `fix/final-starter-audit-hardening`; 시작 시 working tree clean 확인.
- 목적: 최종 audit의 운영·인증·배포·계약 잔여 문제 7개만 닫고 School Starter baseline을 마감한다.
- 아래 finding, 기준 HEAD의 증거와 “이번 run에서는 구현하지 않는다”, “후속 run에서 구현” 등의 표현은 audit spec 작성 당시의 기록이다. 현재 미구현 목록으로 해석하지 않으며 당시 finding과 검증 한계는 보존한다.

후속 implementation 완료 항목:

- Dependency/security hardening
- User/Student principal isolation
- Production Docker DB preparation
- Individual Teacher `login_id` immutability
- Admin email 변경 re-authentication
- Rollover manager credential fail-closed
- Stale account/avatar artifact cleanup

관련 기준은 [현재 시스템](../architecture/current_system.md), [역할과 권한](../architecture/roles_and_permissions.md), [RSpec 전략](../testing/rspec_strategy.md)이다. Admin/Teacher는 Devise `User`, Student는 Classroom에 직접 속하는 별도 `Student`와 Rails session/PIN 구조를 유지한다. Controller/policy authority와 canonical lifecycle source는 바꾸지 않는다.

## Audit 사실 확인

아래는 기준 HEAD의 source, 기존 spec/test와 설치된 동일 버전 Devise 5.0.4/Warden 1.2.9 source를 읽은 정적 검증이다. RSpec, 실제 로그인, Docker boot, migration과 Security CI는 실행하지 않았다. 실행 재현 또는 workflow green을 확보했다고 해석하지 않는다.

| 항목 | 기준 HEAD에서 확인한 사실 | 판정의 한계 |
|---|---|---|
| 1. rubyzip | lock은 2.4.1, Selenium 4.47.0 범위는 `>= 1.2.2, < 4.0`; Security의 bundler-audit 다음에 importmap audit이 있다. | 취약 버전과 후속 step skip 구조 확인. 과거 CI 실패 로그와 실제 update resolution은 이번에 실행·조회하지 않음. |
| 2. principal session | Student 성공 로그인은 User sign-out/reset을 수행하지만 Teacher/Admin 성공 로그인은 Student keys를 제거하지 않는다. | 정상 Devise logout은 전체 session reset 경로이므로 그 뒤 Student 복귀를 확인한 것은 아니다. Teacher 자격 상실의 scoped sign-out에는 잔여 keys 제거가 없다. |
| 3. Docker | entrypoint 조건은 `./bin/rails server`, Dockerfile/compose 기본 명령은 `bundle exec puma -C config/puma.rb`다. | 자동 DB 준비 누락 확인. 운영 문서의 수동 `db:prepare`까지 없다는 뜻은 아님. |
| 4. individual login_id | persisted form은 read-only지만 `TeachersController#update_params`가 `login_id`를 허용하고 저장 흐름에 전달한다. | 서버 계약 누락 확인; 임의 PATCH를 이번 run에서 실행하지 않음. |
| 5. Admin email | email 변경도 password fields가 비어 있으면 `update_without_password`로 전달된다. | Teacher email은 optional profile data 계약이 존재하며 실제 self form에도 노출됨. |
| 6. rollover manager | `RolloverEligibility#eligible?`는 manager 수만 검사하고 `Rollover#validate_target!`도 같은 결과만 사용한다. | inactive/인증 불가능 row 방어 누락 확인. 정상 UI에서 이런 row를 만들 수 있다는 주장은 아님. |
| 7. artifacts | account edit은 custom view를 사용하고 public signup은 controller에서 차단된다. 구 avatar 문서는 현재 schema/helper와 다르다. | 아래 도달 경로 근거에 한정한 삭제/archive 후보이며 이번에는 보존한다. |

## 1. Security CI / rubyzip

### 문제와 기존 계약

`Gemfile.lock`의 rubyzip 2.4.1은 이번 audit의 patched requirement `>= 3.4.0`을 충족하지 않는다. [GHSA-47m2-wp7j-p9vc](https://github.com/advisories/GHSA-47m2-wp7j-p9vc)의 설명도 3.4.0 미만의 extraction path traversal을 명시한다(CVE-2026-85396). 조회 시 advisory는 Unreviewed이며 구조화된 affected/patched 필드는 Unknown이므로 그 필드를 확정된 package metadata처럼 인용하지 않는다.

`Gemfile`에서 selenium-webdriver는 test group이고 잠긴 4.47.0은 rubyzip `>= 1.2.2, < 4.0`을 허용한다. `Dockerfile`은 development/test group을 제외한다. 취약 lock 항목 발견을 production에서 해당 extraction 경로가 사용된다는 주장으로 확대하지 않는다.

### 변경 범위

후속 run은 `Gemfile.lock`의 rubyzip만 최소 업데이트하는 것을 우선한다. 기존 Selenium constraint와 Ruby/platform을 유지한다. `.github/workflows/security.yml`의 기존 Brakeman → bundler-audit → importmap audit 계약을 완료 기준으로 사용한다.

### Acceptance criteria

- 잠긴 rubyzip은 `>= 3.4.0, < 4.0`이고 기존 Selenium 4.47.0과 dependency resolution이 성공한다.
- 가능하면 rubyzip lock entry만 바뀐다. 다른 dependency 변경이 필수이면 이유와 파일 범위를 먼저 제시하고 해당 부분을 재검토한다.
- 동일 구현 revision의 Security workflow에서 Brakeman, `bundle exec bundle-audit check --update`, `bin/importmap audit`가 모두 실제 실행되어 성공해야 한다. Skip은 green의 근거가 아니다.
- advisory ignore, step 제거, `continue-on-error`로 완료 처리하지 않는다. importmap에서 별도 문제가 발견되면 원인과 범위를 보고하고 무관한 dependency update로 확장하지 않는다.

### Regression protection / non-goals

Lock diff, test group 유지와 production bundle 제외 설정을 확인한다. Security 전체 green과 rubyzip 3.x를 사용하는 Selenium의 기존 browser/system smoke를 human verification으로 남긴다. Production dependency 범위 변경, Selenium/Ruby/Rails 일괄 업데이트와 무관한 dependency 정리는 제외한다.

## 2. Student ↔ User principal session boundary

### 문제와 기존 invariant

`StudentSessionsController#create`는 성공 시 `sign_out(:user)`와 `reset_session` 후 Student keys를 설정한다. 반대 방향의 `TeacherSessionsController#create`, `Users::SessionsController#create`에는 Student 정리가 없다. Warden의 sign-in 시 session renewal은 application session keys 삭제가 아니다.

`ApplicationController#pundit_user`는 `current_user || current_student`를 사용한다. 이 우선순위가 Student principal 제거를 대신하지 않는다. 이 항목은 authorization 우회 증명이 아니라 **동일 browser session의 principal isolation invariant**다.

기준 HEAD의 명시적 Devise logout은 기본 `sign_out_all_scopes = true`와 Warden 전체 session reset을 따른다. 다만 `expire_ineligible_teacher_session`의 `sign_out(:user)`는 scoped logout이고 Student keys를 보존한다. 정상 logout 뒤 재등장을 이미 재현했다고 기록하지 않는다.

### 변경 범위

두 User 인증 성공 경계에서 기존 `clear_student_session` 책임을 재사용해 Student principal을 제거한다. 정리 대상은 `student_id`, `student_login_classroom_id`, `student_last_seen_at`과 memoized `@current_student`다. Redirect helper 한 곳만 고쳐 forced-password 분기를 빠뜨리지 않는다.

### Acceptance criteria

- Student → active Teacher, eligible planning manager, Admin 성공 로그인 직후 세 keys와 cached Student가 모두 없다. 후속 request에서도 Student로 판단되지 않는다.
- Temporary password로 인증되어 forced-password 화면으로 가는 Teacher도 같은 정리를 먼저 완료한다.
- 이후 명시적 User logout 또는 Teacher 자격 상실로 scoped sign-out되어도 이전 Student가 다시 나타나지 않는다. Student 기능은 새 PIN 인증을 요구한다.
- 단순 User 로그인 화면 방문이나 잘못된 비밀번호/throttled 인증 실패는 성공한 principal 전환으로 취급하지 않는다. 기존 유효 Student session을 불필요하게 파괴하지 않는다.
- User → Student 성공 전환의 기존 reset, Student TTL/PIN/token/lifecycle, User rate limit, landing과 forced-password 계약을 유지한다. 지원되는 HTML/Turbo request에서 동일하다.

### Regression protection / non-goals

`spec/requests/teacher_sessions_spec.rb`, `users/sessions_spec.rb`, `student_sessions_spec.rb`의 기존 scenario를 보존한다. 새 회귀는 실제 PIN 로그인 → password 로그인 → 후속 request/logout 순서로 keys와 접근 결과를 검증한다. 테스트 helper `sign_in`만으로 인증 성공 경계를 대체하지 않는다. 새 인증 모델, session-version framework, 권한 확대는 제외한다.

## 3. Production Docker DB preparation

### 문제와 기존 계약

`bin/docker-entrypoint`는 `./bin/rails server`일 때만 `db:prepare`를 실행하지만 `Dockerfile`과 `compose.prod.yml`은 Puma 직접 실행을 기본값으로 쓴다. Dockerfile의 entrypoint DB 준비 설명과 실제 기본 boot가 일치하지 않는다.

[OCI runbook](../ops/deploy_oci.md)은 최초 준비와 migration이 있는 재배포에 수동 `bin/rails db:prepare`를 이미 명시한다. 따라서 기존 수동 절차를 따르면 준비할 수 있지만, 새 web image 시작 자체의 보장은 없다.

### 변경 범위

현재 single web-container Starter의 기본 boot 경로를 entrypoint와 맞춘다. 우선 실제 Puma command를 entrypoint의 DB 준비 대상으로 인식하는 작은 수정으로 해결하며, Dockerfile/compose command를 불필요하게 변경하지 않는다. 후속 구현 때 `docs/ops/deploy_oci.md`와 필요 시 `production_checklist.md`에 자동 준비 계약을 맞춘다.

### Acceptance criteria

- Dockerfile 기본 CMD 및 compose web 기본 command 모두 Puma 시작 전에 같은 새 image의 `bin/rails db:prepare`를 실행한다.
- 빈 DB에는 schema를 준비하고 기존 DB에는 pending migration을 적용한다. 준비 성공 후에만 Puma가 요청을 받는다.
- 준비 실패는 nonzero exit이며 Puma를 실행하지 않는다. 원인은 container log로 확인할 수 있다.
- 이미 준비된 DB의 재시작은 데이터 삭제/초기화 없이 성공한다. 기존 Rails server entry도 준비 동작을 유지한다.
- 명시적 console/shell/task command에 자동 preparation을 무조건 끼워 넣지 않는다. 직접 `bin/rails db:prepare`를 실행하면 그 task만 한 번 실행한다.
- 최종 server는 기존 `exec` signal 전달을 유지한다. `app:bootstrap`은 최초 관리자 생성 전용이고 일반 boot에서 자동 실행하지 않는다.
- Runbook의 수동 preflight preparation은 허용하지만 새 image web boot의 자동 보장을 대신하는 필수 수작업으로 남기지 않는다. 기존 backup/rollback 절차는 유지한다.

### Regression protection / non-goals

후속 검증은 실제 기본 command의 호출 순서·실패 시 server 미실행을 확인하고, 격리한 production-like DB에서 최초 boot/pending migration/restart smoke를 수행한다. 실제 운영 DB로 실패 주입을 하지 않는다. Multi-replica release job, 배포 플랫폼 교체, migration reversal과 자동 데이터 복구는 제외한다.

## 4. Individual Teacher login_id immutability

### 문제와 기존 계약

[UX polish §2](final_starter_ux_polish.md#2-teacher-login-id-표시)의 persisted individual edit read-only 계약은 `app/views/teachers/_form.html.erb`에 반영되어 있다. 그러나 `TeachersController#update_params`는 `login_id`를 허용하고 `normalized_profile_attributes`를 거쳐 save에 전달한다.

[Teacher bulk의 Bulk row update](teacher_bulk_management.md#bulk-row-update)는 name/login ID/grade/Classroom 수정을 명시적으로 허용하며 `Teachers::BulkUpdater`도 이를 구현한다. 두 surface는 구분한다.

### 변경 범위와 acceptance criteria

- `TeachersController` individual update permitted params에서 `login_id`를 제외한다. Authorized PATCH/PUT에 변조 값이 있어도 persisted login ID는 그대로이며 나머지 허용 profile/assignment 수정은 기존 규칙을 따른다.
- Active/planning individual edit 모두 적용한다. Return context나 bulk에서 넘어온 개별 edit도 individual update라는 계약을 유지한다.
- Individual create의 login ID 입력·정규화·중복 검증은 유지한다.
- Authorized bulk update의 login ID 수정·정규화·중복 거부·전체 transaction rollback은 그대로 유지한다.
- Archived/inactive/cross-School/unauthorized mutation은 기존 정책대로 거부한다.

### Regression protection / non-goals

`spec/requests/teachers_spec.rb`의 기존 read-only form example에 더해 저장 값 보존 request를 보호한다. `spec/requests/teacher_bulk_management_spec.rb`, `spec/services/teachers/bulk_updater_spec.rb`의 허용된 bulk 변경 계약도 유지한다. Model-wide `attr_readonly`, DB immutability constraint, bulk login ID 변경 금지는 제외한다.

## 5. Admin email 변경 re-authentication

### 문제와 기존 계약

`Users::RegistrationsController#update_resource`는 password fields가 비어 있으면 `current_password`를 제거하고 `update_without_password`를 호출한다. Devise의 이 경로는 email도 저장하므로 Admin authentication identifier를 password 확인 없이 바꿀 수 있다.

[Annual auth의 Teacher email](annual_teacher_auth_authority_cutover.md#teacher-email)은 Admin email required/authentication, Teacher email optional contact/profile data를 구분한다. `User.find_for_database_authentication`도 Admin email lookup만 수행한다. 이름/gender/avatar의 passwordless self profile update와 별도 password 변경 시 current-password 검증은 기존 request spec의 계약이다.

### 변경 범위

기존 `Users::RegistrationsController`와 실제 `app/views/users/registrations/edit.html.erb`에서 Admin email 변경만 재인증한다. 현재 공용 account form의 email `required: true`는 Admin required / Teacher optional로 구분하는 것을 이번 hardening 구현 범위에 포함한다. Teacher email surface는 유지한다. 필요한 사용자 문구는 locale key로 제공한다. 새 인증 흐름이나 계정 관리 계층을 만들지 않는다.

### Acceptance criteria

- Admin email은 required authentication identifier다. 저장될 email이 실제 변경될 때 current password를 요구한다. 누락·오류 시 email과 같은 제출의 다른 profile 값 모두 저장하지 않고 기존 edit에 validation error를 표시한다.
- 올바른 current password와 유효한 새 email이면 저장되고 기존 account edit 복귀/session 계약을 유지한다. 이후 Admin 인증에는 새 email을 사용하며 이전 email로는 인증되지 않는다.
- Email 미제출 또는 기존 Devise 정규화 후 동일한 email 제출은 재인증 요구를 새로 만들지 않는다. 새 normalization 정책은 도입하지 않는다.
- Email을 바꾸지 않는 이름/gender/avatar 변경은 passwordless다. Avatar role pool과 parameter filtering은 재인증 분기에서도 우회되지 않는다.
- Teacher email은 authentication identifier가 아닌 optional contact/profile data로 유지하며 self profile의 email surface를 제거하지 않는다.
- Teacher는 email 없이도 profile을 저장할 수 있어야 한다. 공용 account form의 required 동작을 role별로 구분하고 서버도 기존 Teacher email optional 계약을 유지한다.
- Teacher email 입력·변경은 기존 일반 profile update처럼 current password를 새로 요구하지 않는다. 기존 Teacher email 데이터를 자동 삭제하거나 migration하지 않으며 Teacher email login을 도입하지 않는다.
- 별도 password endpoint와 profile endpoint의 password 변경은 기존 current-password 검증을 유지한다. HTML/Turbo 오류 렌더링과 성공 복귀도 유지한다.

### Regression protection / non-goals

`spec/requests/users/registrations_spec.rb`에 Admin email 변경의 누락/오류/성공, 동일 email의 passwordless update와 원자적 실패를 추가한다. 기존 Teacher/Admin profile/avatar/password/signup 차단 scenario는 유지한다. `users/sessions_spec.rb`의 Admin 전용 email 인증도 보호한다. Email confirmation/recovery/mail delivery, Teacher email login, contact data 자동 삭제, login ID 변경 기능은 제외한다.

Teacher email field 유지와 role별 required 표시, email 없는 Teacher profile 저장, current password 없는 Teacher email 입력·변경도 회귀 검증에 포함한다.

## 6. Planning rollover manager fail-closed

### 문제와 기존 invariant

[Planning B9/B10](planning_year_bootstrap.md#rollover-eligibility)은 manager exactly one과 구조 안전성을 요구하고, 인증 불가능한 비정상 manager row는 rollover transaction에서 fail closed하도록 명시한다. Preparation 현황과 lifecycle boolean을 일반 준비 checklist로 만들지 않는 계약도 유지한다.

현재 `SchoolYears::RolloverEligibility`는 role 기준 count만 검사한다. `SchoolYears::Rollover`는 School/SchoolYear lock 뒤 이 결과만 사용하므로 유일한 manager가 inactive이거나 credential이 비어 있어도 transition 방어가 없다. `active_for_authentication?`만으로는 login ID/digest 상태까지 검증되지 않는다.

### 변경 범위

기존 eligibility query와 rollover transaction의 defensive validation을 강화한다. Normal operation authority, manager designation, informational preparation counts와 `User` authentication predicate의 의미는 바꾸지 않는다. 판정은 derived state로 유지한다.

이 검증은 rollover transaction의 최소 defensive precondition이다. Manager exactly one 확인 후 target planning SchoolYear의 유일한 manager만 대상으로 active 여부와 현재 인증 구조에 필요한 `login_id`/password digest의 구조적 사용 가능성만 fail-closed로 확인한다. 모든 Teacher row를 검사하거나 generic User/Teacher credential integrity framework, 별도 범용 audit subsystem 또는 재사용 목적의 인증 가능성 검사 서비스를 만들지 않는다. 실제 password 인증이나 credential 재발급을 수행하지 않고, production DB constraint를 완화하거나 기존 User authentication predicate의 의미를 전역적으로 변경하지 않는다. Test를 위해 구현 세부사항에 강하게 결합된 abstraction도 새로 만들지 않는다.

### Acceptance criteria

- Manager count는 해당 SchoolYear의 Teacher manager 전체를 센다. Active scope로 비정상 row를 숨겨 `exactly one`을 통과시키지 않는다.
- Manager 0명/2명 이상은 기존대로 거부한다. 정확히 1명이어도 inactive 또는 현재 인증 구조상 사용 불가능한 row면 실행 가능으로 판정하지 않는다.
- 최소 방어 사례는 inactive manager, 누락/공백 또는 기존 login lookup의 정규화와 맞지 않는 login ID, 누락/공백 또는 기존 BCrypt가 해석할 수 없는 password digest다. Credential plaintext를 요구하거나 실제 로그인·password 재발급을 수행해서 검사하지 않는다.
- 정상 temporary credential의 `password_change_required: true`는 인증 실패가 아니다. 최초 password 변경을 아직 마치지 않았다는 이유로 rollover를 막지 않는다. Teacher email, grade, Classroom, assignment 부재도 blocker가 아니다.
- Existing School/SchoolYear structural validation을 유지하고, 실행 시 lock 이후 현재 manager 상태를 다시 읽어 검증한다. 사전 화면의 eligible 결과만 신뢰하지 않는다.
- 인증 불가능 manager면 기존 domain failure 경로와 localized 오류로 종료한다. Parser exception을 500으로 노출하거나 manager를 자동 활성화/교체/수정하지 않는다.
- 실패 시 이전 active/target planning status와 User/assignment/credential event 등 기존 데이터는 그대로다. 두 status transition의 atomicity를 유지한다.
- 유효 manager 1명만 있고 Classroom/HomeroomAssignment가 0개인 최소 planning은 여전히 전환 가능하다. Preparation UI를 새 readiness checklist로 바꾸지 않는다.

### Regression protection / non-goals

`spec/services/school_years/rollover_eligibility_spec.rb`, `rollover_spec.rb`에서 비정상 fixture의 rejection, 정상 temporary credential과 최소 planning 성공, lock 이후 재검증과 rollback을 보호한다. `spec/requests/school_rollovers_spec.rb`에서는 기존 global-admin-only 경계와 실패 안내를 보존한다. Inactive/빈 digest 등은 test에서만 validation을 우회해 구성한다. Login ID canonical form과 manager uniqueness는 기존 DB constraint도 보호하므로, DB가 금지하는 corruption 사례를 위해 production constraint를 완화하지 않고 필요한 query 단위 test double로 검증한다. 기존 scenario를 삭제·약화하지 않는다. 모든 Teacher 데이터의 generic integrity audit, 신규 lifecycle/ready flag, force override와 recovery는 제외한다.

## 7. Dead/stale artifacts cleanup

### 문제와 기존 계약 / 도달 경로 증거

| 후보 | 기준 HEAD의 근거 | 후속 처리 제안 |
|---|---|---|
| `app/views/devise/registrations/edit.html.erb` | `config/routes.rb`가 `users/registrations`로 연결한다. Custom edit과 inherited update 실패는 custom controller의 `users/registrations` prefix에서 `app/views/users/registrations/edit.html.erb`를 먼저 찾는다. Devise `_prefixes`는 이 기본 lookup을 유지한다. App/config/spec 내 후보의 명시적 render 참조는 없다. 기존 avatar-choice request assertions도 custom view의 동작을 대상으로 한다. | 현재 routes의 HTML account edit/update 실패에서 선택되지 않는 fallback override로 삭제 후보. 실제 custom edit과 password view는 보존. |
| `app/views/devise/registrations/new.html.erb` | Public signup routes는 존재하나 custom `disable_public_registration!`가 `new/create` 전에 redirect한다. GET/POST signup 차단 tests가 이미 있으며 후보의 명시적 render 참조는 없다. | 현재 public signup에서 도달 불가하므로 삭제 후보. Route/controller 차단은 그대로 보존. |
| `docs/specs/avatar_default_custom_upload.md` | 학생을 User로 전제하고 `default_avatar_index`, custom upload 우선 렌더링을 요구한다. 현재 schema는 User/Student `avatar_key`, helper는 preset asset lookup이며 Student canonical은 custom upload를 제외한다. Account request tests도 upload field 미노출을 검증한다. 현재 canonical/architecture/ops/testing 문서에서 이 파일로 향하는 참조는 검색되지 않았다. | 현재 canonical로 쓰기에는 stale. 삭제보다 `docs/archive/avatar_default_custom_upload.md`로 이동하고 historical/superseded 표시를 추가하는 후보. |

### 변경 범위와 acceptance criteria

- 이 spec에서는 후보 파일을 삭제·이동하지 않는다. 후속 cleanup run은 위 두 view 삭제와 구 avatar 문서 archive만 대상으로 목록을 먼저 제시한다.
- Cleanup revision에서 route/controller/template lookup과 명시적 참조를 다시 확인한다. Runtime의 실제 참조가 발견되면 그 후보 처리를 멈춘다.
- Account edit GET과 validation 실패 렌더링은 계속 실제 custom view에서 작동해야 한다. Admin 재인증 UI와 Teacher/Admin preset avatar 선택, 별도 password modal도 유지한다.
- Public signup GET은 계속 차단되고 POST는 User를 생성하지 않는다. Template 삭제를 signup 차단 수단으로 삼지 않는다.
- Archived 문서는 현재 설계가 아님을 명시하고 이 spec 및 `student_model_migration.md`의 현재 avatar 계약으로 연결한다. 이동으로 생기는 참조가 있으면 해당 링크만 수정한다.
- Avatar preset/role pool/fallback과 현재 저장 데이터는 그대로 유지한다.

### Regression protection / non-goals

`spec/requests/users/registrations_spec.rb`의 signup/profile/avatar/password example과 `spec/helpers/users_helper_spec.rb`를 보존한다. Template 삭제를 이유로 test를 삭제하지 않는다. Active Storage framework/schema 제거, asset 정리, 전체 stale docs 탐색과 새 avatar canonical 재설계는 제외한다.

## Human review와 후속 run 경계

1. Human review로 이 spec의 acceptance criteria를 확정했다. 각 항목의 구현은 후속 독립적인 작은 run으로 진행하며 같은 의미 있는 feature branch를 유지한다. 이번 run에서는 구현하지 않는다.
2. Teacher self email은 optional contact/profile field 유지로 확정했다. Role별 required 동작 수정은 hardening 구현 범위이며, Teacher email 입력·변경은 passwordless로 유지하고 기존 데이터를 자동 삭제·migration하지 않는다.
3. 정상 logout의 Student 복귀와 CI의 과거 실패/skip은 이번 실행 재현으로 주장하지 않는다. 세션 회귀 tests와 실제 Security 전체 green은 구현 완료 증거로 별도 확보한다.
4. 각 run은 관련 scenario만 추가/보완하며 기존 권한·오류·lifecycle assertion을 유지한다. Test 삭제·통합·약화가 필요해지면 별도 검토한다.
5. 이번 문서 작업의 확인은 `git diff --check`다. 후속 targeted RSpec/CI/container/browser 검증은 사용자에게 인계하며 결과가 없으면 완료했다고 기록하지 않는다.

공통 non-goals: Planning SchoolYear 취소, Planning Student roster/preparation, rollover reversal/recovery, archived Teacher login, historical reporting UX, rollover force override, 신규 인증 구조, generic management context, Tailwind/filter abstraction, 대형 refactor, unrelated cleanup/dependency update.
