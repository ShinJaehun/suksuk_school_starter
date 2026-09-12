# Planning-year teacher/classroom bootstrap

## 목적

이 문서는 다음 planning SchoolYear의 annual teacher User, Classroom과 HomeroomAssignment 준비, B10 actual SchoolYear rollover, B11 archived read-only authority와 B12 planning-manager collaboration의 canonical contract를 정의한다. B10 이전의 preparation operation은 active SchoolYear를 변경하지 않는다.

예를 들어 2026 active와 2027 planning이 함께 있을 때 허용된 actor는 2027 준비 data만 명시적으로 생성·수정할 수 있다. Planning은 rollover 전 staging이자 safety boundary다. Teacher/Classroom CRUD를 복제한 generic planning workspace나 독립된 제품 hierarchy는 만들지 않되, SchoolYear 전체 준비 상태와 cross-resource operation을 모으는 얇은 다음 학년도 준비 페이지를 둔다.

## 전제

- Phase A의 current operational teacher/manager 의미와 School별 SchoolYear context resolver가 구현되어 있다.
- Target School은 active이고 active SchoolYear와 planning SchoolYear가 각각 정확히 하나 존재한다.
- Planning SchoolYear는 current active SchoolYear의 바로 다음 학년도다.
- Teacher User와 Classroom의 `school_year_id`는 생성 후 변경하지 않는다.
- `/teachers`와 `/classrooms`는 active-year canonical surface로 유지한다.
- Planning ordinary Teacher는 planning 상태에서 로그인할 수 없고, active planning manager만 명시적인 planning login context로 기존 Teacher login surface를 사용할 수 있다.
- Planning Student 준비, rollover reversal/recovery, archived authentication과 별도 generic historical UI는 이 phase 밖이다.

## Actor/authority matrix

| Operation | Global admin | Current operational manager | Active planning manager | 그 밖의 actor |
|---|---|---|---|---|
| SchoolYear context 조회 | 모든 School의 planning/active/archived | 자기 School의 current active, 바로 다음 planning과 archived read-only | 자기 annual SchoolYear인 exact immediate planning만 | Ordinary teacher는 자기 operational year 범위, archived actor는 불가 |
| Planning teacher member create | 모든 active School | 자기 School | 자기 planning SchoolYear | 불가 |
| Planning teacher 기본 정보/grade edit와 member lifecycle | 모든 active School | 자기 School | 자기 planning SchoolYear | 불가 |
| Planning manager 지정·교체·해제 | 모든 active School | 자기 School의 exact immediate planning SchoolYear | 불가 | 불가 |
| Classroom 단건 create | 선택한 active School의 active/planning SchoolYear | 자기 active School의 current active와 바로 다음 planning SchoolYear | 자기 planning SchoolYear | 불가 |
| Planning Classroom grade/class_label edit/delete | 선택한 active School의 planning SchoolYear | 자기 active School의 바로 다음 planning SchoolYear | 자기 planning SchoolYear | 불가 |
| Planning Teacher의 HomeroomAssignment 단건 연결·변경·해제 | 선택한 active School의 planning SchoolYear | 자기 active School의 바로 다음 planning SchoolYear | 자기 planning SchoolYear | 불가 |

여기서 current operational manager는 active User, active SchoolYear, active School과 annual manager role을 모두 만족하는 actor다. Active planning manager는 active User, active School, planning SchoolYear, annual manager role과 exact immediate planning relation을 만족하는 preparation actor이며 current operational authority는 얻지 않는다. Archived annual account는 role과 관계없이 authority를 얻지 않는다.

Manager용 operation은 session actor의 annual School로 scope를 고정한다. Global admin은 명시적인 School에서 시작하되 School과 planning SchoolYear의 관계를 server-side로 resolve한다. UI control의 노출 여부와 무관하게 모든 write boundary에서 actor authority, School ownership과 planning status를 재검증한다.

같은 `/teachers`, `/classrooms` surface라도 mutation 가능성은 선택된 SchoolYear status와 actor authority에 따라 policy에서 구분한다. Active는 기존 operation 계약, planning은 이 문서에서 허용한 준비 mutation, archived는 read-only다. Planning ordinary Teacher는 준비 대상일 뿐 actor가 아니며 active planning manager만 자기 exact planning context의 preparation actor가 될 수 있다.

## Surface와 navigation

School overview의 `다음 학년도 준비` 영역은 다음 상태를 제공한다.

- `2027학년도 준비 중`
- 준비된 planning teacher 수
- 준비된 planning Classroom 수
- 현재 담임 연결 수 / 준비된 planning Classroom 수
- Planning manager 확정 여부
- `선생님 준비`, `교실 준비`, `담임 연결` 진입점

분모와 개수는 해당 School의 유일한 planning SchoolYear에 속한 모든 Teacher/Classroom 준비 row를 기준으로 한다. 이 값은 완료 조건이 아니라 얼마나 미리 준비했는지 보여주는 정보다. Planning Teacher/Classroom의 기존 `active` boolean은 준비 현황의 분모를 줄이거나 준비 row를 켜고 끄는 사용자 상태로 사용하지 않는다. 현재 담임 연결 수는 B6 integrity를 만족하는 teacher와 Classroom을 잇는 `ended_on IS NULL` assignment만 센다. Planning context가 없거나 유효하지 않으면 active 또는 archived context로 fallback하지 않는다.

준비 카드는 주요 count/status만 요약하고 `/schools/:school_id/planning`의 얇은 다음 학년도 준비 페이지로 가는 명확한 entry를 제공한다. 이 페이지는 School 이름, planning 연도/status, teacher/Classroom 준비 수, 담임 연결 현황과 planning manager 지정 여부를 보여준다. Global admin, 자기 School의 current operational manager와 해당 active planning manager가 조회할 수 있고 ordinary teacher는 조회할 수 없다. Planning SchoolYear가 없거나 School이 inactive이면 fail closed한다.

준비 페이지의 `선생님 준비`와 `담임 연결`은 기존 `/teachers`, `교실 준비`는 기존 `/classrooms`를 명시적인 planning SchoolYear context로 연다. Planning 담임 연결은 active-year UX와 같이 `/teachers` context에서 Teacher 설정으로 진입해 관리하며, planning `/classrooms`는 담임 정보를 표시할 수 있지만 변경 form을 제공하지 않는다. Planning 전용 Teacher/Classroom CRUD와 lifecycle별 controller/view 복제는 만들지 않는다. B8은 이 orchestration page의 정보성 preparation status를 정의하고 실제 rollover eligibility와 전환은 후속 단계로 남긴다.

기본 `/teachers`, `/classrooms` 진입은 계속 current active SchoolYear다. Planning 또는 archived context는 사용자가 권한 안에서 School과 SchoolYear를 명시적으로 선택한 경우에만 사용한다. URL의 SchoolYear id만 신뢰하지 않고 actor에게 허용된 School의 server-side SchoolYear scope에서 status와 ownership을 함께 확인한다. 선택이 없거나 유효하지 않으면 planning/archived로 추측하거나 fallback하지 않는다.

## Planning teacher bulk contract

한 요청은 한 School의 하나의 planning SchoolYear에 여러 annual teacher User를 생성한다. Active teacher를 이동·복제하지 않으며 이름, `login_id`, email 또는 avatar로 다른 연도의 동일 인물을 추론하지 않는다.

각 row의 입력은 다음과 같다.

- 이름
- `login_id`
- grade 1..6
- optional gender와 avatar 선택

`school_year_id`, role, `school_role`, active 상태와 credential field는 client 입력으로 받지 않는다. Server가 teacher role, resolved planning SchoolYear, active account와 `school_role: member`를 지정한다. `login_id` normalization과 SchoolYear-scoped uniqueness, 이름·grade·gender·avatar validation은 기존 User 계약을 따른다. Avatar는 현재 teacher 생성의 허용 pool과 기본 선택 정책을 재사용하며 active-year User의 avatar를 복사하지 않는다.

