# School Year Operations Foundation

## 목적

이 문서는 다학년도 운영을 시작하기 전에 `SchoolYear` context와 teacher authority 의미를 명시하는 구현 canonical spec이다. 현재 active-year 일상 운영을 보존하면서 planning 준비, rollover, archived 조회와 archived authentication을 서로 다른 후속 phase로 안전하게 나누는 기준으로 사용한다.

이 단계는 foundation 계약만 확정한다. 구체 route, controller, policy, service와 UI는 승인된 후속 구현 단위에서 정하며, 이 문서 승인만으로 bulk bootstrap, rollover 또는 archived login을 한 번에 구현하지 않는다.

이 문서의 초기 manager School operation authority와 context matrix는 후속 canonical contract인 [`planning_year_bootstrap.md`](planning_year_bootstrap.md)가 현재 정책을 supersede한다. 특히 active planning manager는 자기 School의 active operation, exact planning preparation과 archived read-only stewardship authority를 가지지만 `current_operational_manager?`의 의미, SchoolYear governance, actual rollover 또는 global-admin-only authority를 얻지 않는다.

장기 정책은 [`school_year_architecture.md`](school_year_architecture.md), 현재 runtime은 [`current_system.md`](../architecture/current_system.md)와 [`roles_and_permissions.md`](../architecture/roles_and_permissions.md)를 함께 따른다.

## 현재 runtime 전제

- `SchoolYear`는 `planning`, `active`, `archived` 상태를 가지며 School별 active와 planning은 각각 최대 하나다.
- Teacher `User`는 정확히 하나의 `SchoolYear`에 속하는 annual account다. 기존 User의 `school_year_id`를 다른 연도로 변경하지 않는다.
- Classroom은 `SchoolYear`에 속하고 Student는 Classroom에 직접 속한다.
- 현재 담임 관계의 canonical source는 `HomeroomAssignment`다.
- 정상 teacher login은 `School -> active SchoolYear -> normalized login_id`로 resolve하며 사용자가 SchoolYear를 선택하지 않는다.
- 현재 `/teachers`와 `/classrooms`는 active SchoolYear의 일상 운영 canonical surface다. Planning 지원을 위해 이 scope를 active 또는 planning으로 넓히지 않는다.
- 현재 `User#active_teacher?`는 teacher role과 User account의 active 상태만 뜻한다.
- 현재 request guard는 User, SchoolYear 또는 School이 active가 아닌 teacher session을 종료한다. 이 guard가 planning/archived account의 기존 policy 통과 가능성을 가리고 있으므로 archived authentication 전에 authority 의미를 분리해야 한다.
- Planning bootstrap, rollover, archived school-operation UI와 archived teacher login은 아직 runtime에 없다.

## Lifecycle semantics

### active

- School의 현재 실제 운영 학년도다.
- 정상 teacher/student login과 허용된 read/write operation은 active School, active SchoolYear 및 각 resource lifecycle 조건을 함께 만족해야 한다.
- Active-year 기본 context는 School별 유일한 active SchoolYear다. Planning 또는 archived year로 fallback하지 않는다.

### planning

- Active SchoolYear와 동시에 존재할 수 있는 다음 학년도 준비 context다.
- 다음 학년도의 teacher, Classroom, Student와 담임을 준비하고 rollover readiness를 확인하기 위한 staging이자 safety boundary다. 현재 active-year runtime은 planning 존재와 무관하게 계속 운영한다.
- Planning은 별도 SchoolYear dashboard나 navigation hierarchy를 두지 않는다. 상태와 후속 준비 entry는 School 화면의 자연스러운 school-operation surface에 둔다.
- 정상 planning operation에서는 current active year의 바로 다음 학년도만 허용한다.
- 별도의 annual teacher User, credential, Classroom, HomeroomAssignment와 Student 명단을 명시적으로 준비할 수 있다.
- Teacher, Student, Classroom, 담임과 과거 Student를 자동 복사·진급·연결하지 않는다.
- Planning teacher credential은 준비할 수 있지만 normal runtime login을 허용하지 않는다. Planning Student login도 허용하지 않는다.
- Planning data mutation은 명시적으로 선택되고 승인된 planning context에서만 허용한다. `/teachers`, `/classrooms`의 기본 active-year query에 planning을 섞지 않되 같은 surface를 SchoolYear context에 따라 재사용할 수 있다.

