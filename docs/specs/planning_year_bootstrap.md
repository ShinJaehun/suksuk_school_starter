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
| Classroom 단건 create | 선택한 active School의 active/planning SchoolYear | 자기 active School의 current active와 바로 다음 planning SchoolYear | 불가 |
| Planning Classroom edit/deactivate/reactivate | 모든 active School | 자기 School | 불가 |
| Planning Teacher의 HomeroomAssignment 단건 연결·변경·해제 | 선택한 active School의 planning SchoolYear | 자기 active School의 바로 다음 planning SchoolYear | 불가 |

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

준비 카드는 별도 planning dashboard로 연결하지 않는다. `선생님 준비`와 `담임 연결`은 기존 `/teachers`, `교실 준비`는 기존 `/classrooms`를 명시적인 planning SchoolYear context로 연다. Planning 담임 연결은 active-year UX와 같이 `/teachers` context에서 Teacher 설정으로 진입해 관리하며, planning `/classrooms`는 담임 정보를 표시할 수 있지만 변경 form을 제공하지 않는다. Planning 전용 `/planning/teachers`, `/admin/teachers`, `/admin/classrooms` CRUD와 lifecycle별 controller/view 복제는 만들지 않는다.

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

## Planning Classroom single-create contract

Planning Classroom 준비의 기본 경로는 별도 planning surface나 bulk 전용 workflow가 아니다. 기존 `/classrooms/new`와 `POST /classrooms`를 명시적인 School/SchoolYear context와 함께 재사용하여 한 번에 하나의 Classroom을 생성한다.

- Global admin은 선택한 active School의 active 또는 planning SchoolYear에 생성할 수 있다.
- Current operational manager는 자기 School의 current active SchoolYear와 바로 다음 planning SchoolYear에 생성할 수 있다.
- Ordinary teacher와 그 밖의 actor는 Classroom을 생성할 수 없다.
- Archived SchoolYear에는 actor와 관계없이 생성할 수 없다.
- Explicit `school_id`와 `school_year_id`는 client가 제출하는 context일 뿐 authority source가 아니다. Server가 actor의 authorized School scope에서 School을 resolve하고 SchoolYear의 School 소속, 허용 status와 manager의 바로 다음 planning year 조건을 매 request에서 다시 확인한다.
- Malformed id, School과 SchoolYear가 다른 조합, actor scope 밖의 School, 허용되지 않은 SchoolYear와 archived context는 다른 active/planning year로 fallback하지 않고 fail closed한다.
- Planning context에서 생성된 Classroom의 `school_year_id`는 server가 선택·승인한 planning SchoolYear로 지정한다. Active year의 Classroom을 복사하거나 동일 label을 근거로 연결하지 않는다.
- `class_label` trimming 및 `반` suffix normalization, 길이·형식 validation과 `(school_year_id, grade, class_label)` uniqueness는 기존 Classroom 계약과 DB index를 재사용한다.
- Validation 또는 persistence가 실패하면 선택한 School과 SchoolYear context를 form에 유지한다. 실패를 이유로 active SchoolYear로 돌아가거나 다른 year를 추측하지 않는다.
- Planning 생성 성공 후에는 해당 School과 planning SchoolYear가 선택된 `/classrooms` context로 복귀한다.
- 기존 active-year Classroom 생성 동작과 inactive School에 대한 validation/error 응답 계약은 유지한다.
- Planning Classroom 생성에서는 Student나 HomeroomAssignment를 함께 생성·복사·연결하지 않는다. Teacher 준비와 Classroom 준비 사이에도 선행 순서 precondition을 두지 않는다.

여러 Classroom을 한 번에 생성하는 bulk workflow는 현재 canonical 필수 경로가 아니다. 필요성이 별도로 확인되면 단건 생성 계약을 우회하지 않는 optional enhancement로 다시 specification하고 승인받는다.

## HomeroomAssignment contract

Teacher와 Classroom 준비 뒤 기존 `/teachers` surface의 명시적인 planning SchoolYear context에서 Teacher 한 건의 설정 화면으로 진입해 HomeroomAssignment를 연결·변경·해제한다. 별도 planning route/controller/view나 bulk assignment workflow를 만들지 않으며, Teacher bulk나 Classroom 단건 생성에 담임 입력을 강제하지 않는다. Planning `/classrooms`에서는 현재 담임 정보를 표시할 수 있지만 담임 변경 form은 제공하지 않는다.

