# Teacher bulk management

## Status and canonical ownership

이 문서는 School Starter의 active/planning 공통 Teacher bulk management에 대한 primary canonical contract다. `planning_year_bootstrap.md`는 planning SchoolYear의 lifecycle, preparation authority, assignment history 의미와 rollover/governance 경계를 계속 소유하며, Teacher bulk의 공통 UI, 입력, transaction, validation과 credential 결과 계약은 이 문서가 소유한다.

Reference UI는 `ShinJaehun/suksuk_class_vote` main의 현재 Teacher bulk 구현이다. School Starter는 reference의 화면 구조, 문구, 버튼 배치, Tailwind class와 Stimulus interaction을 가능한 한 그대로 이식한다. 다만 `SchoolMembership`, membership grade와 `Classroom#teacher_id` 기반 persistence는 가져오지 않고 annual Teacher `User`, `User#school_year`, `User#grade`와 `HomeroomAssignment`로 구현한다.

## Purpose

Global admin과 자기 School의 operational manager가 기존 `/teachers` School/SchoolYear context에서 여러 annual Teacher를 안전하게 생성·수정하거나 lifecycle/grade operation을 수행할 수 있게 한다. Bulk는 single Teacher operation을 대체하는 별도 domain이 아니며 기존 authority, annual identity, credential audit와 assignment lifecycle을 우회하지 않는다.

## Reference UI contract

다음 reference UI와 interaction을 새로 디자인하지 않는다.

- `app/views/teachers/bulk_setup.html.erb`: School/context, 학년과 1~30명 인원 선택, 최대 30명 안내, `여러 선생님 추가` 진입
- `app/views/teachers/bulk_new.html.erb`: 이름, 로그인 ID, 학년, 담당 반 row table, row 제외, 현재 인원 표시와 중복 submit 방지
- `app/views/teachers/_school_management.html.erb`: `전체 / 1~6학년 / 미배정` 탭과 management table 배치
- `app/views/teachers/_bulk_edit_table.html.erb`: 모두 선택, 선택 인원 표시, name/login ID/grade/Classroom inline edit, 상태와 credential action, 선택 작업 영역, `선생님 추가`, `여러 선생님 추가`, `변경 사항 저장`
- `app/views/teachers/_bulk_status.html.erb`와 `_bulk_password_action.html.erb`: 기존 lifecycle/credential action을 table row에 배치하는 구조
- `app/javascript/controllers/teacher_bulk_controller.js`: 학년별 Classroom filtering, 변경 field/row highlighting, 모두 선택, selection count, operation button 상태, inactive row 동기화와 create submit-once
- `app/views/teachers/credentials.html.erb`와 reference `credential-list` Stimulus interaction: 이름, 로그인 ID, 임시 비밀번호, 행별 복사, 전체 복사, 인쇄와 일회성 확인 안내

Reference의 inactive Teacher row는 table에 표시하되 profile/grade/Classroom edit field를 disabled 상태로 둔다. Row 선택은 가능하며 허용된 activate/deactivate operation은 server policy가 최종 판정한다. Active row는 reference와 같이 변경된 field와 row를 amber 계열 style로 강조한다.

Starter의 기존 SchoolYear selector, context title, read-only 안내와 authority surface는 outer layout으로 유지한다. 그 내부 management 영역만 reference UI로 교체·확장한다. Reference의 School-only parameter와 route는 Starter의 `{ school_id, school_year_id }` context-preserving parameter로 치환한다. 사용자 표시 문구는 reference의 한국어와 의미를 유지하되 Starter locale key로 제공한다.

Archived context에서는 Teacher 목록을 현재 read-only 형식으로 조회할 수 있지만 bulk setup, inline editable table, selection operation, create/update/lifecycle control을 렌더링하지 않는다.

## Context resolution

모든 Teacher bulk endpoint는 기존 `Teachers::ManagementContext`를 사용한다. 별도 School/SchoolYear resolver나 generic bulk context를 만들지 않는다.