Global admin과 manager의 초기 bulk 모두 member teacher만 생성한다. Manager 지정·교체·해제는 bulk row option으로 섞지 않고 별도의 authorized planning manager operation으로 분리한다. 이로써 manager용 payload 조작으로 `school_role: manager`를 만들 수 없고 두 actor가 같은 member 생성 operation을 공유할 수 있다.

## Planning manager designation

Planning manager 지정은 teacher bootstrap 뒤의 별도 B7 단계다. 새 successor/proposal model이나 상태를 만들지 않고 planning SchoolYear의 annual Teacher `school_role` (`member`/`manager`)을 canonical source로 사용한다.

Current operational manager는 자기 School의 다음 학년도 준비와 인수인계를 책임진다. 현재 manager A가 planning SchoolYear와 annual Teacher를 준비하고 다음 manager B를 지정하면 A와 B가 같은 planning preparation authority로 공동 준비한다. Global admin은 전체 School을 감독하고 필요하면 planning manager를 지정·교체·해제하며 actual rollover는 계속 global admin만 실행한다.

- Global admin은 active School의 명시적으로 선택되고 server-side로 승인된 planning SchoolYear에서 manager를 지정·교체·해제할 수 있다. Current operational manager도 자기 active School의 exact immediate planning SchoolYear에서 같은 operation을 수행할 수 있다. Planning manager 자신, ordinary teacher와 그 밖의 actor는 수행할 수 없다.
- Target은 해당 School과 planning SchoolYear에 속한 active `role: teacher` annual User여야 한다. Inactive Teacher, 다른 School, active/archived SchoolYear의 Teacher와 admin User 등 non-teacher는 target scope에 포함하지 않는다.
- Explicit School/SchoolYear/Teacher id는 client context일 뿐 authority source가 아니다. Malformed id, cross-School, cross-year, active-year-as-planning, archived, inactive School, planning이 아닌 임의 year와 Teacher/SchoolYear 불일치는 fallback 없이 fail closed한다. Planning SchoolYear가 없으면 mutation control이나 fallback target을 제공하지 않는다.
- Planning 과정에서는 manager가 0명 또는 1명일 수 있다. 기존 planning manager가 있으면 같은 transaction에서 `member`로 내리고 새 target을 `manager`로 지정한다.
- 교체 transaction은 planning SchoolYear와 관련 manager row를 lock하고 demotion/promotion을 원자적으로 수행한다. 실패하면 기존 manager를 유지하며 정상 완료 뒤 manager가 둘 이상 존재할 수 없다. SchoolYear별 manager partial unique DB index를 최종 방어선으로 유지한다.
- 동일 target이 이미 manager이면 추가 row나 role churn 없이 idempotent success로 처리할 수 있다. 해제는 현재 planning manager를 `member`로 되돌려 manager 0명 상태를 허용한다.
- Manager role 변경은 HomeroomAssignment, Teacher profile, grade, credential 또는 `active` 값을 변경하지 않는다. Planning manager는 반드시 active여야 하며 manager인 동안 deactivate할 수 없다. 먼저 global admin 또는 authorized current operational manager가 manager를 교체하거나 해제해야 한다.
- 기존 active-year manager endpoint는 계속 active SchoolYear만 암묵적으로 대상으로 삼으며 planning 지원 때문에 target scope가 넓어지지 않는다. Planning mutation은 request에서 SchoolYear context를 명시하고 server-side에서 planning status와 ownership을 다시 검증한다.

Planning Teacher의 `school_role: manager`는 다음 학년도 관리자 준비 정보일 뿐 current operational authority가 아니다. Active planning manager는 B12 session eligibility 안에서 preparation operation에 로그인할 수 있지만 active SchoolYear operation, archive 조회, manager mutation이나 rollover를 수행할 수 없다. 실제 운영 manager 권한은 SchoolYear가 active로 전환된 뒤 기존 invariant에 따라 생긴다.

기존 `/schools/:id/edit` School settings는 학교 이름, 표시 색상, active SchoolYear의 현재 운영 manager와 School lifecycle만 관리하며 planning 정보나 mutation control을 추가하지 않는다. Planning manager UI는 다음 학년도 준비 페이지에 둔다. Planning manager가 없으면 `아직 다음 학년도 학교 관리자가 지정되지 않았습니다.`에 해당하는 localized empty state를 표시하고, 후보 selector에는 해당 planning SchoolYear의 active annual Teacher만 포함한다. Global admin과 자기 School의 current operational manager에게 manager mutation control을 보여주고 planning manager 자신에게는 보여주지 않는다. 별도 planning-manager-only workspace는 만들지 않는다.

Source manager를 복제하거나 destination manager로 자동 지정하지 않는다. Current manager의 successor 추천/proposal도 B7에 포함하지 않으며 실제 필요가 확인되면 별도 canonical specification과 승인을 거친다.

Planning 중 manager 0명은 허용한다. 다만 후속 rollover eligibility의 현재 확정된 최소 invariant는 destination planning SchoolYear에 manager가 정확히 1명인 것이다. B7은 manager cardinality와 mutation만 제공하며 실제 eligibility 판정과 전환은 후속 단계에서 다룬다.

## Planning preparation status와 rollover 경계

B8에서 planning SchoolYear는 다음 학년도 운영 데이터를 미리 준비하는 staging 영역이다. Teacher, Classroom과 HomeroomAssignment 구성을 planning 중 모두 완료할 의무는 없으며 active 전환 이후에도 기존 운영 surface에서 추가·수정할 수 있다.

```text
preparation status = 얼마나 미리 준비했는지 보여주는 정보
rollover eligibility = 실제 SchoolYear 전환에 필요한 최소 invariant
```

B8은 전체 `ready?`나 구조적 준비 완료를 판정하지 않는다. Planning Teacher 1명이 다음 학년도 manager이고 Classroom과 HomeroomAssignment가 0개인 상태도 정상적인 planning 상태이며 현재 확정된 최소 rollover invariant를 충족할 수 있다.

### Informational preparation status

Preparation page는 다음 값을 정보성 현황으로 표시한다.

- planning annual Teacher 수
- planning Classroom 수
- current HomeroomAssignment가 연결된 Classroom 수 / 전체 planning Classroom 수
- planning manager 지정 여부와 manager 이름

Teacher 수, Classroom 수, 모든 Classroom의 담임 연결 여부, 모든 Teacher의 grade나 담임 배정 여부, Student/roster와 planning Teacher/Classroom의 `active` boolean은 rollover blocker가 아니다. Assignment의 same-SchoolYear, grade와 cardinality integrity는 기존 validation과 DB constraint를 그대로 신뢰하며 preparation status에서 다시 구현하지 않는다.

화면은 Teacher/Classroom/Homeroom 현황을 경고성 완료 조건으로 표현하지 않는다. `선생님 5명 준비`, `교실 3개 준비`, `담임 연결 2 / 3`처럼 현재 상태를 보여주고, 운영 시작 후에도 추가하거나 변경할 수 있음을 안내한다.

### Rollover eligibility

B9가 확정하는 최소 business invariant는 planning SchoolYear의 annual Teacher 중 `school_role: manager`가 정확히 1명인 것이다. Manager 0명은 ineligible, 1명은 eligible, 2명 이상은 정상 DB invariant 위반이면서 ineligible이다. SchoolYear별 manager partial unique index를 최종 방어선으로 유지하되 domain 판정은 항상 `exactly 1`을 사용한다.

Teacher/Classroom/Homeroom 준비 현황은 business eligibility에 영향을 주지 않는다. 예를 들어 planning Teacher 1명이 manager이고 Classroom과 HomeroomAssignment가 0개인 상태도 business eligibility를 충족한다. Planning manager 삭제로 manager가 0명이 되면 즉시 ineligible이 되고 global admin이 manager를 지정하면 다시 eligible이 된다.

Eligibility는 현재 data에서 계산하는 derived state다. `ready`, `rollover_ready`, `prepared` column이나 enum으로 저장하지 않는다. 후속 구현에서 작은 `SchoolYears::RolloverEligibility` query를 둘 수 있으며, 정확한 이름은 당시 namespace에 맞춘다. 최소 결과는 `eligible?`, `manager`, `manager_count`이고 필요하면 `inactive_school`, `active_school_year_missing`, `planning_school_year_missing`, `non_consecutive_year`, `manager_missing`, `manager_cardinality_invalid` 같은 stable error key를 반환할 수 있다. Authorization과 한국어 문장은 query에 넣지 않으며 generic readiness framework나 state machine을 만들지 않는다.