- Teacher와 Classroom은 모두 같은 resolved planning SchoolYear에 속해야 한다.
- Teacher와 Classroom은 active이고 target School도 active여야 한다.
- Teacher grade가 존재하고 Classroom grade와 일치해야 한다. Planning Teacher의 grade는 해당 planning SchoolYear의 예정 담당 학년이다.
- 동일 teacher와 동일 Classroom은 각각 current assignment를 최대 하나만 가진다.
- Classroom 후보는 resolved planning SchoolYear에서 active이고 Teacher grade와 같은 Classroom이다. 다른 Teacher의 current assignment에 이미 사용된 Classroom은 후보와 mutation scope에서 제외하되, 현재 이 Teacher에게 연결된 Classroom은 선택 상태 유지를 위해 후보에 포함한다.
- 담당 학년이 아직 정해지지 않아 grade가 없는 planning Teacher는 HomeroomAssignment를 만들 수 없다. 학년 미정은 cross-grade 연결을 허용하는 사유가 아니라 아직 담임 미배정인 준비 상태다.
- Planning Teacher 설정은 기존 active Teacher의 `teacher-classroom-picker` UX를 재사용한다. 사용자가 `membership_grade`를 바꾸면 별도 저장 없이 같은 화면에서 해당 grade의 planning Classroom 후보를 즉시 다시 불러오고, Classroom을 선택한 뒤 최종 저장 한 번으로 grade와 HomeroomAssignment를 함께 반영한다. Grade를 먼저 저장하고 edit 화면에 다시 진입하게 요구하지 않는다.
- Classroom 후보 조회 request도 기존 explicit School/SchoolYear와 Teacher context를 보존하고 server-side authorization과 ownership/status 검증을 다시 통과해야 한다. 다른 Teacher에게 이미 배정된 Classroom은 UI 후보에서 제외하고 직접 제출도 거부하며 기존 담임을 자동 해제하지 않는다.
- Global admin은 명시적으로 선택하고 server-side로 승인된 active School의 planning SchoolYear에서 수행할 수 있다.
- Current operational manager는 자기 active School의 current active SchoolYear 바로 다음 planning SchoolYear에서만 수행할 수 있다.
- Ordinary teacher와 그 밖의 actor는 planning assignment authority를 얻지 못한다.
- School, SchoolYear, Classroom과 teacher id는 모두 actor에게 허용된 planning association scope에서 resolve한다. Malformed, cross-School, cross-year, archived 또는 unauthorized 조합은 다른 context나 row로 fallback하지 않고 fail closed한다.
- Active 또는 archived year의 id는 planning teacher picker와 mutation scope에 포함하지 않는다.
- Planning assignment의 `started_on`은 calendar current date가 아니라 해당 SchoolYear의 3월 1일이다.
- Planning assignment는 아직 실제 운영 이력이 아니다. 연결 변경은 기존 planning assignment를 삭제하고 새 assignment를 만드는 작업을 하나의 transaction으로 수행한다.
- Planning 중 해제는 기존 planning assignment를 삭제하며 `ended_on` history를 만들지 않는다.
- 이미 같은 연결이면 row를 다시 만들지 않는 idempotent success로 처리할 수 있다.
- Active-year의 기존 HomeroomAssignment 연결·변경·해제와 `ended_on` history semantics는 변경하지 않는다. Planning 전용 삭제 semantics가 active operation으로 번지지 않게 별도의 operation boundary를 유지한다.

Planning assignment operation은 한 요청에서 하나의 Teacher를 대상으로 한다. 여러 Teacher의 연결을 한 번에 제출하는 bulk assignment는 현재 canonical workflow가 아니며 필요성이 확인되면 별도 specification과 승인을 거친다. 정확한 Classroom picker와 layout은 기존 Teacher 설정 surface와 현재 UI 패턴에 맞춘다.

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

각 teacher batch, Classroom 단건 생성, planning assignment 단건 operation, teacher lifecycle/credential operation과 manager designation은 독립된 transaction boundary다.

