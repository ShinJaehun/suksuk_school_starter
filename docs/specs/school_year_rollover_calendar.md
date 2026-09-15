# SchoolYear rollover calendar contract

## 목적과 범위

이 문서는 target planning SchoolYear Y의 **manual rollover only** 계약을 정의한다. Planning 준비에는 날짜 제한이 없으며, target year의 수동 rollover 시작일, 전환 지연 표시와 global admin 복구를 다룬다. SchoolYear rollover는 global admin의 명시적인 수동 실행으로만 수행한다. HTTP request, scheduler, background job 또는 Rake reconciliation에서 자동 rollover를 실행하지 않는다.

기존 [Planning bootstrap B9/B10](planning_year_bootstrap.md#actual-schoolyear-rollover-contract)의 structural validation, manager eligibility, locking/transaction과 authority 승계를 유지한다. Rollover 날짜 기준과 실행 방식은 이 문서의 manual-only 계약을 따른다. Manager credential safety는 [Final Starter Audit Hardening §6](final_starter_audit_hardening.md#6-planning-rollover-manager-fail-closed)을 따른다.

## 1. 날짜 기준과 planning preparation

Y는 현재 calendar year가 아니라 target planning SchoolYear의 연도다. 날짜 경계는 애플리케이션의 설정된 time zone에서 판단하는 현재 날짜를 기준으로 하고, UI·수동 transition·overdue 판단에 같은 기준을 적용한다. Client가 전달한 날짜나 서버 OS의 별도 날짜로 guard를 우회하지 않는다.

Planning 생성과 Teacher/Classroom/HomeroomAssignment 준비, planning manager 지정은 rollover 날짜 제한과 별개다. 기존 actor authority, active School, exact immediate planning relation과 preparation invariant는 그대로 지킨다.

- 2026년에도 2026 active의 다음 학년도인 2027 planning을 생성하고 준비할 수 있다.
- Y-02-01 전이라는 이유로 planning preparation을 차단하지 않는다.
- Y-03-01 이후 뒤늦게 서비스를 시작해도 planning 생성과 준비를 차단하지 않는다. 2027년 4월에 2026 active만 있다면 global admin이 2027 planning을 만들고 Teacher·manager·credential을 준비한 뒤 정상 rollover할 수 있다.
- Planning preparation은 active SchoolYear를 변경하지 않으며, 준비 data나 다음 planning SchoolYear를 자동 생성하지 않는다.

## 2. Manual rollover calendar guard

Y학년도 수동 rollover는 **Y-02-01부터** 가능하다. Y-01-31까지는 global admin도 실행할 수 없으며 override를 제공하지 않는다. 이 guard는 UI 노출 여부와 무관하게 canonical `SchoolYears::Rollover` transition의 server-side boundary에서 검증한다. Direct POST와 transition 직접 호출도 같은 제한을 받는다.

날짜 조건은 기존 전환 조건에 추가된다. Calendar가 열려도 다음을 모두 충족해야 한다.

- Active School이고 current active와 target planning SchoolYear가 각각 정확히 하나다.
- 두 SchoolYear는 같은 School에 속하며 target은 active year + 1인 exact immediate planning year다.
- Lock 이후에도 각 status가 active/planning이고 기존 structural invariant가 유효하다.
- Target manager가 정확히 한 명이며 active이고 credential이 기존 인증 구조상 사용 가능하다.
- 기존 School → current active SchoolYear → target planning SchoolYear locking, transaction과 invariant를 유지하고 lock 이후 현재 상태를 재검증한다.

Credential usable은 기존 login ID/password digest의 구조적 사용 가능성이다. 실제 password 인증이나 credential 자동 복구를 수행하지 않는다. 정상 temporary credential의 최초 password 변경 미완료는 blocker가 아니다. Teacher/Classroom/Homeroom 수를 추가 완료 조건으로 만들지 않는다.

수동 실행 authority는 global admin에게만 있다. Current operational manager와 planning manager에게 rollover 권한을 부여하지 않는다. 각 target Y마다 자기 Y-02-01 guard를 적용하므로 미래 학년도로 연속 전환할 수 없다. 예를 들어 2027년 2월에 2027 rollover를 마쳐도 2028 rollover는 2028-02-01 전까지 불가능하다. 이미 날짜 경계가 지난 연도의 정상 복구를 금지하는 뜻은 아니다.

## 3. Manual transition과 assignment release

수동 rollover는 canonical `SchoolYears::Rollover`의 validation, locking과 transaction을 유지한다.

| 결과 | 기존 active SchoolYear | Target planning SchoolYear |
|---|---|---|
| 성공 | archived | active |
| 실패 | active 유지 | planning 유지 |

두 status 변경은 같은 transaction에서 모두 commit되거나 모두 rollback된다. 실패 후 기존 active가 계속 운영 기준이며, 날짜만으로 강제 archive하지 않는다. 기존 lock과 status 재검증으로 부분 전환이나 이중 전환을 막고 이미 완료된 pair의 stale request는 fail closed한다.

### Future-start HomeroomAssignment

Planning assignment의 `started_on`은 target SchoolYear의 3월 1일이다. 2월 1일부터 수동 rollover가 가능하므로 SchoolYear가 active가 되어도 assignment의 시작일은 미래일 수 있다. 예를 들어 2027 planning을 2027-02-15에 수동 전환해도 기존 assignment의 `started_on = 2027-03-01`은 바꾸지 않는다.

- Planning assignment 또는 `started_on > Date.current`인 current assignment는 아직 실제 운영 이력이 아니므로 변경·해제 시 기존 row를 삭제한다.
- 이미 시작된 active assignment(`started_on <= Date.current`)만 `ended_on = Date.current`로 종료 이력을 남긴다.
- 교체로 새 active assignment를 만들면 기존 active context의 `started_on = Date.current` semantics를 따른다.
- Teacher 비활성화도 같은 release semantics를 따르며, 재활성화 때 이전 assignment를 자동 복원하지 않는다.
- `started_on` 불변성, DB/model의 `ended_on >= started_on` 불변식, 종료된 history의 immutability와 archived read-only 계약은 유지한다.

이 규칙은 2월 수동 rollover에 필요한 기존 assignment 계약이며 자동 rollover에 의존하지 않는다.

## 4. Derived overdue와 recovery

현재 날짜가 Y-03-01 이상이고 Y의 status가 여전히 planning이면 `rollover overdue`다. `rollover_overdue?`는 전환 지연을 알리는 derived warning이며 자동 실행 조건이 아니다. 새 `overdue` status enum이나 persisted overdue flag를 추가하지 않는다. Global admin은 현재 blocker를 확인·복구한 뒤 기존 수동 rollover를 실행한다.

예를 들어 2027-04-10에 2026 active와 2027 planning이 있으면 그대로 유지한다. 시스템은 calendar year에 맞춰 active year를 자동 보정하지 않는다.

Overdue여도 global admin은 기존 planning workspace에서 다음 recovery operation을 수행할 수 있다.

- 필요할 때 exact immediate planning SchoolYear 생성
- Planning Teacher 생성과 credential 발급·재발급
- Planning manager 지정·교체와 credential 사용 가능성 확인
- Classroom/HomeroomAssignment 등 기존 planning preparation operation

이전/current manager가 없거나 전근·퇴직하여 협조할 수 없어도 global admin은 새 planning Teacher를 만들고 manager로 지정할 수 있다. Current manager의 로그인·동의·승계 작업을 복구의 전제조건으로 두지 않는다. 기존 global authority와 operation validation을 재사용한다.

2027년 4월, 2026 active와 2027 planning 또는 planning 없음 상태의 복구 순서는 다음과 같다.

1. 필요하면 2027 planning을 생성한다.
2. 2027 Teacher를 생성한다.
3. 새 planning manager를 지정한다.
4. Credential을 발급·복구하고 사용 가능성을 확인한다.
5. 기존 eligibility를 모두 충족한 상태에서 global admin이 수동 rollover한다.

결과는 2026 archived, 2027 active다. 지정한 planning manager의 기존 annual User와 `school_role`이 그대로 current operational manager authority의 근거가 된다. 새 대표는 기존 current-manager authority로 2027 Teacher/Classroom을 계속 관리한다. Role 복사나 새 successor 계정을 만들지 않는다.

날짜가 아무리 늦어도 **global admin이 invariant 복구 → 정상 rollover**를 사용한다. Manager 부재, credential 오류나 invariant 위반을 무시하는 force-close/eligibility override는 제공하지 않는다. 여기서 recovery는 전환 전 planning 복구이며 완료된 rollover reversal이 아니다.

## 5. UI와 authorization

- Y-02-01 전에는 rollover 실행 control을 활성화하지 않는다. `YYYY학년도 시작은 YYYY년 2월 1일부터 가능합니다`에 해당하는 localized 안내를 제공하고 direct POST도 server-side에서 거부한다.
- Y-02-01부터 기존 eligibility까지 충족하면 global admin이 수동 실행할 수 있다. 기존 confirmation은 active → archived, planning → active, 새 manager authority와 undo 미제공을 설명한다.
- Y-03-01 이후 planning이 유지되면 global admin에게 전환 지연 경고와 현재 blocker를 명확히 표시한다. Manager missing, credential invalid 등 기존 eligibility reason을 재사용하며 blocker가 없는 미전환 상태에 오류 원인을 지어내지 않는다.
- Overdue 화면에서도 기존 recovery 진입점을 제공하고, 복구 뒤 global admin이 수동 rollover할 수 있다.
- 날짜·overdue 판단과 권한은 view에 복잡하게 넣지 않는다. Controller/policy와 canonical domain boundary를 기준으로 HTML/Turbo와 direct request에 동일하게 적용한다.
- 안내·경고·오류·버튼 문구는 기존 locale key를 우선 재사용하고 필요한 key는 구현 단계에서 `config/locales`에 추가한다. 사용자 표시 literal을 코드에 새로 하드코딩하지 않는다.
- Current/planning manager의 preparation authority는 유지하되 rollover control과 실행 authority를 새로 제공하지 않는다.

## Acceptance criteria

1. Y-01-31에는 정상 eligibility를 갖춰도 global admin의 Y rollover가 거부된다. UI 비활성화와 direct POST/domain boundary 거부를 모두 충족한다.
2. Y-02-01부터 정상 eligibility를 갖춘 global admin의 수동 rollover가 가능하다.
3. Calendar open 이후라도 inactive School, non-immediate target, manager cardinality/credential 또는 기존 invariant가 실패하면 전환하지 않는다.
4. Y-02-01 전에도 기존 권한과 invariant 아래 planning 생성·Teacher/Classroom/Homeroom 준비·manager 지정이 가능하다.
5. Rollover 실행 authority는 global admin에게만 있다. HTTP request, scheduler, background job 또는 Rake reconciliation에서 자동 rollover를 실행하지 않는다.
6. 수동 성공 시 기존 active → archived, target planning → active만 수행한다. 실패 시 두 status를 모두 보존하고 부분 전환하지 않는다.
7. Y-03-01 이후 Y planning 유지는 derived overdue다. 새 status나 persisted flag 없이 지연 경고와 현재 blocker를 표시하고 기존 active를 유지한다.
8. Overdue에서도 global admin은 planning Teacher 생성·credential 발급/재발급·대표 지정/교체·Classroom 준비 등 기존 recovery operation을 수행할 수 있다.
9. 이전/current manager의 도움 없이 global admin이 필요한 planning과 새 Teacher/manager를 마련하고 정상 eligibility를 충족해 수동 rollover할 수 있다.
10. 늦은 날짜나 blocker를 이유로 eligibility override, 강제 rollover/force-close 또는 automatic retry를 제공하지 않는다.
11. Rollover 후 기존 planning manager가 같은 annual User/role로 current operational manager가 되어 새 active-year Teacher/Classroom을 관리하고 이전 manager는 operational authority를 잃는다.
12. 각 target year의 Y-02-01 guard 때문에 아직 시작일이 오지 않은 미래 연도로 연속 rollover할 수 없다.
13. 2월 수동 rollover 뒤에도 future-start assignment의 변경·해제와 Teacher 비활성화는 기존 row를 삭제한다. 이미 시작된 active assignment만 종료 이력을 남기며 새 active assignment는 당일 시작 semantics를 따른다.
14. 기존 lock과 status 재검증을 유지하며 이미 완료된 rollover의 stale/repeated request는 fail closed한다.

검증 범위는 수동 날짜 경계, domain/direct request 거부, 전환의 원자성, overdue recovery, authority 승계와 future-start assignment release다. 이번 단계에서는 canonical 문서만 수정하며 runtime, migration과 spec test 반영은 별도 구현 단계에서 수행한다.

## Non-goals

- 강제 rollover, force-close 또는 eligibility override
- 새 `overdue` SchoolYear status나 persisted overdue flag
- Active year 자동 보정 또는 날짜만으로 강제 archive
- Planning SchoolYear 자동 생성
- Teacher/Classroom/HomeroomAssignment/Student 자동 생성·복사·승계
- 자동 rollover와 automatic retry, 이를 위한 scheduler/background job/Rake reconciliation
- Generic lifecycle/state-machine framework 또는 audit framework 확장
- Current/planning manager rollover 권한 확대
- Rollover reversal, rollback/undo UI
- Production time-travel helper/debug endpoint
