# School Year Architecture

## 목적

이 문서는 학교 기반 서비스를 여러 학년도에 걸쳐 운영하고 과거 자료를 보존하기 위한 장기 canonical architecture를 정의한다. 특정 서비스 도메인은 포함하지 않으며, migration 시작 당시 starter 구조에서 장기 target으로 안전하게 발전시키는 기준으로 사용한다. 현재 runtime은 [`current_system.md`](../architecture/current_system.md)와 [`roles_and_permissions.md`](../architecture/roles_and_permissions.md)를 따른다.

이 문서는 목표 구조를 정의한다. migration, route, controller, view와 데이터 이전 절차는 각 구현 단계의 별도 승인 대상이다.

## 핵심 원칙

- `SchoolYear`는 한 `School`의 특정 학년도 운영 context다.
- global admin, teacher와 student의 authentication identity를 구분한다.
- teacher login account는 SchoolYear에 종속되며 `login_id + password`로 인증한다.
- School manager는 자기 Classroom이 아니라 자기 School 전체를 운영하는 school-level operator다.
- 정상 운영은 active SchoolYear에서만 이루어진다.
- archived SchoolYear는 하위 운영 데이터를 보존하는 read-only 경계다.
- 상위 SchoolYear 상태를 하위 row마다 중복 저장하지 않는다.
- account lifecycle, `SchoolYear.status`, `Classroom.active`, `Student.active`는 서로 다른 lifecycle이다.
- 현재 학년도 화면에는 학년도를 반복 표시하지 않고 context가 바뀌거나 여러 연도를 구별할 때만 표시한다.
- 다음 학년도 구성은 planning 단계에서 명시적으로 준비하며 자동 복사·진급하지 않는다.

## Historical pre-cutover baseline과 전환 방향

Migration 시작 당시의 legacy 구조는 다음과 같다.

```text
School
├── SchoolMembership ── User
└── Classroom
    ├── teacher_id ── User
    └── ClassroomMembership ── student User
```

당시 제약은 teacher당 `SchoolMembership` 하나, `Classroom.teacher_id` 기반 현재 담임 1:1, student User당 active `ClassroomMembership` 하나였다. 이는 단일 현재 학년도 운영에는 맞지만 연도별 이력과 학년도 중 담임 교체를 충분히 표현하지 못했다.

목표 구조는 다음과 같다.

```text
User
├── global admin (SchoolYear 비종속)
└── teacher (정확히 하나의 SchoolYear에 귀속)

School
└── SchoolYear
    ├── teacher Users
    └── Classroom
        ├── HomeroomAssignment ── teacher User
        └── Student
```

Student `ClassroomMembership`은 전환 기간의 historical source였으며 현재 runtime source가 아니다. 현재 학생 소속과 lifecycle 책임은 Classroom에 직접 속한 Student가 가진다.

## SchoolYear lifecycle

`SchoolYear`는 최소한 다음 속성을 가진다.

```text
school_id
year: integer
status: planning | active | archived
```

한 School 안에서 같은 `year`는 하나만 존재한다. `school_id + year`에 DB unique invariant를 둔다. 한 School에는 active SchoolYear와 planning SchoolYear가 각각 최대 하나만 존재하며 DB partial unique invariant로 방어한다. archived SchoolYear는 여러 개 존재할 수 있다.

`year`는 네 자리 integer `1000..9999`로 검증한다. 현재 연도 주변으로 범위를 좁히는 시간 의존 validation은 두지 않는다.

School 생성이나 초기 bootstrap 중에는 active year가 0개일 수 있다. 정상 학생·교실 운영을 시작하려면 정확히 하나의 active SchoolYear가 필요하다. planning year는 현재 active year를 중단하지 않고 다음 구성을 준비하는 context이며 active year와 함께 존재할 수 있다.

Planning은 다음 학년도의 teacher, Classroom, Student와 담임 구성을 준비하고 rollover readiness를 확인하기 위한 staging이자 domain safety boundary다. 별도 SchoolYear dashboard나 navigation hierarchy를 뜻하지 않으며, 준비 상태와 후속 작업 진입은 School 화면의 자연스러운 school-operation surface에서 제공할 수 있다.

### planning