### archived

- 종료된 과거 학년도이며 그 아래 teacher, Classroom, Student, HomeroomAssignment와 downstream 자료를 그대로 보존한다.
- School-operation data는 read-only다. SchoolYear archive 시 하위 row를 삭제하거나 일괄 inactive로 바꾸지 않는다.
- Archived account authentication은 후속 별도 flow에서만 허용한다. 인증 성공은 archived data mutation authority를 뜻하지 않는다.
- Application의 정상 operation에서 archived SchoolYear를 active 또는 planning으로 되돌리지 않는다. 직전 rollover 사고 복구를 위한 global-admin-only reversal은 일반 lifecycle operation과 구분한다.

학년도 변경은 기존 `SchoolYear.year` 또는 연관 row의 SchoolYear FK를 바꾸는 방식이 아니다. 정상 전환은 기존 active row를 archived로, 준비된 planning row를 active로 바꾸며 두 학년도의 `year`와 연결 data를 보존한다.

## Authority semantics

Authority는 `actor role × School scope × SchoolYear status`의 결합으로 판단한다. Account predicate 하나나 session guard에 의존해 write authority를 부여하지 않는다.

- **Active teacher account**: teacher role이고 `User.active`가 true인 annual User다. SchoolYear나 School의 운영 가능 상태까지 보장하지 않는다.
- **Current operational teacher**: active teacher account이며 그 User의 SchoolYear와 School이 모두 active다.
- **Current operational manager**: current operational teacher이며 annual `school_role`이 manager다.
- **Archived authenticated teacher**: explicit School과 archived SchoolYear context에서 인증된 해당 annual User다. 당시 role과 assignment가 read scope를 결정하며 mutation authority는 없다.

정확한 Ruby method 이름과 배치 위치는 implementation detail로 남긴다. 그러나 policy, scope, controller/domain operation, navigation과 landing path는 위 의미를 일관되게 사용해야 한다.

## Actor/authority matrix

| Actor | Active context | Planning context | Archived context | Rollover |
|---|---|---|---|---|
| Global admin | 모든 School의 현재 허용 operation | 모든 School 생성·준비 | 모든 School read-only | 모든 School 가능 |
| Current operational manager | 자기 School의 school-wide 허용 operation | 자기 School 생성·준비 | 자기 School 전체 read-only | 자기 School 가능 |
| Current operational ordinary teacher | 실제 담당 Classroom 범위 | 불가 | 현재 manager authority 없음 | 불가 |
| Planning teacher account | Normal login과 runtime operation 불가 | 준비 대상일 뿐 actor authority 없음 | 불가 | 불가 |
| Archived manager account | 불가 | 불가 | 해당 annual account의 SchoolYear에서 자기 School 전체 read-only | 불가 |
| Archived ordinary teacher account | 불가 | 불가 | 해당 SchoolYear의 실제 HomeroomAssignment로 담당했던 Classroom 범위 read-only | 불가 |
| Student | active SchoolYear의 자기 active Classroom/Student 범위 | login 불가 | login 불가 | 불가 |

현재 manager account의 historical management authority와 archived annual account의 당시 authority는 서로 다른 source다. 예를 들어 2026 ordinary teacher, 2027 manager인 사람의 2027 current manager account는 자기 School의 2026 전체를 read-only로 볼 수 있다. 반면 2026 archived account로 로그인하면 2026 당시 실제 담당 Classroom 범위만 볼 수 있다. 이름, `login_id`, email 또는 avatar로 두 User가 같은 사람인지 자동 추론하지 않는다.

Manager designation과 변경은 계속 global-admin-only다. Planning/rollover 권한은 manager에게 `/admin/*` 접근이나 자기 자신·다른 teacher를 manager로 지정할 권한을 주지 않는다.

## SchoolYear context resolution

