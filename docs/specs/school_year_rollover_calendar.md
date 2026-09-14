# SchoolYear rollover calendar contract

## 목적과 범위

이 문서는 target planning SchoolYear Y의 수동 rollover 시작일, system의 자동 시도, 전환 지연 표시와 global admin 복구에 대한 focused canonical spec이다. 확정 정책을 문서화하며 runtime, migration과 spec test 구현은 별도 run에서 진행한다.

기존 [Planning bootstrap B9/B10](planning_year_bootstrap.md#actual-schoolyear-rollover-contract)의 structural validation, manager eligibility, locking/transaction과 authority 승계를 유지한다. 이 문서가 기존 B10의 날짜 제한 없음 및 자동·날짜 기반 rollover 제외 계약을 대체한다. Manager credential safety는 [Final Starter Audit Hardening §6](final_starter_audit_hardening.md#6-planning-rollover-manager-fail-closed)을 따른다.

## 1. 날짜 기준과 planning preparation

Y는 현재 calendar year가 아니라 target planning SchoolYear의 연도다. 날짜 경계는 애플리케이션의 설정된 time zone에서 판단하는 현재 날짜를 기준으로 하고, UI·수동 transition·자동 reconciliation에 같은 기준을 적용한다. Client가 전달한 날짜나 서버 OS의 별도 날짜로 guard를 우회하지 않는다.

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

## 3. Automatic rollover attempt

Y-03-01부터 system은 아직 자동 시도가 없는 target planning SchoolYear에 대해 한 번 자동 rollover를 시도한다. 정확히 3월 1일 순간에 실행될 필요는 없다. Downtime이나 늦은 planning 생성으로 해당 시각을 놓쳐도 이후 첫 lifecycle reconciliation 기회에 미시도 target을 한 번 처리할 수 있다.

자동 시도는 global admin이 Submit을 누른 것과 같은 `SchoolYears::Rollover` domain transition을 사용한다. 별도 강제 transition, admin 사용자 가장 또는 manager authority 확대를 도입하지 않는다. Calendar guard, structural validation, manager cardinality/credential eligibility, locking, transaction과 status transition semantics를 그대로 재사용한다.

| 결과 | 기존 active SchoolYear | Target planning SchoolYear |
|---|---|---|
| 성공 | archived | active |
| 실패 | active 유지 | planning 유지 |

두 status 변경은 같은 transaction에서 모두 commit되거나 모두 rollback된다. 자동 실행이라는 이유로 eligibility를 우회하거나 manager·credential·기존 data를 자동 수정하지 않는다. 실패 후 기존 active가 계속 운영 기준이며, 날짜만으로 강제 archive하지 않는다.

### Target당 durable at-most-once

자동 시도의 단위는 target planning SchoolYear의 identity다. Process memory, session, cache 또는 request마다 계산하는 eligible flag만으로 시도 여부를 판단하지 않는다. 중복 worker, 동시 reconciliation, process 재시작과 job 재전달에도 동일 target의 자동 domain transition 진입은 최대 한 번이어야 한다.

- Domain transition을 호출하기 전에 target별 자동 시도 기회를 원자적으로 확보하고 durable하게 기록한다. 동시에 여러 실행자가 같은 기회를 획득할 수 없어야 한다.
- 자동 시도의 실패도 기회를 소진한다. 전환 transaction의 rollback이 시도 기록까지 지워 다시 자동 실행 가능하게 만들면 안 된다.
- 기회 확보 후 process가 중단되거나 결과가 불확실하더라도 같은 target의 자동 transition을 다시 실행하지 않는다. At-most-once는 장애 상황에서 성공이나 실행 완료를 보장하는 exactly-once 계약이 아니다. 남은 planning은 global admin이 확인·복구하고 수동 전환한다.
- 최초 reconciliation에서 eligibility 실패를 확인한 경우도 한 번의 자동 시도 실패로 처리한다. Eligibility가 좋아질 때까지 매 request마다 미시도 상태로 남겨 반복 실행하지 않는다.
- 자동 실패 후 Teacher/manager/credential을 복구해도 자동 시도 기회를 초기화하지 않는다. 이후 전환은 global admin의 수동 실행으로 수행한다.
- 수동 실행은 자동 시도 기회를 소진하지 않으며, 자동 시도 소진도 수동 실행을 막지 않는다. 수동 성공으로 이미 active가 된 target은 자동 전환 대상이 아니다.
- 수동·자동 실행 경합에서도 기존 lock과 status 재검증으로 부분 전환이나 이중 전환을 막는다. 이미 완료된 pair의 stale request는 기존대로 fail closed한다.

정확한 scheduler/cron/job wiring, persistence field/table와 중복 방지 구현은 후속 implementation 선택으로 남긴다. 단, 위 durable 보장과 전환 실패 시 status 보존은 필수다. 시도 기록은 SchoolYear lifecycle status나 generic audit framework가 아니다.

### Production scheduler 운영 계약

Production deployment에는 `bin/rails school_years:reconcile_rollovers`를 **최소 하루 1회** 실행하는 scheduler가 필요하다. 정확히 Y-03-01 00:00 실행을 요구하지 않으며, Y-03-01 이후 첫 scheduler 실행에서 아직 자동 시도가 없는 target planning SchoolYear를 catch-up할 수 있다. Downtime 이후에도 같은 durable at-most-once 계약을 적용한다.

Scheduler 구현 방식(cron, systemd timer, container scheduler 등)과 실행 등록은 deployment concern이다. 이 기능을 위해 Solid Queue나 generic background-job framework를 도입하지 않는다. Reconciliation은 전용 Rake task로 수행하며 일반 HTTP request에서는 실행하지 않는다.

## 4. Derived overdue와 recovery

현재 날짜가 Y-03-01 이상이고 Y의 status가 여전히 planning이면 `rollover overdue`다. 자동 시도 여부·성공 가능성과 별도로 계산하는 derived state이며 새 `overdue` status enum이나 persisted overdue flag를 추가하지 않는다.

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
- Overdue 화면에서도 기존 recovery 진입점을 제공하고, 복구 뒤 수동 rollover할 수 있다. 자동 시도 실패 후 지속 자동 재시도를 약속하지 않는다.
- 날짜·overdue 판단과 권한은 view에 복잡하게 넣지 않는다. Controller/policy와 canonical domain boundary를 기준으로 HTML/Turbo와 direct request에 동일하게 적용한다.
- 안내·경고·오류·버튼 문구는 기존 locale key를 우선 재사용하고 필요한 key는 구현 단계에서 `config/locales`에 추가한다. 사용자 표시 literal을 코드에 새로 하드코딩하지 않는다.
- Current/planning manager의 preparation authority는 유지하되 rollover control과 실행 authority를 새로 제공하지 않는다.

## Acceptance criteria

1. Y-01-31에는 정상 eligibility를 갖춰도 global admin의 Y rollover가 거부된다. UI 비활성화와 direct POST/domain boundary 거부를 모두 충족한다.
2. Y-02-01부터 정상 eligibility를 갖춘 global admin의 수동 rollover가 가능하다.
3. Calendar open 이후라도 inactive School, non-immediate target, manager cardinality/credential 또는 기존 invariant가 실패하면 전환하지 않는다.
4. Y-02-01 전에도 기존 권한과 invariant 아래 planning 생성·Teacher/Classroom/Homeroom 준비·manager 지정이 가능하다.
5. Y-03-01부터 system automatic attempt는 기존 canonical `SchoolYears::Rollover` transition과 validation/locking/transaction을 사용한다.
6. 자동 성공 시 manual Submit과 동일하게 기존 active → archived, target planning → active만 수행한다.
7. 자동 실패 시 기존 active와 target planning status를 모두 보존하고 부분 전환하지 않는다.
8. 자동 실패를 성공으로 만들기 위해 eligibility를 우회하거나 manager/credential을 자동 수정하지 않는다.
9. Target planning SchoolYear당 자동 시도는 durable at-most-once다. 동시 실행·재시작·job 재전달에도 중복 domain transition 진입이 없다.
10. 3월 1일 downtime 또는 늦은 planning 생성으로 정확한 시각을 놓쳐도 이후 첫 reconciliation에서 아직 미시도면 한 번 시도할 수 있다.
11. 자동 실패와 transaction rollback 뒤에도 시도 소진이 유지된다. 반복 request나 복구 후 reconciliation에서 다시 자동 시도하지 않으며 global admin 수동 전환은 가능하다.
12. Y-03-01 이후 Y planning 유지는 derived overdue다. 새 status enum 없이 지연 경고와 현재 blocker를 표시하고 기존 active를 유지한다.
13. Overdue에서도 global admin은 planning Teacher 생성·credential 발급/재발급·대표 지정/교체·Classroom 준비 등 기존 recovery operation을 수행할 수 있다.
14. 이전/current manager의 도움 없이 global admin이 필요한 planning과 새 Teacher/manager를 마련하고 정상 eligibility를 충족해 수동 rollover할 수 있다.
15. 늦은 날짜나 자동 실패를 이유로 eligibility override, 강제 rollover/force-close를 제공하지 않는다.
16. Rollover 후 기존 planning manager가 같은 annual User/role로 current operational manager가 되어 새 active-year Teacher/Classroom을 관리하고 이전 manager는 operational authority를 잃는다.
17. 각 target year의 Y-02-01 guard 때문에 아직 시작일이 오지 않은 미래 연도로 연속 rollover할 수 없다.

후속 구현 검증은 날짜 경계, domain/direct request 거부, 자동 중복·실패 기록 보존·장애·수동 경합, overdue recovery와 기존 authority 승계를 중심으로 한다. 이번 문서 run에서는 코드/spec test를 수정하거나 테스트를 실행하지 않는다.

## Non-goals

- 강제 rollover, force-close 또는 eligibility override
- 새 `overdue` SchoolYear status나 persisted overdue flag
- Active year 자동 보정 또는 날짜만으로 강제 archive
- Planning SchoolYear 자동 생성
- Teacher/Classroom/HomeroomAssignment/Student 자동 생성·복사·승계
- 실패하거나 결과가 불확실한 automatic rollover의 지속 자동 retry
- Generic lifecycle/state-machine framework 또는 audit framework 확장
- Current/planning manager rollover 권한 확대
- Rollover reversal, rollback/undo UI
- Production time-travel helper/debug endpoint
