# Starter SchoolYear Abstraction

## 상태와 목적

**Draft — canonical architecture 후보, 사용자 검토 대기.** 감사 기준은 로컬 `main`의
`139adbc0647d9dcfd5bb5a53b39034e652b24918`이다. 원격 최신성, 실행 중인 DB와 실제 request는
검증하지 않았다. 이 문서는 정적 감사와 원하는 경계를 제안하며 구현 또는 기존 정책 변경을 승인하지 않는다.

목표는 downstream 서비스 개발자가 실제 데이터 owner와 기능 권한을 정의하면, Starter가
SchoolYear lifecycle의 공통 제약을 적용하도록 하는 것이다. SchoolYear storage를 없애거나
연도별 권한을 무시하는 것이 아니다. 사실, 확인된 문제, 제안, 미결정 사항을 구분한다.

현재 runtime은 [Current System](../architecture/current_system.md),
[Roles And Permissions](../architecture/roles_and_permissions.md),
[School/Classroom Boundaries](../architecture/school_classroom_boundaries.md)를 따른다.
장기 구조는 [School Year Architecture](school_year_architecture.md), 현재 preparation과
archive 권한은 [Planning Bootstrap](planning_year_bootstrap.md), rollover는
[Rollover Calendar](school_year_rollover_calendar.md)를 함께 참조한다.

## Current state

### Storage와 현재 public interface

```text
School → SchoolYear → Classroom → Student → downstream data (향후)
                  └→ annual teacher User
Classroom → HomeroomAssignment → annual teacher User
```

- `Classroom.school_year_id`와 persisted teacher `User.school_year_id`는 변경 불가능하다.
  `Student.classroom_id`도 변경 불가능하다. Student와 HomeroomAssignment에는 SchoolYear FK가 없다.
- `Classroom.active`는 교실 자체의 lifecycle이며 School/SchoolYear의 운영 가능성을 뜻하지 않는다.
  `Student.active`, User account active와 SchoolYear status도 독립적이다.
- `User#current_operational_teacher?`, `current_operational_manager?`,
  `school_operations_manager_for?`, `planning_preparation_operator_for?`는 이미 authority 일부를 감싼다.
  `annual_school`은 `school_year.school`의 조회 interface이며 권한을 보장하지 않는다.
- Classroom/Student를 입력받는 일상 운영용 공통 lifecycle interface는 아직 없다.
  `ClassroomPolicy#manage_members?`와 `manage_operations?`가 기존 기능에서 그 일부를 담당한다.

### 현재 의존 관계

