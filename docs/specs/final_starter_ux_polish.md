# Final Starter UX Polish

## 목적

School Starter v1 마감 전에 인증 복귀, Teacher 식별정보, avatar, temporary credential, planning 진입과 SchoolYear context 표현에서 생기는 사용자 혼란을 줄인다. 현재 SchoolYear domain, authority, 개별/bulk management surface와 mutation semantics는 유지한다.

이 문서는 해당 UX polish의 primary canonical contract다. 새로운 domain, route hierarchy 또는 범용 framework를 설계하지 않는다.

## 현재 surface와 불변식

- `/teachers`, `/classrooms`: 기존 개별 관리 surface
- `/admin/teachers`, `/admin/classrooms`: 기존 bulk management surface
- `/schools/:id`: 현재 운영 현황과 이미 존재하는 planning 현황
- `/schools/:id/edit`: School settings와 planning 시작 control
- `/schools/:id/planning`: 이미 생성된 planning SchoolYear의 orchestration surface

Authority와 context resolution은 기존 policy, `Teachers::ManagementContext`, `Classrooms::ManagementContext` 및 SchoolYear operation을 재사용한다.

## 1. Teacher logout 복귀

로그인한 Teacher가 명시적으로 Devise logout을 실행하면 logout 직전 annual School을 기억하여 기존 `/schools/:school_id/teacher_login`으로 이동한다. Current operational Teacher와 eligible planning manager에 동일하게 적용한다.

- 새 Teacher login route를 만들지 않는다.
- Global admin logout은 기존 `/users/sign_in` 흐름을 유지한다.
- 명시적 logout과 session eligibility 상실에 따른 강제 종료를 구분한다.
- Inactive, School/SchoolYear 상태 변화 등으로 Teacher session이 자격을 상실했을 때의 기존 fail-closed 종료와 redirect 계약은 변경하지 않는다.
- Redirect target은 client parameter가 아니라 logout 직전 authenticated annual Teacher의 School에서 결정한다.

현재 `Users::SessionsController#destroy`는 Teacher School을 보존하지 않고 Devise 기본 redirect를 사용하므로, 구현에서는 sign-out 전에 actor와 annual School을 안전하게 capture해야 한다.

## 2. Teacher login ID 표시

### `/teachers`

- Teacher 이름 가까이에 `login_id`를 명확하게 표시한다.
- Teacher에게 의미 없는 email을 primary 식별정보처럼 표시하지 않는다.
- School, manager/member role, grade, current Classroom과 lifecycle 표시는 유지한다.
- Archived read-only context에서도 `login_id`를 볼 수 있다.
- 별도 Teacher show route/page를 만들지 않는다.

### `/teachers/:id/edit`

- Persisted Teacher의 `login_id`를 Growth Record의 기존 form UX처럼 읽기 전용 `dl/dt/dd` 또는 동등하게 명확한 형태로 표시한다.
- `login_id`를 form input이나 permitted mutation으로 바꾸지 않는다.
- 신규 Teacher create form의 기존 `login_id` 입력은 유지한다.
- 현재 관리 detail surface는 edit page이며 별도 `/teachers/:id` show page를 만들지 않는다.