### Active context

```text
explicit School -> 그 School의 유일한 active SchoolYear
```

- 현재 normal teacher login과 `/teachers`, `/classrooms`의 기본 의미를 유지한다.
- Active SchoolYear가 없으면 fail closed한다.
- Planning 또는 archived SchoolYear를 대신 선택하지 않는다.

### Planning context

```text
authorized actor + explicit School -> 그 School의 유일한 planning SchoolYear
```

- School과 planning year 관계를 서버에서 확인한다.
- Planning year가 없으면 active year나 임의의 archived year로 fallback하지 않는다.
- Global admin은 대상 School을 명시하고, manager는 session의 current operational School 밖으로 scope를 넓힐 수 없다.
- Planning context는 School의 자연스러운 school-operation entry에서 표시한다. `/teachers`와 `/classrooms`는 context가 생략되면 active year를 유지하고, 명시적으로 승인된 planning context에서 같은 surface를 재사용한다. 별도 SchoolYear workspace는 두지 않는다.

### Archived context

```text
authorized actor + explicit School + explicit archived SchoolYear
```

- SchoolYear는 반드시 URL/entry의 School에 속하고 archived 상태여야 한다.
- Active 또는 planning year를 archived context로 취급하지 않는다.
- Archived teacher login은 `School + explicit archived SchoolYear + normalized login_id`로 account를 resolve한다.
- Archived login rate-limit key에는 최소한 School, archived SchoolYear, normalized login ID와 기존에 요구되는 remote/credential-generation context를 포함한다.

## Planning SchoolYear creation boundary

- Global admin은 모든 School에, current operational manager는 자기 School에 planning SchoolYear를 생성할 수 있다.
- Actor와 School scope는 request 시작 시와 저장 직전에 서버에서 재확인한다.
- 생성 요청은 target School만 사용한다. Server가 target School의 current active SchoolYear를 resolve하고 `planning.year = active.year + 1`로 다음 학년도를 결정한다. Active 2026이면 2027만 생성한다.
- 사용자는 planning year를 입력하거나 선택하지 않는다. Client가 year parameter를 함께 제출해도 신뢰하거나 사용하지 않으며 날짜, School 생성일 또는 이름을 기준으로 계산하지 않는다.
- Target School에 planning SchoolYear가 이미 있거나 같은 `year`가 이미 존재하면 실패한다. DB unique invariant가 최종 방어선이다.
- Planning year 생성은 teacher 복제, Classroom 복사, Student 진급, 담임 승계, manager 지정 또는 rollover를 수행하지 않는다.
- Manager와 global admin의 planning 진입은 기존 school-operation surface를 재사용하되 actor별 School scope를 server-side로 제한한다. Manager에게 `/admin/*`를 개방하지 않는다.
- Active SchoolYear가 없는 School을 정상 rollover 준비 대상으로 간주하지 않는다. Initial School bootstrap과 복구는 이 operation 밖의 별도 절차다.
- 바로 다음 학년도 invariant는 server-side domain operation과 concurrency를 포함한 필요한 model/DB 경계에서 방어한다. Active SchoolYear가 없는 School의 initial bootstrap과 recovery는 이 operation 밖이다.

## State transition rules

허용되는 정상 lifecycle은 다음과 같다.

```text
planning -> active
active   -> archived
```

두 변경은 rollover 하나에서만 동시에 수행한다. Planning을 단독 active로 만들거나 destination planning 없이 active만 archived로 만드는 정상 operation은 허용하지 않는다. Archived에서 다른 상태로의 전환과 기존 `year` 변경도 허용하지 않는다.

정상 operation의 예외로, global admin은 직전 rollover 사고에 한해 same-School pair를 `current active -> planning`, `previous archived -> active`로 함께 되돌리는 제한된 reversal/recovery를 수행할 수 있다. Manager, ordinary teacher와 archived teacher account는 실행할 수 없다. 이는 archived generic reactivation이나 일반 undo가 아니며 강한 confirmation, deterministic locking과 하나의 transaction을 요구한다.