Business eligibility를 계산하기 전에 rollover target 자체에 다음 structural safety precondition을 적용한다.

- School이 active다.
- Current active SchoolYear와 planning SchoolYear가 각각 정확히 하나 존재한다.
- 두 SchoolYear가 같은 School에 속한다.
- Planning year는 active year + 1이다.
- Current SchoolYear status는 active이고 target SchoolYear status는 planning이다.

하나라도 깨지면 fail closed한다. 이는 사용자가 Teacher/Classroom을 더 준비해서 해결하는 checklist나 preparation blocker가 아니라 정상 UI flow에서는 발생하지 않아야 하는 integrity/configuration error다.

Planning manager는 rollover 전 operational authority가 아니다. Rollover가 성공해 planning SchoolYear가 active가 되면 해당 annual Teacher의 기존 `school_role: manager`가 새 active SchoolYear의 운영 authority 근거가 된다. Successor record를 만들거나 role을 다른 annual User에 복사하지 않는다. Planning manager의 `active` boolean을 별도 eligibility checklist로 사용하지 않으며, 인증 불가능한 비정상 row가 발견되면 후속 rollover transaction safety validation에서 fail closed한다.

Preparation page는 기존 정보성 count를 유지하면서 향후 작은 `운영 전환 조건` 영역에서 manager 지정 여부만 eligibility 조건으로 구분할 수 있다. Manager가 없으면 `다음 학년도 운영을 시작하려면 대표 선생님을 지정해야 합니다.`에 해당하는 localized 안내를 표시하고, Teacher/Classroom/Homeroom count를 완료/실패 checklist로 바꾸지 않는다. B9에서는 rollover button을 추가하지 않는다.

B9는 target eligibility만 정의한다. 실제 실행 actor, confirmation UX, 실행 날짜, locking과 transaction ordering, active → archived 및 planning → active transition, session revocation, failure rollback, recovery/idempotency와 audit/logging 필요 여부는 실제 rollover canonical specification에서 별도로 결정한다.

## Actual SchoolYear rollover contract

B10 actual rollover는 B9 business eligibility와 structural safety를 통과한 School의 annual lifecycle을 명시적으로 전환하는 operation이다. 실행 권한은 global admin에게만 있다. Current operational manager는 planning data를 준비할 수 있지만 SchoolYear lifecycle을 전환할 수 없으며 ordinary teacher와 planning Teacher도 실행할 수 없다.

정상 transition은 정확히 다음 두 status 변경이다.

```text
current active SchoolYear → archived
target planning SchoolYear → active
```

Planning manager의 `school_role`을 복사하거나 새 User를 만들지 않는다. Target SchoolYear가 active가 되면 기존 planning manager가 자연스럽게 새 operational manager가 되고, 이전 manager는 자신의 SchoolYear가 archived되므로 operational authority를 잃는다.

### Transaction과 locking

Rollover는 하나의 DB transaction에서 수행한다. School, current active SchoolYear, target planning SchoolYear 순서로 lock하고, lock 이후 B9 structural safety와 manager exactly one business eligibility를 다시 검증한다. 검증을 통과한 뒤 같은 transaction에서 current active를 archived로, target planning을 active로 변경한다. 두 status 변경 중 하나라도 실패하거나 transaction 도중 invariant가 달라지면 전체 rollback하며 부분 전환을 허용하지 않는다.

다음 상태는 fallback이나 성공 처리 없이 fail closed한다.

- School이 inactive다.
- Current active SchoolYear 또는 target planning SchoolYear가 없거나 정확히 하나가 아니다.
- Active와 planning SchoolYear가 서로 다른 School에 속한다.
- Planning year가 active year + 1이 아니다.
- Current target status가 각각 active/planning이 아니다.
- Planning manager가 정확히 1명이 아니다.
- 이미 완료된 rollover의 stale/repeated request다.
- Lock 이후 transaction 도중 structural 또는 business invariant가 바뀐다.

Repeated request는 이미 완료된 transition을 idempotent success로 가장하지 않는다. 요청이 가리키는 active/planning pair가 더 이상 정상 current state가 아니면 실패한다.

### 날짜와 실행 UX

B10은 calendar/date restriction을 두지 않는다. `Date.current.year`, 특정 월·일 또는 학기 시작일은 eligibility나 실행 조건이 아니며 global admin의 명시적 실행과 B9 invariant만 기준으로 삼는다. 미래 연도 검증을 위한 production time-travel helper나 debug endpoint를 만들지 않는다.

향후 implementation은 global admin의 planning preparation page에 rollover action을 제공하고 실행 전에 명확한 confirmation을 요구한다. Confirmation은 현재 학년도가 archived되고 다음 학년도가 active가 되며 새 학년도 manager가 운영 권한을 얻고 단순 취소/undo 기능은 제공되지 않는다는 의미를 전달한다. 정확한 사용자 문구는 locale implementation 단계에서 정한다.

### Runtime result와 authentication boundary

성공 직후 다음 invariant를 만족한다.

- 이전 active SchoolYear는 archived이고 target planning SchoolYear는 active다.
- School에는 active SchoolYear가 정확히 하나 있으며 planning SchoolYear는 0개일 수 있다.
- 전환된 SchoolYear는 더 이상 planning preparation 대상으로 보이지 않는다.
- 새 active SchoolYear의 기존 manager가 operational authority를 얻고 이전 manager는 이를 잃는다.
- `/teachers`와 `/classrooms`의 기본 active context는 새 active SchoolYear를 사용한다.
- 새 planning SchoolYear, Teacher, Classroom, HomeroomAssignment 또는 User를 자동 생성·복사하지 않는다.

Archived SchoolYear Teacher는 rollover 이후 current operational authority를 사용할 수 없어야 하고 새 active SchoolYear Teacher는 기존 authentication eligibility에 따라 로그인할 수 있어야 한다. 명시적인 session revocation이 필요한지는 implementation 단계에서 현재 authentication/session 구조를 확인해 결정한다. 이 결과를 위해 session-version framework를 선행 도입하지 않는다.

현재 실제 연도와 무관한 미래 SchoolYear/archived 상태는 development 또는 browser 검증 전에 Rails console로 최소 test state를 구성할 수 있다. Console은 fixture/state setup에만 사용하고 실제 transition은 production rollover implementation을 통해 검증한다. Production helper/module/debug endpoint로 시간을 가장하지 않는다.

B10은 자동·날짜 기반 rollover, next planning SchoolYear 자동 생성, Teacher/Classroom/Student 복사·승계, rollback/undo UI, generic lifecycle engine과 audit framework 확장을 포함하지 않는다.

## Archived SchoolYear read-only authority

B11은 Teacher User를 계속 annual operational account로 유지하면서 historical School data의 stewardship를 current operational manager에게 승계한다. Annual Teacher account는 영구적인 개인 identity가 아니라 특정 SchoolYear 운영을 위해 학교가 발급한 업무 계정이다. Persistent TeacherAccount, Person identity, cross-year membership/account linking 또는 `previous_user_id`를 도입하지 않는다.

### Archive authority와 승계

- Global admin은 기존 global authority 범위에서 모든 School의 active, planning과 archived SchoolYear를 조회할 수 있다.
- Current operational manager는 자기 School의 current active 운영, immediate planning 준비와 모든 archived SchoolYear read-only 조회가 가능하다.
- Archive authority는 archived annual User의 과거 role이 아니라 현재 active SchoolYear의 operational manager authority에서 나온다.
- Current ordinary Teacher는 자기 current operational 범위만 사용하며 archived SchoolYear를 조회할 수 없다.
- Archived SchoolYear의 former manager와 former Teacher는 로그인하거나 archived data를 직접 조회할 수 없다. 과거 manager role은 지속적인 archive authority가 아니다.

