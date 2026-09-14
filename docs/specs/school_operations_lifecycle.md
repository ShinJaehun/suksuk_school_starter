# School Operations Lifecycle

## 목적

학교 공통 starter에서 Teacher와 Classroom의 운영 lifecycle, 역할별 접근·관리 권한, 개별 운영 영역과 구현된 bulk management 영역의 경계를 정의한다.

이 문서의 teacher/School/Classroom 정책은 현재 runtime을 설명한다. Student cutover는 완료됐으며, 문서 안의 student User, `ClassroomMembership.status`와 student membership 설명 전체는 historical pre-cutover baseline이지 현재 runtime source가 아니다. 현재 학생 lifecycle과 소속은 `Student.active`와 `Student.classroom_id`가 canonical source다. 현재 runtime은 [`current_system.md`](../architecture/current_system.md), [`roles_and_permissions.md`](../architecture/roles_and_permissions.md)와 학생 관련 [`student_model_migration.md`](student_model_migration.md), [`student_membership_lifecycle.md`](student_membership_lifecycle.md), [`student_roster.md`](student_roster.md)가 우선한다.

## 용어와 현재 구조

- global admin은 `User.role == "admin"`인 사용자다.
- current operational manager는 active annual `User.school_role == "manager"`인 자기 School 운영자다. Eligible planning manager는 exact planning annual manager이며 자기 planning SchoolYear의 preparation actor다.
- 일반 선생님은 `User.role == "teacher"`이고 `User.school_role == "member"`인 사용자다.
- teacher의 학교는 `User.school_year.school`이다.
- teacher와 classroom의 현재 담당 관계는 current `HomeroomAssignment`로 표현한다.
- `Classroom`은 `SchoolYear`에 속하고 학교는 `classroom.school_year.school`로 결정하며 기존 학년 정책은 [Classroom Grade Foundation](classroom_grade_foundation.md)을 따른다.

## 운영 영역 구조

### 일반 운영 영역

- `/teachers`는 global admin과 학교 대표 선생님이 사용하는 일반 교사 운영 영역이다.
- `/classrooms`는 global admin, 학교 대표 선생님, 일반 선생님이 각자의 권한 범위에서 사용하는 일반 교실 운영 영역이다.
- `/teachers`와 `/classrooms`의 기존 개별 운영 UI는 유지한다.

### bulk management

- `/admin/teachers`와 `/admin/classrooms`는 구현된 bulk management 영역이다.
- global admin, current operational manager와 eligible planning manager가 허용된 School/SchoolYear context에서 접근한다. Ordinary Teacher는 접근할 수 없다.
- 상세 계약은 [Teacher bulk management](teacher_bulk_management.md)와 [Classroom bulk management](classroom_bulk_management.md)가 소유한다.

## 역할별 권한

### Global admin

global admin은 다음 권한을 가진다.

- 모든 학교 범위의 `/teachers`와 `/classrooms` 접근
- `/admin/teachers`와 `/admin/classrooms` 접근
- 학교 범위 제한 없이 teacher와 classroom 관리
- manager 계정의 활성/비활성 변경
- 기존 global admin 영역에서 manager role 승격/강등

global admin도 Pundit policy, `policy_scope`와 서버 검증을 우회하지 않는다. 교사와 교실의 학교가 다른 assignment 등 데이터 불변식을 만들 수 없다.

### 학교 대표 선생님

학교 대표 선생님의 모든 권한은 자신의 `User.school_year.school_id` 범위로 제한된다.

Current manager의 기본 context는 active이고 자기 School의 active/planning에서 Teacher와 Classroom을 관리하며 archived year를 read-only로 조회한다. Planning manager의 기본 및 유일한 허용 context는 자기 exact planning이며 Teacher/Classroom/Homeroom preparation만 관리한다. Planning manager의 active Student operation과 archive 조회는 허용하지 않는다.

`/teachers`에서 다음을 할 수 있다.

- 자기 학교 teacher 조회 및 추가
- 자기 학교에 새 teacher를 생성하고 temporary credential을 일회성으로 전달
- 자기 학교 teacher의 이름, 이메일, 성별, avatar 등 현재 starter가 지원하는 일반 profile 수정
- 자기 학교 일반 선생님(`User.school_role == "member"`)의 활성/비활성 변경
- 자기 학교 teacher의 단일 담당 교실 배정·해제
- 자기 자신의 일반 profile 수정

다음은 할 수 없다.

- 다른 학교 teacher 조회·수정 또는 다른 학교로 이동
- teacher의 global admin 권한 부여·해제
- manager role 승격·강등
- 기존 teacher의 비밀번호 직접 변경 또는 초기화
- 자기 자신을 포함한 manager 계정의 활성/비활성 변경

manager lifecycle은 manager 수나 다른 active manager 존재 여부와 관계없이 global admin만 관리한다. 일반 profile 편집 권한과 lifecycle·role 변경 권한은 서로 분리한다.