- Global admin은 명시적으로 선택한 active School과 active 또는 planning SchoolYear에서 bulk operation을 수행한다. Bulk mutation endpoint에서는 School과 SchoolYear가 모두 명시되어야 한다.
- Current operational manager의 기본 `/teachers` context는 자기 School active SchoolYear다.
- Eligible planning manager의 기본 `/teachers` context는 자기 exact immediate planning SchoolYear다.
- 두 manager는 자기 School active와 exact immediate planning context를 명시적으로 선택해 bulk operation을 수행할 수 있다.
- Archived, inactive School, cross-School, non-immediate planning, malformed, unpaired 또는 unauthorized context에는 mutation control이 없고 direct mutation request도 fallback 없이 fail closed한다.
- Submitted Teacher와 Classroom id는 resolved SchoolYear association scope 안에서만 찾는다. 다른 School 또는 SchoolYear resource의 존재 여부를 오류 메시지로 구분해 노출하지 않는다.

## Authority matrix

| Actor / context | Bulk create | Bulk row update | assign grade | activate/deactivate |
| --- | --- | --- | --- | --- |
| Global admin / selected active | allow | allow | allow | allow, per-target lifecycle policy 적용 |
| Global admin / selected planning | allow | allow | allow | allow, planning lifecycle protection 적용 |
| Global admin / archive | deny | deny | deny | deny |
| Current manager / own active | allow | allow | allow | allow, self-protection 적용 |
| Current manager / own exact planning | allow | allow | allow | allow, planning manager target protection 적용 |
| Current manager / own archive | deny | deny | deny | deny |
| Eligible planning manager / own active | allow | allow | allow | allow, self-protection 적용 |
| Eligible planning manager / own exact planning | allow | allow | allow | allow, planning manager target protection 적용 |
| Eligible planning manager / own archive | deny | deny | deny | deny |
| Either manager / other School | deny | deny | deny | deny |
| Ordinary teacher | deny | deny | deny | deny |

Bulk authority는 `TeacherManagementPolicy`, `UserPolicy`와 현재 School-operation authority를 최종 기준으로 사용한다. Bulk row로 manager를 지정·교체·해제할 수 없으며 School lifecycle, SchoolYear governance, rollover와 generic `/admin/*` 권한은 확대하지 않는다.

## Common input boundary

한 request는 정확히 하나의 resolved SchoolYear만 대상으로 한다. Row마다 School 또는 SchoolYear를 선택할 수 없다.

Create/update row가 받는 business field는 다음과 같다.

- `name`
- `login_id`
- `grade`: 미배정 또는 1..6
- optional `classroom_id`: 미배정 또는 resolved SchoolYear의 active Classroom

Bulk create UI에는 reference에 없는 gender/avatar field를 추가하지 않는다. Starter의 single-create는 gender가 없어도 유효하며 avatar가 제출되지 않으면 teacher role의 허용 pool에서 server-side 기본값을 선택한다. Bulk create도 같은 server-side 기본 정책을 사용한다. Active-year User의 gender/avatar를 추론하거나 복사하지 않는다.

Client에서 다음 값을 받거나 신뢰하지 않는다.

- row별 `school_id` 또는 `school_year_id`
- `role`, `school_role`, `active`
- password, password confirmation, `password_change_required`
- credential generation 또는 audit field

Server는 create row마다 resolved SchoolYear, `role: teacher`, `school_role: member`, `active: true`를 지정한다. Payload에 보호 field가 있어도 permit하지 않으며 manager role mutation으로 해석하지 않는다.

모든 field가 비어 있는 create row는 입력에서 제외할 수 있다. 하나 이상의 field만 있는 불완전한 row는 row/field가 식별되는 validation error다. 정규화 후 유효 row는 1명 이상 30명 이하여야 하며 controller나 client의 count를 신뢰하지 않고 service boundary에서 다시 검사한다. Update와 selection operation도 빈 batch를 거부한다.

## Bulk create

Active와 planning create는 동일한 UI와 application boundary를 사용한다.

- Active context에서는 선택된 active Classroom에 기존 active HomeroomAssignment contract로 선택적으로 연결한다.
- Planning context에서는 선택된 planning Classroom에 기존 planning preparation contract로 선택적으로 연결한다. `started_on`은 해당 SchoolYear의 3월 1일이며 Student data는 만들지 않는다.
- Classroom 미선택은 grade만 가진 Teacher 또는 grade도 없는 미배정 Teacher를 만든다.
- 모든 create target은 member Teacher다. Manager designation은 별도 governance flow다.