- teacher User, classroom, 담임과 학생 편성을 준비할 수 있다.
- 일반 학생 운영, token/PIN login과 운영 기록 생성은 허용하지 않는다.
- planning SchoolYear는 global admin 또는 현재 active SchoolYear의 manager가 자기 School에 생성하고 준비할 수 있다.
- Planning year는 현재 active SchoolYear의 바로 다음 학년도여야 한다. Server가 current active SchoolYear를 기준으로 `planning.year = active.year + 1`을 계산하며 사용자는 year를 입력하거나 선택하지 않는다. Client가 year parameter를 제출해도 신뢰하지 않으며 날짜 기준으로 계산하지 않는다.
- SchoolYear 생성은 manager 지정 권한을 포함하지 않으며 manager 지정·해제는 global admin만 수행한다.
- planning teacher User는 생성·구성할 수 있지만 정상 teacher runtime login에는 사용할 수 없다.
- 실제 운영 데이터는 자동 복사하지 않고 명시적으로 구성한다.

### active

- 해당 학교의 현재 정상 운영 context다.
- active School, active Classroom과 active Student 등 하위 lifecycle 조건을 함께 만족해야 실제 운영할 수 있다.
- active year가 있다는 이유만으로 inactive School이나 Classroom을 우회하지 않는다.

### archived

- 종료된 과거 학년도다.
- 하위 운영 row와 당시 상태를 보존한다.
- 하위 school-operation data는 read-only다.
- archived teacher User는 명시적인 SchoolYear context로 인증할 수 있고, 그 User에 저장된 당시 role과 scope에서 자료를 읽을 수 있다.
- 현재 학년도의 역할로 archived account 권한을 다시 계산하지 않는다.
- Application의 정상 operation에서는 archived year를 planning이나 active로 되돌리지 않는다. 단, 직전 rollover 사고를 복구하는 global-admin-only reversal은 아래의 제한된 recovery operation으로 구분한다.

## 현재·다음·과거 학년도

- 현재: School의 유일한 active SchoolYear
- 다음: bootstrap 중인 planning SchoolYear
- 과거: archived SchoolYear

현재 운영 화면은 active year를 기본 context로 사용한다. planning이나 archived year를 선택한 화면은 상위에 `2027학년도 · 준비 중`, `2025학년도 · 읽기 전용`처럼 context와 상태를 한 번 명확히 표시한다.

## Classroom과 반 식별

Classroom은 `SchoolYear`에 속한다. 목표 구조에서는 School이 `classroom.school_year.school`로 결정되므로 `Classroom.school_id`를 영구 중복 source로 유지하지 않는다. 전환 중에는 backfill과 기존 query 호환을 위해 일시적으로 두 FK가 공존할 수 있지만, 검증 완료 후 `school_year_id`만 canonical school path로 남기는 것을 권장한다. 이는 두 school pointer의 불일치 가능성을 제거하며 query는 association과 적절한 index로 단순화한다.

Classroom의 목표 식별 정보는 다음과 같다.

```text
school_year_id
grade: integer (1..6)
class_label: string
active: boolean
```

`class_label`은 숫자로 제한하지 않는다. `"1"`, `"가"`, `"햇살"`처럼 저장하고 presentation layer에서 `반`을 붙인다.

입력은 다음 순서로 normalize한다.

1. 앞뒤 공백을 제거한다.
2. 끝의 단일 `반` suffix가 있으면 그 한 글자만 제거한다.
3. suffix 제거 뒤 생긴 앞뒤 공백을 다시 제거한다.
4. 결과가 비어 있으면 거부한다.

문자열 내부나 시작 부분의 `반`은 제거하지 않는다. 따라서 `반디`는 그대로 저장하고 `햇살반`은 `햇살`로 저장한다. 같은 SchoolYear 안에서 `grade + class_label`은 유일해야 하며 DB unique invariant로 방어한다. 다른 SchoolYear의 같은 조합은 허용한다.

`Classroom.active`는 해당 학년도 안에서 그 교실 자체의 운영 상태다. SchoolYear를 archive해도 Classroom을 inactive로 바꾸지 않는다. archived year 아래의 `active: true` classroom은 당시 정상 운영됐으나 지금은 과거 context라 read-only라는 뜻이다.

## Teacher User와 인증 context

Migration 시작 당시 구현은 teacher와 global admin을 하나의 Devise `User`에서 email/password로 인증했다. 장기 target은 다음 세 인증 경계를 분리하며, 현재까지 구현된 인증 경계는 current runtime 문서를 따른다.