SchoolYear manager는 없거나 한 명이며 canonical source는 `User.school_role == "manager"`다. Global admin은 모든 SchoolYear에서 지정·교체·해제할 수 있고 current operational manager는 자기 School의 exact planning SchoolYear에서 수행할 수 있다. Planning manager 자신과 ordinary Teacher는 수행할 수 없다.

`/classrooms`에서 다음을 할 수 있다.

- 자기 학교의 active·inactive classroom 조회
- 자기 학교에 classroom 추가
- 반과 학년 등 구조 정보 수정
- 단일 담당 teacher 배정·해제
- classroom 활성/비활성 전환과 재활성화

다른 학교 classroom은 URL이나 parameter 조작으로도 조회·수정할 수 없다.

### 일반 선생님

- `/teachers`와 `/admin/*` school operations 영역에 접근할 수 없다.
- `/classrooms` 접근 범위는 current `HomeroomAssignment`로 자신에게 배정된 active Classroom으로 제한한다.
- 담당 active classroom이 0개이면 접근 가능한 담당 교실이 없다는 정상 안내 상태를 보여준다.
- 담당 active classroom이 1개이면 `/classrooms` 목록 대신 해당 `/classrooms/:id`로 바로 진입한다.
- 담당 active classroom에서는 학생 명부, 학생 정보, 학생 PIN 등 기존 운영 권한을 사용할 수 있다.
- 반·학년, 담당 teacher, classroom 활성 상태, 학교 구조를 변경할 수 없다.

## Teacher와 Classroom의 단일 담당 관계

- teacher는 담당 classroom이 없거나 정확히 하나다.
- classroom은 담당 teacher가 없거나 정확히 한 명이다.
- 현재 담당 관계의 canonical source of truth는 current `HomeroomAssignment`다.
- HomeroomAssignment의 Classroom/User foreign key와 current row partial unique index로 한 teacher가 여러 classroom을 동시에 담당하지 못하게 한다.
- current HomeroomAssignment partial uniqueness이므로 한 classroom에 여러 teacher를 배정하지 않는다.
- Student의 현재 소속은 `Student.classroom_id`이며 runtime membership model은 없다.

### Pre-HomeroomAssignment historical migration baseline

기존 `ClassroomMembership(role: "teacher")` 데이터는 당시 `Classroom.teacher_id`를 거쳐 HomeroomAssignment로 이전했다. 이 절의 source들은 current runtime fallback이 아니다.

한 teacher가 여러 classroom을 담당하거나 한 classroom에 여러 teacher가 연결된 충돌 데이터가 있으면 migration이 임의의 관계를 선택하지 않는다. 구현 전에 실제 데이터를 점검하고 충돌을 명시적으로 정리한 뒤 이전한다. starter의 seed와 spec fixture도 새 invariant에 맞춘다. silent data loss는 허용하지 않는다.

## Teacher lifecycle

Teacher lifecycle은 기존 `User.active`를 사용한다.

### Active teacher

- 정상 로그인과 운영이 가능하다.
- 조건을 충족하는 active classroom 하나에 배정될 수 있다.

### Inactive teacher

- 로그인할 수 없다.
- 새 담당 classroom에 배정될 수 없다.
- 일반 운영 권한을 갖지 않는다.
- 과거 서비스 기록을 삭제하지 않는다.
- 비활성화 transaction에서 현재 담당 classroom의 `teacher_id`를 `nil`로 변경한다.

비활성화는 삭제가 아니다. 재활성화하면 membership과 과거 기록은 유지하지만 과거 담당 classroom은 자동 복원하지 않는다. 필요하면 활성 조건과 권한 검증 아래 다시 명시적으로 배정한다.

학교 대표 선생님은 자기 학교의 member teacher만 비활성화·재활성화할 수 있다. manager 계정 lifecycle과 manager role 변경은 global admin만 수행한다.

## Student lifecycle

이 절의 `ClassroomMembership`과 student User 설명은 Student cutover 이전 historical
baseline이다. 현재 동작으로 해석하지 않으며 현재 학생 동작은 위에 지정한 current/student
문서의 `Student.active`와 `Student.classroom_id` 계약을 따른다.

학교 운영의 세 lifecycle source는 서로 구분한다.

- teacher의 재직·운영 상태: `User.active`
- student의 현재 학급 재학·운영 상태: `ClassroomMembership.status`
- classroom의 운영 상태: `Classroom.active`

student의 전출과 현재 운영 제외는 `User.active`가 아니라 `ClassroomMembership.status = "inactive"`로 표현한다. deactivate는 membership row, `classroom_id`, 학생 계정과 과거 서비스 기록을 삭제하지 않으며 그 시점의 `student_number`를 자동 변경하지 않는다. inactive membership은 현재 roster, active 학생 수, PIN/token 로그인과 기존 student session의 운영 대상에서 제외한다.