새 active year에서 operational mutation이 발생한 경우 자동 reversal을 허용한다고 가정하지 않는다. 운영 시작으로 판단할 mutation, 직전 rollover pair를 증명할 audit data와 정확한 reversal readiness 기준은 후속 human-reviewed bounded spec에서 확정하며 이번 phase에서는 구현하지 않는다.

Rollover destination에는 전환 전에 정확히 한 명의 유효한 manager annual User가 준비되어 있어야 한다. Source manager를 자동 복제·승계하지 않으며 모든 Classroom, HomeroomAssignment와 Student의 완성은 요구하지 않는다.

Rollover 실행 권한은 global admin의 모든 School 또는 current operational manager의 자기 School로 제한한다. Ordinary teacher, planning teacher account와 archived teacher account는 실행할 수 없다.

## Authorization과 mutation/read-only boundary

- 모든 write policy와 domain operation은 target resource의 School, SchoolYear와 status를 명시적으로 확인한다.
- Current operational manager 판정은 User active, SchoolYear active, School active와 annual manager role을 모두 요구한다.
- Archived authenticated teacher가 기존 active-year policy나 scope를 통과하지 않아야 한다.
- Planning mutation은 명시적인 planning context와 허용된 actor에게만 열고 normal teacher/student runtime operation은 계속 차단한다.
- Archived SchoolYear 아래 Classroom, Student, HomeroomAssignment, teacher annual authority와 manager role 등 school-operation data는 actor와 무관하게 변경할 수 없다.
- Authentication credential이나 account profile처럼 school-operation data와 구분되는 mutation은 archived authentication phase의 별도 spec에서 정한다.
- UI control 숨김은 보조 수단이다. 직접 request, stale form, 변조된 id와 nested parameter도 동일한 server-side authorization을 통과해야 한다.

## Failure behavior

- Missing, duplicate 또는 잘못된 status의 context는 다른 SchoolYear로 fallback하지 않고 fail closed한다.
- Actor가 권한을 잃거나 School/SchoolYear status가 바뀌면 stale session이나 이미 표시된 form으로 mutation하지 못한다.
- Cross-School SchoolYear, teacher, Classroom 또는 Student id를 제출하면 조회/변경 범위를 넓히지 않고 거부한다.
- Planning creation validation이나 persistence가 실패하면 School과 기존 active SchoolYear는 변하지 않고 부분 생성 data를 남기지 않는다.
- Client가 year parameter를 제출해도 무시하며 server가 current active year에서 계산한 다음 학년도 외의 row를 생성하지 않는다.
- Rollover precondition, authorization, lock 이후 재검증 또는 어느 상태 변경이든 실패하면 transaction 전체를 rollback하고 기존 active SchoolYear를 유지한다.
- Destination planning SchoolYear에 정확히 한 명의 유효한 manager annual User가 없으면 rollover 전체를 실패시키고 source active SchoolYear를 유지한다.
- Reversal/recovery의 authority, same-School 직전 pair 또는 atomic transition 재검증이 실패하면 현재 active/archived 상태를 유지한다.
- 실패 응답은 권한 밖 resource 존재 여부나 credential 정보를 불필요하게 노출하지 않는다.

## Transaction과 locking 기대사항

- Planning SchoolYear 생성은 transaction에서 수행하고 target School을 lock한 뒤 School의 current active/planning 상태와 actor authority를 재확인한다.
- Rollover는 target School, source active SchoolYear와 destination planning SchoolYear를 일관된 순서로 lock한다.
- Rollover transaction 안에서 actor authority, School active 상태, source가 여전히 active인지, destination이 여전히 planning인지, 둘이 같은 School 소속인지, `destination.year == source.year + 1`인지와 School별 cardinality invariant를 재검증한다.
- Destination planning SchoolYear의 annual User 관계를 필요한 범위에서 lock하고, 해당 SchoolYear에 속하며 active account이고 annual teacher/manager invariant를 만족하는 manager가 정확히 한 명인지 transaction 안에서 재검증한다.
- `active -> archived`와 `planning -> active`는 한 transaction에서만 commit한다.
- Reversal/recovery도 current active와 previous archived를 deterministic하게 lock하고 `active -> planning`과 `archived -> active`를 한 transaction에서만 commit한다.
- Model validation만 concurrency 방어로 간주하지 않고 기존 DB unique invariant를 유지한다.
- 정확한 service class 이름이나 lock 호출 순서는 구현 spec에서 정하되 deadlock을 피할 수 있는 deterministic order를 사용한다.