```text
Global admin User → SchoolYear 비종속 시스템 계정
Teacher User      → SchoolYear별 account, login_id + password
Student           → 별도 Student identity, classroom token + 학생 선택 + PIN
```

Global admin의 최종 login identifier는 이 문서에서 변경하지 않는다. Teacher의 email은 optional contact profile이 될 수 있지만 authentication identifier가 아니다. Student를 분리한 뒤 `User`는 global admin과 teacher를 표현하되 두 role의 SchoolYear 귀속과 lifecycle은 서로 다르다.

Global admin User는 SchoolYear에 종속되지 않는다. Teacher User 하나는 정확히 한 SchoolYear의 annual login account 하나를 의미한다. School scope는 `teacher.school_year.school`을 통해 결정하는 것을 target으로 하며 중복 `school_id` 필요 여부는 migration과 query 설계 단계에서 검토한다.

Teacher User는 개념적으로 다음 annual 정보를 가진다. 정확한 column 이름은 구현 spec에서 정한다.

```text
school_year
login_id / encrypted credential / password_change_required
annual role: member | manager
grade
name
avatar/profile
account active/inactive state
```

`login_id`는 사람 identity나 영구 username이 아니며 같은 값은 서로 다른 SchoolYear에서 재사용할 수 있다. 같은 SchoolYear 안에서는 중복될 수 없으므로 개념적으로 다음 DB invariant가 필요하다.

```text
UNIQUE (school_year_id, login_id)
```

예를 들어 다음 두 User는 서로 다른 사람이어도 정상이다.

```text
2025 / tara0411 / 김교사 / 4학년 11반
2026 / tara0411 / 박교사 / 4학년 11반
```

같은 사람이 다음 학년도에도 근무하면 다음 학년도용 teacher User를 새로 발급한다. 이름, `login_id`, avatar나 profile 일치로 연도간 동일인을 자동 추론하거나 연결하지 않는다. 영구 Teacher identity와 annual account의 2계층은 starter target에 두지 않으며, 장기 동일인 연결은 이를 필요로 하는 downstream 서비스의 별도 확장이다.

Pre-cutover `SchoolMembership`의 school, role과 grade 책임은 migration 기간에 compatibility structure로 남을 수 있었지만 장기 target에서는 annual teacher User와 SchoolYear relation으로 흡수한다. Teacher User와 사실상 1:1인 annual membership model을 중복 유지하지 않는다.

따라서 authentication code가 `find_by(login_id: "tara0411")`처럼 SchoolYear context 없는 global lookup을 해서는 안 된다. Teacher login entry point가 School context를 식별하고, active login에서는 그 School의 active SchoolYear를 자동으로 resolve한다.

### Annual role과 account lifecycle

Teacher User의 role, grade, school scope와 login credential은 해당 SchoolYear context에 속한다. 연도별 User는 독립된 account이므로 같은 사람이 2025에는 manager이고 2026에는 member일 수 있다.

```text
2025 account login → 2025 manager scope, archived read-only
2026 account login → 2026 member scope, active-year 허용 범위에서 read/write
```

현재 역할로 과거 권한을 덮어쓰지 않는다. SchoolYear archive는 teacher User의 credential을 삭제하거나 account를 자동 inactive로 만들지 않는다. 반대로 account가 인증 가능하더라도 SchoolYear 상태가 허용하는 operation 범위를 넘을 수 없다. Teacher User 자체의 active/inactive account lifecycle은 SchoolYear status와 별개이며 구체 field 이전은 후속 spec에서 정한다.

`active_teacher?`처럼 teacher role과 User account의 active 상태만 표현하는 predicate는 SchoolYear의 운영 가능 상태까지 보장하지 않는다. 권한과 navigation은 최소한 active teacher account, active School과 active SchoolYear에 속한 current operational teacher, 여기에 annual manager role까지 만족하는 current operational manager, archived context에서 인증한 teacher를 구분해야 한다. 정확한 Ruby method 이름은 구현 단계에서 정하되 write authority는 session guard가 대신 막아 줄 것이라고 가정하지 않고 policy와 domain operation에서 School scope와 SchoolYear status를 명시적으로 확인한다.

