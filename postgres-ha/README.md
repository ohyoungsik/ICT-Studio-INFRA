# PostgreSQL HA on Docker Swarm with repmgr + HAProxy

이 프로젝트는 Docker Swarm 위에서 PostgreSQL 16 HA 구성을 배포하는 예제이다.  
기존 Replica1 내부의 자체 장애 감시 loop와 수동 승격 명령 직접 호출을 제거하고, `repmgr`가 Primary 장애 감지와 자동 승격을 담당하도록 리팩토링했다.

## 최종 아키텍처

```text
projectmain
└── PostgreSQL Primary
    └── repmgr

projectrep1
└── PostgreSQL Replica1
    └── repmgr

advancedproject
├── PostgreSQL Replica2
│   └── repmgr
│
├── HAProxy
│
└── Docker Swarm Manager
```

애플리케이션은 더 이상 `projectmain:5432`로 직접 접속하지 않는다.  
항상 아래 주소만 사용한다.

```text
haproxy:5432
```

Swarm 외부에서 테스트할 때는 HAProxy가 배치된 `advancedproject:5432`를 사용한다.

## 구성 목표

- PostgreSQL Primary 1대와 Replica 2대를 Docker Swarm에 고정 배치한다.
- 직접 작성한 failover shell loop를 제거한다.
- `repmgr` 기반 자동 failover를 적용한다.
- Primary 장애 시 Replica1이 우선 승격되도록 `REPMGR_NODE_PRIORITY`를 설정한다.
- Replica2는 승격된 Primary를 따라가도록 repmgr 클러스터에 참여시킨다.
- HAProxy가 현재 Primary만 backend로 선택하도록 SQL 기반 health check를 적용한다.
- `docker stack deploy -c stack.yml postgres-ha` 1회로 배포 가능하게 구성한다.
- Terraform, Ansible, GitHub Actions로 확장 가능한 파일 구조를 유지한다.

## 디렉터리 구조

```text
postgres-ha/
├── backup/
├── Dockerfile
├── README.md
├── deploy.sh
├── haproxy.cfg
├── init.sql
├── reset-data.sh
├── scripts/
│   ├── backup.sh
│   ├── prepare-data-dirs.sh
│   └── restore.sh
└── stack.yml
```

## Swarm 노드 배치

서비스는 Docker Swarm placement constraint로 아래 노드에 고정된다.

| Swarm Node Hostname | 서비스 | 역할 |
| --- | --- | --- |
| `projectmain` | `postgres-ha_primary` | 초기 PostgreSQL Primary + repmgr |
| `projectrep1` | `postgres-ha_replica1` | PostgreSQL Replica1 + repmgr, 1순위 승격 후보 |
| `advancedproject` | `postgres-ha_replica2` | PostgreSQL Replica2 + repmgr |
| `advancedproject` | `postgres-ha_haproxy` | PostgreSQL write endpoint |

노드 hostname이 다르면 서비스가 배치되지 않는다. 배포 전 아래 명령으로 확인한다.

```bash
docker node ls
```

## 데이터 디렉터리 준비

`stack.yml`은 PostgreSQL 데이터 디렉터리를 노드별 bind mount로 연결한다.  
따라서 `docker stack deploy` 실행 전에 각 노드에서 host path를 먼저 생성하고 권한을 맞춘다.

아래 스크립트는 `projectmain`, `projectrep1`, `advancedproject`에 접속해 필요한 디렉터리를 자동으로 준비한다.

```bash
./scripts/prepare-data-dirs.sh
```

기본 SSH 사용자는 현재 로컬 사용자이다. 다른 SSH 사용자를 써야 하면 아래처럼 실행한다.

```bash
SSH_USER=ubuntu ./scripts/prepare-data-dirs.sh
```

SSH key 옵션이 필요하면 `SSH_OPTS`로 전달한다.

```bash
SSH_USER=ubuntu SSH_OPTS="-i ~/.ssh/project-key.pem" ./scripts/prepare-data-dirs.sh
```

스크립트가 각 노드에서 실행하는 작업은 다음과 같다.

```text
mkdir -p <host-path>
chown -R 1001:1001 <host-path>
chmod 700 <host-path>
```

## 클러스터 생성