Bulk create는 하나의 outer transaction에서 다음 순서를 따른다.

1. context와 actor authority를 resolve한다.
2. 모든 row를 정규화하고 1..30 boundary를 검사한다.
3. request 내부 normalized `login_id` duplicate와 Classroom duplicate를 모든 해당 row에 표시한다.
4. resolved SchoolYear의 existing Teacher `login_id` duplicate를 검사한다.
5. submitted Classroom을 resolved SchoolYear의 active Classroom scope에서 resolve하고 id 순서로 lock한다.
6. Teacher/Classroom grade 일치, Classroom 점유 여부와 모든 User/HomeroomAssignment validation을 저장 전에 검사한다.
7. 모든 row가 유효한 경우에만 Teacher, credential event와 assignment를 저장한다.
8. 한 row, credential event 또는 assignment라도 실패하면 전체 batch를 rollback한다.

부분 성공, duplicate row skip, existing Teacher implicit update와 retry의 idempotent success 처리는 하지 않는다.

## Bulk row update

Reference table과 같이 active Teacher row에서 name, login ID, grade와 Classroom을 한 번에 제출한다. Inactive row의 edit field와 id field는 disabled이며 bulk row update 대상이 아니다. Inactive Teacher 변경은 먼저 authorized activate operation을 완료한 뒤 수행한다.

- Submitted Teacher id는 resolved SchoolYear의 authorized Teacher scope에 모두 포함되어야 한다.
- Update row는 SchoolYear, role, `school_role`, active, credential, gender 또는 avatar를 변경하지 않는다.
- Name/login ID/grade/Classroom의 final target state를 전체 batch 기준으로 먼저 검증한다.
- Request 내부와 DB의 normalized login ID duplicate를 거부한다.
- 동일 target Classroom을 둘 이상의 final row가 선택하면 모든 관련 row를 거부한다.
- 다른 Teacher가 점유한 Classroom은 그 occupant가 같은 submitted batch에서 해당 Classroom을 명시적으로 떠나는 경우에만 target이 될 수 있다.
- Batch 밖 Teacher가 점유한 Classroom을 탈취하지 않는다.
- Teacher와 Classroom은 같은 resolved SchoolYear이고 grade가 일치하며 둘 다 assignment 가능한 lifecycle 상태여야 한다.
- Inactive Classroom에 연결된 기존 Teacher는 single-edit invariant와 같이 name/login ID만 그대로 보존 가능한 범위에서 다루며, bulk table에서 grade/Classroom 변경이나 해제를 허용하지 않는다. 해당 row를 일반 editable row로 제출하지 않는 방향을 우선한다.

### Classroom exchange and assignment lifecycle

같은 batch에 포함된 Teacher 사이의 Classroom 교환과 순환 이동을 지원한다. 구현은 generic assignment engine을 만들지 않고 bulk updater 내부에서 final target map을 검증한다.

1. Submitted Teacher, target Classroom과 관련 current HomeroomAssignment를 id 순서로 lock한다.
2. Duplicate target, batch 외 occupant, SchoolYear/grade/lifecycle 불일치가 없는 final state를 전부 검증한다.
3. 기존 assignment 중 final target과 달라지는 row를 먼저 모두 해제한다.
4. 새 current assignment를 deterministic order로 생성한다.

Active SchoolYear에서 해제되는 assignment는 기존 single-edit와 같이 `ended_on = Date.current` history로 보존하고 새 assignment는 `started_on = Date.current`로 만든다. Planning SchoolYear에서는 기존 current preparation assignment를 삭제하고 새 assignment를 해당 SchoolYear 3월 1일 시작일로 생성하며 ended history를 만들지 않는다. 동일 Teacher/Classroom 연결은 row를 churn하지 않는다. 어느 단계라도 실패하면 profile, grade와 모든 assignment 변경을 rollback한다.

## Selection operations