student membership을 reactivate하면 같은 membership row의 기존 classroom과 현재 저장된 `student_number`를 사용한다. 새 membership이나 번호를 자동 생성하거나 다른 classroom을 임의 배정하지 않으며, active classroom, active 학생 최대 30명과 학생당 active membership 최대 1개 불변식을 만족해야 한다. 현재 번호가 같은 classroom의 다른 active 학생 번호와 충돌하면 자동 조정하지 않고 재활성화를 거부하며, 관리자가 번호를 명시적으로 수정한 뒤 다시 시도한다.

`student_number`는 교사가 개별 생성·수정과 일괄 관리 과정에서 직접 관리하는 운영 정보다. inactive 학생의 번호도 필요하면 수정할 수 있다. 시스템은 최대 번호 + 1이나 빈 번호 재사용 금지를 강제하지 않으며, bulk 생성의 제안 번호는 편의를 위한 기본값일 뿐 canonical invariant가 아니다. 번호는 historical immutable identifier가 아니지만, 같은 classroom의 active student membership끼리는 중복될 수 없다.

현재 starter 운영에서 student는 최대 하나의 active `ClassroomMembership`을 가진다. inactive membership은 삭제하지 않고 보존한다. 여러 inactive membership과 학급·학년도 이력을 어떻게 해석할지는 학년도, 진급, 반 편성 및 학교 이동 history 설계에서 별도로 결정하며 이번 범위에서는 DB 구조를 추가로 제한하지 않는다.

`/classrooms/:id/members` 같은 구성원 관리 화면에서는 active와 inactive 학생을 모두 조회하고 비활성화·재활성화할 수 있다. inactive 학생도 이름, `student_number`, 기존 classroom과 상태를 확인할 수 있어야 하며, 기존의 중립 배경, 낮은 opacity와 inactive badge 패턴을 재사용해 구분한다. 텍스트 식별과 접근성을 해칠 정도로 흐리게 표시하지 않는다.

현재 학생 목록, 집계, 선택과 로그인 등 일반 교실 운영 화면에서는 active membership만 사용하고 inactive 학생을 표시하지 않는다. 구성원 관리 화면의 inactive 조회 정책을 일반 운영 화면이나 `/schools` 단위 학생 inventory로 확대하지 않는다.

## Classroom lifecycle

`Classroom`에 다음 공통 lifecycle 속성을 도입한다.

```text
active:boolean, default: true, null: false
```

이번 spec 단계에서는 migration을 만들지 않는다.

### Active classroom

- 정상 운영할 수 있다.
- 신규 student membership과 단일 active teacher를 배정할 수 있다.
- 일반 선생님의 담당 교실 목록과 직접 진입 대상이 될 수 있다.

### Inactive classroom

- 삭제하지 않고 기존 student membership과 학생·서비스 기록을 보존한다.
- 신규 student와 teacher를 배정할 수 없다.
- 비활성화는 교실 전체 운영을 잠그며 current HomeroomAssignment, student membership과 `student_number`를 그대로 보존한다.
- 학생 관리 등 일반 운영 mutation을 허용하지 않는다.
- student token/PIN 로그인을 허용하지 않으며 기존 학생 session도 다음 request에서 종료한다.
- 일반 선생님의 목록, 자동 진입과 정상 운영 대상에서 제외한다.
- 학교 대표 선생님은 자기 학교 범위에서, global admin은 관리 권한 범위에서 조회하고 재활성화할 수 있다.

inactive School에 대한 기존 lifecycle과 접근 차단이 상위 경계다. classroom의 active 상태가 inactive School의 운영을 다시 허용하거나 기존 School policy를 우회하지 않는다.

classroom을 재활성화하면 보존된 current HomeroomAssignment와 student membership을 별도 복원 작업 없이 다시 사용한다. 기존 teacher가 그 시점에도 active이고 school·grade 불변식을 만족해야 한다. classroom이 inactive인 동안 teacher 자체가 비활성화되면 Teacher lifecycle 정책에 따라 `teacher_id`를 해제하며, 이 경우 classroom을 재활성화해도 teacher를 자동 복원하지 않는다.

inactive classroom에 보존된 teacher assignment는 classroom을 재활성화하기 전까지 해당 teacher의 grade 변경, classroom 이동과 assignment 해제를 허용하지 않는다. 이름·이메일·성별·avatar 등 일반 profile 변경은 허용하며, teacher 자체의 lifecycle 변경은 별도 정책을 따른다.

## 교사·교실 배정 불변식

teacher를 classroom에 배정할 때 다음을 모두 만족해야 한다.

- 대상 사용자는 active teacher다.
- 대상 classroom은 active다.
- teacher와 Classroom의 `school_year_id`가 같다.
- teacher의 SchoolYear와 School이 active다.
- teacher의 `User.grade`와 `Classroom.grade`가 같고 grade가 `nil`이 아니다.
- teacher에게 다른 담당 classroom이 없다.
- classroom에 다른 담당 teacher가 없다.
- 학교 대표 선생님의 변경 대상은 자기 학교에 한정된다.