| 영역과 근거 | SchoolYear 의존 | 판단 |
|---|---|---|
| [School](../../app/models/school.rb), [SchoolYear](../../app/models/school_year.rb) | active/planning/archive collection, 상태·연도 invariant와 rollover 날짜 | 직접 의존이 정당한 기반 |
| [User](../../app/models/user.rb), [HomeroomAssignment](../../app/models/homeroom_assignment.rb) | annual account/authority, 같은 연도 담임, planning·archive 이력 규칙 | Starter identity/assignment 내부 책임 |
| [Classroom](../../app/models/classroom.rb), [Student](../../app/models/student.rb) | Classroom은 연도 FK·불변성·연도별 반 uniqueness, Student는 Classroom만 참조 | 이미 owner를 통한 context 전달 가능 |
| [Teachers::ManagementContext](../../app/services/teachers/management_context.rb), [Classrooms::ManagementContext](../../app/services/classrooms/management_context.rb) | actor School, 허용 연도, 기본/명시 context, mutation context resolution | 연도별 운영 infrastructure이며 중복 존재 |
| [TeacherManagementPolicy](../../app/policies/teacher_management_policy.rb), [UserPolicy](../../app/policies/user_policy.rb), [SchoolPolicy](../../app/policies/school_policy.rb), [SchoolYearPolicy](../../app/policies/school_year_policy.rb) | annual authority와 School scope, preparation/governance | 직접 의존이 필요한 Starter 정책 |
| [ClassroomPolicy](../../app/policies/classroom_policy.rb), [StudentPolicy](../../app/policies/student_policy.rb) | active School/SchoolYear/Classroom, archive read와 actor 범위 | 일반 운영으로 연결되는 경계에서 lifecycle 조건 반복 |
| `TeachersController`, `ClassroomsController`, `Admin::{Teachers,Classrooms}Controller`, `Classrooms::SettingsController` | context 선택·검증과 annual resource 조회/저장 | 연도별 구조 관리 adapter |
| `SchoolYearsController`, `SchoolPlanningController`, `SchoolRolloversController`, `Admin::{Schools,SchoolManagers}Controller`, `SchoolsController`, `SchoolWorkspacePrepareable` | 생성·준비·전환·manager 지정·연도별 현황 | lifecycle/School 운영 infrastructure |
| [ApplicationController](../../app/controllers/application_controller.rb), [TeacherSessionsController](../../app/controllers/teacher_sessions_controller.rb), [StudentSessionsController](../../app/controllers/student_sessions_controller.rb), `Users::SessionsController` | session eligibility, annual login lookup, landing/navigation/logout context | 인증 infrastructure 내부에서는 정당하나 조건 중복 존재 |
| [ClassroomStudentsController](../../app/controllers/classroom_students_controller.rb) | 재활성화 시 `operational_classroom?`에서 상위 상태 직접 확인 | 일상 기능 controller로 lifecycle 판정이 누출된 예 |
| `Teachers::{SaveWithAssignment,BulkCreator,BulkUpdater,BulkOperator}`, `Classrooms::{BulkCreator,BulkUpdater,BulkOperator}` | target year, active/planning mutation, 같은 연도 후보, assignment 날짜·해제 | annual resource 운영에 정당한 의존; 공통 상태 guard도 반복 |
| `SchoolYears::{CreatePlanning,CancelPlanning,Rollover,RolloverEligibility}`, `Planning{Teachers,Classrooms}::Destroy`, `SchoolStructure::IntegrityAudit` | 직접 상태 전환·준비 삭제·readiness·무결성 검사 | SchoolYear-aware infrastructure |
| [ClassroomStudents::BulkRegistration](../../app/services/classroom_students/bulk_registration.rb), [RosterUpdate](../../app/services/classroom_students/roster_update.rb) | SchoolYear를 직접 참조하지 않고 Classroom에서 Student를 처리 | 분리 가능한 domain의 기존 예; 호출 전 policy에 의존 |
| [Classrooms::IndexContext](../../app/services/classrooms/index_context.rb) | `school_year: :school` preload | 조회 adapter의 storage 지식이며 domain lifecycle 분기와 구별 |

성장기록·칭찬·쿠폰·메시지의 실행 model/policy는 현재 `app`에 없다. 따라서 이들에 이미
SchoolYear 의존이 퍼졌다는 결론은 내리지 않는다. 다만 [db/schema.rb](../../db/schema.rb)에
`daily_growth_records`, `daily_growth_scores`, `daily_virtue_configurations`,
`daily_virtue_configuration_items`, `virtues`가 남아 있고 대응 runtime model 및 생성 migration은
이번 확인 범위에서 발견되지 않았다. schema와 runtime의 차이는 별도 확인 대상이며 이 문서에서 정리하지 않는다.

## Confirmed problems

1. **School/SchoolYear resolver 중복.** 두 ManagementContext의 `schools`, `selected_school`,
   `school_years`, `selected_school_year`, `actor_school`, `manager_school_years`, `positive_id!`가
   같은 결정을 반복한다. 그러나 생성 context, `read_only?`, resource policy 위임은 다르다.
   공통 resolution 책임을 추출할 근거는 있지만 두 클래스 전체의 동등성은 확인되지 않았다.
2. **일상 운영 조건의 반복.** `StudentPolicy#operational_classroom?`,
   `ClassroomPolicy#active_school?/#student_of?`, `ApplicationController#student_session_eligible?`,
   `StudentSessionsController#load_classroom`, `ClassroomStudentsController#operational_classroom?`가
   School/SchoolYear/Classroom active 조건의 전부 또는 일부를 직접 조합한다.
   인증과 operation 양쪽의 검사는 필요하지만 조건의 정의까지 각자 유지할 이유는 없다.