- Request 시작 시 actor와 explicit School을 authorize하고 planning context를 server-side로 resolve한다.
- Transaction 안에서 target School과 planning SchoolYear를 deterministic하게 lock한다.
- Lock 이후 actor가 여전히 global admin인지 또는 그 School의 current operational manager인지, School이 active인지, SchoolYear가 여전히 그 School의 유일한 planning context인지 재검증한다.
- 관련 persisted teacher, Classroom, current HomeroomAssignment와 manager row는 id 순서 등 deterministic order로 필요한 범위만 lock한다.
- Batch operation은 전체를 선검증한 뒤 저장하며 한 row라도 실패하면 전체 rollback한다. Planning assignment 단건 변경도 기존 row 삭제와 새 row 생성을 하나의 transaction으로 처리한다.
- DB unique constraint 위반은 성공이나 implicit update로 간주하지 않고 해당 operation의 실패로 처리한다.
- 실패한 operation은 teacher, Classroom, credential event 또는 planning assignment 변경을 일부라도 남기지 않는다.

Teacher bulk와 Classroom 단건 생성 사이의 전체 wizard transaction은 만들지 않는다. 사용자는 각 성공 단계를 저장한 뒤 다음 준비 작업을 진행한다.

## Row validation, error와 duplicate handling

- Teacher bulk에서 모든 field가 비어 있는 row는 입력에서 제외한다. 하나 이상의 field만 입력된 불완전한 row는 validation error로 처리한다.
- Teacher bulk 오류는 row 번호와 field를 식별할 수 있게 반환하되 다른 School의 resource 존재 여부를 노출하지 않는다.
- Teacher bulk는 normalization 후 batch 내부 duplicate와 target planning SchoolYear의 existing row duplicate를 모두 검사한다.
- Duplicate `login_id`는 기존 row를 update하거나 skip하지 않는다. Classroom 단건 생성의 duplicate grade/label은 기존 Classroom validation과 DB constraint에 따라 실패한다.
- Retry 시 이미 저장된 teacher batch나 Classroom을 성공으로 오인하지 않는다. 중복은 명시적 실패이며 사용자가 existing planning data를 확인해 수정한다.
- Teacher bulk에서 입력 순서와 상관없이 일부 유효 row만 저장하는 partial success는 허용하지 않는다.

## Cross-School/cross-year defense

- SchoolYear와 School id는 explicit query/form context로 전달할 수 있지만 신뢰하지 않고 actor에게 authorized된 School/SchoolYear scope에서 resolve한다.
- Manager가 다른 School id를 URL, query, nested parameter 또는 record id로 제출해도 자기 current operational School 밖으로 scope를 넓히지 못한다.
- Teacher, Classroom과 HomeroomAssignment id는 resolved planning SchoolYear의 association scope에서 조회한다.
- Submitted `school_year_id`와 `school_id`는 Classroom의 mass-assigned attributes로 permit하지 않는다. `role`, `school_role`, active/status 또는 credential field도 permit하지 않는다.
- Classroom 단건 생성의 global admin은 일치하는 active 또는 planning context만 사용할 수 있다. Manager는 자기 School의 current active 또는 바로 다음 planning context만 사용할 수 있다.
- Stale form 처리 시 다른 SchoolYear로 fallback하지 않는다. 같은 `/teachers`·`/classrooms` surface를 사용하더라도 request마다 선택된 context와 현재 권한을 다시 확인한다.

## Acceptance criteria