`stack.yml`은 Dockerfile을 직접 빌드하지 않는다.  
따라서 `docker stack deploy -c stack.yml postgres-ha` 실행 전에 PostgreSQL 커스텀 이미지를 Docker Hub에 push해야 한다.

```bash
export DOCKERHUB_ID=wodurl
docker build -t ${DOCKERHUB_ID}/postgres-ha-repmgr:16 .
docker login
docker push ${DOCKERHUB_ID}/postgres-ha-repmgr:16
```

그 다음 Swarm manager 노드인 `advancedproject`에서 같은 환경 변수를 지정한 뒤 stack을 배포한다.

```bash
export DOCKERHUB_ID=wodurl
docker stack deploy --with-registry-auth -c stack.yml postgres-ha
```

## 초기화 + 재배포

DB bind mount 데이터를 초기화하고 stack을 다시 배포하려면 Swarm manager 노드에서 아래 명령을 실행한다.

```bash
sudo ./deploy.sh
```

`deploy.sh`는 내부에서 `reset-data.sh`를 먼저 실행한 뒤 `docker stack deploy -c stack.yml postgres-ha`와 `docker service ls`를 실행한다.

실행 순서는 다음과 같다.

```text
./reset-data.sh
docker stack deploy -c stack.yml postgres-ha
docker service ls
```

`reset-data.sh`는 다음 작업을 수행한다.

```text
docker stack rm postgres-ha
서비스 종료 대기
/data/postgres/primary 초기화
/data/postgres/replica1 초기화
/data/postgres/replica2 초기화
디렉터리 재생성
chown -R 1001:1001 /data/postgres
```

예상 로그 예시는 다음과 같다.

```text
[2026-06-16 10:00:00] Starting PostgreSQL HA deployment.
[2026-06-16 10:00:00] Running data reset script.
[2026-06-16 10:00:00] Starting PostgreSQL HA data reset.
[2026-06-16 10:00:00] Removing Docker stack: postgres-ha
Removing service postgres-ha_haproxy
Removing service postgres-ha_primary
Removing service postgres-ha_replica1
Removing service postgres-ha_replica2
Removing network postgres-ha_postgres_net
[2026-06-16 10:00:01] Waiting for stack services to stop: postgres-ha
[2026-06-16 10:00:04] All stack services are stopped.
[2026-06-16 10:00:04] Resetting PostgreSQL bind mount directories.
[2026-06-16 10:00:04] Resetting remote data directory: projectmain:/data/postgres/primary
[2026-06-16 10:00:05] Resetting remote data directory: projectrep1:/data/postgres/replica1
[2026-06-16 10:00:06] Resetting local data directory: /data/postgres/replica2
[2026-06-16 10:00:06] PostgreSQL HA data reset completed.
[2026-06-16 10:00:06] Deploying Docker stack: postgres-ha
Creating network postgres-ha_postgres_net
Creating service postgres-ha_primary
Creating service postgres-ha_replica1
Creating service postgres-ha_replica2
Creating service postgres-ha_haproxy
[2026-06-16 10:00:10] Current Docker services:
ID             NAME                    MODE         REPLICAS   IMAGE
xxxxxxxxxxxx   postgres-ha_primary      replicated   1/1        wodurl/postgres-ha-repmgr:16
xxxxxxxxxxxx   postgres-ha_replica1     replicated   1/1        wodurl/postgres-ha-repmgr:16
xxxxxxxxxxxx   postgres-ha_replica2     replicated   1/1        wodurl/postgres-ha-repmgr:16
xxxxxxxxxxxx   postgres-ha_haproxy      replicated   1/1        haproxy:2.9
[2026-06-16 10:00:10] PostgreSQL HA deployment command completed.
```

Ansible이나 Terraform 이후 단계와 연결하기 쉽도록 주요 값은 환경 변수로 변경할 수 있다.

| 환경 변수 | 기본값 | 설명 |
| --- | --- | --- |
| `STACK_NAME` | `postgres-ha` | Docker Stack 이름 |
| `STACK_FILE` | `stack.yml` | 배포에 사용할 stack 파일 |
| `DATA_ROOT` | `/data/postgres` | PostgreSQL bind mount 상위 경로 |
| `POSTGRES_UID` | `1001` | PostgreSQL 컨테이너 UID |
| `POSTGRES_GID` | `1001` | PostgreSQL 컨테이너 GID |
| `SUDO` | `sudo` | 원격 및 로컬 권한 상승 명령 |
| `SSH_USER` | `SUDO_USER` 또는 현재 사용자 | 원격 노드 SSH 사용자 |
| `SSH_OPTS` | 빈 값 | SSH key 등 추가 옵션 |
| `SERVICE_WAIT_TIMEOUT` | `120` | 서비스 종료 대기 최대 초 |
| `SERVICE_WAIT_INTERVAL` | `3` | 서비스 종료 확인 주기 초 |