Rollover 전 current manager는 자기 School의 기존 archive를 조회할 수 있다. Rollover 후 이전 manager의 annual account는 archived되어 authority를 잃고 새 active SchoolYear manager가 같은 School의 모든 과거 archive stewardship를 이어받는다. 과거 자료가 필요한 former Teacher는 current manager 또는 global admin을 통해 확인한다.

### Archived read-only 범위

Global admin과 authorized current manager는 현재 서비스가 SchoolYear-aware 조회 surface를 제공하는 범위에서 다음 archived data를 조회할 수 있다.

- Archived Teacher 목록과 상세
- Archived Classroom 목록과 상세
- Classroom의 historical HomeroomAssignment 정보
- Archived Classroom의 Student/roster 정보
- 그 밖에 이미 존재하는 archived operational record의 조회 surface

별도 `/archives` CRUD나 generic archive dashboard를 만들지 않는다. 기존 `/teachers?school_id=...&school_year_id=...`와 `/classrooms?school_id=...&school_year_id=...` 같은 SchoolYear-aware surface를 재사용한다. Current manager의 selector에는 자기 School의 archived years를 포함할 수 있지만 ordinary Teacher selector는 확장하지 않는다. Global admin의 기존 multi-School/year selector semantics를 유지한다.

Current manager의 `/teachers`, `/classrooms` 기본 context는 계속 current active SchoolYear다. Archived context는 authorized actor가 명시적으로 선택한 경우에만 사용하고 오래된 year를 default나 fallback으로 추측하지 않는다. Current manager는 query parameter, record id 또는 detail URL 조작으로 다른 School archive를 조회할 수 없으며 global admin만 cross-School archive authority를 가진다.

Archived context에서는 조회만 허용한다. 최소 다음 mutation과 그 UI control을 모두 금지한다.

- Teacher 생성, profile/grade 수정, hard delete, deactivate/reactivate와 temporary credential 발급·재발급
- Manager 지정·교체·해제
- Classroom 생성, grade/class_label 수정, hard delete와 deactivate/reactivate
- HomeroomAssignment 생성·교체·해제
- Student 생성·수정·삭제와 roster mutation
- 그 밖의 SchoolYear operational mutation

Read-only는 control을 숨기는 것만으로 충족하지 않는다. Direct mutation request도 controller/policy/model/service boundary에서 fail closed해야 하며 archived association을 active/planning context로 fallback하지 않는다.

### Authentication과 annual-account 원칙

Archived browsing을 위해 annual Teacher authentication을 완화하지 않는다. `TeacherSessionsController`는 current active SchoolYear Teacher만 인증하며, rollover 전에 로그인한 Teacher의 SchoolYear가 archived되면 기존 runtime guard가 다음 request에서 session을 종료한다. Current manager는 자신의 current active annual account로 로그인한 상태에서 archive를 조회한다.

Teacher self-signup 없이 planning 단계의 관리자 provisioning, annual credential와 temporary password, 학년도별 role/grade/Classroom 및 rollover 후 새 annual Teacher의 운영 시작이라는 현재 모델을 유지한다. Archived credential을 재발급하거나 오래된 password를 historical access 수단으로 사용하지 않는다. 개인별 `내 과거 기록`, identity reconciliation과 archive access delegation은 실제 필요가 확인될 때 별도 specification한다.

## Planning manager login과 shared preparation authority

B12는 current operational manager와 active planning manager가 planning 기간에 공존하며 같은 immediate planning SchoolYear data를 함께 준비하도록 한다. 예를 들어 2026 manager A는 2026 operational authority와 2027 preparation authority를 가지고, 2027 planning manager B는 2027 preparation authority만 가진다. A와 B는 2027 preparation editor로서는 동일하지만 B는 2026 operational authority를 얻지 않는다.

Global admin, current operational manager와 active planning manager는 authorized exact planning SchoolYear에서 기존 surface와 operation semantics를 재사용해 다음을 수행할 수 있다.

- Planning Teacher 생성과 profile/grade 수정
- Planning member Teacher hard delete 및 deactivate/reactivate
- Planning Classroom 생성·수정·삭제
- Planning HomeroomAssignment 생성·교체·해제
- `/schools/:school_id/planning` preparation page 조회

Planning manager Teacher 자체의 hard delete는 계속 global admin만 수행한다. Manager 지정·교체·해제는 global admin 또는 자기 School의 authorized current operational manager만 수행하며 planning manager 자신은 수행할 수 없다. Planning manager는 active SchoolYear operation, archived 조회, School lifecycle, actual rollover, global-admin-only operation과 다른 School planning에 접근할 수 없다. 별도 planning-manager CRUD, collaborative editing, reservation/presence 또는 conflict framework를 만들지 않고 기존 validation과 transaction behavior를 사용한다.

### Login context와 authentication

별도 planning login route를 만들지 않고 기존 `/schools/:school_id/teacher_login` page와 endpoint를 재사용한다. Login 가능한 annual account는 current active SchoolYear의 active Teacher 또는 exact immediate planning SchoolYear의 active manager Teacher다. Planning ordinary Teacher, inactive planning Teacher, archived Teacher와 다른 School Teacher는 로그인할 수 없다.

같은 School에서 annual `login_id`가 학년도별로 재사용될 수 있으므로 password 추측으로 active/planning account를 자동 선택하지 않는다. 같은 login page에서 로그인할 SchoolYear context를 명시적으로 선택한다.

```text
2026학년도 · 운영 중
2027학년도 · 다음 학년도 준비
```

Default는 current active SchoolYear다. Planning option은 School이 active이고 current active SchoolYear와 exact immediate planning SchoolYear가 존재하며, 그 planning SchoolYear에 active manager가 정확히 1명 있을 때만 보여준다. Planning SchoolYear만 있고 manager가 아직 지정되지 않았으면 option을 노출하지 않는다. Submitted `school_year_id`는 화면 노출 여부와 관계없이 server-side에서 이 login eligibility 전체와 School ownership, active/planning status 및 immediate relation을 다시 검증한다. Hidden/direct parameter로 노출되지 않은 planning SchoolYear를 보내거나 arbitrary, malformed, archived, non-immediate 또는 cross-School SchoolYear를 보내면 다른 account로 fallback하지 않고 fail closed한다.

선택된 annual context에서 User를 정확히 resolve한 뒤 기존 password validation과 rate-limit contract를 그대로 적용한다. 같은 `login_id`가 active와 planning 양쪽에 있어도 explicit context로 구분하며 rate-limit bypass, 별도/shared/master password를 만들지 않는다.

### Session eligibility와 landing

Teacher session은 다음 중 하나일 때만 유효하다.

1. Operational session: Teacher active, School active, Teacher SchoolYear active
2. Planning-manager session: Teacher active, School active, Teacher SchoolYear planning, `school_role: manager`, 해당 School의 exact immediate planning SchoolYear

Planning manager role 해제, 비정상 deactivation, planning year 제거·교체 또는 School 비활성화가 발생하면 다음 request에서 sign out한다. Active Teacher의 기존 landing은 유지하고 planning manager login은 자기 `/schools/:school_id/planning`으로 이동한다. Planning manager가 active-year Teacher/Classroom 또는 School management URL을 직접 입력해도 operational authority를 얻지 않으며 planning access에는 explicit SchoolYear context를 사용한다.

Planning manager가 로그인한 상태에서 global admin rollover로 해당 SchoolYear가 active가 되면 User와 `school_role: manager`를 변경하거나 session을 migration하지 않는다. 다음 request부터 같은 session이 operational-manager eligibility를 자연스럽게 만족하며 navigation과 landing은 새 active context를 사용한다. 재로그인, session-version 또는 별도 handoff framework를 만들지 않는다.