Annual role이 manager이면 자기 School 전체가 authority scope다. Manager가 담임을 함께 맡을 수는 있지만 school-wide authority는 자신의 Classroom authority보다 넓다. Archived manager account는 당시 자기 School 전체를 read-only로 열람하고, archived ordinary teacher account는 HomeroomAssignment로 확인되는 당시 담당 Classroom 범위만 read-only로 열람한다.

과거 Classroom, HomeroomAssignment와 작성 기록은 해당 학년도의 teacher User를 그대로 참조한다. SchoolYear를 archive해도 그 User를 삭제하거나 다른 연도의 User로 교체하지 않으므로 당시 이름, annual role, grade, login account와 담임 이력을 그 학년도 context 안에서 보존한다.

### 임시 비밀번호 lifecycle

관리 권한이 있는 주체가 teacher User를 만들 때 예측하기 어려운 임시 비밀번호를 발급하고 강제 변경 상태를 설정한다.

```text
login_id
temporary password
password_change_required = true
```

교사는 최초 인증 성공 후 정상 application 사용 전에 본인 비밀번호를 변경해야 한다. 성공하면 강제 변경 상태를 해제하고 session fixation 방지를 위해 session을 rotation한다. planning teacher User는 credential 준비가 가능하지만 SchoolYear가 active가 되기 전에는 정상 runtime login을 허용하지 않는다.

Active 또는 planning year의 teacher가 비밀번호를 잊으면 global admin 또는 자기 School의 current active-year manager가 허용된 범위에서 새 임시 비밀번호를 재발급할 수 있다. Archived teacher User도 global admin 또는 현재 해당 School의 active-year manager가 재발급할 수 있다. Manager는 다른 School의 account를 재발급할 수 없다.

재발급은 기존 credential을 즉시 무효화하고 새 temporary credential과 강제 변경 상태로 교체한다. 기존 비밀번호는 누구도 조회할 수 없고 평문 temporary password는 DB에 저장하지 않는다. 누가, 언제, 어떤 account를 재발급했는지 감사 가능한 기록을 남긴다.

임시 비밀번호와 재발급은 다음 보안 원칙을 따른다.

- 평문 비밀번호를 DB column에 저장하지 않는다.
- 일반 비밀번호와 동일하게 digest/encrypted credential만 저장한다.
- 생성된 평문 임시 비밀번호는 발급 성공 시점에만 표시한다.
- 기존 또는 현재 비밀번호를 조회하는 기능을 제공하지 않는다.
- 충분히 예측하기 어려운 random 값을 사용하며 구체 형식은 authentication 구현 spec에서 정한다.
- login brute-force/rate limiting을 적용한다.
- password 발급·재발급을 민감한 운영 action으로 authorize하고 감사 가능하게 한다.

Archived account의 본인 password 변경은 school-operation data mutation과 구분한다. 이를 SchoolYear가 archived라는 이유만으로 일괄 금지하지 않으며 구체 정책은 authentication spec에서 확정한다.

### Authentication routing

`UNIQUE (school_year_id, login_id)`만으로는 전역 login form이 account를 유일하게 찾을 수 없다. 서로 다른 School의 active year에도 같은 `login_id`가 존재할 수 있기 때문이다. 정상 lookup은 반드시 School context와 SchoolYear context를 포함해야 한다.

Active-year login entry point는 School context를 이미 알고 있어야 한다. Server는 다음 순서로 account를 resolve한다.

```text
School → active SchoolYear → teacher User(login_id)
```

사용자는 `login_id + password`만 입력하며 SchoolYear를 선택하지 않는다. 예를 들어 active year가 2026이면 `tara0411`은 2026 account를 의미한다. 현재 학년도를 매번 선택시키거나 일상 login 화면에 반복 노출하지 않는다.

Archived account login에는 School과 SchoolYear context를 명시한다. 기본 UX는 active login과 분리된 `지난 학년도 자료 보기` 진입점에서 과거 SchoolYear를 선택한 뒤 `login_id + password`를 입력하는 형태다. 앞선 예의 2025 `tara0411`을 사용하려면 이 archived flow에서 2025를 명시한다. 동등한 school/year-specific entry point도 가능하다.

Archived login의 rate-limit context도 School과 explicit archived SchoolYear를 포함한다. Active login과 archived login은 서로 다른 account resolution context를 사용하며 planning account로 fallback하지 않는다.

정확한 public School identifier와 URL 형식은 구현 단계에서 정한다. 이는 active login에서 SchoolYear를 선택할지에 관한 정책 문제가 아니라, entry point가 School scope를 안전하게 전달하는 routing 세부사항이다.

