# School Year Operational Boundary

## 상태와 목적

이 문서는 SchoolYear abstraction을 구현하기 전 마지막 bounded canonical spec이다. Downstream
서비스가 Classroom 또는 Student를 실제 owner로 사용하면서 School, SchoolYear, Classroom과
Student lifecycle 조건을 매번 직접 조합하지 않도록 Starter가 제공할 최소 operational boundary를
정의한다.

이 문서는 구현을 승인하거나 정확한 Ruby class/method 이름을 확정하지 않는다. 기준 권한과
ownership은 다음 canonical 문서를 따른다.

- [Starter SchoolYear Abstraction](starter_school_year_abstraction.md)
- [Roles and Permissions](../architecture/roles_and_permissions.md)
- [Current System](../architecture/current_system.md)
- [School Operations](../architecture/school_operations.md)
- [Planning-year Bootstrap](planning_year_bootstrap.md)

## 핵심 경계

Starter의 operational boundary는 다음 세 판단을 구분한다.

1. **Owner context:** 이 record가 실제로 어느 School, SchoolYear, Classroom 또는 Student에
   귀속되는가?
2. **Lifecycle eligibility:** 그 owner가 요청된 종류의 operation을 현재 수행할 수 있는가?
3. **Actor authority:** 이 actor가 해당 owner에서 이 action을 수행할 권한이 있는가?

Lifecycle eligibility가 true여도 actor 권한을 부여하지 않는다. Actor가 global admin 또는
manager여도 planning/archive/inactive lifecycle을 일상 mutation 가능한 상태로 바꾸지 않는다.
서비스별 작성자, 수신자, 공개 범위와 수량 제한도 이 경계가 대신 결정하지 않는다.

## Owner 기반 context

일상 서비스 operation은 실제 owner에서 context를 결정한다.

| 실제 owner | Canonical context path |
|---|---|
| Classroom-owned data | `record → Classroom → SchoolYear → School` |
| Student-owned data | `record → Student → Classroom → SchoolYear → School` |
| SchoolYear-owned data | `record → SchoolYear → School` |

새 record를 만들기 전에는 저장될 owner를 명시적으로 전달한다. 기존 record에서는 저장된 owner
association을 사용한다. Actor의 `school_year_id`, actor의 annual School 또는 School의 현재 active
year로 기존 record의 귀속을 다시 계산하지 않는다. URL이나 form의 School/SchoolYear id도 owner
association을 대체하는 authority source가 아니다.

Nested resource의 parent와 record owner가 다르면 fail closed한다. Student operation에서 URL의
Classroom과 `student.classroom`이 다르면 다른 Classroom이나 current active year로 fallback하지 않는다.

School-level 또는 global data는 해당 ownership을 별도 domain spec에 명시한다. 여러 학년도에
지속되는 School-level data를 편의상 active SchoolYear에 귀속시키지 않는다. Classroom 또는 Student를
통해 context가 결정되는 record에 `school_year_id`를 중복 저장하지 않는다.

## Operational lifecycle 계약

Boundary는 단일 범용 `active?`나 `writable?`를 제공하지 않는다. 최소한 일상 Classroom operation,
일상 Student operation, Student 재활성화, archive read와 planning preparation을 서로 다른 operation
kind로 취급한다. 정확한 식별자 이름은 구현 단계에서 정할 수 있다.

| Owner 상태 | 일상 operation | 별도 의미 |
|---|---|---|
| active School + active SchoolYear + active Classroom | Classroom-owned mutation 가능. Student-owned mutation은 Student도 active일 때 가능 | 최종 허용은 actor/action policy와 서비스 invariant가 결정 |
| inactive School | 일상 read/write 불가 | School 재활성화와 system governance는 별도 경계 |
| planning SchoolYear | 일상 서비스 operation 불가 | 승인된 Teacher/Classroom/HomeroomAssignment preparation만 planning infrastructure에서 처리. Student operation은 불가 |
| archived SchoolYear | 일상 mutation 불가 | 허용된 actor의 명시적인 archive read만 가능 |
| inactive Classroom in active SchoolYear | 일상 operation 불가 | Classroom 재활성화는 별도 lifecycle action |
| inactive Student in operational Classroom | 일반 Student mutation과 Student self access 불가 | 권한 있는 운영자의 management read와 Student 재활성화는 action별로 판단 |