global admin도 이 불변식을 우회할 수 없다. 다른 school, 다른 grade, inactive teacher, inactive classroom 또는 이미 배정된 teacher/classroom ID를 직접 제출해도 거부한다.

teacher의 담당 classroom을 바꾸면 기존 assignment 종료와 새 assignment 생성을 하나의 transaction에서 처리한다. 미배정으로 변경하면 기존 `teacher_id`만 해제한다. 이 변경은 현재 운영 관계만 갱신하며 과거 서비스 기록이나 작성자 정보를 삭제하지 않는다.

teacher의 grade가 `nil`이면 classroom을 배정할 수 없다. 담당 classroom이 있는 teacher의 grade를 다른 값으로 변경할 때 기존 classroom을 유지할 수 없으며, 새 grade의 classroom을 선택하거나 미배정으로 저장해야 한다. grade 변경은 기존 classroom assignment를 자동으로 다른 classroom에 옮기지 않는다.

담당 teacher가 있는 classroom의 grade 변경으로 `User.grade`와 불일치가 생기면 저장을 거부한다. 기본 운영 경로에서는 teacher grade를 자동 연쇄 변경하지 않으며 먼저 담당 teacher를 해제해야 한다.

신규 student assignment도 active classroom에만 허용한다. inactive School에 대한 기존 배정 제한을 함께 적용한다.

## 삭제 정책

- 활성/비활성이 teacher와 classroom의 기본 lifecycle이다.
- 학교 대표 선생님은 teacher나 classroom을 삭제하지 않고 비활성화한다.
- 이 spec은 teacher 물리 삭제 권한을 확대하지 않는다. global admin의 실제 teacher 삭제 허용 여부와 조건은 별도 정책으로 남긴다.
- global admin의 classroom 삭제는 잘못 생성된 빈 교실 등 제한적인 정리 용도를 지향한다.
- student membership 또는 서비스 기록이 있는 classroom은 삭제하지 않고 비활성 상태로 보존한다.
- 현재 `Classroom`의 delete protection을 약화하지 않는다.
- 이 삭제 방향을 위해 이번 spec 단계에서 새 삭제 기능을 만들지 않는다.

## `/teachers` 일반 운영 영역

권한 범위는 다음과 같다.

- global admin: 모든 학교
- 학교 대표 선생님: 자기 학교
- 일반 선생님: 접근 불가

기본 기능은 Teacher 목록, 추가, 일반 profile 편집과 단일 담당 Classroom 배정·해제다. Current manager는 자기 School의 지원되는 active/planning Teacher operation을 수행하고 planning manager는 자기 exact planning Teacher preparation만 수행한다. Self protection, manager target protection과 manager designation 전용 flow는 유지한다. Global admin에게는 School 범위 선택을 제공하고 manager는 자기 School로 제한한다. 모든 record 조회와 변경은 서버에서 역할별 School scope를 다시 검증한다.

Teacher 생성과 재발급은 서버가 생성하는 temporary credential, 강제 비밀번호 변경, audit와 일회성 표시 계약을 따른다. Manager가 초기 password를 직접 입력하거나 일반 profile update로 password 또는 `school_role`을 바꾸지 않는다. 상세 보안 계약은 [Planning Year Bootstrap](planning_year_bootstrap.md)과 [Teacher Bulk Management](teacher_bulk_management.md)를 따른다.

## `/classrooms` 일반 운영 영역

권한 범위는 다음과 같다.

- global admin: 모든 학교의 관리 가능한 classroom
- 학교 대표 선생님: 자기 학교의 active·inactive classroom
- 일반 선생님: 자신이 담당하는 active classroom

global admin과 학교 대표 선생님은 권한 범위에서 classroom 추가, 이름·학년 수정, 단일 담당 teacher 배정·해제, 활성/비활성 전환을 할 수 있다. 일반 선생님은 구조를 변경하지 않고 담당 active classroom의 학생·운영 기능만 사용한다.

학년 값, 표시, 목록 필터와 정렬은 [Classroom Grade Foundation](classroom_grade_foundation.md)을 유지한다. lifecycle 필터는 grade와 school filter를 적용하기 전 역할별 `policy_scope`에서 허용된 범위를 넘어서는 결과를 만들 수 없다.

## `/admin` bulk management 경계

`/admin/teachers`와 `/admin/classrooms`는 global admin 전용 namespace가 아니다. Global admin은 명시한 School/SchoolYear, current manager는 자기 School의 active/exact planning과 read-only archive context에서 사용한다. Planning manager는 자기 exact planning preparation context에서만 사용한다. Ordinary Teacher와 다른 School actor는 거부한다. Atomic transaction, scope 재검증과 HomeroomAssignment 규칙은 [Teacher bulk management](teacher_bulk_management.md)와 [Classroom bulk management](classroom_bulk_management.md)가 정의한다.