Reference UI와 같이 `assign_grade`, `activate`, `deactivate`만 허용한다. Operation name, grade와 Teacher id 형식을 server-side에서 validate하며 duplicate id와 빈 선택을 거부한다. 모든 target은 resolved SchoolYear authorized scope에서 resolve하고 id 순서로 lock한다.

### assign_grade

이 operation에는 Classroom final target 입력이 없으므로 current HomeroomAssignment가 있는 Teacher의 grade를 추측하거나 assignment를 자동 해제하지 않는다. 모든 selected Teacher가 active이고 current assignment가 없어야 하며, 하나라도 그렇지 않으면 전체 batch를 실패시킨다. 미배정 또는 1..6만 허용하고 성공 시 assignment와 다른 profile field는 변경하지 않는다.

Assignment가 있는 Teacher의 grade와 Classroom을 함께 변경하거나 명시적으로 해제하려면 bulk row update를 사용한다.

### activate

모든 selected Teacher에 대해 `UserPolicy#reactivate_teacher?`와 context scope를 저장 전에 검사한다. Target은 inactive여야 하며 하나라도 active, archived, cross-School/cross-year 또는 unauthorized이면 전체 batch를 실패시킨다. 성공 시 Teacher만 active로 만들고 과거/삭제된 HomeroomAssignment를 복원하거나 credential을 재발급하지 않는다.

### deactivate

모든 selected Teacher에 대해 `UserPolicy#deactivate_teacher?`와 context scope를 저장 전에 검사한다. Target은 active여야 하며 다음 보호를 유지한다.

- actor self-deactivation 금지
- planning manager Teacher가 manager인 동안 deactivation 금지
- archived Teacher mutation 금지
- cross-School/cross-year target 금지

하나라도 operation 불가이면 assignment를 포함한 전체 batch를 변경하지 않는다. 성공 시 User의 기존 lifecycle callback을 우회하지 않는다. Active assignment는 `ended_on = Date.current`로 종료하고 planning preparation assignment는 삭제하며 자동 재배정은 하지 않는다.

## Transaction, locking and validation

Create, row update와 selection operation은 각각 독립된 하나의 outer transaction이다.

- Context authorization은 controller에서 수행하고 service도 resolved SchoolYear와 scoped resources만 입력받는다.
- Transaction 안에서 target SchoolYear, Teacher, Classroom과 current HomeroomAssignment를 필요한 범위에서 id 순서로 lock한다.
- 모든 row와 batch-level invariant를 저장 전에 검증한다.
- DB uniqueness/foreign-key 충돌은 전체 실패로 처리한다.
- 실패 응답은 row 번호와 field를 식별할 수 있지만 다른 School/SchoolYear resource의 존재 여부는 노출하지 않는다.
- 실패 후 화면에는 submitted value와 row error를 유지하되 persisted record와 assignment는 transaction 전 상태를 표시한다.
- Generic bulk framework, configurable operation engine 또는 shared assignment state machine을 만들지 않는다.

## Temporary credential result

Bulk create는 기존 `AnnualTeacherUsers::TemporaryCredential`을 사용해 각 Teacher password, `password_change_required`와 `TeacherCredentialEvent(action: temporary_password_issued)`를 만든다. 각 내부 credential transaction은 outer batch transaction에 참여해야 하며 result failure를 반드시 전체 rollback으로 전파한다.

- Plaintext temporary password는 DB, credential event, log, flash, session 또는 재조회 가능한 URL에 저장하지 않는다.
- 모든 Teacher와 audit event가 commit된 후 성공 batch의 in-memory credential만 결과 화면에 전달한다.
- Rollback된 Teacher의 password는 일부라도 응답에 포함하지 않는다.
- 결과 응답은 `Cache-Control: no-store`와 Turbo cache 방지를 적용한다.
- 이름, 로그인 ID, 임시 비밀번호, 행별 복사, 전체 복사, 인쇄와 “화면 이탈 후 다시 확인할 수 없음” 안내는 reference `credentials.html.erb` UI를 그대로 따른다.
- Refresh, back 또는 결과 URL 재접속으로 plaintext를 재구성하거나 다시 표시하지 않는다. 분실 시 기존 authorized reissue flow를 사용한다.