이 read-only 계약은 individual edit/update에 한정되며 [Teacher bulk row update](teacher_bulk_management.md#bulk-row-update)의 허용된 login ID 수정은 유지한다. 최종 audit에서 발견한 individual update permitted params 누락의 서버측 보강 기준은 [Final Starter Audit Hardening §4](final_starter_audit_hardening.md#4-individual-teacher-login_id-immutability)에 기록한다.

## 3. Classroom Student avatar

`app/views/classroom_students/_student_card.html.erb`의 avatar class만 Growth Record와 일치시킨다.

```text
h-10 w-10 shrink-0 rounded-lg border border-slate-200 bg-slate-100 object-cover
```

Student card의 전체 구조, link, 번호 표시, spacing과 card layout은 변경하지 않는다.

## 4. Temporary Teacher password

Starter에 좁은 generator `Teachers::TemporaryPassword`를 둔다.

```ruby
LENGTH = 8
CHARACTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
```

- 각 문자는 `SecureRandom` 기반으로 허용 alphabet에서 선택한다.
- `I`, `O`, `0`, `1` 등 혼동하기 쉬운 문자는 생성하지 않는다.
- 생성 결과가 `login_id`와 case-insensitive하게 완전히 같으면 다시 생성한다.
- `AnnualTeacherUsers::TemporaryCredential`은 initial issue와 reissue 모두 이 generator를 사용한다.
- 기존 password digest 저장, `password_change_required`, transaction과 `TeacherCredentialEvent` audit를 유지한다.
- Plaintext는 DB, log, flash 또는 session에 저장하지 않는다.
- 성공적으로 commit된 credential만 no-store 응답에서 한 번 표시한다.
- Password complexity 또는 generic credential framework로 확장하지 않는다.

이는 credential contract 변경이므로 generator와 initial issue/reissue integration의 focused service spec을 갱신한다.

## 5. Teacher bulk avatar

`/admin/teachers` bulk table에는 별도 avatar column을 추가하지 않는다.

- 이름 cell 안에서 기존 `user_avatar_image` helper로 약 `h-8 w-8` 크기의 Teacher avatar를 표시한다.
- Avatar와 name input은 compact flex row로 구성한다.
- Inactive row와 disabled input의 기존 muted styling을 유지한다.
- Table 폭을 불필요하게 늘리지 않는다.
- New/bulk create에 avatar 선택 또는 편집 기능을 추가하지 않는다.
- 그 밖의 Teacher bulk layout과 behavior는 변경하지 않는다.

### Teacher single-create return context

Teacher 단건 생성과 temporary credential 결과 화면은 create를 시작한 management surface와 resolved context를 보존한다.

- `/teachers`에서 시작하면 동일한 `school_id`, `school_year_id`를 가진 `/teachers`로 돌아간다.
- `/admin/teachers`에서 시작하면 동일한 `school_id`, `school_year_id`를 가진 `/admin/teachers`로 돌아간다.
- Admin bulk surface에서 시작한 경우 필요하면 현재 grade context도 보존할 수 있다.
- Client가 제출한 arbitrary return URL로 redirect하지 않는다. 제한된 trusted source/sentinel 또는 동등한 server-controlled context만 허용한다.
- Existing credential one-time/no-store 계약은 변경하지 않는다.
- Bulk-create credential 결과의 기존 `/admin/teachers` 복귀 계약은 유지한다.

## 6. Planning 시작 위치

Planning SchoolYear 생성은 navigation이 아니라 privileged operational mutation이다.

- Planning year가 없을 때 `/schools/:id`에는 planning section과 “다음 학년도 준비 시작” control을 표시하지 않는다.
- Start control은 `/schools/:id/edit`의 별도 “다음 학년도 준비” settings section에만 둔다.
- Section은 current active year와 server가 생성할 exact next year를 명확히 보여준다.
- Start button은 planning SchoolYear가 생성되는 privileged mutation임을 분명히 하는 confirmation을 요구한다.
- 기존 `school_years#create` route, service/model lifecycle과 authorization을 재사용한다.
- 새 route, service, model 또는 status를 만들지 않는다.

### School settings 진입과 mutation 권한

현재 `SchoolsController#edit`는 `SchoolPolicy#update?`로 보호되어 global admin만 진입하지만 planning create authority는 current operational manager에게도 존재한다. 구현은 settings page 진입 권한과 School 자체 update 권한을 분리한다.

- Global admin은 기존 School settings 전체를 사용한다.
- Current operational manager는 자기 School settings page에 진입할 수 있지만 planning start/manage 관련 section만 사용한다.
- Current manager에게 School name, color, status 또는 current manager 관리 권한을 새로 부여하지 않는다.
- Eligible planning manager와 ordinary Teacher에게 School settings page 권한을 새로 부여하지 않는다.
- `SchoolPolicy#update?`를 manager까지 넓혀 해결하지 않는다. School 자체 update authorization은 기존 global-admin-only 의미를 유지한다.
- View는 actor가 권한 없는 School profile, lifecycle과 manager mutation control을 렌더링하지 않는다. UI 숨김과 별개로 각 mutation endpoint의 기존 server-side authorization도 유지한다.

### Planning 생성 결과

- Planning SchoolYear 생성에 성공하면 `/schools/:id/planning` preparation management page로 이동한다.
- 생성 실패 시 `/schools/:id/edit` School settings로 돌아가 오류를 표시한다.
- 실패한 explicit create를 다른 SchoolYear 또는 active context로 fallback하지 않는다.
- Planning cancellation은 계속 이 작업 범위 밖이다.

## 7. School overview와 planning page

### Planning year가 없을 때

`/schools/:id`는 planning section 자체를 렌더링하지 않는다. Overview에는 현재 School operation 현황만 남는다.

### Planning year가 있을 때

`/schools/:id`는 informational summary를 표시한다.

- Planning year와 “준비 중” 상태
- Teacher count
- Classroom count
- Current HomeroomAssignment count
- “다음 학년도 준비 관리” link

Manage link는 기존 `/schools/:id/planning`으로 이동한다. School show에서는 planning 생성, 취소 또는 rollover mutation을 제공하지 않는다.

`/schools/:id/planning`은 이미 시작된 planning의 orchestration/manage surface를 유지한다. “선생님 준비”와 “교실 준비” link는 기존 `school_id`와 `school_year_id`를 명시하여 각각 shared `/teachers`, `/classrooms` surface를 연다. 별도 planning Teacher/Classroom controller나 view를 만들지 않는다.

## 8. Planning cancellation

Planning cancel은 이 작업에서 구현하지 않는다. Planning SchoolYear에는 annual Teacher, Classroom, HomeroomAssignment, credential event와 planning manager가 존재할 수 있으므로 단순 destroy로 정의하지 않는다. 필요하면 별도 bounded canonical spec과 human review를 거친다.

## 9. SchoolYear selector와 visual context

Teacher/Classroom 개별 및 bulk surface의 기존 context resolution과 authorization은 변경하지 않는다.

- Active: `2027학년도 · 운영 중`
- Planning: `2028학년도 · 준비 중`
- Archived: “지난 학년도” group 아래 `2026학년도`, `2025학년도`

Existing select에서 `optgroup` 또는 동등하게 명확한 grouping을 우선 검토한다. 현재 controller/context가 제공하는 SchoolYear collection에서 status별 presentation data를 최소한으로 준비하며 새 context framework를 만들지 않는다.

기본 context는 그대로 유지한다.

- Current operational manager: active
- Eligible planning manager: 자기 exact immediate planning
- Global admin: 기존 explicit School/SchoolYear selection semantics
- Archive: global admin과 current operational manager의 explicit selection only, read-only

Malformed, cross-School, cross-year 또는 unauthorized explicit context는 fallback 없이 fail closed한다.

Planning Teacher/Classroom은 inactive data가 아니므로 row/card 자체에 opacity 또는 disabled-looking styling을 적용하지 않는다. Page/header의 `YYYY학년도 · 준비 중` 표시는 유지하면서 planning row/card도 active 운영 data와 구분한다.

- `/teachers`: selected SchoolYear가 planning이면 각 Teacher row에 amber 계열의 border/ring accent와 이름 근처의 작은 “준비 중” badge 또는 동등한 표시를 둔다. 기존 inactive Teacher styling과 의미를 섞지 않는다.
- `/classrooms`: 기존 `school_color_card_class` 배경을 유지하고 amber 배경으로 덮지 않는다. Card에 amber border/ring accent와 작은 “준비 중” badge를 추가한다. Active/inactive Classroom lifecycle badge semantics는 변경하지 않는다.
- Archive는 기존 read-only 표현을 유지하고 planning accent를 사용하지 않는다.
- 기존 Tailwind visual vocabulary를 사용하며 새 design system을 만들지 않는다.

## 10. Management filter UI consistency

다음 management surface의 filter/select 영역은 같은 visual vocabulary와 순서를 사용한다.

| Surface | Filter 순서 |
|---|---|
| `/schools` | 상태 |
| `/classrooms` | 학교 → 학년도 → 학년 |
| `/admin/classrooms` | 학교 → 학년도 |
| `/teachers` | 학교 → 학년도 → 계정 상태 |
| `/admin/teachers` | 학교 → 학년도 |

공통 표현은 다음 수준으로 맞춘다.

- Filter panel: `rounded-xl border border-slate-200 bg-white p-4`
- Label: `text-xs font-semibold text-slate-500`
- Select: `rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm`
- Apply button: `rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm font-semibold text-slate-700 hover:bg-slate-50`
- Mobile에서는 filter form과 control이 wrap될 수 있어야 한다.

School filter와 SchoolYear/filter form이 dependent context 때문에 나뉘어 있어도 그대로 둔다. 하나의 form으로 억지로 합치거나 dependent-select Stimulus를 추가하지 않는다. Existing filtering, authorization, actor별 default, selected value와 SchoolYear optgroup semantics는 변경하지 않는다. Bulk grade tab과 selection/operation control은 이 panel 통일 범위 밖이다. 실제 중복을 줄이는 경우에만 작은 partial/helper를 사용하며 generic filter component/framework를 만들지 않는다.

## 11. Authority regression boundary

다음을 변경하지 않는다.

- Global admin은 모든 School의 operation scope를 가진다.
- Current operational manager는 자기 School active/planning management와 archive read authority를 가진다.
- Eligible planning manager는 자기 exact immediate planning SchoolYear의 preparation authority만 가진다.
- Planning manager 자신은 manager designation/replace/remove를 수행할 수 없다.
- Actual rollover는 global-admin-only다.
- Ordinary Teacher는 Teacher management 권한이 없고 담당 active Classroom만 운영한다.
- Planning Student operation은 없다.
- Archived context mutation은 없다.
- Cross-School/cross-year request는 fail closed한다.

## 예상 구현 및 검증 surface

현재 코드가 더 작은 변경을 허용하면 이 목록 전체를 수정할 필요는 없다.

- Role-aware explicit logout: `Users::SessionsController` 또는 기존 Devise redirect hook, focused request spec
- Teacher ID: `teachers/index`, `teachers/_form`, 관련 request/view assertions
- Student avatar: `classroom_students/_student_card`, focused rendering/request assertion
- Credential: 새 `Teachers::TemporaryPassword`, `AnnualTeacherUsers::TemporaryCredential`, focused service specs
- Bulk avatar: `teachers/_bulk_edit_table`, bulk request/view assertion
- Planning location: School overview/settings partial과 controller preparation, SchoolYear create request regression specs
- Selector: 기존 Teacher/Classroom individual/bulk selector rendering 또는 작은 shared presentation helper, focused request specs
- Teacher single-create return: trusted management-surface context 전달과 credential result return path request specs
- Planning accent: Teacher row와 Classroom card의 planning-only badge/border rendering assertions
- Filter consistency: 다섯 management surface의 panel/control class와 기존 filter behavior regression assertions
- 새 사용자 표시 문자열은 locale key로 추가한다.

## Acceptance criteria

1. 명시적으로 logout한 current Teacher와 planning manager는 각자의 annual School Teacher login으로 이동한다.
2. Admin logout은 기존 admin login 흐름을 유지한다.
3. 자격 상실로 강제 종료되는 Teacher session의 기존 fail-closed redirect는 유지된다.
4. `/teachers`의 active/planning/archive row에서 Teacher 이름 가까이에 `login_id`가 표시되고 email은 primary identifier로 표시되지 않는다.
5. Persisted Teacher edit에는 read-only `login_id`가 보이며 create에는 기존 editable input이 유지된다.
6. 별도 Teacher show route와 login ID update support를 만들지 않는다.
7. Student card avatar class는 Growth Record 기준과 같고 card의 나머지 구조는 유지된다.
8. Temporary password는 정확히 8자이며 허용 alphabet만 사용하고 `login_id`와 case-insensitive하게 같지 않다.
9. Initial issue와 reissue가 같은 generator를 사용하며 one-time/no-store/audit/transaction 계약을 유지한다.
10. Teacher bulk table은 별도 column 없이 이름 cell 안에 작은 avatar를 표시하고 inactive styling을 유지한다.
11. Planning year가 없으면 School show에 planning section/start control이 없고 School settings에만 authorized start section과 명확한 confirmation이 있는 start button이 보인다.
12. Global admin은 기존 School settings 전체를 사용하고 current manager는 자기 School의 planning section만 사용한다. Planning manager와 ordinary Teacher는 settings page에 새로 접근할 수 없다.
13. Settings page 진입 권한을 School update 권한과 분리하며 `SchoolPolicy#update?`를 manager에게 확대하지 않고, 권한 없는 School mutation control은 렌더링하지 않는다.
14. Planning 생성 성공은 planning management page로 이동하고 실패는 오류와 함께 School settings로 돌아가며 다른 SchoolYear로 fallback하지 않는다.
15. Planning year가 있으면 School show에 year/status/count summary와 planning manage link가 보이고 생성·취소·rollover control은 없다.
16. Planning page의 Teacher/Classroom link는 existing shared surface를 explicit planning context로 연다.
17. SchoolYear selector는 active/planning/archive를 명확히 구분하며 actor별 default와 fail-closed semantics를 유지한다.
18. Planning row/card는 opacity 등으로 inactive처럼 보이지 않고 page/header context로 준비 상태를 구분한다.
19. Planning cancellation route/control/service를 추가하지 않는다.
20. Existing authority, archive immutability, planning Student prohibition과 cross-School/cross-year 경계를 보존한다.
21. `/admin/teachers`에서 시작한 Teacher single-create 결과는 동일 School/SchoolYear의 `/admin/teachers`로 복귀한다.
22. 일반 `/teachers`에서 시작한 Teacher single-create 결과는 동일 School/SchoolYear의 `/teachers`로 복귀한다.
23. Arbitrary redirect target을 주입할 수 없고 bulk-create credential의 기존 return 계약은 유지된다.
24. Planning Teacher row는 amber badge/accent로 active row와 구분되며 inactive처럼 opacity가 낮아지지 않는다.
25. Planning Classroom card는 School color background와 lifecycle 의미를 유지하면서 amber badge/border로 planning임을 식별할 수 있다.
26. Archive에는 planning visual accent를 적용하지 않는다.
27. 다섯 management surface의 filter panel, label, select와 apply button styling 및 지정된 배치 순서가 일관된다.
28. Filter form 분리, SchoolYear optgroup, filtering, authorization와 context default/fail-closed semantics는 회귀하지 않는다.

## Explicit non-goals

- Planning cancellation implementation
- Rollover reversal/recovery
- Archived Teacher authentication
- Historical reporting redesign
- Planning Student roster
- Planning-only Teacher/Classroom controller/view
- Dependent select JavaScript
- Generic filter architecture/component/framework
- Generic context framework
- Generic credential framework 또는 password complexity system
- Route namespace redesign
- Student card redesign beyond avatar class
- Teacher bulk redesign beyond name-cell avatar
- School color system 변경
- Inactive Teacher/Classroom lifecycle 표현 변경
- `login_id` edit support
- 별도 Teacher show page