3. **안전한 재사용 단위가 불명확.** Student 명단 service와 model 자체는 연도 상태를 검사하지 않는다.
   현재 controller가 먼저 authorize하지만, 이 service를 background job 등에서 재사용할 때의
   공통 operational 진입 계약은 없다. 이는 경계의 누락이며 실제 request 우회가 재현됐다는 뜻은 아니다.
4. **policy 하나만 공통 boundary로 간주하기 어렵다.** 예를 들어
   `TeacherManagementPolicy#update_profile?`는 planning 분기 뒤 admin을 허용하고,
   실제 저장 흐름은 별도 context/service guard를 사용한다. 현재 방어가 여러 계층에 분산되어
   있으므로 한 policy 호출이나 로그인 성공만으로 모든 mutation 안전성을 추정할 수 없다.
5. **downstream 계약의 공백.** 기존 spec의 target-year 확인 의무를 새 기능마다 직접 조건을
   쓰라는 지침으로 해석할 여지가 있다. actor의 연도와 record의 owner 연도를 구분하는
   public interface 및 간접 ownership 규칙을 명시할 필요가 있다.

`actor.annual_school`, `actor.school_year_id`, planning 판정은 주로 관리 context와 annual
Teacher/권한 infrastructure에 집중되어 있다. 일반 Student model과 명단 service까지 전면적으로
퍼진 상태는 아니다. 새 서비스가 기존 policy를 복사하면 누출이 확대될 위험은 있다.
현재 중복 `school_year_id` 저장 사례가 확인된 것은 아니며, 향후 schema 관행에 대한 예방 규칙이 필요하다.

## Desired abstraction boundary

아래는 승인 전의 목표 계약이다. 정확한 Ruby class/method 이름과 구현 형태를 확정하지 않는다.

| 책임 | 입력과 제공할 계약 | 담당 |
|---|---|---|
| 관리 context resolution | actor, 허용 School scope, 선택 parameter → 검증된 target School/SchoolYear | Starter 관리 infrastructure |
| 일상 운영 eligibility | 실제 owner Classroom/Student와 operation → 상위 lifecycle에 따른 허용/거부 | Starter 공통 operational boundary |
| actor authority와 조회 scope | actor, target owner, action → 역할·담당·학교 범위를 제한한 권한/scope | Starter policy와 boundary |
| 서비스별 규칙 | 실제 owner, actor, 서비스 record → 작성자·수신자·공개 범위·수량 등 기능 규칙 | downstream model/policy/operation |

일상 서비스의 public domain interface는 Classroom 또는 Student와 기능 action을 받는다.
내부에서는 SchoolYear association과 join을 사용해도 된다. 서비스 개발자가 연도 selector,
`actor.school_year_id` 대입, planning/archive 상태 분기를 매번 만들 필요가 없어야 한다.

- **record owner가 context의 source다.** actor의 annual year나 현재 active year로 record의
  귀속을 덮어쓰지 않는다. Current manager는 자기 연도와 다른 planning/archive에 접근할 수
  있으므로 actor와 target의 year equality를 모든 권한에 적용하지 않는다.
- **lifecycle eligibility는 권한 부여가 아니다.** operational Classroom이라도 다른 학교 actor,
  미담당 teacher, 다른 Student의 자료는 기능 policy가 거부해야 한다. Starter의 학생 관리
  권한을 모든 downstream 메시지·개인 기록 열람 권한으로 자동 확장하지 않는다.
- 일상 mutation, archive read, preparation, 재활성화와 governance는 다른 action이다.
  단일 `active?`/`writable?` flag나 admin 조기 허용으로 모두 합치지 않는다.
- malformed/cross-School/unauthorized explicit context는 fallback 없이 거부한다.
  School-only 기본 연도 resolution은 관리 진입점의 책임이며 기존 record 조회에 적용하지 않는다.
- 인증 session guard, 목록 scope, 개별 policy와 저장 operation이 같은 lifecycle 정의를 사용한다.
  HTML/Turbo, 직접 요청, job 호출에도 필요한 경계가 적용되어야 한다.
- mutation 시점의 재검증과 rollover 사이의 경쟁 상태를 고려한다. 현재 roster의 Classroom lock과
  rollover의 School/SchoolYear lock만으로 모든 경쟁이 해결됐다고 가정하지 않는다.
  lock 순서와 transaction 내 검증 방식은 후속 bounded spec에서 결정한다.
