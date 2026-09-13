# suksuk_school_starter

학교 기반 Rails 서비스를 시작하기 위한 bootstrap repository입니다. 새 서비스는 이 저장소를 복제한 뒤 공통 학교 운영 기반 위에 service-specific domain을 추가합니다.

## 제공하는 기반

- `School`과 planning / active / archived `SchoolYear`
- 하나의 SchoolYear에 속하는 annual Teacher `User`
- Classroom에 직접 속하는 별도 `Student` 모델
- current `HomeroomAssignment` 기반 Teacher ↔ Classroom 0..1 대 0..1 담임 관계
- global admin, current operational manager, eligible planning manager, ordinary Teacher와 Student 권한 경계
- Teacher / Classroom / Student lifecycle과 archived read-only 경계
- Teacher `login_id`, 임시 자격증명 발급·재발급과 Devise 인증
- Student PIN/token 로그인과 짧은 session
- planning 학년도 준비와 global-admin-only rollover
- `/teachers`, `/classrooms` 개별 운영 화면
- `/admin/teachers`, `/admin/classrooms` Teacher·Classroom 일괄 관리 화면
- Rails, Tailwind CSS, Devise, Pundit, ActiveStorage, PostgreSQL

Student의 소속과 lifecycle source는 각각 `Student.classroom_id`, `Student.active`입니다. Teacher의 학교·역할·학년은 annual User의 `school_year`, `school_role`, `grade`에 있으며, 별도 membership fallback은 사용하지 않습니다.

## 포함하지 않는 도메인

이 starter에는 praise/compliment, coupon, message, holiday 또는 growth-specific domain을 포함하지 않습니다.

## 주요 문서

- 현재 구조: [`docs/architecture/current_system.md`](docs/architecture/current_system.md)
- 역할과 권한: [`docs/architecture/roles_and_permissions.md`](docs/architecture/roles_and_permissions.md)
- 학교 운영 lifecycle: [`docs/specs/school_operations_lifecycle.md`](docs/specs/school_operations_lifecycle.md)
- 학생 lifecycle: [`docs/specs/student_membership_lifecycle.md`](docs/specs/student_membership_lifecycle.md)
- planning 학년도 준비: [`docs/specs/planning_year_bootstrap.md`](docs/specs/planning_year_bootstrap.md)
- Teacher 일괄 관리: [`docs/specs/teacher_bulk_management.md`](docs/specs/teacher_bulk_management.md)
- Classroom 일괄 관리: [`docs/specs/classroom_bulk_management.md`](docs/specs/classroom_bulk_management.md)

## 개발

```bash
bin/setup
bin/dev
```

검증은 프로젝트 정책에 따라 RSpec을 사용합니다.

```bash
bundle exec rspec
```

개발·테스트 demo 데이터는 필요할 때 다음 명령으로 준비합니다.

```bash
bin/rails db:seed
```