현재의 전역 `/users/sign_in`과 Devise email lookup은 현행 구현이며 이 target을 그대로 만족하지 않는다. scoped Devise customization 또는 분리된 teacher authentication flow는 별도 구현 spec과 threat review 뒤 선택한다.

## 담임 assignment history

장기적으로 현재 담임과 과거 담임을 `HomeroomAssignment`로 표현한다.

```text
HomeroomAssignment
├── classroom_id
├── teacher_id
├── started_on
└── ended_on (nullable)
```

`teacher_id`는 Classroom과 같은 SchoolYear에 속한 teacher User를 참조한다. 영구 Teacher identity나 legacy SchoolMembership을 참조하지 않으며 teacher role User만 assignment할 수 있다.

`ended_on IS NULL`인 row가 current assignment다. 다음 invariant를 model과 DB가 함께 방어한다.

- 같은 Classroom에는 current assignment가 최대 하나다.
- 같은 teacher User에는 current classroom이 최대 하나다.
- Classroom과 teacher User는 같은 SchoolYear에 속한다.
- `ended_on`은 `started_on`보다 빠를 수 없다.
- 종료된 assignment는 보존하며 새 assignment가 과거 row를 덮어쓰지 않는다.
- 담임 교체는 기존 assignment 종료와 새 assignment 시작을 한 transaction에서 수행한다.

위 history semantics는 active SchoolYear의 실제 운영 이력과 archived history에 적용한다. Planning HomeroomAssignment는 아직 실제 운영 이력이 아니므로 `started_on`을 해당 SchoolYear의 3월 1일로 두고, planning 중 연결 변경·해제 또는 teacher/Classroom 준비 제외 시 기존 assignment를 삭제하여 `ended_on` history를 만들지 않는다. Rollover로 SchoolYear가 active가 된 뒤에는 planning 삭제 semantics를 적용하지 않는다.

현재 `Classroom.teacher_id`는 HomeroomAssignment 이전 완료 후 제거 대상이다.

## Student identity와 소속 방향

학생은 staff `User`에서 분리된 별도 `Student`이며 특정 Classroom에 직접 속한다. Devise credential이나 staff role을 갖지 않고 Classroom token, 학생 선택, PIN과 별도 Rails session context로 인증한다.

Student는 학년도 간 이어지는 장기 identity가 아니다. 다음 학년도에는 새 Classroom에 새 Student를 등록하며 서로 연결하지 않는다. `student_number`, active/inactive와 PIN digest도 Student가 직접 가진다. `StudentEnrollment`는 만들지 않는다. 상세 계약은 [`student_model_migration.md`](student_model_migration.md)를 따른다.

## Archive와 read-only

SchoolYear archive는 하위 row를 삭제하거나 일괄 inactive로 바꾸는 작업이 아니다. archived year 아래에서 다음 mutation은 기본적으로 금지한다.

- Classroom 생성·수정·삭제와 lifecycle 변경
- grade와 class_label 변경
- HomeroomAssignment 추가·교체·종료
- Student 생성·수정, active 상태 및 student_number 변경
- 학생 login token 재발급
- teacher User의 annual authority와 manager role 변경

정책과 domain operation이 SchoolYear 상태를 서버에서 최종 확인한다. UI를 숨기는 것만으로 read-only를 보장하지 않는다.

Teacher User의 인증 credential과 account profile은 SchoolYear 하위 school-operation data와 구분한다. Archived account의 당시 role/scope는 read-only 열람 권한을 결정하지만 classroom, student, 담임이나 manager data를 변경할 권한은 주지 않는다.

## 학년도 rollover

정상 rollover는 하나의 명시적 domain operation이다.

```text
기존 active SchoolYear  → archived
준비된 planning SchoolYear → active
```

Rollover는 global admin이 모든 School에 수행할 수 있고 current operational manager가 자기 School에 수행할 수 있다. Ordinary teacher, planning teacher account와 archived teacher account는 수행할 수 없다. 명시적 confirmation, source active SchoolYear와 destination planning SchoolYear 확인, actor authority 재확인, School과 관련 SchoolYear locking 및 상태 invariant 재검증 뒤 두 상태를 한 transaction에서 원자적으로 변경한다. 실패하면 기존 active year를 유지한다. 일반 operation에서는 destination planning year 없이 active year만 archive하여 정상 학교가 current year를 잃게 하지 않는다.