## Teacher의 school-context 학년 정책

### Teacher 학년

teacher의 school-context 학년은 `User.grade`다. 현재 annual account의 운영 정보이며 classroom assignment 없이도 독립적으로 저장할 수 있다. `User.grade`는 nullable integer로 `nil` 또는 정수 1부터 6까지만 허용한다.

teacher form의 classroom 후보는 teacher의 annual school, `User.grade`와 같은 grade, active 상태이며 담당 teacher가 없는 classroom으로 제한한다. edit에서는 현재 teacher가 담당하는 classroom을 현재 선택값으로 포함할 수 있다. active teacher, active SchoolYear와 School, same-school 불변식도 함께 적용한다.

teacher 생성 시 school은 기존 정책대로 필요하고 학년은 `nil` 또는 1부터 6 중 하나이며 classroom assignment는 없거나 하나다. 따라서 classroom이 아직 없어도 school과 학년만으로 teacher를 생성할 수 있다.

teacher의 grade와 담당 classroom grade는 연결 상태에서 항상 일치해야 한다. grade를 변경해 불일치가 생기면 기존 담당 관계를 유지할 수 없으며 새 grade의 classroom 하나를 선택하거나 미배정으로 저장한다. 현재 담당 관계를 해제해도 과거 서비스 기록은 삭제하지 않는다.

global admin은 관리 가능한 teacher의 `User.grade`를 설정·수정할 수 있다. 학교 대표 선생님은 자기 school의 ordinary member teacher에 대해 설정·수정할 수 있고, 자신의 일반 profile·운영 정보는 기존 canonical 권한 범위 안에서 수정할 수 있다. ordinary teacher는 `/teachers`에서 학년을 관리할 수 없으며 다른 school의 teacher grade는 URL 또는 parameter 조작으로도 변경할 수 없다. 이 권한은 lifecycle이나 manager role 변경 권한을 확대하지 않는다.

teacher 운영 목록에서 기본 학년 표시는 `User.grade`를 사용하고 값이 없으면 미배정 또는 기존 locale의 동일 의미를 표시한다. 학급은 current HomeroomAssignment로 연결된 단일 classroom을 표시하고 없으면 미배정으로 표시한다.

Teacher의 학교 소속과 권한은 annual User에만 저장하며 별도 membership fallback을 두지 않는다. 별도 Grade model이나 table은 만들지 않는다.

## 운영 후보 선택 UI의 확장성

### 공통 후보 선택 원칙

학교 운영 UI에서 teacher 또는 classroom 후보를 선택할 때 전체 후보를 무제한으로 한 번에 렌더링하지 않는다. 먼저 사용자가 관리할 수 있는 school scope를 확정한 뒤 그 school 안에서만 후보를 조회하고, 현재 모델에 존재하거나 기존 관계에서 파생할 수 있는 기준으로 후보를 좁힌다.

- server-side policy scope와 validation을 최종 권한 경계로 사용하며 검색과 필터는 그 범위를 넓힐 수 없다.
- 모든 school의 후보 데이터를 HTML이나 JavaScript에 미리 내려받고 화면에서 숨기는 방식은 사용하지 않는다.
- 필요하면 GET query parameter, Turbo Frame 부분 갱신 또는 server-side pagination으로 필요한 범위만 조회한다.
- 구체적인 전송 방식은 구현 시점의 starter 구조와 데이터 규모에 맞는 가장 단순한 방식을 선택하며 autocomplete나 외부 검색 library 도입을 요구하지 않는다.
- 후보 조회에서 N+1 query를 만들지 않는다.
- 별도 Grade 모델을 추가하지 않는다. teacher 학년에는 canonical `User.grade`를 사용한다.

### Teacher 학년 filter의 의미

teacher의 기본 학년 filter는 `User.grade`를 사용한다.

- `1학년`부터 `6학년`: `User.grade`가 해당 값인 teacher
- `미배정`: `User.grade`가 `nil`인 teacher
- `전체`: 현재 허용된 school scope의 모든 대상 teacher

teacher 학년 filter는 `User.grade`만 기준으로 한다. 현재 담당 학급은 current HomeroomAssignment로 연결된 단일 classroom이며 학년 filter의 source가 아니다.

### `/teachers/new`, `/teachers/:id/edit` classroom picker

teacher form은 school, 학년, 담당 classroom의 단일 단계형 흐름을 사용한다. 학년 select는 하나만 제공하며 그 값은 `User.grade`에 저장되는 동시에 classroom candidate를 좁히는 기준으로 사용한다.

global admin은 다음 순서로 선택한다.

1. school 선택
2. 학년 선택 또는 미배정
3. 선택한 school과 학년에 속한 active classroom 조회·표시
4. classroom 미배정 또는 하나 선택

학교 대표 선생님에게는 고정된 school 이름, 학년, 담당 classroom 순서로 제공하고 다른 school 선택 UI는 제공하지 않는다.