## Direct URL/parameter manipulation 방어

- Manager가 다른 School id를 URL, form 또는 nested parameter로 제출해도 current operational School 밖의 planning/rollover/historical authority를 얻지 못한다.
- Planning creation에 임의의 year parameter를 추가해도 server-side target year에 영향을 주지 못한다.
- `/teachers`·`/classrooms`의 SchoolYear context parameter는 actor에게 허용된 server-side School/SchoolYear scope에서만 resolve한다. 임의 id로 다른 School이나 허용되지 않은 status의 scope를 선택할 수 없다.
- School과 SchoolYear가 서로 다른 조합, source와 destination이 같은 row인 조합, expected status와 다른 조합은 거부한다.
- Planning/archived account id를 active login이나 active teacher management endpoint에 제출해 fallback lookup 또는 mutation할 수 없다.
- Archived 화면의 mutation endpoint를 추측해 직접 요청해도 read-only 경계를 우회할 수 없다.

## Acceptance criteria

1. `active_teacher?`와 current operational teacher/manager의 의미 차이가 코드와 focused specs에서 드러난다.
2. Existing teacher session, navigation, landing과 active-year policy는 User, SchoolYear와 School operational eligibility를 일관되게 사용한다.
3. `/teachers`와 `/classrooms`의 기본 context는 active SchoolYear로 유지된다. 명시적으로 선택되고 승인된 planning/archived context에서 같은 surface를 재사용하며 archived는 read-only다.
4. Global admin은 모든 School, current operational manager는 자기 School의 planning context만 생성·조회할 수 있다.
5. Ordinary, planning과 archived teacher account는 planning creation/mutation authority를 얻지 못한다.
6. Planning SchoolYear 생성은 server가 current active SchoolYear를 기준으로 `planning.year = active.year + 1`을 계산한다. 사용자는 year를 입력·선택하지 않고 client year parameter는 결과에 영향을 주지 않으며 날짜 기반 계산을 하지 않는다.
7. Concurrent 또는 중복 planning 생성은 실패하며 기존 active context가 보존된다.
8. Active, planning과 archived resolver는 status와 School ownership을 확인하고 missing/invalid context에서 fallback하지 않는다.
9. 모든 write authorization은 actor role, School scope와 SchoolYear status를 확인하며 session guard나 UI 숨김에만 의존하지 않는다.
10. Global admin과 current operational manager만 허용된 School에서 rollover할 수 있다는 후속 operation 계약이 policy와 service boundary에 반영된다.
11. Rollover는 explicit confirmation, source/destination 확인, authority 재확인, locking과 transaction을 요구한다. Lock 이후 destination에 정확히 한 명의 유효한 manager annual User가 있음을 재검증하고, 없거나 invalid하면 source active year를 유지한다.
12. Archived school-operation data는 모든 actor에게 read-only이며 archived authenticated teacher가 active-year write policy를 통과하지 않는다.
13. Global admin, current manager, archived manager account와 archived ordinary account의 historical read scope가 서로 구분된다.
14. Cross-School 및 status/id parameter 조작 request가 거부되고 기존 current-year login과 operation regression specs가 유지된다.
15. Rollover reversal은 global admin만 same-School 직전 pair에 수행하는 제한된 recovery이며 generic archived reactivation이 아니다. Post-rollover operational mutation과 audit/readiness 기준은 별도 승인 전까지 구현하지 않는다.

## Non-goals