- Rails association, 기존 policy와 명시적인 작은 메서드부터 검토한다. 범용 context framework,
  암묵적 current-year `default_scope`, 모든 model callback에 연도 정책 주입은 요구하지 않는다.

## Rules for downstream service models

1. 실제 owner가 SchoolYear인 경우에만 `school_year_id`를 둔다. 검색·집계의 편의나
   creator가 annual teacher라는 이유만으로 추가하지 않는다.
2. Classroom 소유 데이터는 Classroom, Student 소유 데이터는 Student에서 연도 context를 얻는다.
   Student의 Classroom과 Classroom의 SchoolYear가 현재 불변이므로 이 경로는 과거 귀속도 보존한다.
3. 서비스별 spec에 실제 owner, actor 관계, read/write action과 archive 취급을 명시한다.
   일상 운영의 기본 lifecycle 계약은 Starter boundary를 참조하고 기능별 예외만 별도 승인한다.
4. author/issuer/sender가 가리키는 annual User는 작성 주체이며 데이터 owner와 같다고 가정하지 않는다.
   이름이나 `login_id`로 다음 연도 User와 자동 연결하지 않는다.
5. School-level/global 데이터는 그 ownership과 lifecycle을 명시한다. Teacher 개인 설정을
   영구 보존하려는 요구를 annual User 또는 active year에 암묵적으로 묶지 않는다.
6. 관계가 여러 개인 record는 canonical owner와 다른 관계의 일치 조건을 정한다.
   예를 들어 Student와 Classroom FK가 모두 필요하면 서로 같은 교실인지 검증해야 하며,
   이런 중복을 해소하려고 SchoolYear FK를 추가하지 않는다.

### Ownership decision guide

- Record 자체가 특정 SchoolYear의 학교 전체 데이터라면 SchoolYear 직접 ownership을 검토한다.
- Classroom에서 발생한 데이터라면 Classroom을 owner/context source로 사용하고 SchoolYear FK를
  중복 추가하지 않는다.
- Student 개인 데이터라면 Student를 owner/context source로 사용하고 SchoolYear FK를 중복 추가하지 않는다.
- Teacher가 author, issuer 또는 sender라는 사실만으로 SchoolYear ownership을 추론하지 않는다.
- 여러 학년도에 지속되는 학교 단위 데이터라면 School ownership을 우선 검토한다.

이 guide는 새 schema를 승인하지 않는다. 새 domain spec에서 실제 수명과 ownership을 판단하기 위한 규칙이다.

| 향후 예시 | owner 선택의 기준 | SchoolYear FK |
|---|---|---|
| 학생 성장기록·학생 대상 칭찬 | 학생 개인 기록이면 Student; 학급 공통 기록이면 Classroom | 간접 context이면 추가하지 않음 |
| 쿠폰 발급·사용 기록 | Student 소유인지 학급 운영 장부인지 서비스 spec에서 결정 | 간접 context이면 추가하지 않음 |
| 쿠폰 template | 학급 설정, School 공통 또는 global catalog 중 실제 수명으로 결정 | 학년도 자체 소유가 아니면 추가하지 않음 |
| 메시지 | Classroom 대화인지, 개인/학교 범위 대화인지 먼저 결정 | sender의 annual year를 자동 저장하지 않음 |
| 학년도 전체 결산·계획 | SchoolYear 자체가 명시적인 owner인 경우 | 직접 FK 허용 |

이 표는 새 서비스 schema 승인이 아니다. Cross-year 통계는 owner association을 통한 명시적
조회로 시작하며, 성능 측정 전 중복 FK를 추가하지 않는다. 향후 snapshot/cache가 필요하면
canonical ownership과 구별한 별도 설계 및 일관성 계약을 검토한다.

## SchoolYear-aware infrastructure

다음은 **현재 runtime 구조에서** SchoolYear를 직접 알아야 하는 infrastructure다. 이 목록은
annual Teacher/Classroom 또는 annual identity를 장기 구조로 새로 확정하지 않는다.

- SchoolYear 생성·운영, planning 준비/취소, 현재 annual Teacher와 SchoolYear 소속 Classroom 구성,
  manager designation.