Planning member lifecycle에서 deactivate와 hard delete는 구분한다. Delete는 준비 record를 제거하고 deactivate는 record를 유지한 채 다음 학년도 운영 대상에서 일시 제외한다. Authorized manager가 조회할 수 있는 non-archived Teacher는 active 여부와 관계없이 목록의 기존 설정 surface로 진입할 수 있다. Inactive planning Teacher 설정에서는 reactivate control을 제공하되 grade/Homeroom 준비와 manager 지정 대상에는 포함하지 않는다. Planning ordinary Teacher deactivation 시 current planning HomeroomAssignment가 있으면 같은 operation과 transaction에서 준비 row를 삭제하고 `ended_on` history를 만들지 않은 뒤 Teacher를 inactive로 변경하며 Classroom은 유지한다. Reactivation은 Teacher만 active로 복원하고 삭제된 assignment나 manager role을 자동 복구하지 않으므로 필요하면 사용자가 다시 배정한다. Planning manager deactivation 및 inactive Teacher의 manager 지정·교체 target 사용은 fail closed한다.

B9의 business eligibility는 계속 `school_role: manager` exactly one으로 계산한다. Manager active 상태는 designation/deactivation mutation이 보존해야 하는 integrity invariant이며 별도의 active-manager readiness count나 preparation checklist를 추가하지 않는다.

## Temporary credential contract

각 새 planning teacher는 기존 `AnnualTeacherUsers::TemporaryCredential` 계약으로 temporary password, `password_change_required`와 `TeacherCredentialEvent`를 함께 만든다. 새 credential framework나 평문 저장소를 만들지 않는다.

Temporary password 재발급은 기존 credential service와 audit event를 재사용하되 annual SchoolYear authority를 따른다. Global admin은 active School의 active 또는 planning active Teacher를 관리할 수 있다. Current operational manager는 자기 current active SchoolYear의 active member Teacher와 자기 School의 exact immediate planning SchoolYear에 속한 active member/manager Teacher를 재발급할 수 있다. Active planning manager는 자기 exact planning SchoolYear의 active member Teacher만 재발급할 수 있다. 모든 actor에게 self, inactive, archived, cross-School target은 금지하며 planning manager에게 active-year credential authority를 주지 않는다. Inactive Teacher 설정에는 재발급 control을 표시하지 않고 먼저 reactivate하도록 하며 direct request도 fail closed한다.

- Batch의 모든 teacher row와 credential audit event는 하나의 outer transaction 안에서 성공해야 한다.
- 모든 row를 normalization·validation하고 batch 내부 및 DB의 duplicate를 확인한 뒤 credential을 발급한다.
- 한 row의 teacher 또는 audit event 저장이 실패하면 batch 전체를 rollback한다.
- Plaintext temporary password는 DB, audit event, log, flash/session 또는 재조회 가능한 페이지에 저장하지 않는다.
- 성공한 batch의 모든 temporary password는 commit된 결과에서 한 번만 표시한다.
- 결과 응답은 기존 individual credential 결과처럼 `Cache-Control: no-store`를 적용한다.
- 결과 페이지를 refresh하거나 뒤로 가기 해도 plaintext를 재구성하거나 다시 표시하지 않는다. 분실 시 허용된 actor가 명시적으로 재발급한다.
- Outer transaction이 rollback된 경우 이미 생성했던 in-memory password를 응답에 포함하지 않는다.

기존 credential service의 내부 transaction은 outer transaction에 참여할 수 있지만, 현재 active-year `Teachers::SaveWithAssignment`는 active SchoolYear lookup과 단일-row assignment 흐름을 결합하므로 planning batch를 위해 `active OR planning`으로 확장하지 않는다.

Planning Teacher는 아직 operational account가 아니므로 해당 준비 Teacher를 hard delete할 때 그 Teacher에 종속된 temporary credential issuance 기록도 함께 정리할 수 있다. 이는 planning Teacher 폐기에만 한정하며 최초 credential 발급 계약이나 active/archived Teacher의 credential event 보존 semantics를 변경하지 않는다.

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

## Planning Classroom structure-edit contract

잘못 준비한 planning Classroom의 구조 정보는 기존 Classroom edit/update surface를 재사용하여 수정한다. 별도 planning route/controller/view를 만들지 않는다.

- 수정 가능한 필드는 `grade`와 `class_label`뿐이다. `school_year_id`, School, `active`와 그 밖의 lifecycle/status field는 변경하지 않는다.
- Global admin은 명시적으로 선택하고 server-side로 승인된 active School의 planning SchoolYear Classroom을 수정할 수 있다.
- Current operational manager는 자기 active School의 current active SchoolYear 바로 다음 planning SchoolYear Classroom만 수정할 수 있다.
- Ordinary teacher와 그 밖의 actor는 planning Classroom 수정 authority를 얻지 못한다.
- School, SchoolYear와 Classroom id는 actor에게 허용된 planning association scope에서 resolve한다. Malformed, cross-School, cross-year, archived, inactive School 또는 unauthorized context는 다른 row나 SchoolYear로 fallback하지 않고 fail closed한다.
- Persisted Classroom의 `school_year_id`는 변경할 수 없고 update payload의 School/SchoolYear id를 신뢰하거나 mass assignment하지 않는다.
- 현재 HomeroomAssignment가 없는 planning Classroom은 grade를 변경할 수 있다.
- 현재 담임이 있는 planning Classroom의 `class_label`은 변경할 수 있다. Grade는 현재 Teacher grade와 같은 값으로만 저장할 수 있으며 Teacher grade와 불일치하는 변경은 active Classroom과 동일한 기존 `Classroom#grade_must_match_current_teacher` integrity에 따라 거부한다.
- Grade 변경 실패 시 실패 원인과 담임 해제 후 다시 시도해야 한다는 해결 방법을 공용 Classroom form에 표시하고, 제출한 grade와 planning context를 유지한다. 기존 담임을 자동 해제하거나 다른 Teacher로 재배정하지 않는다. HomeroomAssignment 변경은 B6 Teacher 설정 flow에서만 수행한다.
- `class_label`은 기존 trimming, `반` suffix normalization, 길이·형식 validation과 `(school_year_id, grade, class_label)` uniqueness를 따른다.
- Planning `/classrooms`에서 수정 가능한 Classroom은 기존 용어의 설정 링크로 기존 edit surface에 진입한다.
- 저장 성공 후 같은 School과 planning SchoolYear가 선택된 `/classrooms` context로 복귀한다. Validation 실패 시 같은 context와 제출한 입력값을 form에 유지한다.
- 기존 active-year Classroom edit/update UX, authorization과 validation semantics는 변경하지 않는다.

`SchoolYear.status`가 planning/active/archived 시간 lifecycle을 담당한다. 새 Classroom status enum을 추가하지 않고 Classroom의 `active` boolean 의미를 확장하거나 planning 준비 상태로 UI에 노출하지 않는다. Planning Classroom deactivate/reactivate와 `준비에서 제외`/`다시 포함`은 B5b 범위 밖이다.

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
- Current operational manager와 active planning manager는 자기 exact planning SchoolYear의 Teacher 기본 정보와 grade를 수정할 수 있다. `school_role` 지정·교체·해제는 계속 global admin 경계다.
- Planning member Teacher의 `active` boolean은 다음 학년도 운영 예정 여부를 나타낸다. Active row는 grade/Homeroom 준비 대상이고 inactive row는 record를 보존한 채 운영 대상에서 일시 제외한 상태다. Global admin, current operational manager와 active planning manager는 authorized planning member를 deactivate/reactivate할 수 있다.
- Planning manager는 active 상태를 유지해야 하며 deactivate request는 actor와 관계없이 fail closed한다. `다음 학년도 대표 선생님은 비활성화할 수 없습니다. 먼저 대표 선생님을 변경하거나 해제해 주세요.`에 해당하는 localized 안내를 제공한다. 별도 lifecycle/status enum은 만들지 않는다.
- 잘못 준비한 planning member Teacher의 향후 hard delete는 global admin과 자기 School의 바로 다음 planning을 관리하는 current operational manager에게 허용한다. Planning manager Teacher 삭제는 B7 authority를 우회하지 않도록 global admin에게만 허용한다.
- Planning Teacher에 current HomeroomAssignment가 있으면 운영 history를 만들지 않고 해당 준비 assignment를 제거한 뒤 Teacher를 삭제할 수 있다. Active/archived Teacher의 기존 보존과 lifecycle 정책에는 적용하지 않는다.

### Classroom