- Model/controller/policy/service/view implementation과 migration
- 새 route 또는 generic context/workflow/state-machine framework
- Planning 전용 `/planning/teachers`, `/admin/teachers`, `/admin/classrooms`와 lifecycle별 중복 CRUD 구현
- Planning teacher/Classroom/Student bulk create
- Rollover service와 confirmation UI 구현
- Rollover reversal/recovery service, UI와 audit 구현
- Archived read-only UI와 historical reporting 구현
- Archived teacher login, password lifecycle과 context UI 구현
- Teacher, Student, Classroom, 담임의 자동 복사·진급·승계
- Permanent Teacher identity 또는 annual User 간 자동 연결
- Manager용 `/admin/*` 개방 또는 manager designation 권한 변경
- Existing current-year surface와 unrelated authorization/view refactor

## 후속 implementation phase 경계

### A. Planning SchoolYear operation foundation

- Current operational teacher/manager semantics를 명시하고 session, navigation, landing과 관련 active-year policy를 그 의미에 맞춘다.
- Active/planning/archived context resolver의 최소 server boundary를 둔다.
- Global admin과 own-School current operational manager의 planning SchoolYear 생성 및 planning context 진입만 구현한다.
- Existing `/teachers`와 `/classrooms`의 기본 active-year scope는 변경하지 않는다.

### B. Planning bulk bootstrap

- B1: planning annual teacher User와 temporary credential 준비
- B2: planning Classroom 준비
- B3: planning HomeroomAssignment 준비
- Planning Student 명단 준비는 Phase B에 포함하지 않고 teacher/Classroom/담임 계약이 안정된 뒤 별도 bounded phase로 진행한다.
- 기존 `/teachers`, `/classrooms`를 명시적인 SchoolYear context로 재사용하고 planning 전용 controller/view를 복제하지 않는다.
- Current manager의 후임 manager 후보 제안과 global-admin-only 최종 manager designation을 구분한다.
- 기존 credential/teacher/classroom domain operation을 재사용할 수 있는지 각 bounded spec에서 검토하되 기본 active-year query에 planning을 섞지 않는다.

### C. Archived read-only enforcement

- Archived resource의 policy/scope와 domain mutation 방어를 먼저 구현한다.
- Global admin, current active-year manager와 당시 archived account role/assignment의 historical read scope를 구분한다.
- Rollover와 archived authentication을 열기 전에 active-year write authority가 archived context에 닫혀 있음을 검증한다.

### D. Rollover

- Explicit confirmation, source/destination 식별, authority 재확인, readiness validation, deterministic locking과 atomic transition을 구현한다.
- Destination이 source의 바로 다음 학년도이고 정확히 한 명의 유효한 manager annual User를 가지는지 lock 이후 transaction 안에서 재검증한다.
- Destination manager는 rollover 전에 global admin이 명시적으로 지정하며 source manager를 자동 복제·승계하지 않는다. Current operational manager의 rollover 권한은 manager designation 권한을 주지 않는다.
- Manager가 없거나 invalid하면 전체 transition을 rollback하고 source active SchoolYear를 유지한다. 모든 Classroom, HomeroomAssignment와 Student의 완성은 요구하지 않는다.
- Global admin은 모든 School, current operational manager는 자기 School에만 실행한다.
- 자동 복사·진급은 포함하지 않는다.

### D 후속. Rollover reversal/recovery

- Normal rollover와 분리된 global-admin-only recovery operation을 별도 bounded spec으로 확정한다.
- Same-School 직전 rollover pair, 강한 confirmation, deterministic locking과 atomic reversal을 요구한다.
- Post-rollover operational mutation 판정, audit evidence와 정확한 readiness 기준을 human review로 확정하기 전에는 구현하지 않는다.

### E. Archived teacher authentication과 historical context UI

- School + explicit archived SchoolYear + login ID 인증, SchoolYear-aware rate limiting과 session context를 구현한다.
- Archived navigation/landing, read-only 표시와 허용된 historical UI를 구현한다.
- Archived credential 재발급과 본인 password 변경 정책은 이 phase의 별도 human-reviewed spec에서 확정한다.

각 phase는 별도 bounded run과 human approval을 거친다. 특히 C의 read-only enforcement가 승인·검증되기 전에 D의 rollover나 E의 archived login을 개방하지 않는다.
