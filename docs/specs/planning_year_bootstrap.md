# Planning-year teacher/classroom bootstrap

## 목적

이 문서는 active SchoolYear를 건드리지 않고 다음 planning SchoolYear의 annual teacher User, Classroom과 HomeroomAssignment를 준비하는 Phase B canonical spec이다.

예를 들어 2026 active와 2027 planning이 함께 있을 때 허용된 actor는 2027 준비 data만 명시적으로 생성·수정할 수 있다. Planning은 rollover 전 staging이자 safety boundary이며 별도 SchoolYear dashboard나 독립된 제품 hierarchy를 만들지 않는다.

## 전제

- Phase A의 current operational teacher/manager 의미와 School별 SchoolYear context resolver가 구현되어 있다.
- Target School은 active이고 active SchoolYear와 planning SchoolYear가 각각 정확히 하나 존재한다.
- Planning SchoolYear는 current active SchoolYear의 바로 다음 학년도다.
- Teacher User와 Classroom의 `school_year_id`는 생성 후 변경하지 않는다.
- `/teachers`와 `/classrooms`는 active-year canonical surface로 유지한다.
- Planning teacher는 credential을 준비할 수 있지만 planning 상태에서는 normal runtime login을 할 수 없다.
- Planning Student 준비, rollover, reversal, archived authentication과 historical UI는 이 phase 밖이다.

## Actor/authority matrix

| Operation | Global admin | Current operational manager | 그 밖의 actor |
|---|---|---|---|
| SchoolYear context 조회 | 모든 School의 planning/active/archived | 자기 School의 current active와 바로 다음 planning, 기존 historical 계약의 archived read-only | Ordinary teacher는 자기 operational year 범위, planning teacher는 불가, archived actor는 별도 historical 계약 |
| Planning teacher member bulk create | 모든 active School | 자기 School | 불가 |
| Planning teacher member edit/deactivate/reactivate/credential reissue | 모든 active School | 자기 School | 불가 |
| Planning manager 지정·교체·해제 및 manager account mutation | 모든 active School | 불가 | 불가 |
| Planning Classroom bulk create/edit/deactivate/reactivate | 모든 active School | 자기 School | 불가 |
| Planning HomeroomAssignment 연결·변경·해제 | 모든 active School | 자기 School | 불가 |

여기서 current operational manager는 active User, active SchoolYear, active School과 annual manager role을 모두 만족하는 actor다. Planning 또는 archived annual account에 manager role이 있어도 preparation authority를 얻지 않는다.

Manager용 operation은 session actor의 annual School로 scope를 고정한다. Global admin은 명시적인 School에서 시작하되 School과 planning SchoolYear의 관계를 server-side로 resolve한다. UI control의 노출 여부와 무관하게 모든 write boundary에서 actor authority, School ownership과 planning status를 재검증한다.

같은 `/teachers`, `/classrooms` surface라도 mutation 가능성은 선택된 SchoolYear status와 actor authority에 따라 policy에서 구분한다. Active는 기존 operation 계약, planning은 이 문서에서 허용한 준비 mutation, archived는 read-only다. Planning teacher는 준비 대상일 뿐 context를 선택하거나 운영하는 actor가 아니다.

## Surface와 navigation

School overview의 `다음 학년도 준비` 영역은 다음 상태를 제공한다.

- `2027학년도 준비 중`
- 활성 planning teacher 수
- 활성 planning Classroom 수
- 현재 담임 연결 수 / 활성 planning Classroom 수
- Planning manager 확정 여부와, 제안이 있다면 후임 manager 후보 상태
- `선생님 준비`, `교실 준비`, `담임 연결` 진입점

분모와 개수는 해당 School의 유일한 planning SchoolYear에 속한 활성 row만 사용한다. 현재 담임 연결 수는 활성 teacher와 활성 Classroom을 잇는 `ended_on IS NULL` assignment만 센다. Planning context가 없거나 유효하지 않으면 active 또는 archived context로 fallback하지 않는다.

준비 카드는 별도 planning dashboard로 연결하지 않는다. `선생님 준비`, `교실 준비`, `담임 연결`은 기존 `/teachers`, `/classrooms`와 그 자연스러운 담임 관리 흐름을 명시적인 planning SchoolYear context로 연다. Planning 전용 `/planning/teachers`, `/admin/teachers`, `/admin/classrooms` CRUD와 lifecycle별 controller/view 복제는 만들지 않는다.