Starter의 단건 `temporary_password.html.erb`와 bulk credentials table은 같은 credential 보안 원칙과 가능한 locale 문구를 공유할 수 있지만, 이번 기능을 위해 generic credential framework나 plaintext 저장소를 만들지 않는다.

## Acceptance criteria

1. Teacher index의 기존 School/SchoolYear selector 바깥 구조는 유지되고 editable active/planning context 내부에는 reference의 학년 탭과 bulk edit table이 표시된다.
2. `전체 / 1~6학년 / 미배정`, 모두 선택, 선택 인원, 변경 highlighting, Classroom filtering, inactive row 표현과 선택 작업 UI가 reference와 같은 흐름으로 동작한다.
3. Global admin은 명시적으로 선택한 active School의 active 또는 planning SchoolYear에서 bulk를 수행할 수 있다.
4. Current manager와 eligible planning manager는 자기 School active와 exact immediate planning context에서 bulk를 수행할 수 있다.
5. Ordinary teacher, 다른 School, archive, inactive School, malformed와 unauthorized SchoolYear context는 mutation control이 없고 direct request도 fail closed한다.
6. Bulk create는 1..30 member annual Teacher만 만들며 protected field injection으로 manager/admin 또는 다른 SchoolYear User를 만들 수 없다.
7. Gender/avatar input은 bulk UI에 추가하지 않고 server-side single-create 기본 avatar 정책을 적용한다.
8. Active와 planning create 모두 optional matching Classroom을 HomeroomAssignment로 연결하며 Student data를 만들지 않는다.
9. 모든 create row를 선검증하고 duplicate login ID/Classroom, occupied/foreign/wrong-grade Classroom 또는 credential audit failure 시 Teacher/event/assignment가 하나도 남지 않는다.
10. Bulk row update는 authorized current context Teacher만 수정하며 inactive row와 injected Teacher id를 거부한다.
11. Grade/Classroom 동시 변경, 명시적 해제와 같은-batch Classroom 교환은 active/planning 각각의 assignment history semantics로 원자 처리된다.
12. Batch 밖 Teacher의 Classroom은 탈취하지 않는다.
13. `assign_grade`는 모든 target이 active이며 current assignment가 없을 때만 전체 성공한다.
14. Activate/deactivate는 모든 target policy를 선검증하며 self-deactivation, planning manager target protection과 archive 금지를 우회하지 않는다.
15. 한 target이라도 invalid/unauthorized이면 create/update/operation의 어떤 row도 부분 저장되지 않는다.
16. 성공한 bulk create credential만 no-store 결과 화면에서 한 번 표시되며 DB/log/flash/session에는 plaintext가 없다.
17. Existing single Teacher flow, ordinary Teacher의 담당 Classroom authority, manager designation, SchoolYear governance와 rollover 권한은 변경되지 않는다.

## Non-goals

- Classroom 또는 Student bulk 변경
- Manager 지정·교체·해제
- SchoolYear creation/rollover/recovery
- Cross-year Teacher identity 연결 또는 active Teacher의 planning 복제
- CSV import/export와 spreadsheet upload
- Background job
- Generic bulk/assignment/authorization framework
- `SchoolMembership` 또는 `Classroom#teacher_id`
- Planning Student/member data 또는 operation
- Role enum 변경, manager의 admin 승격 또는 generic `/admin/*` 개방
- UI redesign

## Expected implementation surface

예상 파일은 구현 승인 후 실제 구조를 다시 좁게 확인한다.

- Routes와 `TeachersController` bulk actions
- `TeacherManagementPolicy` 및 필요하면 bulk-specific policy query
- 기존 `Teachers::ManagementContext` 사용부
- `Teachers::BulkCreator`, `Teachers::BulkUpdater`, `Teachers::BulkOperator`
- Teacher index preparation과 context-preserving path 구성
- Reference 기반 `bulk_setup`, `bulk_new`, `_school_management`, `_bulk_edit_table`, `_bulk_status`, `_bulk_password_action`, `credentials` views
- Reference 기반 `teacher_bulk_controller.js`, `credential_list_controller.js`
- 기존 locale에 Teacher bulk 문구 추가
- Focused service, policy와 request specs

DB schema와 migration 변경은 예상하지 않는다.