Rollover는 다음을 자동 수행하지 않는다.

- 학생 진급이나 Student 복사
- 이전 SchoolYear teacher User의 다음 SchoolYear 자동 복제·자동 승계
- classroom 복사
- 담임 재배정
- 이전 학년도 Student 연결

필요한 다음 학년도 구성은 planning 단계에서 명시적으로 준비한다. 다음 SchoolYear의 teacher User도 이 단계에서 별도로 생성한다. Classroom이나 담임이 없는 planning year도 준비 중에는 허용한다. Active 전환 전 최소 readiness validation은 active School, destination planning year의 유효성, `destination.year == source.year + 1`, source active year 일치와 destination planning SchoolYear에 정확히 한 명의 유효한 manager annual User가 존재함을 포함한다. 유효한 destination manager는 해당 SchoolYear에 속하고 active account이며 annual teacher/manager invariant를 만족해야 한다. 모든 Classroom, HomeroomAssignment와 Student가 완성되어 있을 필요는 없다.

Destination manager는 rollover 전에 global admin이 명시적으로 준비한다. Source manager를 자동 복제·승계하지 않으며 current operational manager의 rollover 권한은 manager 지정·교체·해제 권한을 포함하지 않는다. Manager가 없거나 유효하지 않으면 rollover 전체를 실패시키고 source active year를 유지한다. 이 readiness는 관련 row를 lock한 뒤 transaction 안에서도 재검증한다.

전환이 성공하면 old-year teacher User는 archived read-only login context가 되고, planning에서 준비한 new-year teacher User는 active runtime login 대상이 된다. Rollover를 실행한 old-year manager account는 전환 직후 archived account가 되므로 새 요청에서 current operational manager authority를 계속 유지하지 않는다.

### Rollover reversal/recovery

Rollover reversal은 일반 undo나 임의 상태 변경이 아니라 직전 rollover 사고를 복구하기 위한 global-admin-only recovery operation이다. Manager, ordinary teacher와 archived teacher account는 실행할 수 없다.

정상 recovery 후보는 같은 School에 속한 직전 rollover pair 하나이며 다음 두 변경을 명시적인 강한 confirmation, deterministic locking과 하나의 transaction에서 함께 수행한다.

```text
current active SchoolYear   → planning
previous archived SchoolYear → active
```

Archived SchoolYear 하나를 임의로 active로 바꾸거나 두 상태 중 하나만 되돌리는 generic reactivation은 허용하지 않는다. Authority, pair와 상태 재검증 또는 어느 변경이든 실패하면 현재 active/archived 상태를 그대로 유지한다.

Reversal은 rollover 직후의 제한된 사고 복구만 대상으로 한다. 새 active year에서 operational mutation이 발생했다면 자동 reversal을 허용한다고 가정하지 않는다. 어떤 mutation을 운영 시작으로 판단할지, 직전 pair를 증명할 audit data와 정확한 recovery readiness 기준은 별도 human-reviewed bounded spec에서 확정하며 그 전에는 generic reversal을 구현하지 않는다.

## 권한과 접근 경계

권한은 `role × School scope × SchoolYear status`로 판단한다. Role만으로 다른 School이나 다른 상태의 mutation 권한을 얻을 수 없다.