SchoolYear가 archived이면 당시 `Classroom.active` 또는 `Student.active` 값은 historical state다.
Archive read eligibility를 이 boolean으로 다시 차단하거나 archive mutation 권한으로 해석하지 않는다.
Archive read lifecycle 자체는 `School.active`를 요구하지 않는다. 따라서 inactive School의 archive도
global admin은 읽을 수 있지만 current operational manager authority는 성립하지 않는다. Archive에서는
모든 School operation mutation을 거부한다.

SchoolYear 자체가 실제 owner인 data는 domain spec이 허용 status와 action을 명시해야 한다. 특정
SchoolYear 소유라는 사실만으로 planning mutation이나 archive mutation을 허용하지 않는다.

## Actor authority

Actor authority는 owner context와 action을 입력으로 판단하며 lifecycle 결과와 별도로 유지한다.
현재 canonical 권한은 다음과 같다.

| Actor | Active operational context | Planning context | Archive context |
|---|---|---|---|
| Global admin | 모든 School에서 action별 허용 operation | 승인된 preparation과 governance | 모든 School read-only |
| Current operational manager | 자기 School의 active Classroom 전체에서 담당 여부와 관계없이 현재 승인된 Student operation | 자기 School의 exact planning preparation | 자기 School read-only |
| Ordinary Teacher | current HomeroomAssignment로 담당하는 active Classroom의 허용 operation | 거부 | 거부 |
| Eligible planning manager | active operation 거부 | 자기 exact immediate planning SchoolYear의 승인된 preparation | 거부 |
| Student | 자기 active Classroom의 자기 Student에 허용된 session/action만 | 거부 | 거부 |

Archived annual Teacher account는 로그인하거나 authority를 얻지 않는다. Current operational manager의
archive authority는 archived annual role에서 나오지 않고 현재 자기 School 운영 책임에서 나온다.

Starter의 school-wide Student management 권한은 downstream 서비스의 모든 record에 자동 전파되지
않는다. 예를 들어 manager가 Student roster를 수정할 수 있다는 사실만으로 개인 메시지나 비공개
성장기록을 읽을 수 있다고 추론하지 않는다. 각 downstream policy가 서비스 action을 별도로 정의한다.

## 최소 public contract

정확한 객체 배치와 method 이름을 정하지 않고 다음 semantic contract를 확정한다.

### 1. Owner context resolution

```text
resolve owner context(owner)
→ school, school_year, optional classroom, optional student, persisted lifecycle state
```

- 지원하는 owner path를 명시적으로 따라간다.
- missing association, inconsistent nested owner와 unsupported owner는 fail closed한다.
- actor나 current active year를 이용해 빠진 context를 보충하지 않는다.
- read와 mutation이 같은 canonical owner path를 사용한다.

### 2. Lifecycle eligibility

```text
lifecycle eligible?(owner context, operation kind)
→ allowed or denied with a stable reason
```

최소 denial reason은 inactive School, planning SchoolYear, archived SchoolYear, inactive Classroom,
inactive Student와 owner mismatch를 구분할 수 있어야 한다. UI 문구나 HTTP response는 이 계약의
책임이 아니다.

`archive read context?`는 archived SchoolYear를 명시적으로 선택한 read인지 판별한다. 이것만으로
actor의 archive authority를 승인하지 않는다. Planning preparation과 governance도 일상 operation의
예외 flag가 아니라 별도 operation kind다.

### 3. Actor/action authority

```text
authorized?(actor, owner context, action)
→ policy가 actor role, School scope, assignment와 action을 판단
```

Action은 최소한 read, mutate, reactivate, archive read, preparation과 governance 차이를 잃지 않아야
한다. 하나의 generic `manage?`를 모든 downstream 기능 권한으로 재사용하지 않는다. 기존 Pundit
policy를 유지하거나 작은 공통 predicate를 사용하는 선택은 구현 단계에 남긴다.

### 4. Protected mutation entry

```text
perform protected mutation(actor, owner, action)
→ owner integrity + actor authority + lifecycle eligibility 재검증
→ domain-specific invariant 검증
→ mutation
```