예시는 다음과 같다.

```bash
SSH_USER=ubuntu SSH_OPTS="-i ~/.ssh/project-key.pem" sudo -E ./deploy.sh
```

## 전체 클러스터 삭제

전체 Docker Stack을 삭제하려면 Swarm manager 노드에서 아래 명령을 실행한다.

```bash
docker stack rm postgres-ha
```

## 상태 확인

Stack 서비스 목록을 확인한다.

```bash
docker service ls
```

각 서비스의 task 배치와 상태를 확인한다.

```bash
docker service ps postgres-ha_primary
docker service ps postgres-ha_replica1
docker service ps postgres-ha_replica2
docker service ps postgres-ha_haproxy
```

전체 stack 기준으로 확인할 수도 있다.

```bash
docker stack services postgres-ha
docker stack ps postgres-ha
```

컨테이너 로그는 아래처럼 확인한다.

```bash
docker service logs -f postgres-ha_primary
docker service logs -f postgres-ha_replica1
docker service logs -f postgres-ha_replica2
docker service logs -f postgres-ha_haproxy
```

## 접속 정보

학습용 기본 계정은 다음과 같다. 운영 환경에서는 반드시 Docker Secret 또는 외부 Secret Manager로 교체한다.

| 용도 | 계정 | 비밀번호 | 설명 |
| --- | --- | --- | --- |
| PostgreSQL 관리자 | `postgres` | `postgres_password` | superuser |
| 애플리케이션 | `appuser` | `app_password` | `ticketing` DB 접속 계정 |
| repmgr | `repmgr` | `repmgr_password` | repmgr 클러스터 관리 계정 |

애플리케이션 DB는 `ticketing`이다.

접속 예시는 다음과 같다.

```bash
psql -h advancedproject -p 5432 -U appuser -d ticketing
```

Swarm 내부의 다른 서비스에서는 아래처럼 접속한다.

```text
host=haproxy
port=5432
database=ticketing
user=appuser
password=app_password
```

## 데이터 백업

PostgreSQL 데이터는 Active Primary 컨테이너 내부의 `pg_dump`로 SQL dump 파일을 생성해 로컬 `backup/` 디렉터리에 저장한다.

```text
VM
↓
docker exec
↓
Active Primary Container
↓
pg_dump
↓
Local Backup Directory
```

기본 실행 명령은 아래와 같다.

```bash
./scripts/backup.sh
```

스크립트는 Swarm PostgreSQL 서비스 컨테이너를 순회하며 `pg_is_in_recovery()` 결과가 `false`인 Active Primary를 자동 탐지한다.

| 항목 | 기본값 |
| --- | --- |
| Stack Name | `postgres-ha` |
| Port | `5432` |
| Database | `ticketing` |
| User | `postgres` |
| Backup Directory | `backup/` |

백업 파일명은 timestamp를 포함한다.

```text
backup/ticketing_YYYYMMDD_HHMMSS.sql
```

예시는 다음과 같다.

```text
backup/ticketing_20260615_120000.sql
```

필요하면 환경 변수로 stack 이름, DB 이름, 계정, SSH 사용자를 바꿀 수 있다.

```bash
STACK_NAME=postgres-ha PGDATABASE=ticketing SSH_USER=ubuntu ./scripts/backup.sh
```

## 백업 파일 확인

```bash
ls -al backup/
```

## 데이터 복구

생성된 dump 파일을 지정해 PostgreSQL에 복구한다.

```bash
./scripts/restore.sh backup/<dump-file>
```

예시는 다음과 같다.

```bash
./scripts/restore.sh backup/ticketing_20260615_120000.sql
```

`.sql` 파일은 `psql`로 복구한다.  
향후 `pg_dump -Fc` 같은 custom dump 형식을 사용할 경우 `restore.sh`는 `pg_restore`로 복구한다.