- 허용된 actor는 planning Classroom의 grade와 `class_label`을 수정할 수 있다.
- Grade 변경이 current planning assignment와 불일치하면 거부한다. 먼저 담임을 변경·해제해야 한다.
- Planning Classroom deactivate/reactivate와 `준비에서 제외`/`다시 포함`은 정의하거나 구현하지 않는다.
- 잘못 준비한 planning Classroom의 향후 hard delete는 global admin과 자기 School의 바로 다음 planning을 관리하는 current operational manager에게 허용하고 ordinary teacher에게는 허용하지 않는다. Current HomeroomAssignment가 있으면 운영 history를 만들지 않고 해당 준비 assignment를 제거한 뒤 Classroom을 삭제할 수 있다. Active/archived Classroom의 기존 삭제 정책에는 적용하지 않는다.

### HomeroomAssignment

- Planning 연결 변경과 해제는 current row를 삭제하며 ended history를 만들지 않는다.
- Rollover로 SchoolYear가 active가 된 뒤에는 해당 assignment가 실제 운영 이력이므로 planning 삭제 semantics를 적용하지 않는다.
- Planning SchoolYear가 active 또는 archived로 바뀐 stale form은 mutation하지 못한다.

## Transaction, locking과 atomicity

각 teacher batch, Classroom 단건 생성·구조 수정, planning assignment 단건 operation과 manager designation은 독립된 transaction boundary다.

- Request 시작 시 actor와 explicit School을 authorize하고 planning context를 server-side로 resolve한다.
- Transaction 안에서 target School과 planning SchoolYear를 deterministic하게 lock한다.
- Lock 이후 operation별 actor authority, active School과 유일한 planning context를 재검증한다. Planning manager 지정·교체·해제에서는 actor가 global admin이거나 target School의 current operational manager이며 exact immediate planning context인지 다시 확인한다.
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
- Planning Classroom structure update는 resolved planning SchoolYear의 Classroom만 조회하며 submitted School/SchoolYear id로 persisted association을 변경하지 않는다.
- Stale form 처리 시 다른 SchoolYear로 fallback하지 않는다. 같은 `/teachers`·`/classrooms` surface를 사용하더라도 request마다 선택된 context와 현재 권한을 다시 확인한다.

## Acceptance criteria