학년 옵션은 미배정과 1학년부터 6학년으로 한정하며 `전체 학년`을 제공하지 않는다. school이 없거나 학년이 정확한 1부터 6의 값이 아니면 classroom 후보를 empty scope로 처리하며 candidate query와 rendering을 하지 않는다. edit에서는 teacher의 annual school과 persisted `User.grade`를 기본값으로 사용한다.

valid school과 학년이 선택되면 해당 school, 해당 grade와 active 상태를 모두 만족하고 다른 teacher에게 배정되지 않은 classroom만 후보로 조회·표시한다. edit에서는 현재 teacher 자신의 classroom을 현재 선택값으로 포함할 수 있다. 다른 school, 다른 grade, inactive 또는 이미 다른 teacher에게 배정된 classroom ID를 직접 제출해도 서버에서 거부한다.

`학교 및 담당 학급` 영역의 시각적 순서는 school, 학년, 담당 classroom으로 유지한다. 하위 후보를 아직 표시할 수 없는 상태에는 기존 locale과 UI style에 맞는 간단한 선택 안내를 표시할 수 있다.

학급 선택은 복수 checkbox나 누적 ID Set이 아닌 단일 select 또는 동등하게 단순한 single-choice UI를 사용한다. 별도의 `현재 담당 학급` summary 영역을 만들지 않고 현재 classroom을 선택값으로 표현한다. school이나 grade가 바뀌면 기존 선택을 초기화하고 새 범위의 후보를 조회한다. 사용자는 새 classroom 하나를 선택하거나 미배정으로 저장할 수 있다.

### `/schools/:id/edit` 대표 선생님 picker

대표 선생님 후보는 global admin이 선택한 현재 school에 소속된 active teacher로 제한한다. 모든 teacher를 긴 `<select>`에 무제한으로 렌더링하는 형태로 고정하지 않고, 다음 기준을 server-side scope 안에서 조합해 좁힐 수 있게 한다.

- 검색: 이름 또는 이메일
- 학년: 전체, 1학년부터 6학년, 미배정

학년 filter는 `User.grade`를 기준으로 하고 미배정은 그 값이 `nil`인 상태를 의미한다. 후보에는 동명이인을 구별할 수 있도록 이름, 이메일과 현재 단일 담당 classroom 정보를 함께 표시한다. 실제 담당 classroom이 없어도 teacher 학년이 있으면 해당 학년 filter에 포함한다. manager 후보는 정확히 한 명을 선택하며 여러 후보를 누적 선택하지 않는다.

이 picker는 manager role의 승격·강등 권한을 변경하지 않는다. 대표 선생님 선택과 role 변경은 기존 정책대로 global admin만 수행한다.

## 권한 검증 원칙

- navigation과 UI 숨김은 편의 수단이며 권한의 최종 방어선이 아니다.
- Pundit policy와 `policy_scope`로 읽기·행위 범위를 제한한다.
- controller와 domain validation에서 school 및 lifecycle 불변식을 다시 검증한다.
- `school_id`, `teacher_id`, `classroom_id` 등 URL·parameter 조작으로 허용 범위를 넘을 수 없어야 한다.
- inactive teacher, inactive classroom과 inactive School 상태를 mutation 시점에 서버에서 확인한다.
- profile 편집, lifecycle 변경, role 변경은 각각 독립된 권한으로 검사한다.

## 현재 구현 상태

- teacher assignment의 controller, service, policy, scope와 UI는 current HomeroomAssignment를 사용하며 신규 teacher `ClassroomMembership` 생성을 거부한다.
- HomeroomAssignment는 Classroom/User foreign key와 current row partial unique index로 1:1 cardinality를 방어한다.
- teacher 비활성화는 현재 assignment를 해제하고, classroom 비활성화는 assignment를 보존한 채 운영만 잠근다.
- classroom grade, teacher school·grade와 lifecycle validation이 assignment 불변식을 방어한다.
- school당 manager 최대 한 명을 model validation과 DB partial unique index로 방어한다.
- 일반 teacher의 담당 active classroom 진입과 manager/admin lifecycle 관리 UI가 역할별 policy를 따른다.
- Classroom delete protection은 Student와 HomeroomAssignment history 및 서비스 기록을 보존한다.

### Pre-Student-cutover Teacher/Student lifecycle 구현 감사 (2026-09-05)

이 감사의 student 항목은 당시 구현 기록이며 현재 Student runtime 설명이 아니다.

#### A. Already consistent