기본 `/teachers`, `/classrooms` 진입은 계속 current active SchoolYear다. Planning 또는 archived context는 사용자가 권한 안에서 School과 SchoolYear를 명시적으로 선택한 경우에만 사용한다. URL의 SchoolYear id만 신뢰하지 않고 actor에게 허용된 School의 server-side SchoolYear scope에서 status와 ownership을 함께 확인한다. 선택이 없거나 유효하지 않으면 planning/archived로 추측하거나 fallback하지 않는다.

## Planning teacher bulk contract

한 요청은 한 School의 하나의 planning SchoolYear에 여러 annual teacher User를 생성한다. Active teacher를 이동·복제하지 않으며 이름, `login_id`, email 또는 avatar로 다른 연도의 동일 인물을 추론하지 않는다.

각 row의 입력은 다음과 같다.

- 이름
- `login_id`
- grade 1..6
- optional gender와 avatar 선택

`school_year_id`, role, `school_role`, active 상태와 credential field는 client 입력으로 받지 않는다. Server가 teacher role, resolved planning SchoolYear, active account와 `school_role: member`를 지정한다. `login_id` normalization과 SchoolYear-scoped uniqueness, 이름·grade·gender·avatar validation은 기존 User 계약을 따른다. Avatar는 현재 teacher 생성의 허용 pool과 기본 선택 정책을 재사용하며 active-year User의 avatar를 복사하지 않는다.

Global admin과 manager의 초기 bulk 모두 member teacher만 생성한다. Manager 지정·교체·해제는 bulk row option으로 섞지 않고 별도의 global-admin-only planning manager operation으로 분리한다. 이로써 manager용 payload 조작으로 `school_role: manager`를 만들 수 없고 두 actor가 같은 member 생성 operation을 공유할 수 있다.

## Planning manager designation

Planning manager 지정은 teacher bootstrap 뒤의 별도 단계다.

- Global admin만 resolved planning SchoolYear의 active annual teacher를 manager로 지정할 수 있다.
- 기존 planning manager가 있으면 같은 transaction에서 member로 내리고 새 manager를 지정한다.
- 해제는 planning year에 manager가 0명인 준비 상태를 만들 수 있다. 이는 rollover 전에는 허용되지만 rollover readiness를 만족하지 않는다.
- Manager role의 partial unique DB constraint를 최종 방어선으로 유지한다.
- Current operational manager의 teacher bootstrap 및 homeroom 권한은 planning manager designation이나 manager account mutation 권한을 포함하지 않는다.

Source manager를 복제하거나 destination manager로 자동 지정하지 않는다.

Current operational manager는 active planning member 중 한 명을 후임 manager 후보로 제안하거나 제안을 변경·해제할 수 있다. 제안은 planning SchoolYear 안의 준비 정보이며 `school_role`을 변경하거나 manager authority, login authority 또는 rollover readiness를 부여하지 않는다. Global admin은 제안을 참고할 수 있지만 이에 구속되지 않고 별도 confirmation으로 최종 manager role을 지정한다. 정확한 proposal persistence와 audit 형태는 manager succession 구현 단위에서 정한다.

## Temporary credential contract

각 새 planning teacher는 기존 `AnnualTeacherUsers::TemporaryCredential` 계약으로 temporary password, `password_change_required`와 `TeacherCredentialEvent`를 함께 만든다. 새 credential framework나 평문 저장소를 만들지 않는다.

- Batch의 모든 teacher row와 credential audit event는 하나의 outer transaction 안에서 성공해야 한다.
- 모든 row를 normalization·validation하고 batch 내부 및 DB의 duplicate를 확인한 뒤 credential을 발급한다.
- 한 row의 teacher 또는 audit event 저장이 실패하면 batch 전체를 rollback한다.
- Plaintext temporary password는 DB, audit event, log, flash/session 또는 재조회 가능한 페이지에 저장하지 않는다.
- 성공한 batch의 모든 temporary password는 commit된 결과에서 한 번만 표시한다.
- 결과 응답은 기존 individual credential 결과처럼 `Cache-Control: no-store`를 적용한다.
- 결과 페이지를 refresh하거나 뒤로 가기 해도 plaintext를 재구성하거나 다시 표시하지 않는다. 분실 시 허용된 actor가 명시적으로 재발급한다.
- Outer transaction이 rollback된 경우 이미 생성했던 in-memory password를 응답에 포함하지 않는다.

