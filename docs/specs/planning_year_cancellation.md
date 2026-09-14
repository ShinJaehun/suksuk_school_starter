# Planning Year Cancellation

## 목적

이 문서는 active SchoolYear를 유지한 채 exact immediate planning SchoolYear와 그 준비 workspace 전체를 폐기하는 global-admin-only governance operation의 canonical contract다. 이는 rollover reversal이나 current-year mutation 복구가 아니다.

예를 들어 2026 active와 2027 planning이 있으면 취소 성공 후 2026과 모든 active 운영 data는 그대로 유지되고, 2027 planning SchoolYear와 그 Teacher, Classroom, HomeroomAssignment 및 workspace credential event는 제거된다. School은 planning SchoolYear가 없는 상태가 되며 기존 `CreatePlanning` 경로로 2027 준비를 다시 시작할 수 있다.

## Authority와 대상 resolution

- Global admin만 취소할 수 있다.
- Current operational manager, active planning manager, ordinary Teacher와 Student는 취소할 수 없다.
- 대상 School은 active여야 한다.
- 대상은 해당 School의 유일한 planning SchoolYear이며 current active SchoolYear의 exact immediate next year여야 한다.
- Client의 SchoolYear id는 authority나 대상 source가 아니다. Cross-School, arbitrary, non-planning, non-immediate와 stale SchoolYear 주입은 fallback 없이 fail closed한다.
- School을 먼저 lock하고 planning SchoolYear를 다음으로 lock한 뒤 School 상태, active/planning cardinality, ownership, status와 exact-immediate relation을 transaction 안에서 다시 검증한다.

Planning manager 자신을 포함한 planning lifecycle 전체 삭제는 preparation authority가 아니라 SchoolYear governance authority다.

## Confirmation과 UI

`/schools/:school_id/planning` 하단에 global admin에게만 danger area를 제공한다. Current manager와 planning manager에게는 control을 렌더링하지 않는다.

Danger area는 다음을 보여준다.

- `다음 학년도 준비 취소`
- 삭제될 planning year
- planning Teacher, Classroom 등 주요 삭제 대상 수
- 복구할 수 없으며 active SchoolYear와 current operation은 되돌리지 않는다는 경고

Turbo confirm만을 최종 확인으로 사용하지 않는다. 요청은 planning year를 사용자가 직접 입력한 confirmation 값으로 받고, server가 현재 lock된 planning year와 정확히 일치하는지 검증한다. 불일치하면 아무것도 삭제하지 않는다. 사용자 표시 문자열은 locale key로 제공한다.

성공하면 `school_path(school)`로 redirect하고 success notice를 표시한다. 삭제된 planning page로 redirect하지 않는다.

## Cancellation transaction

하나의 DB transaction에서 planning Teacher ids와 planning Classroom ids를 확정한 뒤 다음 순서로 명시적으로 destroy한다.

1. Planning HomeroomAssignment
2. Planning workspace credential events
3. Planning Classroom 전부
4. Planning manager를 포함한 planning Teacher 전부
5. Planning SchoolYear

규모가 작은 workspace이므로 service가 record destruction을 명시적으로 수행한다. Blanket `dependent: :destroy`, generic cascade 구조와 domain restriction을 피하기 위한 무분별한 `delete_all`을 추가하지 않는다.

Teacher, Classroom, HomeroomAssignment, credential event 또는 SchoolYear 중 하나라도 destroy에 실패하거나 예상하지 않은 dependency가 있으면 전체 transaction을 rollback한다. 일부 취소 상태는 허용하지 않는다.

## Credential event boundary

정상 planning credential event는 planning Teacher를 target으로 하며 current manager 또는 planning manager가 actor일 수 있다. Planning target에 종속된 발급·재발급 event와 planning manager에서 planning Teacher로 향한 event는 workspace와 함께 제거할 수 있다.

Planning Teacher가 actor이고 target Teacher가 target planning SchoolYear 밖에 있는 credential event가 하나라도 있으면 authority drift로 생긴 외부 audit dependency로 간주한다. 이 event를 삭제하지 않고 cancellation 전체를 fail closed하여 rollback한다. Active 또는 historical target의 credential audit은 cancellation 때문에 삭제하지 않는다.

## Student boundary

Planning Student preparation은 지원하지 않는다. Target planning Classroom에 Student가 하나라도 있으면 out-of-contract data로 간주하여 Student를 자동 삭제하지 않고 cancellation 전체를 fail closed하여 rollback한다.

## Session boundary

Planning manager User는 다른 planning Teacher와 함께 삭제된다. 별도 session-version 또는 revocation framework를 만들지 않는다. 기존 Devise record resolution과 session eligibility에 따라 기존 planning-manager session은 후속 request에서 더 이상 User나 planning authority로 동작할 수 없어야 한다.

## Acceptance criteria

1. Global admin은 현재 planning year와 정확히 일치하는 confirmation year를 제출해 취소할 수 있다.
2. Target planning SchoolYear가 삭제된다.
3. Planning manager를 포함한 planning Teacher 전원이 삭제된다.
4. Planning Classroom 전부가 삭제된다.
5. Planning HomeroomAssignment 전부가 삭제된다.
6. Planning Teacher를 target으로 하는 workspace credential event가 삭제된다.
7. Planning manager가 actor이고 planning Teacher가 target인 credential event도 삭제된다.
8. Active SchoolYear와 active Teacher, Classroom 및 Student는 그대로 보존된다.
9. Current manager가 active year에서 만든 credential event와 operational history는 보존된다.
10. Planning Teacher가 planning SchoolYear 밖의 active 또는 historical Teacher credential event actor이면 전체 취소가 fail closed되고 모든 row가 보존된다.
11. Planning Classroom에 Student가 하나라도 있으면 전체 취소가 fail closed되고 모든 row가 보존된다.
12. Current operational manager, active planning manager와 ordinary Teacher는 취소할 수 없다.
13. Cross-School, arbitrary, non-planning, non-immediate와 stale SchoolYear 주입은 fallback 없이 거부된다.
14. Confirmation year가 현재 planning year와 일치하지 않으면 아무것도 삭제하지 않는다.
15. 성공 후 School에는 planning SchoolYear가 없다.
16. 성공 후 기존 `CreatePlanning` operation으로 같은 exact next year preparation을 다시 시작할 수 있다.
17. 삭제된 planning manager의 기존 session은 후속 request에서 planning authority를 사용할 수 없다.

## Non-goals

- Active SchoolYear rollback
- Rollover reversal 또는 archived data 삭제
- Current-year mutation, credential event나 operational history 되돌리기
- Student planning support
- Generic soft-delete/recovery 또는 cancellation history/audit framework
- 새 authority abstraction
- Generic cascade refactor