- `User.active`는 teacher의 Devise 로그인과 운영 권한을 차단하며, teacher deactivate callback은 current HomeroomAssignment를 종료한다. 과거 기록은 유지되고 reactivate 시 assignment를 자동 복원하지 않는다.
- teacher assignment 저장은 inactive teacher를 신규 assignment 대상으로 거부한다.
- student deactivate와 기존 destroy 호환 action은 membership row를 삭제하지 않고 `ClassroomMembership.status`만 inactive로 바꾼다. `classroom_id`와 `student_number`는 그대로 유지한다.
- student reactivate는 같은 membership row를 active로 바꾸며 기존 classroom과 번호를 유지한다. 다른 active membership, inactive classroom과 active 학생 최대 30명 조건을 검사한다.
- `student_number`는 개별·일괄 관리에서 직접 입력·수정할 수 있고, model과 DB는 같은 classroom의 active student membership 사이 중복을 거부한다. 재활성화 시 기존 번호가 active 번호와 충돌해도 자동 변경하지 않고 저장을 거부한다.
- classroom roster와 active 학생 수는 active student membership만 사용한다. PIN 로그인은 active membership만 허용하고, 로그인 뒤 membership 또는 classroom이 inactive가 되면 다음 일반 request에서 student session을 종료한다.
- `/classrooms/:id/members` 구성원 관리 화면은 inactive 학생을 조회·관리할 수 있고 기존 muted UI와 inactive badge로 상태를 구분한다. 일반 교실 운영 화면은 inactive 학생을 제외한다.
- student의 `User.active`는 현재 PIN 로그인, roster 포함 여부와 student session 유효성의 기준으로 사용되지 않는다. 학생 enrollment lifecycle은 실질적으로 `ClassroomMembership.status`가 담당한다.
- model과 DB가 학생당 active membership을 최대 하나로 제한하고 여러 inactive membership을 허용하는 현재 구조는 이번 canonical 범위와 일치한다.

#### B. Implementation gap

- 없음. 현재 감사 범위에서 Teacher/Student lifecycle 구현은 canonical과 일치한다.

#### C. Ambiguous / needs user decision

- 없음. 이 current-runtime lifecycle 범위에서 제외한 학년도 rollover와 historical classroom target은 `school_year_architecture.md`에서 별도로 확정하며, 진급·반 편성·전입 이력의 상세 운영은 후속 정책 범위다.

#### D. Out of current scope

- `/schools` 학생 목록과 학교 전체 student inventory, 일반 교실 화면의 inactive 학생 표시, 학년도·진급·졸업·학교 간 전입 이력, 별도 history/archive 모델과 physical delete 재설계는 후속 정책 범위다.

## Acceptance criteria