기존 credential service의 내부 transaction은 outer transaction에 참여할 수 있지만, 현재 active-year `Teachers::SaveWithAssignment`는 active SchoolYear lookup과 단일-row assignment 흐름을 결합하므로 planning batch를 위해 `active OR planning`으로 확장하지 않는다.

## Planning Classroom bulk contract

한 요청은 한 School의 하나의 planning SchoolYear에 여러 Classroom을 생성한다. 각 row는 grade 1..6과 `class_label`을 가진다.

- `school_year_id`, School id, active 상태와 student login token은 client가 결정하지 않는다.
- Server가 resolved planning SchoolYear와 active 상태를 지정한다.
- `class_label` trimming 및 `반` suffix normalization, 길이·형식 validation과 `(school_year_id, grade, class_label)` uniqueness를 기존 Classroom 계약과 DB index에서 재사용한다.
- Active year의 Classroom을 복사하거나 동일 label을 근거로 연결하지 않는다.
- Batch 내부에서 normalization 후 같은 grade/label이 중복되면 DB write 전에 각 row 오류로 보고한다.

Teacher bulk와 Classroom bulk는 서로 별개의 transaction이다. 둘 중 하나를 먼저 완료해야 다른 하나를 생성할 수 있다는 domain precondition은 두지 않는다.

## HomeroomAssignment contract

Teacher와 Classroom 준비 뒤 별도의 `담임 연결` 단계에서 planning HomeroomAssignment를 관리한다. Teacher/Classroom 생성 batch에 담임 입력을 강제하지 않는다.

- Teacher와 Classroom은 모두 같은 resolved planning SchoolYear에 속해야 한다.
- Teacher와 Classroom은 active이고 target School도 active여야 한다.
- Teacher grade와 Classroom grade가 일치해야 한다.
- 동일 teacher와 동일 Classroom은 각각 current assignment를 최대 하나만 가진다.
- Active 또는 archived year의 id는 planning picker와 mutation scope에 포함하지 않는다.
- Planning assignment의 `started_on`은 calendar current date가 아니라 해당 SchoolYear의 3월 1일이다.
- Planning assignment는 아직 실제 운영 이력이 아니다. 연결 변경은 기존 planning assignment를 삭제하고 새 assignment를 만드는 작업을 하나의 transaction으로 수행한다.
- Planning 중 해제는 기존 planning assignment를 삭제하며 `ended_on` history를 만들지 않는다.
- 이미 같은 연결이면 row를 다시 만들지 않는 idempotent success로 처리할 수 있다.

한 요청에 여러 연결을 제출하는 UI를 사용한다면 모든 mapping을 선검증하고 전체를 하나의 transaction으로 처리한다. 한 건씩 저장하는 UI도 동일한 operation을 한 row batch로 호출할 수 있다. 정확한 picker와 layout은 implementation phase에서 현재 UI 패턴에 맞춘다.

## Planning data edit/remove semantics

Planning은 수정 가능한 준비 context지만 archived data처럼 보존이 필요한 audit/history와 구분한다.

### Teacher

- 허용된 actor는 planning member teacher의 이름, `login_id`, grade, gender와 avatar를 수정할 수 있다.
- Grade 변경이 current planning assignment와 불일치하면 거부한다. 먼저 담임을 변경·해제해야 한다.
- Product의 `준비에서 제외`는 hard delete가 아니라 `User.active = false`로 처리한다. 같은 transaction에서 current planning assignment를 먼저 삭제한 뒤 User를 비활성화하여 account/credential audit를 보존하고 비활성화 hook이 `ended_on` history를 만들지 않게 한다.
- `재포함`은 같은 annual User를 다시 활성화한다. 이전 plaintext를 다시 노출하지 않으며 새 temporary credential을 발급하고 audit event를 남긴 경우에만 성공한다.
- Credential 재발급은 기존 credential을 즉시 무효화하고 새 temporary credential과 audit event를 한 transaction에서 만든다. 일회성 표시/no-store 계약을 동일하게 적용한다.
- Current operational manager는 자기 School의 planning member만 수정·비활성화·재활성화·재발급할 수 있다. Planning manager account의 profile, lifecycle, credential과 role은 global admin만 변경한다.

### Classroom

