# Student Lifecycle

## 목적

Classroom에 직접 속한 Student의 active/inactive lifecycle, 권한과 session 경계를 정의한다.

## 현재 runtime

- Student는 정확히 하나의 Classroom에 직접 속한다.
- `Student.active`가 현재 운영 학생 여부를 나타내며 기본값은 active다.
- active Student는 현재 roster와 학생 PIN 로그인 대상이고 inactive Student는 보존된 과거 참여자다.
- Classroom의 active Student는 최대 30명이다.
- inactive Student도 이름, 출석번호, PIN digest, gender, avatar와 기존 활동 기록을 삭제하지 않는다.
- SchoolYear archive는 Student.active를 일괄 변경하지 않는다.

### 비활성화와 복구

- 삭제 UI와 직접 `DELETE` 호환 요청은 Student를 hard delete하지 않고 `active = false`로 바꾼다.
- 비활성화할 때 Classroom, 출석번호와 기존 기록을 보존한다.
- 교사/admin은 inactive Student를 상세·관리·복구 대상으로 조회할 수 있다.
- 복구 시 current Classroom이 운영 가능해야 하고 active 30명 제한과 active 출석번호 충돌을 다시 검사한다.
- 복구가 실패하면 Student는 inactive 상태를 유지하며 번호나 Classroom을 자동 변경하지 않는다.
- 인원 수와 번호 invariant가 걸린 복구는 Classroom/Student lock과 DB constraint를 최종 안전망으로 사용한다.

### 권한 경계

- 비활성화/복구와 관리 mutation은 현재 Classroom의 학생 관리 권한을 따른다.
- global admin은 운영 가능한 Classroom을 관리할 수 있다.
- current operational manager와 eligible planning manager는 자기 School의 active operational Classroom에서 학생을 관리한다.
- ordinary teacher는 current `HomeroomAssignment`로 배정된 active Classroom만 관리한다.
- Student는 자신의 self-service와 PIN 변경만 가능하며 다른 Student나 관리 endpoint에 접근할 수 없다.
- URL Classroom과 `Student.classroom_id`가 다르면 scope를 넓힐 수 없다.

### PIN과 session

- 신규 Student는 4자리 PIN이 필수이며 Devise email/password를 갖지 않는다.
- inactive Student는 PIN 선택 목록과 로그인 검증에서 제외한다.
- 로그인 뒤 Student, Classroom, SchoolYear 또는 School이 eligibility를 잃으면 다음 일반 request에서 Student session을 종료한다.
- 20분 inactivity TTL과 PIN 시도 제한을 유지한다.
- 학생 PIN의 canonical source는 `Student.student_pin_digest` 하나다.

### 구현 원칙

- controller는 `authorize`, `policy_scope`와 흐름을 담당하고 view에서 복잡한 권한 판단을 하지 않는다.
- 일반 운영 화면과 PIN 일괄 재설정은 active Student만 대상으로 한다.
- 개별·여러 학생 등록과 복구는 저장 직전 Classroom lock 아래 active 학생 수를 재검증한다.
- 학생 gender/avatar의 validation과 legacy 호환 동작은 [`student_roster.md`](student_roster.md)를 따른다.
- legacy student User와 student ClassroomMembership은 cleanup 전환 데이터이며 runtime authority로 사용하지 않는다.

## 학년도 경계

- Student create/update/deactivate/reactivate는 active operational Classroom에서만 가능하다.
- planning SchoolYear에는 Student 명단 준비 UI/API가 없으며 Student를 생성·수정·이동·삭제하지 않는다. Planning Student preparation은 future work다.
- planning과 archived SchoolYear에서는 학생 login을 허용하지 않는다.
- archived SchoolYear는 Student.active를 바꾸지 않고 하위 자료와 당시 상태를 read-only로 보존한다.
- 다른 학년도에는 새 Student를 만들며 동일 학생 identity 연결이나 StudentEnrollment를 추가하지 않는다.

Migration과 legacy 제거는 [`student_model_migration.md`](student_model_migration.md), 명단 계약은 [`student_roster.md`](student_roster.md)를 따른다.