복구 역시 `pg_is_in_recovery()` 결과가 `false`인 Active Primary 컨테이너 내부에서 실행된다.  
필요하면 백업과 동일하게 환경 변수로 stack 이름, DB 이름, 계정, SSH 사용자를 바꿀 수 있다.

```bash
STACK_NAME=postgres-ha PGDATABASE=ticketing SSH_USER=ubuntu ./scripts/restore.sh backup/ticketing_20260615_120000.sql
```

## PostgreSQL 클라이언트 도구

`backup.sh`와 `restore.sh`는 VM Host에 PostgreSQL client 설치를 요구하지 않는다. 아래 도구는 Active Primary PostgreSQL 컨테이너 내부에서 실행된다.

```text
pg_dump
psql
pg_restore
```

현재 PostgreSQL 컨테이너는 `bitnamilegacy/postgresql-repmgr:16` 이미지를 사용한다.  
이 이미지는 PostgreSQL 서버와 클라이언트 도구를 포함하므로 컨테이너 내부에서 dump와 restore를 수행할 수 있다.

로컬 VM에는 Docker CLI와, Active Primary가 원격 Swarm 노드에 있을 때 사용할 SSH 접속 권한만 필요하다.

## 향후 Terraform 확장 계획

현재 백업 구조는 Active Primary 컨테이너에서 dump를 실행하고 로컬 저장소에 파일을 남기는 구조이다.

```text
VM
↓
docker exec
↓
Active Primary Container
↓
pg_dump
↓
Local Backup Directory
```

향후 AWS 인프라로 확장하면 동일한 dump 파일 생성 흐름 뒤에 S3 업로드 단계를 추가한다.

```text
VM
↓
docker exec
↓
Active Primary Container
↓
pg_dump
↓
AWS S3 Bucket
```

Terraform 적용 시 아래 리소스와 구성을 추가할 예정이다.

```text
AWS S3 Bucket 생성
IAM Role 생성
AWS CLI 구성
```

S3 업로드 예시는 다음과 같다.

```bash
aws s3 cp \
backup/ticketing_20260615_120000.sql \
s3://postgres-backup-bucket/
```

현재 작업 범위에서는 S3 관련 실제 코드를 작성하지 않는다.  
대신 `backup/` 디렉터리에 dump 파일을 먼저 생성하는 구조를 유지해, 이후 `aws s3 cp` 단계만 쉽게 추가할 수 있게 한다.

## repmgr Failover 동작

기존 구현은 Replica1 컨테이너 내부에서 직접 아래와 같은 흐름을 수행했다.

```text
Primary 상태 확인
↓
실패 횟수 증가
↓
수동 승격 명령 직접 실행
```

현재 구현에서는 이 로직을 사용하지 않는다.  
`stack.yml`에는 직접 작성한 무한 감시 loop, 수동 승격 명령, 실패 횟수 증가 로직이 없다.

대신 모든 PostgreSQL 노드가 repmgr 클러스터에 참여한다.

```text
Primary 장애 발생
↓
repmgr daemon이 장애 감지
↓
Replica1이 우선 승격 후보로 선택됨
↓
Replica1 자동 승격
↓
Replica2가 새 Primary로 재연결
↓
HAProxy health check가 새 Primary만 backend로 활성화
```

Replica1을 우선 승격시키기 위해 priority를 아래처럼 둔다.

| 노드 | REPMGR_NODE_PRIORITY | 의미 |
| --- | ---: | --- |
| `primary` | `100` | 초기 Primary |
| `replica1` | `90` | 장애 시 1순위 승격 후보 |
| `replica2` | `80` | 장애 시 2순위 승격 후보 |

## HAProxy 역할

HAProxy는 PostgreSQL write endpoint이다.  
애플리케이션은 Primary가 어느 노드인지 알 필요 없이 `haproxy:5432`만 사용한다.

초기 상태:

```text
Application
↓
HAProxy
↓
projectmain / primary
```

Primary 장애 후:

```text
projectmain Down
↓
repmgr Failover
↓
projectrep1 / replica1 승격
↓
HAProxy Health Check 실패 감지
↓
HAProxy Backend 변경
↓
projectrep1 / replica1 연결
```

## HAProxy Health Check