1. Global admin은 모든 active School, current operational manager는 자기 School의 planning teacher/Classroom/HomeroomAssignment만 준비할 수 있다.
2. Ordinary active Teacher, planning ordinary Teacher, archived/inactive Teacher와 그 밖의 unauthorized actor는 planning preparation authority를 얻지 못한다.
3. Teacher bulk는 member annual User만 만들고 기존 active teacher를 이동·복제하지 않는다.
4. Planning manager 지정·교체·해제는 teacher bulk와 분리되며 global admin 또는 자기 School의 exact immediate planning context를 관리하는 current operational manager만 수행한다. Planning manager 자신과 ordinary Teacher는 수행할 수 없고 successor 추천/proposal workflow는 제공하지 않는다.
5. Teacher batch의 모든 row와 credential audit event가 한 transaction에서 commit되거나 전체 rollback된다.
6. 성공한 temporary passwords만 no-store 결과에서 한 번 표시되고 평문은 저장·재표시되지 않는다.
7. Classroom 준비는 기존 `/classrooms/new`와 `POST /classrooms`에서 단건 생성하며, 선택·승인된 active 또는 planning SchoolYear에만 새 row를 만들고 기존 normalization, validation, unique DB index와 inactive-School 실패 계약을 유지한다.
8. Classroom create context의 malformed, cross-School, unauthorized 또는 archived 입력은 fail closed하며 validation 실패 시 선택 context를 유지하고 planning 성공 후 해당 `/classrooms` context로 복귀한다.
9. Planning HomeroomAssignment는 기존 `/teachers` context의 Teacher 설정 화면에서 Teacher 한 건씩 관리한다. 기존 `teacher-classroom-picker`를 재사용하여 grade 변경 즉시 같은 화면에서 planning Classroom 후보를 갱신하고, 최종 저장 한 번으로 grade와 assignment를 함께 반영한다. Picker request는 planning SchoolYear와 Teacher context를 보존하고 server-side scope를 다시 검증한다. Classroom 후보는 같은 planning SchoolYear의 active Classroom이며 Teacher grade와 일치해야 한다. 다른 Teacher의 current assignment에 사용된 Classroom은 제외하고 현재 이 Teacher에게 연결된 Classroom은 유지 후보에 포함한다. Grade가 없거나 Classroom과 grade가 다른 Teacher는 연결할 수 없다. Global admin은 선택한 planning context, current manager는 자기 School의 바로 다음 planning context에서만 수행하고 malformed, cross-School, cross-year, inactive participant, grade mismatch, 이미 다른 Teacher에게 배정된 Classroom, archived와 unauthorized 조합은 fail closed한다. `started_on`은 해당 SchoolYear의 3월 1일이며 planning 중 변경·해제는 기존 row를 삭제해 `ended_on` history를 만들지 않는다. Active-year의 기존 assignment lifecycle과 history semantics는 유지하고 planning `/classrooms`에는 담임 변경 form을 제공하지 않는다.
10. Planning teacher/Classroom 생성과 담임 연결은 단계적으로 분리되며 Classroom 단건 생성은 Student나 담임을 함께 생성·연결하지 않는다. School overview는 준비된 planning teacher 수, 준비된 planning Classroom 수, 담임 연결 현황과 manager 준비 상태 및 entry를 제공한다.
11. Planning member Teacher는 생성, 기본 정보/grade 수정, HomeroomAssignment 연결·교체·해제와 deactivate/reactivate를 지원한다. Deactivation은 current 준비 assignment를 history 없이 삭제하고 reactivation은 이를 자동 복구하지 않는다.
12. Global admin은 선택한 active School의 planning Classroom에서 기존 edit/update surface로 `grade`와 `class_label`을 수정할 수 있다.
13. Current operational manager는 자기 active School의 바로 다음 planning Classroom에서 같은 구조 정보를 수정할 수 있다.
14. Ordinary teacher와 그 밖의 actor는 planning Classroom을 수정할 수 없다.
15. Archived, cross-School, cross-year, malformed, inactive School과 unauthorized Classroom update context는 fail closed한다.
16. Planning Classroom의 `school_year_id`는 update payload나 context 조작으로 변경할 수 없다.
17. 현재 HomeroomAssignment가 없는 planning Classroom은 grade를 변경할 수 있다.
18. 현재 담임이 있는 planning Classroom은 Teacher grade와 불일치하도록 grade를 변경할 수 없다. 실패 화면은 원인과 담임 해제 안내를 표시하고 제출한 grade와 planning context를 유지하며, 기존 HomeroomAssignment를 자동 해제하거나 재배정하지 않는다.
19. Planning Classroom의 `class_label` 수정은 기존 validation과 normalization을 따른다.
20. Planning Classroom 구조 수정 성공 후 같은 School과 planning SchoolYear의 `/classrooms` context로 복귀한다.
21. Validation 실패 후 같은 planning context와 제출한 `grade`/`class_label` 값을 form에 유지한다.
22. Active-year Classroom의 기존 edit/update UX, authorization과 validation semantics는 회귀하지 않는다.
23. 모든 mutation은 lock 이후 authority, active School, planning context와 record ownership을 재검증하고 DB conflict를 포함한 실패에서 기존 active year와 planning data를 보존한다.
24. URL, hidden field와 nested parameter 조작으로 School, SchoolYear, role, lifecycle 또는 credential scope를 바꿀 수 없다.
25. `/teachers`와 `/classrooms`의 기본 진입은 active year를 유지한다. 명시적으로 선택되고 server-side로 승인된 planning/archived SchoolYear context에서 같은 surface를 재사용하며 archived mutation은 허용하지 않는다.
26. Planning bootstrap은 Student 생성, 실제 rollover transition 또는 archived authentication을 수행하지 않는다.
27. Global admin은 active School의 명시적으로 승인된 planning SchoolYear Teacher를 manager로 지정할 수 있다.
28. 기존 planning manager가 있으면 하나의 transaction에서 member로 내리고 새 target을 manager로 지정하며 실패 시 기존 manager를 보존한다.
29. Planning manager를 해제해 manager 0명 상태로 되돌릴 수 있고 동일 manager 재지정은 idempotent하며 정상 완료 후 manager는 최대 1명이다.
30. Planning manager role 변경은 HomeroomAssignment, Teacher profile, grade, credential와 active 값을 변경하지 않는다.
31. Current operational manager는 자기 School의 exact immediate planning manager를 지정·교체·해제할 수 있다. Planning manager 자신, ordinary teacher와 그 밖의 unauthorized actor는 수행할 수 없다.
32. Planning Teacher의 `school_role: manager`만으로 current operational authority는 생기지 않지만 active exact planning manager는 B12 login/session eligibility와 preparation authority를 얻는다.
33. Cross-School, cross-year, active-year-as-planning, archived, inactive School, malformed와 그 밖의 unauthorized planning manager context는 fail closed한다.
34. 해당 planning SchoolYear 밖의 Teacher와 non-teacher target은 거부한다.
35. 기존 active-year manager 지정·교체·해제의 authorization, transaction/locking, target scope와 redirect semantics는 회귀하지 않는다.
36. `/schools/:id/edit`는 학교 자체 설정과 active SchoolYear manager만 유지하며 planning SchoolYear 정보나 manager mutation control을 표시하지 않는다.
37. Global admin, 자기 School의 current operational manager와 active exact planning manager는 얇은 다음 학년도 준비 페이지로 진입할 수 있다. Ordinary teacher, 다른 School actor, inactive School과 planning SchoolYear가 없는 context는 거부한다.
38. 준비 페이지는 School/planning year/status, teacher/Classroom 수, HomeroomAssignment 현황과 planning manager 상태를 표시하고 기존 `/teachers`·`/classrooms` planning context 링크를 유지한다.
39. Planning manager가 없으면 localized empty state를 표시하며 후보는 해당 planning SchoolYear의 active annual Teacher로 제한한다. Global admin과 자기 School의 current operational manager에게 지정·교체·해제 control을 표시하고 planning manager에게는 표시하지 않는다.
40. Planning manager가 0명이면 rollover business eligibility는 false다.
41. Planning manager가 정확히 1명이면 rollover business eligibility는 true다.
42. Planning manager가 비정상적으로 2명 이상이면 business eligibility는 false다.
43. Planning Teacher 수는 eligibility에 영향을 주지 않는다.
44. Planning Classroom 수는 eligibility에 영향을 주지 않으며 Classroom 0개도 허용한다.
45. 모든 Classroom의 HomeroomAssignment 연결 여부와 모든 Teacher의 grade 또는 담임 배정 여부는 eligibility에 영향을 주지 않는다.
46. Student/roster와 planning Teacher/Classroom의 `active` boolean은 eligibility checklist가 아니다.
47. Preparation status와 rollover eligibility는 별개로 표시하며 Teacher/Classroom/Homeroom 현황을 완료/실패 checklist로 표현하지 않는다.
48. Eligibility는 persisted status가 아니라 현재 planning manager data에서 계산하는 derived state다.
49. Planning manager 지정과 삭제에 따라 eligibility 결과가 즉시 달라진다.
50. School inactive, active/planning SchoolYear 누락·복수·소속 불일치 또는 status 불일치는 preparation blocker가 아닌 structural error로 fail closed한다.
51. Planning SchoolYear는 current active SchoolYear와 같은 School에 속하고 연도가 active year + 1이어야 한다.
52. Planning manager는 rollover 전 operational authority를 갖지 않으며 별도 successor record나 role 복사를 사용하지 않는다.
53. 후속 eligibility query는 `eligible?`, manager와 manager count를 제공할 수 있고 authorization과 localized 문장을 담당하지 않는다.
54. Preparation page는 manager 지정 여부만 운영 전환 조건으로 구분할 수 있으며 B9에서는 rollover button을 제공하지 않는다.
55. 실제 rollover 실행 authority, confirmation, 날짜, locking/transaction, status transition, session 처리, rollback/recovery와 audit 정책은 후속 specification에서 결정한다.
56. 잘못 준비한 planning Classroom은 허용된 global admin 또는 current operational manager가 current 준비 assignment를 제거한 뒤 hard delete할 수 있다.
57. 잘못 준비한 planning member Teacher는 허용된 global admin 또는 current operational manager가 current 준비 assignment를 제거한 뒤 hard delete할 수 있고, planning manager Teacher는 global admin만 삭제할 수 있다.
58. Planning Teacher hard delete는 그 준비 계정에 종속된 credential event 정리를 허용하지만 active/archived Teacher의 credential event 보존 semantics는 변경하지 않는다.
59. B8 preparation status, B9 eligibility와 planning 삭제 원칙은 active-year runtime behavior 및 active/archived Teacher, Classroom과 HomeroomAssignment lifecycle을 변경하지 않는다.
60. Actual rollover는 global admin만 실행할 수 있고 current operational manager, ordinary teacher와 planning Teacher는 실행할 수 없다.
61. 정상 rollover는 current active SchoolYear를 archived로, target planning SchoolYear를 active로 변경하는 정확히 두 status transition만 수행한다.
62. School, current active SchoolYear와 target planning SchoolYear를 순서대로 lock한 뒤 B9 structural safety와 manager eligibility를 transaction 안에서 다시 검증한다.
63. 두 status 변경은 하나의 transaction에서 모두 commit되거나 모두 rollback되며 부분 전환을 허용하지 않는다.
64. Inactive School, SchoolYear 누락·복수·소속/연도/status 불일치, manager cardinality 위반과 lock 이후 invariant 변경은 fail closed한다.
65. 이미 완료된 rollover의 stale/repeated request는 성공으로 처리하지 않는다.
66. Calendar year, 특정 월·일과 학기 시작일은 rollover eligibility 또는 실행 조건이 아니다.
67. Confirmation은 두 SchoolYear의 status 변화, 새 manager authority와 undo 미제공을 명확히 알리며 action은 global admin의 preparation page에 둔다.
68. 성공 후 active SchoolYear는 정확히 하나이고 planning SchoolYear는 0개일 수 있으며 기본 Teacher/Classroom context는 새 active SchoolYear를 사용한다.
69. Planning manager의 role을 복사하거나 User를 만들지 않고 기존 annual Teacher가 active 전환 후 operational manager가 된다.
70. 이전 manager는 archived SchoolYear 소속이 되어 current operational authority를 잃고 새 active Teacher의 login은 기존 authentication eligibility를 따른다.
71. Session revocation 구현 필요성은 현재 session 구조를 확인해 결정하며 B10 계약만을 위해 generic session-version framework를 만들지 않는다.
72. 미래 연도 검증은 Rails console의 최소 test state로 준비할 수 있지만 실제 transition은 production rollover operation으로 검증하고 time-travel/debug endpoint를 만들지 않는다.
73. Global admin은 모든 School의 archived SchoolYear를 기존 global scope에서 조회할 수 있다.
74. Current operational manager는 자기 School의 모든 archived SchoolYear를 read-only로 조회할 수 있다.
75. Current manager의 기본 Teacher/Classroom context는 active year이고 archived year는 명시적으로 선택한 경우에만 사용한다.
76. Current ordinary Teacher는 archived SchoolYear를 조회할 수 없다.
77. Former manager와 former ordinary Teacher는 archived annual account로 로그인하거나 archive authority를 행사할 수 없다.
78. 과거 manager role은 지속 archive authority의 근거가 아니며 rollover 후 stewardship는 새 current manager에게 승계된다.
79. Current manager는 다른 School의 archived context나 record를 조회할 수 없다.
80. Archived Teacher와 credential은 read-only이며 생성, profile/grade/lifecycle/delete와 temporary password mutation을 허용하지 않는다.
81. Archived Classroom은 read-only이며 생성, 구조/lifecycle 변경과 delete를 허용하지 않는다.
82. Archived Student/roster는 read-only이며 생성·수정·삭제와 roster mutation을 허용하지 않는다.
83. Archived HomeroomAssignment는 read-only이며 연결·교체·해제를 허용하지 않는다.
84. Archived mutation control을 UI에 표시하지 않고 direct mutation request도 server-side boundary에서 fail closed한다.
85. Archived browsing은 기존 SchoolYear-aware Teacher/Classroom surface를 재사용하고 별도 archive CRUD/dashboard를 만들지 않는다.
86. Archived browsing을 위해 Teacher login/runtime guard를 완화하지 않는다.
87. Annual Teacher User, annual credential와 학년도별 role/grade/Classroom 모델을 유지하고 persistent personal identity나 cross-year account linking을 도입하지 않는다.
88. Current operational manager와 active planning manager는 exact immediate planning SchoolYear에서 동일한 Teacher/Classroom/Homeroom preparation editor authority를 가진다.
89. Planning manager는 active SchoolYear operation, archived 조회, 자신의 manager 지정·교체·해제, School lifecycle과 actual rollover를 수행할 수 없다. Planning manager mutation authority는 global admin과 authorized current operational manager에게만 있다.
90. Planning ordinary Teacher는 planning 상태에서 로그인할 수 없다.
91. Active planning manager는 기존 School Teacher login page에서 명시적인 planning context를 선택해 로그인할 수 있다.
92. Login page default는 current active SchoolYear이고 active School, current active SchoolYear, exact immediate planning SchoolYear와 그 planning SchoolYear의 active manager 정확히 1명이 모두 존재할 때만 planning option을 제공한다.
93. 동일 `login_id`가 active/planning annual User에 존재해도 explicit SchoolYear context로 정확한 account를 선택한다.
94. 화면에 planning option이 없더라도 hidden/direct parameter로 주입한 planning SchoolYear를 포함해 malformed, archived, non-immediate, cross-School 또는 login eligibility를 충족하지 않는 SchoolYear authentication parameter는 server-side에서 fail closed한다.
95. Planning manager login은 기존 password validation과 rate limiting을 그대로 사용하고 preparation page로 이동한다.
96. Planning member Teacher는 authorized global admin, current manager 또는 active planning manager가 deactivate/reactivate할 수 있다.
97. Planning manager는 deactivate할 수 없고 inactive planning Teacher를 manager 지정·교체 target으로 사용할 수 없다.
98. Planning ordinary Teacher deactivation은 같은 operation에서 current planning assignment를 history 없이 삭제하고 Classroom을 유지한 뒤 Teacher를 inactive로 만들며, reactivation은 Teacher만 active로 복원하고 assignment를 자동 복구하지 않는다.
99. Planning manager role 제거, 비정상 inactive 상태, planning context 제거·교체 또는 School 비활성화 뒤에는 다음 request에서 planning-manager session을 종료한다.
100. 로그인 중인 planning manager의 SchoolYear가 rollover로 active가 되면 같은 session이 재로그인 없이 operational-manager session으로 계속된다.
101. Planning login을 위해 별도 route, password, persistent identity, collaborative editing 또는 session-version framework를 만들지 않는다.
102. Authorized manager는 inactive planning Teacher도 기존 설정 surface에서 조회하고 reactivate할 수 있으며, reactivation은 삭제된 HomeroomAssignment나 manager role을 자동 복구하지 않는다.
103. Current operational manager는 자기 active SchoolYear의 active ordinary Teacher와 exact immediate planning SchoolYear의 active ordinary/manager Teacher credential을 재발급할 수 있고, active planning manager는 자기 planning SchoolYear의 active ordinary Teacher credential만 재발급할 수 있다.
104. Self, inactive, archived, cross-School Teacher의 temporary password 재발급은 거부하며 planning manager는 active-year credential을 관리할 수 없다.