- 허용된 actor는 planning Classroom의 grade와 `class_label`을 수정할 수 있다.
- Grade 변경이 current planning assignment와 불일치하면 거부한다. 먼저 담임을 변경·해제해야 한다.
- Product의 `준비에서 제외`는 hard delete가 아니라 `Classroom.active = false`로 처리한다. 같은 transaction에서 current planning assignment를 먼저 삭제한 뒤 Classroom을 비활성화한다.
- `재포함`은 같은 planning Classroom row를 다시 활성화하며 uniqueness와 School/planning status를 다시 검증한다.
- Student 또는 다른 참조가 생겨도 product UI에서 hard delete하지 않는다. Existing restrict-with-error 관계를 우회하지 않는다.

### HomeroomAssignment

- Planning 연결 변경과 해제는 current row를 삭제하며 ended history를 만들지 않는다.
- Rollover로 SchoolYear가 active가 된 뒤에는 해당 assignment가 실제 운영 이력이므로 planning 삭제 semantics를 적용하지 않는다.
- Planning SchoolYear가 active 또는 archived로 바뀐 stale form은 mutation하지 못한다.

## Transaction, locking과 atomicity

각 teacher batch, Classroom batch, assignment batch, teacher lifecycle/credential operation과 manager designation은 독립된 transaction boundary다.

- Request 시작 시 actor와 explicit School을 authorize하고 planning context를 server-side로 resolve한다.
- Transaction 안에서 target School과 planning SchoolYear를 deterministic하게 lock한다.
- Lock 이후 actor가 여전히 global admin인지 또는 그 School의 current operational manager인지, School이 active인지, SchoolYear가 여전히 그 School의 유일한 planning context인지 재검증한다.
- 관련 persisted teacher, Classroom, current HomeroomAssignment와 manager row는 id 순서 등 deterministic order로 필요한 범위만 lock한다.
- Batch 전체를 선검증한 뒤 저장하며 한 row라도 실패하면 전체 rollback한다.
- DB unique constraint 위반은 성공으로 간주하거나 부분 결과로 바꾸지 않고 batch failure로 변환한다.
- 실패한 batch는 teacher, Classroom, credential event, planning assignment 변경과 plaintext result를 일부라도 남기지 않는다.

Teacher batch와 Classroom batch 사이의 전체 wizard transaction은 만들지 않는다. 사용자는 각 성공 단계를 저장한 뒤 다음 준비 작업을 진행한다.

## Row validation, error와 duplicate handling

- 모든 field가 비어 있는 row는 batch 입력에서 제외한다. 하나 이상의 field만 입력된 불완전한 row는 validation error로 처리한다.
- 오류는 row 번호와 field를 식별할 수 있게 반환하되 다른 School의 resource 존재 여부를 노출하지 않는다.
- Normalization 후 batch 내부 duplicate와 target planning SchoolYear의 existing row duplicate를 모두 검사한다.
- Duplicate `login_id` 또는 Classroom grade/label이 있으면 기존 row를 update하거나 skip하지 않는다.
- Retry 시 이미 저장된 batch를 성공으로 오인하지 않는다. 중복은 명시적 실패이며 사용자가 existing planning data를 확인해 수정한다.
- 입력 순서와 상관없이 모든 유효 row만 저장하는 partial success는 허용하지 않는다.

## Cross-School/cross-year defense

- SchoolYear는 form field나 hidden parameter로 신뢰하지 않고 authorized School의 planning relation에서 resolve한다.
- Manager가 다른 School id를 URL, query, nested parameter 또는 record id로 제출해도 자기 current operational School 밖으로 scope를 넓히지 못한다.
- Teacher, Classroom과 HomeroomAssignment id는 resolved planning SchoolYear의 association scope에서 조회한다.
- Submitted `school_year_id`, `school_id`, `role`, `school_role`, active/status 또는 credential field는 permit하지 않는다.
- Global admin도 School과 SchoolYear가 일치하지 않거나 target이 planning이 아니면 실패한다.
- Stale form 처리 시 다른 SchoolYear로 fallback하지 않는다. 같은 `/teachers`·`/classrooms` surface를 사용하더라도 request마다 선택된 context와 현재 권한을 다시 확인한다.

## Acceptance criteria