Controller authorization 결과나 이전에 계산한 eligibility를 저장 시점의 보증으로 사용하지 않는다.
직접 service 호출과 job 진입도 같은 protected mutation contract를 거쳐야 한다. System actor가 필요한
후속 기능은 actor와 허용 action을 명시적으로 정의하며 thread-local current user를 추측하지 않는다.

이 네 계약을 하나의 범용 context object로 구현할 필요는 없다. 호출자가 구분된 결과를 조합할 수
있어야 하며, 하나의 boolean이 denial 원인과 책임 경계를 지우지 않아야 한다.

## Query, policy, lifecycle과 domain 책임

| 계층/책임 | 계약 |
|---|---|
| Query 또는 policy scope | Actor가 볼 수 있는 candidate를 School/action scope로 제한한다. Explicit archive scope를 구분한다. Scope 통과만으로 mutation eligibility를 보장하지 않는다. |
| 개별 record policy | Actor, canonical owner와 구체 action을 authorize한다. 다른 School, 미담당 Classroom과 허용되지 않은 archive/planning actor를 거부한다. |
| Operational lifecycle boundary | Owner chain에서 School, SchoolYear, Classroom과 필요한 Student 상태를 action별로 판단한다. 서비스별 권한이나 내용 규칙은 판단하지 않는다. |
| Domain operation/service | 서비스별 invariant를 검증하고 mutation 직전에 owner, authority와 lifecycle을 다시 확인한다. |
| Model | Association integrity, immutable owner, uniqueness와 값 validation을 지킨다. Request actor나 policy를 callback으로 주입하지 않는다. |
| Controller | Parameter와 nested owner를 resolve하고 authorize한 뒤 protected operation을 호출하며 결과를 HTML/Turbo response로 변환한다. |

Read path도 scope와 개별 authorization을 유지한다. Archive read는 lifecycle상 archived context라는 사실과
global admin/current manager authority가 모두 충족되어야 한다. 현재 제공되지 않는 archive UI를 이
계약만으로 추가하지 않는다.

## Mutation 직전 재검증과 concurrency

Mutation은 transaction 안에서 canonical owner, actor authority, lifecycle과 domain invariant를 현재
DB state로 저장 직전에 다시 검증한다. Rollover나 다른 lifecycle transition과 경쟁하더라도 stale
mutation이 commit되지 않아야 한다.

정확히 어떤 row를 lock할지는 operation별 구현과 focused concurrency spec에서 결정한다. 모든
Student/Classroom mutation이 School 또는 SchoolYear까지 반드시 lock해야 한다고 이 문서에서 확정하지
않으며, 각 operation의 정확성에 필요한 최소 row만 lock한다. 여러 계층의 row를 함께 lock해야 하면
rollover 및 다른 mutation과 충돌하지 않는 일관된 ordering을 사용한다.

```text
School → SchoolYear → Classroom → Student 또는 service record
```

위 순서는 모든 row의 필수 lock 목록이 아니다. 여러 ancestor row를 함께 잠가야 할 때 검토할
canonical ordering 방향이다.

Actor role이나 current HomeroomAssignment가 action authority의 근거이면 해당 authority source도
mutation 전에 현재 상태로 재검증한다. 첫 Student 재활성화 구현도 현재 Classroom/Student lock을
무조건 확대한다고 미리 결정하지 않는다. Rollover race를 포함한 focused concurrency spec으로 필요한
최소 lock set을 먼저 정한다.

필요한 lock과 현재 state 조회 뒤 저장 직전에 다음을 확인한다.

1. Record가 여전히 같은 canonical owner에 속하는가?
2. Actor가 여전히 해당 owner/action authority를 가지는가?
3. School, SchoolYear, Classroom과 필요한 Student lifecycle이 operation kind에 맞는가?
4. 서비스별 invariant가 현재 state에서 성립하는가?
5. 모두 만족할 때만 mutation을 수행한다.

Boundary가 lifecycle과 authority를 공통으로 재검증하더라도 transaction, lock과 rollback 책임은 실제
mutation operation에 남는다. Model callback이나 `default_scope`로 이 순서를 숨기지 않는다.

## 첫 적용 대상: Student 재활성화

