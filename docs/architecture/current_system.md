# Current System

## 문서 목적

현재 starter에 실제로 존재하는 공통 학교·학년도·교실·사용자 구조를 기록한다. 이 문서는 historical migration 구조가 아니라 현재 runtime을 설명한다.

## 사용자와 인증

- global admin과 Teacher는 `User`다. Teacher는 정확히 하나의 `SchoolYear`에 속한다.
- Teacher의 학교, annual role과 학년의 canonical source는 각각 `User.school_year.school`, `User.school_role`, `User.grade`다. 별도 school membership fallback은 없다.
- Student는 하나의 Classroom에 직접 속한 별도 `Student` 모델이다. 학생용 `User`, 학생 membership 또는 `StudentEnrollment`는 runtime/schema에 없다.
- Teacher는 `login_id + password` Devise 흐름을 사용한다. 생성·재발급되는 임시 자격증명은 일회성 표시와 audit 계약을 따른다.
- Student는 Classroom token과 PIN을 확인한 뒤 짧은 Rails session을 사용한다. `Student.active`와 School/Classroom/SchoolYear 상태가 session eligibility를 결정한다.

## SchoolYear와 운영 context

- `SchoolYear.status`는 `planning`, `active`, `archived`다. School에는 active와 exact immediate planning SchoolYear가 각각 최대 하나다.
- current operational manager의 기본 Teacher/Classroom context는 자기 School의 active year다.
- eligible planning manager의 기본 context는 자기 exact immediate planning year다.
- 두 manager 모두 자기 School의 active, exact planning과 archived year를 selector에서 선택할 수 있다. archived context는 read-only다.
- global admin은 명시적으로 School과 SchoolYear를 선택해 모든 School을 관리한다.
- malformed, cross-School 또는 unauthorized context는 다른 year로 fallback하지 않는다.
- planning에서는 Teacher, Classroom과 current `HomeroomAssignment` 구성을 준비한다. Student 명단 준비 mutation은 현재 제공하지 않는다.
- actual rollover는 global admin-only governance operation이다.

## Teacher와 Classroom

모든 Classroom은 하나의 변경 불가능한 SchoolYear에 속하며 학교는 `Classroom.school_year.school`로 결정한다. Classroom은 필수 `grade`, normalized `class_label`과 active/inactive lifecycle을 가진다.

담임 관계의 canonical source는 current `HomeroomAssignment`다.

```text
HomeroomAssignment(classroom_id, teacher_id, started_on, ended_on)
current: ended_on IS NULL
Teacher 0..1 ↔ 0..1 Classroom
```

- Teacher와 Classroom은 같은 SchoolYear와 grade여야 한다.
- active assignment 변경은 종료 이력을 보존하고, planning assignment 변경은 준비 데이터를 교체한다.
- Teacher 비활성화는 current assignment를 종료하며 재활성화 때 자동 복원하지 않는다.
- Classroom 비활성화는 Student와 assignment/history를 삭제하지 않고 운영을 잠근다.

## 운영 surface

- `/teachers`: 기존 개별 Teacher 목록·생성·편집·lifecycle·임시 비밀번호 관리
- `/admin/teachers`: active/planning Teacher 일괄 생성·수정·operation, archive read-only
- `/classrooms`: 기존 Classroom 카드·상세·설정·member/Student 운영
- `/admin/classrooms`: active Classroom 구조·담임·lifecycle 일괄 관리, planning 구조·담임 준비, archive read-only

`/admin/teachers`와 `/admin/classrooms`는 이름과 달리 global-admin-only surface가 아니다. Global admin, current operational manager와 eligible planning manager가 각자의 SchoolYear scope에서 사용한다. Ordinary Teacher는 Teacher 관리 surface에 접근하지 않고 current HomeroomAssignment로 배정된 active Classroom 범위만 운영한다.

## Student 운영

- Student 소속과 lifecycle의 canonical source는 `Student.classroom_id`, `Student.active`다.
- active operational Classroom에서 권한 있는 global admin, 자기 School manager 또는 담당 ordinary Teacher가 roster, profile, lifecycle과 PIN/token 관련 operation을 수행한다.
- archived Student 자료는 자기 scope에서 read-only다.
- planning Classroom의 Student roster CRUD는 현재 지원하지 않는다.

## 권한 원칙

- Pundit policy와 `policy_scope`가 서버측 권한의 최종 기준이다.
- global admin은 모든 School의 운영 관리자다.
- current operational manager와 eligible planning manager는 자기 School의 active/planning 운영 관리자이며 archive를 read-only로 본다.
- manager 지정은 global admin 또는 current operational manager가 자기 School의 exact planning year에서 수행할 수 있다. Planning manager 자신과 ordinary Teacher는 수행할 수 없다.
- School lifecycle, actual rollover와 system/recovery operation은 별도의 governance 권한을 유지한다.
- UI 숨김이나 parameter만으로 scope를 넓힐 수 없다.

## 관련 canonical 문서

- 역할과 권한: [`roles_and_permissions.md`](roles_and_permissions.md)
- planning과 manager collaboration: [`planning_year_bootstrap.md`](../specs/planning_year_bootstrap.md)
- Teacher bulk: [`teacher_bulk_management.md`](../specs/teacher_bulk_management.md)
- Classroom bulk: [`classroom_bulk_management.md`](../specs/classroom_bulk_management.md)
- Student lifecycle: [`student_membership_lifecycle.md`](../specs/student_membership_lifecycle.md)