- global admin은 모든 School의 SchoolYear를 관리하고 archived 자료를 열람한다. 모든 School의 rollover, manager 지정·교체·해제와 cross-school/system recovery를 수행할 수 있다.
- global admin만 같은 School의 직전 rollover pair에 대한 제한된 reversal/recovery를 수행할 수 있다.
- current active-year manager는 자기 School 전체의 Classroom, teacher User, Student와 운영 현황을 조회하고 각 기능 spec이 허용한 mutation을 수행한다. 담임 assignment 관리와 학교 전체 집계·통계·보고서도 이 school-wide scope에 포함된다.
- current active-year manager는 자기 School의 planning SchoolYear를 생성·준비할 수 있다. Teacher User와 임시 비밀번호 준비, Classroom 구성, 담임과 Student 명단 준비를 포함할 수 있지만 planning teacher/student runtime operation은 수행할 수 없다.
- current active-year manager는 explicit confirmation과 원자적 전환 계약 아래 자기 School의 rollover를 수행할 수 있다.
- current active-year manager는 자기 School의 archived SchoolYears를 school-wide read-only로 조회할 수 있다. 이는 과거 role이 아니라 현재 학교 운영 책임에서 나오는 authority이며 다른 School에는 적용되지 않는다.
- archived manager User는 명시적인 year login context에서 당시 자기 School 전체를 read-only로 열람한다. Archived ordinary teacher User는 당시 실제 담당했던 Classroom 범위만 read-only로 열람한다.
- 같은 사람이 2025 manager, 2026 ordinary teacher인 경우 각 annual account는 독립된 scope를 가진다. 2026 account의 현재 role로 2025 account의 historical authority를 덮어쓰지 않는다.
- archived account는 teacher·student·classroom·담임·manager 등 school-operation data를 변경할 수 없다.
- archived 자료의 화면 조회, 필터·검색, 집계·통계·보고서와 source data를 변경하지 않는 export는 read operation이다. Starter는 학급·teacher·student 현황 같은 공통 지표만 정의하며 서비스별 metric은 downstream domain이 추가한다.
- 학생 login은 active School, active SchoolYear, active Classroom, active Student를 모두 요구한다.
- planning/archived year에서는 학생 token/PIN login을 허용하지 않는다. Teacher archived login과 혼동하지 않는다.
- 기존 PIN throttling, classroom token과 student session TTL 경계를 유지한다.
- manager에게 `/admin/*`를 개방하지 않으며 URL과 parameter 조작으로 school/year scope를 넓힐 수 없다.

## SchoolYear-aware operation surface

`/teachers`와 `/classrooms`의 기본 진입은 현재 active year의 일상 운영 context다. Planning 또는 archived year를 기본 query에 섞지 않는다.

Global admin이 명시적으로 School과 SchoolYear를 선택하면 같은 teacher/classroom surface에서 planning, active와 archived context를 조회할 수 있다. Current operational manager는 자기 School의 current active year와 바로 다음 planning year를 같은 surface에서 관리하며 기존 historical 계약의 archived 자료는 read-only로 조회한다. Ordinary teacher는 자기 operational year의 기존 scope만 접근한다.

Planning context에서는 member teacher bulk, temporary credential, Classroom bulk와 담임 연결을 준비할 수 있다. Archived context에서는 mutation control을 노출하지 않고 policy와 domain boundary도 모든 mutation을 거부한다. Planning 전용 `/planning/teachers`, `/admin/teachers`, `/admin/classrooms`, 별도 dashboard와 lifecycle별 controller/view 복제는 만들지 않는다.

SchoolYear context는 URL parameter만으로 결정하지 않는다. Actor에게 허용된 School scope에서 SchoolYear ownership과 status를 server-side로 resolve하며, context가 생략되면 active year를 사용한다. 명시된 context가 잘못되거나 권한 밖이면 다른 year로 fallback하지 않는다.

Planning teacher bulk는 member만 생성한다. Current operational manager는 planning member 중 후임 manager 후보를 제안·변경·해제할 수 있지만 이는 role이나 authority를 바꾸지 않는다. Manager 지정·교체·해제는 global admin이 별도 confirmation으로 최종 확정한다. 각 새 User는 temporary credential과 강제 password 변경 상태로 시작한다.

## 데이터 무결성 invariants

- School 안의 `SchoolYear.year`는 유일하다.
- School당 active SchoolYear는 최대 하나다.
- School당 planning SchoolYear는 최대 하나다.
- 같은 SchoolYear의 `login_id`는 중복될 수 없고 다른 SchoolYear에서는 재사용할 수 있다.
- SchoolYear당 manager role의 teacher User는 최대 하나다.
- Rollover destination planning SchoolYear에는 정확히 한 명의 유효한 manager annual User가 있어야 한다.
- Classroom은 정확히 하나의 SchoolYear에 속한다.
- 같은 SchoolYear의 `grade + normalized class_label`은 유일하다.
- current HomeroomAssignment는 Classroom당 최대 하나, teacher User당 최대 하나다.
- HomeroomAssignment의 teacher User와 Classroom은 같은 SchoolYear다.
- Student는 정확히 하나의 Classroom에 속한다.
- 같은 Classroom의 active Student끼리 student_number가 중복될 수 없다.
- archived SchoolYear 하위 운영 data는 mutation할 수 없다.
- 학생 정상 login은 School, SchoolYear, Classroom과 Student가 모두 active여야 한다.
- planning teacher User는 정상 runtime login에 사용할 수 없다.
- archived teacher User의 school-operation 권한은 당시 role/scope 안의 read-only로 제한한다.
- current active-year manager는 자기 School의 archived SchoolYears를 school-wide read-only로 열람할 수 있다.
- rollover는 global admin 또는 자기 School의 current operational manager만 원자적으로 수행한다.
- rollover reversal/recovery는 global admin만 직전 same-School pair에 원자적으로 수행할 수 있으며 archived generic reactivation은 허용하지 않는다.

