# OCI Production Deploy Runbook

## Production 구성

기본 운영 요청 경로는 다음과 같다.

```text
Cloudflare
→ Nginx 443
→ 127.0.0.1:3000 Rails
```

- 서비스별 공식 도메인은 배포 환경의 reverse proxy에서 설정한다.
- Cloudflare SSL/TLS는 Full (strict)를 사용한다.
- Rails는 production에서 `FORCE_SSL=true`로 실행한다.
- Docker app port는 localhost에만 bind하며 OCI/host firewall에서 3000을 직접 공개하지 않는다.
- Nginx는 Cloudflare의 검증된 요청에서 실제 client IP를 복원하고, 알 수 없는 HTTPS SNI는 거부한다.
- `.env`, Cloudflare Origin private key 등 secret은 저장소에 두지 않는다.
- 이메일 발송과 Devise password recovery는 사용하지 않는다.

## 최초 DB 준비

새 production DB를 처음 준비할 때만 DB와 schema를 준비하고 최초 관리자를 생성한다.

```bash
docker compose -p suksuk_school_starter --env-file .env -f compose.prod.yml up -d db
docker compose -p suksuk_school_starter --env-file .env -f compose.prod.yml run --rm web bin/rails db:prepare
docker compose -p suksuk_school_starter --env-file .env -f compose.prod.yml run --rm web bin/rails app:bootstrap
docker compose -p suksuk_school_starter --env-file .env -f compose.prod.yml up -d web
```

`app:bootstrap`은 최초 설정 전용이며 일반 재배포에서는 실행하지 않는다.

Single web-container의 기본 `bundle exec puma -C config/puma.rb` 시작은 entrypoint에서 먼저 같은 image의 `bin/rails db:prepare`를 실행한다. 빈 DB는 schema를 준비하고 기존 DB는 pending migration을 적용하며, 준비가 실패하면 nonzero exit로 종료하고 Puma를 시작하지 않는다. 이미 준비된 DB의 재시작도 이 경로를 따른다. 기존 `./bin/rails server`도 동일하며 console/shell/개별 task에는 자동 preparation을 추가하지 않는다. 위 최초 수동 preparation은 관리자 bootstrap 전에 schema를 준비하기 위한 절차다.

## SchoolYear reconciliation scheduler

Production scheduler에 `bin/rails school_years:reconcile_rollovers`를 **최소 하루 1회** 실행하도록 등록한다. 정확히 target year의 3월 1일 00:00에 실행할 필요는 없다. Downtime 이후 첫 실행에서는 아직 automatic attempt가 없는 overdue target을 catch-up한다. 이미 시도한 target은 자동 재시도하지 않으며, 상세 계약은 [SchoolYear rollover calendar](../specs/school_year_rollover_calendar.md)를 따른다.

Scheduler 구현 방식과 등록은 cron, systemd timer, container scheduler 등 deployment concern이다. 이 기능만을 위해 Solid Queue나 generic background-job framework를 도입하지 않는다. Reconciliation은 전용 Rake task로 실행하며 일반 HTTP request에서는 실행하지 않는다.

배포 후 scheduler 실행 기록 또는 안전한 수동 invocation과 log로 task 실행 경로를 확인한다. 수동 invocation도 동일한 reconciliation을 수행하므로 실제 rollover와 automatic attempt 소진이 일어날 수 있음을 확인하고 실행한다.

## 일반 재배포

1. commit SHA 기반 immutable tag와 `latest`를 동일 이미지로 build/push한다.
2. 현재 실행 이미지를 rollback tag로 보존한다.
3. 새 이미지와 compose 파일을 준비하고 다음 명령으로 구성을 검증한다.

   ```bash
   docker compose -p suksuk_school_starter --env-file .env -f compose.prod.yml config --quiet
   ```

4. 일관된 백업이 필요하면 web을 중지한다.
5. PostgreSQL dump와 Active Storage 파일을 백업한다.
6. DB 백업은 gzip 무결성을, 파일 백업은 tar 목록을 확인하고 각각 SHA256을 기록한다.
7. 필요하면 새 이미지로 `bin/rails db:prepare`를 수동 preflight한다. 일반 재배포의 필수 수작업은 아니다.
8. web container를 새 이미지로 recreate하고 log에서 자동 `db:prepare` 성공 후 Puma가 시작됐는지 확인한다. 준비 실패 시 원인을 해결한 뒤 재시작하며 `app:bootstrap`을 재실행하지 않는다.
9. 실행 중인 container의 image ID가 배포 대상과 일치하는지 확인한다.
10. HTTPS/HSTS, reverse proxy host 처리, 로그인, Action Cable WebSocket과 Turbo realtime 갱신을 smoke test한다.

문제 발생 시 보존한 rollback tag로 web을 recreate한다. 데이터 변경을 되돌려야 한다면 검증된 PostgreSQL 및 Active Storage 백업을 사용한다.