단순 TCP check나 `pg_isready`만 사용하면 standby도 정상 backend로 보일 수 있다.  
그래서 `haproxy.cfg`는 PostgreSQL wire protocol로 아래 SQL을 실행한다.

```sql
SELECT NOT pg_is_in_recovery();
```

결과가 `true`인 노드만 현재 Primary이므로 HAProxy backend로 활성화된다.  
결과가 `false`인 standby는 health check가 실패해 write traffic을 받지 않는다.

HAProxy 통계 socket 확인:

```bash
echo "show stat" | socat stdio tcp4-connect:localhost:8404
```

HAProxy 통계 페이지 확인:

```text
http://advancedproject:8405/
```

## 장애 테스트

현재 Primary 컨테이너 ID를 확인한다.

```bash
docker ps --filter name=postgres-ha_primary
```

Primary를 중지한다.

```bash
docker stop <primary-container>
```

repmgr 로그에서 failover 진행을 확인한다.

```bash
docker service logs -f postgres-ha_replica1
docker service logs -f postgres-ha_replica2
```

HAProxy backend 상태를 확인한다.

```bash
echo "show stat" | socat stdio tcp4-connect:localhost:8404
```

## 승격 확인

승격된 Replica1 컨테이너에 접속한다.

```bash
docker exec -it <replica1-container> psql -U postgres -d postgres
```

아래 SQL을 실행한다.

```sql
SELECT pg_is_in_recovery();
```

결과가 아래와 같으면 Primary 승격이 완료된 것이다.

```text
false
```

Primary에서 replication 상태를 확인한다.

```sql
SELECT client_addr, application_name, state, sync_state
FROM pg_stat_replication;
```

## DB 스키마

콘서트 티켓팅 서비스의 핵심 데이터는 PostgreSQL에 저장한다.  
대기열은 PostgreSQL 테이블로 만들지 않고 Redis에서만 관리한다.

최종 ERD는 아래와 같다.

```text
PERFORM_INFO
    │
    │ 1:N
    ▼
SEAT_STATUS
    ▲
    │
    │ N:1
BOOKING
    ▲
    │
    │ N:1
USERS
```

테이블 생성 순서는 Foreign Key 의존성 때문에 반드시 아래 순서를 따른다.

```text
1. perform_info
2. users
3. seat_status
4. booking
```

### perform_info

공연 정보와 예약 가능 상태를 저장한다.

| 컬럼 | 설명 |
| --- | --- |
| `perform_id` | 공연 식별자 |
| `perform_name` | 공연 이름 |
| `booking_opens_at` | 예약 시작 시각 |
| `booking_closes_at` | 예약 종료 시각 |
| `max_tickets_per_user` | 사용자당 최대 예매 가능 수량 |
| `status` | 공연 상태 |
| `created_at` | 생성 시각 |

`perform_info.status`는 아래 값만 허용한다.

```text
READY
OPEN
SOLD_OUT
CLOSED
CANCELLED
```

상태별 동작은 아래와 같다.

| 상태 | 의미 | 동작 |
| --- | --- | --- |
| `READY` | 공연 준비중 | 예약 불가, 대기열 없음 |
| `OPEN` | 예약 가능 | Redis Queue 생성, 사용자 진입 가능 |
| `SOLD_OUT` | 매진 | 예약 불가 |
| `CLOSED` | 예약 마감 | 예약 불가 |
| `CANCELLED` | 공연 취소 | 예약 불가 |

### users

회원 정보를 저장한다.  
`password` 컬럼에는 평문 비밀번호가 아니라 bcrypt, argon2 같은 알고리즘의 해시값을 저장한다.

| 컬럼 | 설명 |
| --- | --- |
| `user_id` | 회원 식별자 |
| `name` | 회원 이름 |
| `email` | 이메일, 중복 불가 |
| `password` | 비밀번호 해시값 |

### seat_status

공연별 좌석 상태를 저장한다.  
동일한 좌석번호라도 공연이 다르면 허용된다.

```text
perform_id    seat_no
1             A01
1             A02
2             A01
2             A02
```

`seat_status.status`는 아래 값만 허용한다.

```text
AVAILABLE
BOOKED
```

`UNIQUE (perform_id, seat_no)` 제약조건을 사용해 같은 공연 안에서 같은 좌석 번호가 중복 생성되지 않게 한다.

### booking