## UI/context 원칙

- active year 안의 일상 화면에서는 학년도를 이름마다 반복하지 않는다.
- active-year teacher login은 SchoolYear selector 없이 `login_id + password`만 받는다.
- archived login은 SchoolYear context를 명시하고 archived 화면 상위에 해당 학년도와 읽기 전용 상태를 표시한다.
- year selector, planning 구성, archived 조회와 여러 연도 비교처럼 필요한 context에서만 학년도를 표시한다.
- planning 상태와 후속 준비 entry는 School operation 화면에서 학년도와 함께 명확히 표시하며 별도 SchoolYear dashboard는 두지 않는다.
- School overview의 다음 학년도 준비 카드는 teacher, Classroom, 담임 연결 수와 manager 제안/확정 상태를 표시하며 별도 planning dashboard로 연결하지 않는다.
- archived 화면은 읽기 전용임을 한 번 분명히 표시하고 mutation control을 노출하지 않는다.
- `class_label` 저장값에는 `반`을 포함하지 않고 presentation layer가 suffix를 붙인다.
- 과거 자료의 표시 가능성과 실제 접근 권한을 혼동하지 않는다.

## Non-goals

- migration과 backfill 구현
- Student 분리와 인증 구현
- SchoolYear, HomeroomAssignment와 Student model 구현
- route, controller, view와 bulk UI 구현
- 자동 진급, 자동 복사와 날짜 기준 학년도 추론
- 학기 모델
- 학교 이동, 졸업과 상세 학생 history 정책
- 연도간 동일 teacher identity 연결
- 특정 성장·칭찬·투표 서비스 도메인
- archived data의 물리 삭제

## Open questions

현재 SchoolYear architecture 수준에서 미해결된 핵심 정책은 없다. Rollover reversal의 operational mutation 판정, 직전 pair audit evidence와 정확한 recovery readiness는 후속 bounded spec의 human review 대상이다.

Migration ordering, 정확한 column 이름, authentication controller와 route, temporary password 형식, rate-limit 수치, audit event schema와 historical UI 세부사항은 각 implementation phase의 별도 spec에서 결정한다.

## 예상 구현 단계

1. Phase 1 — SchoolYear foundation: model, status와 school/year 및 active-year DB invariant
2. Phase 2 — annual teacher User schema와 scoped authentication migration spec
3. Phase 3 — `login_id`, temporary-password login, 강제 변경, 재발급과 rate limiting
4. Phase 4 — Classroom의 `school_year_id`, `class_label`과 연도별 uniqueness
5. Phase 5 — HomeroomAssignment history 도입과 `Classroom.teacher_id` 이전
6. Phase 6 — Student 도입, student ClassroomMembership 이전과 별도 Student authentication
7. Phase 7 — SchoolYear operation foundation과 current operational authority 명시화
8. Phase 8 — planning-year teacher/classroom bulk bootstrap
9. Phase 9 — archived read-only enforcement
10. Phase 10 — global admin과 current operational manager의 rollover
11. Phase 11 — global-admin-only rollover reversal/recovery
12. Phase 12 — archived account login, historical reporting과 context UI
13. Phase 13 — legacy residue 제거
14. Phase 14 — authorization/security와 fresh-DB audit

SchoolYear foundation을 먼저 두어 이후 annual teacher User와 Classroom이 최종 FK를 한 번만 도입하게 한다. Teacher User schema와 scoped authentication을 Classroom/Homeroom 이전보다 먼저 확정해 credential과 authorization FK를 다시 옮기지 않는다. Classroom을 SchoolYear에 귀속한 뒤 HomeroomAssignment와 Student를 연결하며, rollover는 모든 하위 read-only 경계가 준비된 마지막 단계에서 활성화한다.