## Non-goals

- Route, controller, model, policy, service, view와 migration 구현
- `/teachers`, `/classrooms`의 기본 active-year context 또는 lifecycle별 policy 의미 변경
- Planning 전용 `/planning/teachers`, `/admin/teachers`, `/admin/classrooms`와 lifecycle별 controller/view 복제
- Active teacher, Classroom, HomeroomAssignment의 자동 복제·승계
- Student planning registration, roster, PIN 또는 login
- Planning ordinary Teacher login
- 승인된 planning manager mutation endpoint 밖의 Manager용 generic `/admin/*` 개방
- Generic batch/workflow/state-machine/context framework
- Planning Classroom bulk 전용 workflow. 향후 필요하면 단건 생성 계약을 보존하는 optional enhancement로 별도 specification한다.
- Planning Teacher 재포함 시 temporary credential 자동 재발급
- Planning Classroom deactivate/reactivate, `준비에서 제외`/`다시 포함`과 새로운 Classroom status enum
- Planning Teacher/Classroom의 기존 `active` boolean을 preparation status나 rollover eligibility 조건 또는 별도 준비 상태로 사용하는 UX
- Current operational manager의 successor 추천/proposal model, persistence와 UI
- Planning manager용 별도 account, login route 또는 manager-only workspace
- Planning manager 지정에 따른 credential 재발급, HomeroomAssignment/profile/grade 변경
- Planning HomeroomAssignment bulk 연결 workflow. 향후 필요하면 Teacher 단건 operation 계약과 active-year history 경계를 보존하는 별도 enhancement로 specification한다.
- Permanent Teacher identity 또는 연도별 User 자동 연결
- Manager 정확히 1명 외 business eligibility 조건
- 자동 또는 날짜 기반 rollover와 next planning SchoolYear 자동 생성
- Teacher/Classroom/Student 자동 복사·승계
- Rollover reversal/recovery implementation, rollback/undo UI와 generic lifecycle engine
- Production time-travel/debug module 또는 endpoint
- Rollover audit framework 확장
- Eligibility override, admin 강제 전환과 eligibility history/audit log
- Former Teacher의 archived login, former manager 특별 권한과 current ordinary Teacher archive access
- 개인별 과거 기록, Teacher identity continuity, persistent TeacherAccount와 annual account linking
- Archive access delegation, temporary archive permission과 export/download
- Generic archive management framework 또는 별도 archive dashboard

## 후속 phase와의 경계

Phase B는 다음의 작은 implementation 단위로 나눈다.

1. B1 — shared SchoolYear context authorization과 School overview status/entry
2. B2 — 기존 `/teachers`의 explicit planning context와 member teacher bulk create/one-time credential result
3. B3 — 같은 teacher surface의 planning 기본 정보/grade edit
4. B5a — 기존 `/classrooms/new`와 `POST /classrooms`의 explicit active/planning context 단건 create
5. B5b — 기존 Classroom edit/update surface의 planning grade/class_label 구조 수정
6. B6 — 기존 Teacher 설정 surface에서 같은 planning SchoolYear의 HomeroomAssignment 단건 연결·변경·해제
7. B7 — 얇은 다음 학년도 준비 페이지와 그 안의 admin/current-manager planning manager 지정·교체·해제
8. B8 — preparation page의 정보성 planning 준비 현황과 최소 rollover invariant 경계
9. B9 — manager exactly one business eligibility와 rollover target structural safety contract
10. B10 — global-admin-only atomic active/archive SchoolYear rollover contract
11. B11 — current-manager stewardship 기반 archived SchoolYear read-only authority
12. B12 — active/planning manager 공존, shared preparation authority와 same-page login/session handoff

각 단위는 focused spec과 human verification을 거친다. 기본 query에 planning을 섞지 않고 explicit SchoolYear context를 별도로 resolve하며 lifecycle별 controller/view를 복제하지 않는다. 다음 학년도 준비 페이지는 status와 cross-resource entry/orchestration만 담당하고 Teacher/Classroom CRUD를 복제하지 않는다.

Student preparation은 Classroom과 teacher/assignment 계약이 안정된 뒤 별도 human-reviewed bounded phase로 진행한다. B10 implementation은 B9 target eligibility를 입력으로 삼고 global-admin-only confirmation, lock 이후 재검증과 atomic transition을 보존해야 한다. B11은 archived annual account를 재활성화하지 않고 current manager에게 같은 School의 read-only stewardship를 부여한다. B12는 기존 annual login surface와 explicit SchoolYear context를 재사용해 planning manager collaboration과 rollover session handoff를 제공한다.