최종 예약 결과를 저장한다.  
대기열 순번은 Redis에서만 관리하고 PostgreSQL `booking` 테이블에는 저장하지 않는다.

좌석은 한 번만 예약 가능해야 하므로 아래 제약조건을 반드시 유지한다.

```sql
UNIQUE (seat_id)
```

대규모 트래픽에서 같은 좌석에 동시 예약 요청이 들어와도 PostgreSQL UNIQUE 제약조건이 최종 중복 예약을 차단한다.

## Redis Queue 정책

대기열은 PostgreSQL에 저장하지 않는다.  
아래와 같은 테이블은 생성하지 않는다.

```text
queue
waiting
ticket_queue
reservation_queue
```

Queue는 Redis에서만 관리한다.

예시 Redis key:

```text
queue:perform:1

user_101
user_102
user_103
user_104
```

List를 사용할 수 있다.

```redis
LPUSH queue:perform:1 user_101
RPUSH queue:perform:1 user_102
```

또는 순번과 점수를 함께 관리해야 하면 Sorted Set을 사용할 수 있다.

```redis
ZADD queue:perform:1 1710000001 user_101
ZADD queue:perform:1 1710000002 user_102
```

## 예약 흐름

```text
사용자 접속
    ↓
perform_info.status 확인

READY
    ↓
입장 불가

OPEN
    ↓
Redis Queue 진입

순번 도달
    ↓
좌석 선택

seat_status 확인

AVAILABLE
    ↓
예약 생성

BOOKED
    ↓
예약 실패
```

애플리케이션은 예약 생성 시 다음 순서를 지켜야 한다.

1. `perform_info.status`가 `OPEN`인지 확인한다.
2. Redis Queue에서 사용자 순번이 도달했는지 확인한다.
3. 선택한 `seat_status.status`가 `AVAILABLE`인지 확인한다.
4. `booking`에 예약을 생성한다.
5. 같은 트랜잭션에서 `seat_status.status`를 `BOOKED`로 변경한다.
6. 동일 좌석 중복 예약은 `booking.uq_booking_seat` 제약조건으로 최종 차단한다.

## 데이터 확인

HAProxy를 통해 공연, 회원, 좌석, 예약 쓰기가 가능한지 확인한다.

```bash
psql -h advancedproject -p 5432 -U appuser -d ticketing -c "INSERT INTO perform_info (perform_name, booking_opens_at, booking_closes_at, max_tickets_per_user, status) VALUES ('HA Test Concert', NOW(), NOW() + INTERVAL '7 days', 1, 'OPEN');"
```

```bash
psql -h advancedproject -p 5432 -U appuser -d ticketing -c "INSERT INTO users (name, email, password) VALUES ('Test User', 'test@example.com', 'hashed-password');"
```

```bash
psql -h advancedproject -p 5432 -U appuser -d ticketing -c "INSERT INTO seat_status (perform_id, seat_no, status) VALUES (1, 'A01', 'AVAILABLE');"
```

```bash
psql -h advancedproject -p 5432 -U appuser -d ticketing -c "INSERT INTO booking (perform_id, user_id, seat_id) VALUES (1, 1, 1); UPDATE seat_status SET status = 'BOOKED' WHERE seat_id = 1;"
```

예약 결과를 조회한다.

```bash
psql -h advancedproject -p 5432 -U appuser -d ticketing -c "SELECT b.booking_id, p.perform_name, u.email, s.seat_no, b.booked_at FROM booking b JOIN perform_info p ON p.perform_id = b.perform_id JOIN users u ON u.user_id = b.user_id JOIN seat_status s ON s.seat_id = b.seat_id ORDER BY b.booking_id DESC LIMIT 5;"
```

## Volume 정책

각 PostgreSQL 서비스는 노드별 로컬 디렉터리를 bind mount로 사용한다.

| 서비스 | Swarm Node Hostname | Host Path | Container Path |
| --- | --- | --- | --- |
| Primary | `projectmain` | `/data/postgres/primary` | `/bitnami/postgresql` |
| Replica1 | `projectrep1` | `/data/postgres/replica1` | `/bitnami/postgresql` |
| Replica2 | `advancedproject` | `/data/postgres/replica2` | `/bitnami/postgresql` |