- 수동 rollover, readiness, archive read context와 권한 및 향후 별도 승인할 recovery. Archived annual account login과 개인별 historical access는 현재 infrastructure target이 아니다.
- 현재 연도별 credential lookup과 session eligibility, annual User와 담임 관계의 무결성.
- 상위 lifecycle을 검사하는 공통 boundary, 관리 context resolver, 연도별 query/preload/report adapter.

Teacher 영구 identity 여부는 이 infrastructure 경계와 별개의 open question이다. 이 목록은
`TeacherAssignment` 도입, annual User 재사용 또는 현재 User 귀속 구조의 유지를 암묵적으로 결정하지 않는다.

Planning은 현재 Teacher/Classroom/HomeroomAssignment 준비만 허용한다. 일반 서비스 record 생성과
Student roster mutation을 개방하지 않는다. Archived 하위 운영 자료는 read-only이며 rollover는
global admin만 수행한다. 날짜가 바뀌어도 active year를 자동 변경하지 않는다.

이 영역의 직접 참조 개수 감소 자체를 목표로 삼지 않는다. 정당한 infrastructure 의존과
일상 서비스가 복제하는 lifecycle 지식을 분리하는 것이 목표다.

## SchoolYear-agnostic service domain

서비스 model은 자신의 실제 owner, 필드 invariant와 기능 규칙을 다룬다. 일상 controller/policy는
Starter의 owner 기반 operational 계약과 서비스별 권한을 조합하고, domain operation은
검증된 진입점을 통해 실행한다. 내부 순수 로직이 SchoolYear를 몰라도 보호된 호출 경로는 필요하다.

예를 들어 학생 성장기록 작성은 `Student → Classroom`의 운영 eligibility와 actor의 작성 권한을
확인한 뒤 기록 날짜·내용을 검증한다. 서비스가 SchoolYear parameter를 받아 자체적으로 active year를
조회하거나 planning/archive를 switch하지 않는다. Archive 화면 제공은 별도 read 권한과 context를
사용하며, 연도 분기를 제거했다는 이유로 읽기까지 일괄 차단하거나 공개하지 않는다.

현재 `Student`와 `ClassroomStudents` service는 이러한 분리의 일부를 보여준다. 아직 공통
mutation boundary가 완성됐다는 뜻은 아니며 기존 명단 service를 무조건 안전한 public API로 선언하지 않는다.

## Teacher identity open question

현재 Teacher는 영구적인 사람이 아니라 **학년도별 User account**다. School scope, annual role,
credential, 작성자 FK와 assignment가 이 identity에 결합되어 있다. Operational predicate는
일상 권한 계산을 감쌀 수 있지만, 연도를 넘는 동일인 식별·개인 설정·작성 이력 통합까지 해결하지 못한다.

[Annual Teacher User Migration](annual_teacher_user_migration.md)과 School Year Architecture는
영구 Teacher identity와 annual account의 2계층을 Starter target에 두지 않는다.
이를 재검토하려면 인증·과거 작성자·권한·이관 영향을 별도 구조 결정으로 승인해야 한다.
본 초안은 `TeacherAssignment` 도입, User 재사용, annual FK 변경 또는 동일인 자동 연결을 제안의
확정 결과로 삼지 않는다. 담임 이력의 `HomeroomAssignment`와 사람 identity 문제도 구분한다.

## Classroom annuality open question

현재 Classroom의 변경 불가능한 `belongs_to :school_year`는 일상 서비스 개발의 필수 장애물이 아니다.
Classroom 또는 Student owner를 통해 정확한 연도 context를 전달할 수 있고, 상위 archive로
당시 기록을 보존할 수 있다. 테이블마다 SchoolYear FK를 추가할 필요도 없다.

다만 같은 학년·반 표기의 다음 해 Classroom은 다른 entity다. 여러 해 지속되는 교실 공간,
학생 동일인 이력, 연속 대화방 같은 요구는 현재 annual Classroom/Student만으로 해결되지 않는다.
그 요구가 실제로 생기면 별도의 identity/ownership 결정을 검토한다. 현 단계에서는 Classroom을
School 직속으로 되돌리거나 ClassroomAssignment·StudentEnrollment를 추가하지 않는다.

## Compact/Managed profile과의 관계