1. Global admin은 모든 active School, current operational manager는 자기 School의 planning teacher/Classroom/HomeroomAssignment만 준비할 수 있다.
2. Ordinary, planning, archived와 inactive teacher 및 non-operational manager는 planning preparation authority를 얻지 못한다.
3. Teacher bulk는 member annual User만 만들고 기존 active teacher를 이동·복제하지 않는다.
4. Manager designation/교체/해제와 planning manager account mutation은 teacher bulk와 분리된 global-admin-only operation이다. Current operational manager의 후보 제안은 role이나 readiness를 변경하지 않는다.
5. Teacher batch의 모든 row와 credential audit event가 한 transaction에서 commit되거나 전체 rollback된다.
6. 성공한 temporary passwords만 no-store 결과에서 한 번 표시되고 평문은 저장·재표시되지 않는다.
7. Classroom 준비는 기존 `/classrooms/new`와 `POST /classrooms`에서 단건 생성하며, 선택·승인된 active 또는 planning SchoolYear에만 새 row를 만들고 기존 normalization, validation, unique DB index와 inactive-School 실패 계약을 유지한다.
8. Classroom create context의 malformed, cross-School, unauthorized 또는 archived 입력은 fail closed하며 validation 실패 시 선택 context를 유지하고 planning 성공 후 해당 `/classrooms` context로 복귀한다.
9. Planning HomeroomAssignment는 기존 `/teachers` context의 Teacher 설정 화면에서 Teacher 한 건씩 관리한다. 기존 `teacher-classroom-picker`를 재사용하여 grade 변경 즉시 같은 화면에서 planning Classroom 후보를 갱신하고, 최종 저장 한 번으로 grade와 assignment를 함께 반영한다. Picker request는 planning SchoolYear와 Teacher context를 보존하고 server-side scope를 다시 검증한다. Classroom 후보는 같은 planning SchoolYear의 active Classroom이며 Teacher grade와 일치해야 한다. 다른 Teacher의 current assignment에 사용된 Classroom은 제외하고 현재 이 Teacher에게 연결된 Classroom은 유지 후보에 포함한다. Grade가 없거나 Classroom과 grade가 다른 Teacher는 연결할 수 없다. Global admin은 선택한 planning context, current manager는 자기 School의 바로 다음 planning context에서만 수행하고 malformed, cross-School, cross-year, inactive participant, grade mismatch, 이미 다른 Teacher에게 배정된 Classroom, archived와 unauthorized 조합은 fail closed한다. `started_on`은 해당 SchoolYear의 3월 1일이며 planning 중 변경·해제는 기존 row를 삭제해 `ended_on` history를 만들지 않는다. Active-year의 기존 assignment lifecycle과 history semantics는 유지하고 planning `/classrooms`에는 담임 변경 form을 제공하지 않는다.
10. Planning teacher/Classroom 생성과 담임 연결은 단계적으로 분리되며 Classroom 단건 생성은 Student나 담임을 함께 생성·연결하지 않는다. School overview는 활성 teacher 수, 활성 Classroom 수, 담임 연결 현황과 manager 준비 상태 및 entry를 제공한다.
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
- Planning Classroom bulk 전용 workflow. 향후 필요하면 단건 생성 계약을 보존하는 optional enhancement로 별도 specification한다.
- Planning HomeroomAssignment bulk 연결 workflow. 향후 필요하면 Teacher 단건 operation 계약과 active-year history 경계를 보존하는 별도 enhancement로 specification한다.
- Permanent Teacher identity 또는 연도별 User 자동 연결
- Rollover readiness 실행, rollover, reversal/recovery와 UI
- Archived read-only UI, archived login과 historical reporting

## 후속 phase와의 경계

Phase B는 다음의 작은 implementation 단위로 나눈다.

1. B1 — shared SchoolYear context authorization과 School overview status/entry
2. B2 — 기존 `/teachers`의 explicit planning context와 member teacher bulk create/one-time credential result
3. B3 — 같은 teacher surface의 planning edit/deactivate/reactivate 및 credential reissue
4. B4 — 후임 manager 후보 제안과 global-admin-only 최종 designation
5. B5a — 기존 `/classrooms/new`와 `POST /classrooms`의 explicit active/planning context 단건 create
6. B5b — 같은 classroom surface의 planning edit/deactivate/reactivate
7. B6 — 기존 Teacher 설정 surface에서 같은 planning SchoolYear의 HomeroomAssignment 단건 연결·변경·해제

각 단위는 focused spec과 human verification을 거친다. 기본 query에 planning을 섞지 않고 explicit SchoolYear context를 별도로 resolve하며 lifecycle별 controller/view를 복제하지 않는다. B1에서 generic dashboard를 만들지 않는다.

Student preparation은 Classroom과 teacher/assignment 계약이 안정된 뒤 별도 human-reviewed bounded phase로 진행한다. Archived read-only enforcement는 rollover보다 먼저 구현한다. Rollover는 destination manager를 포함한 readiness, confirmation, locking과 atomic transition을 별도 canonical spec에서 확정한 뒤에만 진행한다.