각 경로는 해당 노드의 독립 로컬 디스크 경로여야 한다.  
NFS 같은 공유 스토리지나 여러 PostgreSQL 컨테이너가 동시에 접근하는 공용 디렉터리는 사용하지 않는다.

배포 전에 아래 스크립트로 각 노드의 디렉터리를 자동 생성한다.

```bash
./scripts/prepare-data-dirs.sh
```

스크립트는 각 노드에서 아래 작업을 실행한다.

```text
mkdir -p <host-path>
chown -R 1001:1001 <host-path>
chmod 700 <host-path>
```

`1001:1001`은 Bitnami PostgreSQL 컨테이너가 사용하는 기본 비root 사용자이다.  
이 권한이 맞지 않으면 PostgreSQL이 데이터 디렉터리에 파일을 만들지 못해 컨테이너가 시작되지 않을 수 있다.

이유는 다음과 같다.

- PostgreSQL 데이터 디렉터리는 여러 인스턴스가 동시에 공유해서 쓰면 데이터 손상 위험이 있다.
- Streaming Replication은 각 노드가 독립 데이터 디렉터리를 갖는 구조가 기본이다.
- bind mount는 운영자가 데이터 위치, 디스크 용량, 백업 대상을 명확하게 관리하기 쉽다.
- 장애 복구는 공유 디스크가 아니라 replication, backup, WAL archive, pg_rewind 정책으로 처리해야 한다.

## Dockerfile 사용 방식

`Dockerfile`은 PostgreSQL HA 노드들이 공통으로 사용할 커스텀 이미지를 만든다.  
`stack.yml`은 이 이미지를 Docker Hub에서 pull하고, 노드별 역할/볼륨/배치 정보만 런타임에 주입한다.

예시:

```bash
export DOCKERHUB_ID=wodurl
docker build -t ${DOCKERHUB_ID}/postgres-ha-repmgr:16 .
docker login
docker push ${DOCKERHUB_ID}/postgres-ha-repmgr:16
```

`stack.yml`은 `DOCKERHUB_ID` 환경 변수를 사용해 이미지를 참조한다.

```yaml
image: ${DOCKERHUB_ID}/postgres-ha-repmgr:16
```

배포 전 같은 shell에서 환경 변수를 유지한 상태로 실행한다.

```bash
export DOCKERHUB_ID=wodurl
docker stack deploy --with-registry-auth -c stack.yml postgres-ha
```

## Terraform 확장 방향

Terraform은 아래 작업을 자동화할 수 있다.

- EC2 또는 VM 인스턴스 생성
- Security Group 또는 방화벽 구성
- Swarm manager/worker 노드용 private IP 출력
- HAProxy 노출 포트 `5432`, `8404`, `8405` 접근 제어
- GitHub Actions에서 `terraform apply` 실행

## Ansible 확장 방향

Ansible은 아래 작업을 자동화할 수 있다.

- Docker 설치 및 daemon 설정
- Swarm init/join 자동화
- `projectmain`, `projectrep1`, `advancedproject` hostname 검증
- 운영 계정, 커널 파라미터, 방화벽 설정
- `docker stack deploy -c stack.yml postgres-ha` 실행
- 장애 테스트 playbook 작성

## GitHub Actions 확장 방향

GitHub Actions는 아래 파이프라인으로 확장할 수 있다.

1. Dockerfile 기반 이미지 build
2. Trivy 또는 Grype 이미지 보안 스캔
3. Docker Hub 또는 private registry push
4. Terraform apply
5. Ansible playbook 실행
6. Docker Swarm stack deploy 또는 stack update
7. HAProxy stats와 repmgr 상태 smoke test

## 운영 전 보완 사항

현재 구성은 학습과 초기 HA 검증에 초점을 둔다. 운영 전에는 아래 항목을 보완해야 한다.

- 비밀번호를 Docker Secret 또는 Secret Manager로 분리
- HAProxy health check용 trust 인증을 더 안전한 role-check endpoint 또는 mTLS 구조로 교체
- split-brain 방지를 위한 fencing 정책 검증
- WAL archiving과 정기 backup 구성
- 장애 복구 runbook 작성
- Prometheus, Grafana, Alertmanager 기반 모니터링 구성
- HAProxy 통계 페이지 인증과 접근 제한 적용
- PostgreSQL 파라미터를 실제 서버 사양에 맞게 튜닝