확인한 현재 architecture/spec과 설정에는 Compact/Managed profile의 canonical 정의 또는
전환 계약이 없다. 이름만으로 별도 schema, runtime mode 또는 이미 승인된 정책이 있다고 가정하지 않는다.

검토 후보는 두 profile이 동일한 storage와 owner 기반 public interface를 공유하고,
관리 surface와 운영 책임의 노출 범위를 달리하는 것이다. Compact에서 연도 selector를 일상 UX에
숨기더라도 archive/School 비활성화 경계를 우회해서는 안 된다. Managed에서 planning/archive를
명시적으로 운영하더라도 일반 서비스 model이 연도 FK나 상태 분기를 추가할 이유는 없다.

Compact에서 누가 언제 annual account와 다음 연도를 준비하는지, rollover와 과거 접근을 어떻게
운영하는지, 두 profile 사이 전환을 지원하는지는 미결정이다. UI를 줄이는 것만으로 annual identity의
운영 부담이 없어지지는 않으며, 자동 rollover나 영구 Teacher identity를 암묵적으로 도입하지 않는다.

## 기존 canonical spec과의 충돌·정합성 검토

| 지점 | 현재 문서/구현의 관계 | 본 초안의 취급 |
|---|---|---|
| 각 write policy/domain operation의 직접 SchoolYear 확인 | [Operations Foundation](school_year_operations_foundation.md)의 문구는 target School/SchoolYear/status를 명시적으로 확인하도록 요구 | 검사 의무는 보존하되 공통 boundary에 위임하는 해석을 제안. 승인 전 기존 계약을 삭제하거나 완화하지 않음 |
| annual Teacher identity | 기존 architecture는 영구 identity 2계층을 target에서 제외 | 본 초안은 결정 재검토 가능성을 open question으로만 남김. 새 구조 확정은 기존 결정과 충돌 |
| Classroom annual ownership | 기존 [Classroom Migration](classroom_school_year_migration.md)은 연도 FK와 불변성을 명시 | 그대로 보존. 비연도 Classroom 전환은 별도 정책 변경 |
| planning login/Student 준비/rollover actor | 초기 Operations Foundation 본문에는 planning account 차단, Student 준비, manager rollover 문구가 남아 있음. 문서 머리말은 후속 Bootstrap의 supersede를 명시 | 현재 Bootstrap/Calendar/runtime 기준: eligible planning manager만 준비 로그인, planning Student mutation 미지원, admin-only 수동 rollover |
| archived Teacher login과 historical scope | Archived annual account는 현재 로그인할 수 없고 Teacher identity도 open question임 | Archived annual account login을 현재 또는 확정된 future target으로 두지 않음. 별도 historical identity/access 설계가 승인될 경우에만 재검토 |
| 학교 관리자 학생 운영 | Current operational manager는 담당 여부와 관계없이 자기 학교의 active SchoolYear와 active Classroom 전체에서 현재 승인된 Student operation을 수행 | owner 기반 boundary도 이 school-wide authority를 보존하며 ordinary Teacher만 담당 Classroom으로 제한 |
| archived read 매트릭스 | Global admin은 모든 School, current operational manager는 자기 School archive를 read-only로 조회. Planning manager, ordinary Teacher, archived annual account와 Student는 접근 불가 | Authority와 현재 제공 UI surface를 구분하고 archive mutation은 모두 거부 |
| 서비스 schema와 runtime | schema에 성장기록 계열 테이블이 있으나 현재 runtime model은 없음 | 서비스 구현 또는 canonical ownership의 증거로 취급하지 않음; 별도 확인 |

Manager의 Student 운영과 archived access 충돌은 별도 authority alignment 결정으로 정리되었으며
operational boundary는 위 권한을 기준으로 삼는다. 테스트 전략의 일부 legacy membership 표현도
현재 Student runtime 정의보다 우선하지 않는다.

## Non-goals

- migration, schema/model/policy/controller/service/route 변경과 실제 서비스 domain 구현.
- TeacherAssignment, 영구 Teacher identity, Classroom 귀속 변경, StudentEnrollment 도입.
- 기존 권한 확대·축소, archived login/recovery 구현, 자동 rollover·진급·복사.
- Compact/Managed profile 구현 또는 별도 제품/schema 확정.
- 범용 framework 도입, 성능 추정에 따른 FK 중복, schema 잔여물·기존 문서 일괄 정리.
- 테스트 실행, DB 감사 실행, commit/push/merge.