1. global admin은 policy와 scope 안에서 모든 학교의 `/teachers`와 `/classrooms`를 관리할 수 있다.
2. 학교 대표 선생님은 `/teachers`에서 자기 학교 teacher만 조회·추가·수정할 수 있다.
3. 학교 대표 선생님은 `/classrooms`에서 자기 학교 classroom만 조회·추가·수정할 수 있다.
4. 학교 대표 선생님은 URL 또는 parameter 조작으로 다른 학교 teacher나 classroom을 조회·수정할 수 없다.
5. 일반 선생님은 `/teachers`와 `/admin/*` school operations endpoint에 접근할 수 없다.
6. teacher는 annual SchoolYear에 속하면서 `User.grade`와 담당 classroom이 모두 `nil`일 수 있다.
7. `User.grade`는 `nil` 또는 정수 1부터 6만 허용하고 별도 Grade model을 만들지 않는다.
8. teacher의 담당 classroom은 없거나 정확히 하나이고 classroom의 담당 teacher도 없거나 정확히 한 명이다.
9. 한 teacher가 두 classroom을 동시에 담당하거나 한 classroom을 두 teacher가 동시에 담당할 수 없다.
10. teacher assignment의 canonical source는 current `HomeroomAssignment`이며 신규 teacher `ClassroomMembership`을 생성하지 않는다.
11. teacher와 classroom을 연결하면 양쪽 SchoolYear와 grade가 각각 같아야 한다.
12. inactive teacher나 inactive classroom은 신규 assignment 대상이 될 수 없다.
13. 다른 teacher가 담당 중인 classroom을 직접 제출해도 배정할 수 없다.
14. teacher grade가 `nil`이면 classroom도 미배정이어야 한다.
15. teacher form은 school, 학년, 학급의 single-choice 흐름이며 복수 checkbox와 별도 현재 담당 학급 summary를 사용하지 않는다.
16. global admin은 valid school과 학년을 선택한 뒤에만 후보를 조회하고 manager는 자기 school의 valid 학년 범위에서만 후보를 조회한다.
17. classroom 후보는 선택 school, 선택 grade, active 상태를 만족하고 다른 teacher에게 배정되지 않은 classroom 및 edit 대상 teacher의 현재 classroom으로 제한한다.
18. teacher form의 학년 옵션은 미배정과 1학년부터 6학년만 제공하고 전체 학년은 제공하지 않는다.
19. school이나 grade가 없거나 유효하지 않으면 classroom 후보를 조회·표시하지 않는다.
20. teacher form에서 classroom을 선택하지 않고 school과 grade만 저장할 수 있으며 edit 재진입 시 persisted grade가 선택되어 있다.
21. teacher grade 변경으로 현재 classroom과 grade 불일치가 생기면 그 관계를 유지할 수 없고 새 grade classroom 또는 미배정을 명시적으로 선택해야 한다.
22. 담당 classroom 변경은 기존 assignment 종료와 새 assignment 생성을 하나의 transaction에서 처리한다.
23. 담당 teacher가 있는 classroom의 grade를 불일치 상태로 변경할 수 없으며 기본 운영에서는 먼저 assignment를 해제한다.
24. teacher를 deactivate하면 현재 classroom assignment를 해제하고 reactivation 시 자동 복원하지 않는다.
25. classroom을 deactivate하면 현재 teacher assignment와 student membership을 보존한 채 운영을 잠그고, reactivation 시 별도 복원 없이 보존된 관계를 다시 사용한다.
26. assignment 해제와 lifecycle 전환은 서비스 기록, 작성자 정보와 학생 membership을 삭제하지 않는다.
27. inactive classroom은 일반 선생님의 목록, 자동 진입과 mutation 대상에서 제외되며 manager와 global admin은 권한 범위에서 조회·재활성화할 수 있다.
28. 일반 선생님의 담당 active classroom이 하나이면 해당 classroom으로 바로 진입하고 없으면 정상 안내 상태를 표시한다.
29. Teacher 생성·재발급은 temporary credential과 audit 계약을 따르며 manager가 password를 직접 입력하지 않는다.
30. 학교 대표 선생님은 허용된 일반 profile과 ordinary member teacher lifecycle만 관리하며 manager lifecycle·role이나 global admin 권한을 변경할 수 없다.
31. manager는 active SchoolYear마다 0명 또는 1명이고 두 명 이상의 annual manager를 동시에 저장할 수 없다.
32. manager 지정·교체·해제는 global admin 또는 current operational manager가 자기 School exact planning context에서 수행하며 planning manager 자신과 ordinary Teacher는 거부한다.
33. manager의 canonical source는 `User.school_role`이며 `School.manager_id`를 추가하지 않는다.
34. school manager 후보는 현재 school의 active teacher만 대상으로 하며 이름, 이메일과 현재 단일 담당 classroom 정보로 구별할 수 있다.
35. school manager 후보의 grade filter는 `User.grade`를 사용하고 미배정은 grade가 `nil`인 상태다.
36. `/teachers` 목록은 annual school, `User.grade`, 단일 classroom과 상태를 표시하고 없는 학년 또는 학급은 미배정으로 표시한다.
37. `/classrooms` 목록은 school, 학년, 반, 단일 담당 teacher와 상태를 표시하고 teacher가 없으면 미배정으로 표시한다.
38. Pre-HomeroomAssignment migration 기록은 current assignment source로 해석하지 않는다.
39. Current runtime은 `Classroom.teacher_id`나 membership fallback 없이 current `HomeroomAssignment`만 사용한다.
40. teacher와 classroom 후보 UI는 전체 scope 데이터를 무제한으로 사전 loading하거나 숨겨서 rendering하지 않는다.
41. 후보 검색, filtering과 직접 parameter 조작은 policy scope 또는 authorization 범위를 넓히지 않는다.
42. `/admin/teachers`와 `/admin/classrooms`는 global admin과 자기 School의 current manager가 허용 context에서 접근하며 planning manager는 자기 exact planning preparation context에서만 접근한다. Ordinary Teacher는 거부한다.
43. `Classroom.grade`의 필수 1부터 6 데이터·표시·filter·정렬 정책은 `classroom_grade_foundation.md`를 유지한다.

## 제약

- 현재 runtime은 Classroom의 SchoolYear와 `class_label` cutover를 반영하며 후속 lifecycle 구조는 별도 spec에서 구현한다.
- lifecycle 구현은 학생 membership과 과거 서비스 기록을 파괴하지 않아야 한다. classroom lifecycle은 현재 teacher assignment를 보존하며, teacher lifecycle에서 teacher를 비활성화할 때만 현재 assignment를 해제한다.
- 기존 Pundit 경계를 우회하는 별도 조회나 update 경로를 만들지 않는다.
- bulk management 상세 권한과 transaction은 각 bulk canonical spec을 따른다.

## Non-goals

- 쑥쑥교실투표 코드 직접 복사
- teacher 또는 classroom 물리 삭제 기능 확대
- teacher의 복수 classroom 담당 또는 classroom의 복수 teacher 담당
- StudentEnrollment 도입
- 교사 비밀번호 관리 또는 초기화 정책
- global admin 역할 편집
- manager 승격·강등 UI 변경
- 학생 도메인 재설계
- 성장기록 기능
- 서비스별 비즈니스 기능 추가
- teacher/classroom picker의 controller, view, policy, route, Stimulus 또는 Turbo Frame 구현
- 후보 pagination 또는 autocomplete 구현과 외부 검색 library 도입