1. Global admin은 모든 active School, current operational manager는 자기 School의 planning teacher/Classroom/HomeroomAssignment만 준비할 수 있다.
2. Ordinary, planning, archived와 inactive teacher 및 non-operational manager는 planning preparation authority를 얻지 못한다.
3. Teacher bulk는 member annual User만 만들고 기존 active teacher를 이동·복제하지 않는다.
4. Manager designation/교체/해제와 planning manager account mutation은 teacher bulk와 분리된 global-admin-only operation이다. Current operational manager의 후보 제안은 role이나 readiness를 변경하지 않는다.
5. Teacher batch의 모든 row와 credential audit event가 한 transaction에서 commit되거나 전체 rollback된다.
6. 성공한 temporary passwords만 no-store 결과에서 한 번 표시되고 평문은 저장·재표시되지 않는다.
7. Classroom bulk는 resolved planning SchoolYear에만 새 row를 만들고 기존 normalization, validation과 unique DB index를 유지한다.
8. Teacher와 Classroom bulk는 normalization 후 batch 내부 및 existing planning data duplicate를 명시적으로 거부하며 partial success나 implicit update를 하지 않는다.
9. HomeroomAssignment는 같은 planning SchoolYear, 같은 grade, active participants와 current uniqueness를 요구하고 cross-year 연결을 거부한다. `started_on`은 해당 SchoolYear의 3월 1일이며 planning 중 변경·해제는 기존 row를 삭제해 ended history를 만들지 않는다.
10. Planning teacher/Classroom 생성과 담임 연결은 단계적으로 분리되며 School overview가 활성 teacher 수, 활성 Classroom 수, 담임 연결 현황과 manager 준비 상태 및 entry를 제공한다.
11. Planning teacher의 준비 제외는 assignment 삭제 후 deactivation, 재포함은 새 temporary credential 발급과 함께 원자적으로 수행하며 account/credential audit를 보존한다.
12. Planning Classroom의 준비 제외는 assignment 삭제 후 deactivation이며 재포함은 같은 row를 활성화하고 restrict-with-error 관계를 우회하지 않는다.
13. 모든 mutation은 lock 이후 authority, active School, planning context와 record ownership을 재검증하고 DB conflict를 포함한 실패에서 기존 active year와 planning data를 보존한다.
14. URL, hidden field와 nested parameter 조작으로 School, SchoolYear, role, lifecycle 또는 credential scope를 바꿀 수 없다.
15. `/teachers`와 `/classrooms`의 기본 진입은 active year를 유지한다. 명시적으로 선택되고 server-side로 승인된 planning/archived SchoolYear context에서 같은 surface를 재사용하며 archived mutation은 허용하지 않는다.
16. Planning bootstrap은 Student 생성, rollover readiness 실행, rollover 또는 archived authentication을 수행하지 않는다.

## Non-goals

- Route, controller, model, policy, service, view와 migration 구현
- `/teachers`, `/classrooms`의 기본 active-year context 또는 lifecycle별 policy 의미 변경
- Planning 전용 `/planning/teachers`, `/admin/teachers`, `/admin/classrooms`와 lifecycle별 controller/view 복제
- Active teacher, Classroom, HomeroomAssignment의 자동 복제·승계
- Student planning registration, roster, PIN 또는 login
- Planning teacher normal login
- Manager용 `/admin/*` 개방
- Generic batch/workflow/state-machine/context framework
- Permanent Teacher identity 또는 연도별 User 자동 연결
- Rollover readiness 실행, rollover, reversal/recovery와 UI
- Archived read-only UI, archived login과 historical reporting

## 후속 phase와의 경계

Phase B는 다음의 작은 implementation 단위로 나눈다.

1. B1 — shared SchoolYear context authorization과 School overview status/entry
2. B2 — 기존 `/teachers`의 explicit planning context와 member teacher bulk create/one-time credential result
3. B3 — 같은 teacher surface의 planning edit/deactivate/reactivate 및 credential reissue
4. B4 — 후임 manager 후보 제안과 global-admin-only 최종 designation
5. B5 — 기존 `/classrooms`의 explicit planning context와 bulk create/edit/deactivate/reactivate
6. B6 — 같은 SchoolYear context 안의 planning HomeroomAssignment 연결·변경·해제

각 단위는 focused spec과 human verification을 거친다. 기본 query에 planning을 섞지 않고 explicit SchoolYear context를 별도로 resolve하며 lifecycle별 controller/view를 복제하지 않는다. B1에서 generic dashboard를 만들지 않는다.

Student preparation은 Classroom과 teacher/assignment 계약이 안정된 뒤 별도 human-reviewed bounded phase로 진행한다. Archived read-only enforcement는 rollover보다 먼저 구현한다. Rollover는 destination manager를 포함한 readiness, confirmation, locking과 atomic transition을 별도 canonical spec에서 확정한 뒤에만 진행한다.
