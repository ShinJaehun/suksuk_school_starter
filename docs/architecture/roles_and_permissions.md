# Roles And Permissions

이 문서는 현재 runtime의 role × School scope × SchoolYear context 권한을 요약한다. Pundit policy, scope와 domain validation이 최종 경계이며 `/admin` namespace 자체는 권한 source가 아니다.

## Actor

- **Global admin**: 모든 School의 운영 resource를 관리한다. SchoolYear governance와 system operation은 각 operation의 별도 정책을 따른다.
- **Current operational manager**: 현재 유효한 active annual manager로서 자기 School의 active/planning 운영과 archive read를 담당한다. 기본 context는 active다.
- **Eligible planning manager**: exact immediate planning year의 유효한 manager로서 자기 annual planning year의 preparation만 담당한다. 기본 context는 planning이다.
- **Ordinary Teacher**: Teacher 관리 권한은 없으며 current `HomeroomAssignment`로 배정된 active Classroom 범위만 운영한다.
- **Student**: `Student.classroom_id`의 active Classroom에서 허용된 자기 session 기능만 사용한다.

Manager의 School operation authority는 global admin role 부여가 아니다. 다른 School, generic system administration, School lifecycle, actual rollover와 recovery authority는 확대되지 않는다.

## 현재 권한 매트릭스

| 리소스/액션 | Global admin | Current manager | Planning manager | Ordinary Teacher | Student |
|---|---|---|---|---|---|
| `/teachers` | 모든 School, 허용 context | 자기 School active/planning, archive read | 자기 exact planning preparation | 거부 | 거부 |
| `/admin/teachers` bulk | 모든 School active/planning, archive read | 자기 School active/planning, archive read | 자기 exact planning preparation | 거부 | 거부 |
| `/classrooms` | 모든 School | 자기 School active/planning, archive read | 자기 exact planning preparation | 담당 active Classroom | 자기 active Classroom의 허용 기능 |
| `/admin/classrooms` bulk | 모든 School active/planning, archive read | 자기 School active/planning, archive read | 자기 exact planning preparation | 거부 | 거부 |
| active Student/member operation | 모든 School | 자기 School 전체 | 거부 | 담당 Classroom | 관리 operation 거부 |
| planning preparation | Teacher/Classroom/담임 | 자기 School Teacher/Classroom/담임 | 자기 School Teacher/Classroom/담임 | 거부 | 거부 |
| planning Student roster mutation | 미지원 | 미지원 | 미지원 | 미지원 | 미지원 |
| archived Teacher/Classroom/Student | read-only | 자기 School read-only | 거부 | 거부 | 거부 |
| planning manager 지정·교체·해제 | 가능 | 자기 School exact planning에서 가능 | 거부 | 거부 | 거부 |
| actual rollover | 가능 | 거부 | 거부 | 거부 | 거부 |

## 중요한 보호 경계

- Current manager의 운영 authority와 planning manager의 preparation authority는 `annual_school`이 같은 resource에만 적용한다. Planning manager가 active/archive context를 직접 주입한 경우를 포함해 malformed, cross-School 또는 unauthorized SchoolYear는 fallback 없이 거부한다.
- Planning manager designation은 일반 Teacher profile/bulk mutation으로 우회할 수 없다.
- Archived context의 mutation은 모든 manager에게 금지한다.
- Active Student mutation은 active School, active SchoolYear, active Classroom과 Student lifecycle 조건을 모두 요구한다.
- Planning은 Teacher, Classroom과 HomeroomAssignment 준비만 지원하고 Student를 생성·수정·이동·삭제하지 않는다.
- Teacher와 Classroom 담임 관계는 current `HomeroomAssignment`만 사용한다.
- Ordinary Teacher의 권한은 같은 School 전체가 아니라 담당 active Classroom에 한정된다.

## Governance와 operation 구분

Current manager의 운영 authority와 planning manager의 preparation authority는 SchoolYear lifecycle predicate의 의미를 바꾸지 않는다. `current_operational_manager?`, planning manager eligibility와 preparation authority는 각자의 의미를 유지한다. Planning manager는 rollover 뒤 해당 SchoolYear가 active가 된 때부터 같은 session에서 current operational manager authority를 얻는다. Actual rollover, recovery/reversal, global system operation과 manager 자신의 designation은 operation별 policy가 별도로 통제한다.