첫 구현 후보는 `ClassroomStudentsController#reactivate`의 단일 Student 재활성화다.

현재 이 action은 `StudentPolicy#manage?`로 actor를 authorize하고, controller 안에서
`Classroom.active?`, `SchoolYear.active?`, `School.active?`를 다시 조합한다. 이어 Classroom과 Student를
lock하고 정원 제한을 확인한 뒤 `Student.active`를 변경한다. Policy에도 같은 operational Classroom
판정이 있어 공통 boundary가 필요한 지점이 작고 분명하다.

재활성화는 inactive Student가 정상 target이므로 단일 `active?`가 모든 action을 표현할 수 없다는 점도
검증한다. 첫 적용 계약은 다음과 같다.

- Canonical owner는 `Student → Classroom → SchoolYear → School`이다.
- Nested Classroom과 `student.classroom`이 일치해야 한다.
- Global admin, 자기 School의 current operational manager 또는 해당 Classroom의 ordinary Teacher만
  기존 권한 범위에서 시도할 수 있다.
- School, SchoolYear와 Classroom은 active여야 하고 Student는 inactive여야 한다.
- Mutation transaction에서 owner, actor authority와 lifecycle을 재검증한다.
- `Classroom::MAX_ACTIVE_STUDENTS`, student number uniqueness와 Student validation은 domain/model
  invariant로 유지한다.
- 성공 시 `Student.active`만 true로 바꾸며 Classroom 귀속이나 Student identity를 변경하지 않는다.
- 기존 HTML/Turbo redirect, 성공·실패 의미와 exception rollback behavior를 보존한다.

이 한 action에서 protected mutation contract가 검증되기 전에는 create/update/deactivate, bulk roster,
PIN/token operation 또는 downstream 서비스로 확대하지 않는다.

## 가능한 후속 구현 단계

1. Owner context와 action별 lifecycle result를 제공하는 가장 작은 boundary를 구현한다.
2. Student 재활성화에만 적용해 controller authorization과 transaction 내부 재검증 책임을 분리한다.
3. Direct operation 호출, actor별 authority, owner mismatch, 각 lifecycle denial과 rollover 경쟁을 focused
   spec으로 검증한다.
4. 계약이 안정된 뒤 Student create/update/deactivate, roster, PIN/token operation을 한 종류씩 이관한다.
5. 실제 downstream 서비스 하나가 owner association만으로 같은 계약을 사용할 수 있는지 별도 spec에서
   검증한다.

각 단계는 별도 승인과 bounded run으로 수행한다. 전체 policy/controller/service를 한 번에 리팩터링하지
않는다.

## 구현 선택으로 남기는 사항

다음은 정책 open question이 아니라 후속 구현에서 repository style에 맞춰 선택할 세부사항이다.

- Boundary module/class와 method 이름
- Boolean, result object 또는 exception 중 내부 반환 형태
- 기존 Pundit policy helper와 lifecycle predicate의 배치
- Stable denial reason을 controller response와 locale key에 매핑하는 방식

어떤 선택도 범용 framework, global context object, `CurrentAttributes`, implicit active-year
`default_scope`, callback 기반 authorization 또는 policy를 model에 주입하는 구조를 선행 도입해서는
안 된다.

## Non-goals

- 코드, migration, model, policy, controller, service, route와 test 구현
- Teacher 영구 identity, `TeacherAssignment`와 annual User 재사용 결정
- Classroom의 SchoolYear 귀속 변경
- Student persistent identity 또는 `StudentEnrollment`
- Compact/Managed profile 정의
- 새 archive UI, generic archive dashboard 또는 archive surface 확대
- Archived annual Teacher login과 개인별 historical access
- Planning Student operation 또는 archive mutation
- Downstream 성장기록, 칭찬, 쿠폰, 메시지 등 실제 서비스 구현
- 모든 기존 SchoolYear 참조의 일괄 제거 또는 전체 application refactor

## Open questions

이 spec 범위의 policy open question은 없다. Owner source, lifecycle operation kind, actor authority,
archive read-only 경계와 mutation 재검증 책임을 위 계약으로 확정한다. 정확한 Ruby 이름과 작은 객체의
배치는 구현 선택이며 별도 정책 결정을 요구하지 않는다.
