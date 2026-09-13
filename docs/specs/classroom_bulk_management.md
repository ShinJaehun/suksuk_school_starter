# Classroom bulk management

## Canonical ownership and surface

이 문서는 School Starter의 active/planning Classroom bulk management primary canonical contract다. 기존 `/classrooms` 카드·상세·settings·member·Student 흐름은 변경하지 않는다. Bulk UI는 `/admin/classrooms`에만 존재하며 `admin` namespace는 global-admin-only authority를 뜻하지 않는다.

`planning_year_bootstrap.md`는 planning lifecycle과 governance를 계속 소유한다. 이 문서는 Classroom bulk UI, 입력, transaction, validation과 HomeroomAssignment final-state 계약을 소유한다.

## Authority and context

- Global admin: 명시적으로 선택한 active School의 active/exact planning SchoolYear에서 mutation, archive read-only
- Current operational manager: 자기 School active 기본, active/exact planning mutation, archive read-only
- Eligible planning manager: 자기 exact planning 기본, 자기 School active/exact planning mutation, archive read-only
- Ordinary Teacher와 다른 School actor: deny

기존 `Classrooms::ManagementContext`와 `ClassroomPolicy`가 authority source다. Malformed, unpaired, cross-School, unauthorized SchoolYear는 fallback 없이 fail closed한다. School lifecycle, rollover, manager designation과 Student authority는 확대하지 않는다.

## Reference UI

`suksuk_class_vote` main의 Classroom management UI를 source로 사용한다. Starter School/SchoolYear selector 아래에 전체/1~6학년 tabs, inline grade/class_label/담임 table, 학생 수, 상태/action, 모두 선택, 선택 수, 학년 배정, active lifecycle controls, 교실 생성·여러 교실 생성·변경 저장을 같은 구조와 Tailwind/Stimulus interaction으로 제공한다. Archived context는 mutation control 없는 read-only 목록이다.

Navigation은 기존 교실 메뉴를 유지하고 허용 actor에게 `교실 일괄 관리` → `/admin/classrooms`를 별도로 노출한다.

## Common transaction boundary

Create/update/operator는 각각 하나의 outer transaction이다. Server는 하나의 resolved SchoolYear만 신뢰하며 row별 School/SchoolYear, active와 Student payload를 받지 않는다. 각 service는 1..30 boundary, normalize, scoped resource resolution, batch/DB duplicate, deterministic lock과 모든 final state를 검증한 뒤 write한다. 한 row라도 invalid면 전체 rollback하며 partial success는 없다.

Mutable context는 active School의 active 또는 exact planning SchoolYear뿐이다. Submitted Classroom/Teacher ID는 resolved SchoolYear association scope에서만 resolve한다.

## Bulk create

Row는 `grade`, `class_label`, optional `teacher_id`다. Classroom은 resolved SchoolYear의 active record로 생성한다. `Classroom`의 trim/`반` suffix normalization과 `(school_year_id, grade, class_label)` uniqueness가 canonical source이며 normalized batch duplicate와 DB duplicate를 전체 거부한다.

Optional Teacher는 같은 SchoolYear의 active Teacher이고 grade가 일치하며 current HomeroomAssignment가 없어야 한다. 동일 Teacher를 두 row에 배정할 수 없다. 모든 validation 후 Classroom과 assignment를 저장한다. Active assignment 시작일은 `Date.current`, planning은 해당 연도 3월 1일이다. Student는 생성·수정하지 않는다.

## Bulk update and assignment exchange

Active Classroom row에서 grade, class_label과 final Teacher를 변경한다. Inactive Classroom row는 표시하지만 수정하지 않는다. 모든 Classroom ID는 current context scope에 있어야 한다.

Final state는 Classroom/Teacher same SchoolYear, active Teacher, grade 일치, Teacher/Classroom current assignment 최대 하나, batch 밖 assignment 탈취 금지를 만족해야 한다. 동일 final Teacher를 둘 이상의 Classroom이 선택할 수 없다. Final class label uniqueness도 batch 전체와 DB outside batch를 기준으로 검증한다.

같은 batch의 담임 swap/cycle은 지원한다. 관련 Classroom, Teacher와 current assignment를 ID 순서로 lock하고 final state를 검증한 뒤 변경 assignment를 모두 release하고 Classroom fields를 저장한 다음 새 assignment를 만든다. 동일 assignment는 churn하지 않는다.

- Active: 기존 assignment `ended_on = Date.current`, 새 assignment `started_on = Date.current`
- Planning: 기존 preparation assignment 삭제, 새 assignment `Date.new(school_year.year, 3, 1)`

Classroom grade를 바꿀 때 final Teacher grade가 자동 변경되지는 않는다. 유지/교체할 Teacher가 final grade와 다르면 거부하며, 사용자는 담임을 해제하거나 matching Teacher를 선택해야 한다.

## Bulk operations

지원 operation은 `assign_grade`, `activate`, `deactivate`다.

- `assign_grade`: 1..6만 허용. 모든 target이 active이며 current assignment가 없어야 한다. Final class-label uniqueness를 검증하고 하나라도 불가하면 전체 실패한다.
- `activate`/`deactivate`: active context에서만 제공하고 모든 target에 기존 `ClassroomPolicy#reactivate?`/`deactivate?`를 write 전에 적용한다.
- Planning: create, inline structure/assignment update와 assign_grade만 허용한다. lifecycle operation은 거부한다.
- Archive: 모든 mutation을 거부한다.

Delete는 bulk operation이 아니다. Row action은 기존 `ClassroomPolicy#destroy?`, `PlanningClassrooms::Destroy`와 Classroom의 Student/HomeroomAssignment history restriction을 그대로 사용한다.

## Students and non-goals

학생 수는 기존 association count로 표시한다. Classroom bulk는 Student를 생성·수정·이동·삭제하지 않는다. 기존 `/classrooms` redesign, Student bulk, migration, `Classroom#teacher_id`, SchoolMembership, CSV/upload, background job, generic bulk framework와 Teacher bulk refactor는 범위 밖이다.

## Acceptance criteria

1. `/classrooms` 기존 카드와 개별 관리 flow에는 bulk table/control이 없다.
2. `/admin/classrooms`에서 허용 actor가 context selector와 reference bulk UI를 사용한다.
3. Manager defaults, active/planning 선택, archive read-only와 cross-School fail-closed가 유지된다.
4. Create 1..30과 update/operator는 전체 선검증·lock·원자 저장한다.
5. Normalized class label, Teacher scope/grade/assignment와 final uniqueness가 보존된다.
6. Active history 및 planning preparation semantics로 swap/cycle이 성공하고 외부 assignment 탈취는 실패한다.
7. Planning lifecycle과 archive mutation은 거부된다.
8. Student data와 기존 governance/ordinary Teacher authority는 변경되지 않는다.