## Open questions

1. 공통 lifecycle 메서드와 actor/action policy를 어디에 둘 것인가? 기존 Classroom/Student policy의
   재사용 범위와 새 downstream policy의 최소 호출 계약을 먼저 결정해야 한다.
2. Controller 외 job/service 진입의 검증 책임, transaction 재검증과 rollover lock 계약을 어떻게
   제공할 것인가? 범용 wrapper 없이 보장할 수 있는 최소 구조는 무엇인가?
3. 허용된 archive read surface와 inactive School/Classroom 조회·재활성화 예외를 어떻게
   action별로 표현할 것인가? Archived annual account credential mutation은 현재 권한 계약에 포함하지 않는다.
4. 두 ManagementContext의 생성/읽기 전용 의미 차이를 보존하면서 어느 resolution 부분까지 공유할 것인가?
5. 연도간 동일 Teacher·Student·교실 identity가 Starter의 책임인가, downstream 확장인가?
   실제 지속 데이터 요구 없이 현재 annual 구조를 바꾸지 않는다.
6. Compact/Managed의 정확한 목적, 운영 주체와 전환 지원 범위는 무엇인가?
7. 남은 schema/runtime 차이를 어느 별도 run에서 확인·정리할 것인가?

## 가능한 후속 구현 단계

각 단계는 이 초안 검토 후 별도 승인·run으로 수행한다. 새 의존성 전수 조사를 반복하지 않고
위 inventory를 시작점으로 사용한다.

1. **권한 기준 적용:** current operational manager의 자기 학교 active Student 전체 운영과
   global admin/current operational manager의 archive read-only stewardship를 boundary 기준으로 삼는다.
   Planning manager, ordinary Teacher, archived annual account와 Student에는 archive authority를 부여하지 않는다.
2. **계약 확정:** open question 중 operational action/owner 계약을 결정하고, 선행 정리에서
   승인된 권한과 lifecycle 계약을 boundary의 기준으로 삼는다. Teacher/Classroom 구조 변경은 분리한다.
3. **관리 resolver:** 두 ManagementContext의 공통 School/SchoolYear 선택 규칙만 추출한다.
   생성 context와 resource별 policy는 보존한다.
4. **운영 eligibility:** owner 기반 lifecycle 정의를 만들고 현재 policy·인증·session의 반복 조건을
   좁은 단위로 이관한다. scope와 read/mutate/재활성화 예외를 보존한다.
5. **mutation 진입 계약:** 일상 Student operation 하나를 대상으로 호출 전 권한과 transaction 내
   상태 재검증·rollover 경합 계약을 적용한 뒤 다른 operation으로 확대한다.
6. **downstream 적용 검증:** 실제 서비스 하나의 별도 spec에서 owner와 기능 권한을 정의하고,
   중복 SchoolYear FK·상태 분기 없이 기능과 archive 차단을 구현할 수 있는지 확인한다.
7. **독립 구조 결정:** 필요가 확인되면 annual identity와 profile 운영 문제를 각각 별도로 검토한다.

후속 검증은 [RSpec Strategy](../testing/rspec_strategy.md)에 따라 사용자가 수행한다.
기존 example과 권한 assertion을 보존하고 다음 경계를 확인한다.

- 정상 active 운영, inactive School/Classroom/Student와 account, 비담당·cross-School actor 거부.
- current manager와 exact planning manager의 기본/명시 context, malformed ID와 fallback 금지.
- planning 일반 서비스 mutation 거부, 허용된 archive read와 모든 운영 mutation 거부.
- 재활성화·credential·governance 등 별도 action의 기존 의미 보존.
- stale form/session, 직접 service/job 호출과 rollover 경쟁 시 승인한 계약 준수.
- 새 서비스 record의 연도 귀속이 actor가 아닌 owner에서 결정되고 rollover 뒤에도 보존됨.

이번 run은 문서 diff 검토만 요청하며 제품 구현 승인이나 검증 완료를 의미하지 않는다.
