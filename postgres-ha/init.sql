-- ---------------------------------------------------------------------------
-- PostgreSQL 초기화 SQL
-- ---------------------------------------------------------------------------
-- 이 파일은 PostgreSQL 컨테이너의 /docker-entrypoint-initdb.d 규칙에 따라
-- 데이터 디렉터리가 비어 있는 최초 1회 초기화 시점에 자동 실행된다.
--
-- 목적
-- 1. 콘서트 티켓팅 서비스가 사용할 application database 보장
-- 2. 애플리케이션 접속 계정 권한 보강
-- 3. 공연 정보, 회원, 좌석 상태, 예약 정보를 저장하는 핵심 테이블 생성
--
-- Queue 정책
-- - 대기열은 PostgreSQL에 저장하지 않는다.
-- - queue, waiting, ticket_queue, reservation_queue 같은 테이블은 생성하지 않는다.
-- - 대기열은 Redis의 List 또는 Sorted Set 구조에서만 관리한다.
--
-- 주의
-- - repmgr 계정과 replication 메타데이터는 bitnami postgresql-repmgr entrypoint가 관리한다.
-- - 운영 환경에서는 아래 비밀번호를 Docker Secret 또는 외부 Secret Manager로 분리해야 한다.
-- - PostgreSQL 16 기준으로 실행 가능한 SQL만 사용한다.
-- ---------------------------------------------------------------------------

-- ticketing 데이터베이스가 없을 때만 생성한다.
-- POSTGRESQL_DATABASE 환경 변수로도 생성되지만, SQL 파일 단독 재사용성을 위해 한 번 더 보장한다.
-- CREATE DATABASE는 트랜잭션 블록 내부에서 실행할 수 없기 때문에 psql의 \gexec 기능을 사용한다.
SELECT 'CREATE DATABASE ticketing'
WHERE NOT EXISTS (
    SELECT 1
    FROM pg_database
    WHERE datname = 'ticketing'
)\gexec

-- 애플리케이션 계정을 보장한다.
-- appuser는 서비스 SQL 실행용 계정이며 superuser 권한을 주지 않는다.
-- superuser 권한을 제거하면 애플리케이션 장애나 SQL Injection 발생 시 피해 범위를 줄일 수 있다.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'appuser'
    ) THEN
        CREATE USER appuser WITH
            LOGIN
            PASSWORD 'app_password';
    END IF;
END
$$;

-- ticketing 데이터베이스로 접속 대상을 변경한다.
\connect ticketing

-- appuser가 ticketing 데이터베이스와 public schema를 사용할 수 있도록 권한을 부여한다.
-- CONNECT 권한은 데이터베이스 접속에 필요하다.
-- USAGE 권한은 schema 내부 객체 접근의 기본 조건이다.
-- CREATE 권한은 애플리케이션 마이그레이션 실행에 필요하다.
GRANT CONNECT ON DATABASE ticketing TO appuser;
GRANT USAGE, CREATE ON SCHEMA public TO appuser;

-- 기존 객체가 있을 경우 appuser가 접근할 수 있도록 권한을 부여한다.
-- 초기 상태에서는 객체가 없을 수 있지만, 재배포와 SQL 단독 실행을 고려해 포함한다.
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO appuser;
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO appuser;

-- 이후 public schema에 생성되는 테이블과 시퀀스에도 appuser 권한이 자동 적용되도록 한다.
-- 마이그레이션 도구가 새 객체를 만들 때 권한 누락을 줄인다.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO appuser;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO appuser;

-- ---------------------------------------------------------------------------
-- 1. 공연 정보: perform_info
-- ---------------------------------------------------------------------------
-- 공연별 예약 오픈/마감 시간, 사용자당 최대 예매 가능 수량, 공연 상태를 저장한다.
-- 다른 테이블이 perform_info.perform_id를 참조하므로 가장 먼저 생성한다.
-- status CHECK 제약조건은 애플리케이션 버그로 정의되지 않은 상태값이 들어오는 것을 방지한다.
CREATE TABLE IF NOT EXISTS perform_info (
    -- 공연 식별자이다.
    -- BIGSERIAL은 대규모 공연 데이터 누적을 고려해 64비트 정수 sequence를 사용한다.
    perform_id BIGSERIAL PRIMARY KEY,

    -- 공연 이름이다.
    -- 화면 표시와 검색 조건으로 사용할 수 있으므로 필수값으로 둔다.
    perform_name VARCHAR(200) NOT NULL,

    -- 예약 시작 시각이다.
    -- TIMESTAMPTZ는 서버/사용자 timezone 차이를 안전하게 처리하기 위해 사용한다.
    booking_opens_at TIMESTAMPTZ NOT NULL,

    -- 예약 종료 시각이다.
    -- 예약 가능 여부 판단과 운영 마감 처리를 위해 필수값으로 둔다.
    booking_closes_at TIMESTAMPTZ NOT NULL,

    -- 사용자 1명당 최대 예매 가능 수량이다.
    -- 기본값 1은 티켓팅 경쟁 상황에서 다량 선점을 제한하기 위한 보수적 기본 정책이다.
    max_tickets_per_user INTEGER NOT NULL DEFAULT 1,

    -- 공연 상태이다.
    -- READY, OPEN, SOLD_OUT, CLOSED, CANCELLED 외 값은 CHECK 제약조건으로 차단한다.
    status VARCHAR(20) NOT NULL
        CHECK (
            status IN (
                'READY',
                'OPEN',
                'SOLD_OUT',
                'CLOSED',
                'CANCELLED'
            )
        ),

    -- 레코드 생성 시각이다.
    -- 운영 감사와 정렬 기준으로 사용한다.
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- 2. 회원: users
-- ---------------------------------------------------------------------------
-- 티켓을 예약하는 회원 정보를 저장한다.
-- booking 테이블이 users.user_id를 참조하므로 booking보다 먼저 생성한다.
-- password 컬럼에는 평문이 아니라 bcrypt, argon2 같은 알고리즘의 해시값을 저장한다.
CREATE TABLE IF NOT EXISTS users (
    -- 회원 식별자이다.
    -- 예약 테이블에서 외래키로 참조한다.
    user_id BIGSERIAL PRIMARY KEY,

    -- 회원 이름이다.
    -- 서비스 표시와 운영자 확인에 사용한다.
    name VARCHAR(100) NOT NULL,

    -- 회원 이메일이다.
    -- 로그인 식별자로 사용할 수 있으므로 UNIQUE 제약조건으로 중복 가입을 막는다.
    email VARCHAR(320) NOT NULL UNIQUE,

    -- 비밀번호 해시값이다.
    -- 평문 비밀번호 저장을 금지하고 충분한 길이의 해시 문자열을 저장하기 위해 VARCHAR(255)를 사용한다.
    password VARCHAR(255) NOT NULL
);

-- ---------------------------------------------------------------------------
-- 3. 공연별 좌석: seat_status
-- ---------------------------------------------------------------------------
-- 공연별 좌석 번호와 좌석 예약 상태를 저장한다.
-- 동일한 seat_no라도 perform_id가 다르면 다른 공연의 좌석이므로 허용한다.
-- perform_info를 참조하므로 perform_info 생성 이후에 생성한다.
CREATE TABLE IF NOT EXISTS seat_status (
    -- 좌석 식별자이다.
    -- booking 테이블에서 예약 대상 좌석을 식별할 때 참조한다.
    seat_id BIGSERIAL PRIMARY KEY,

    -- 좌석이 속한 공연 식별자이다.
    -- 공연 삭제 시 관련 좌석도 함께 삭제되도록 fk_seat_perform에서 ON DELETE CASCADE를 사용한다.
    perform_id BIGINT NOT NULL,

    -- 공연 안에서의 좌석 번호이다.
    -- 예: A01, A02, B10 같은 값을 저장한다.
    seat_no VARCHAR(20) NOT NULL,

    -- 좌석 상태이다.
    -- AVAILABLE 또는 BOOKED만 허용해 예약 가능 여부 판단을 단순하고 안전하게 만든다.
    status VARCHAR(20) NOT NULL
        CHECK (
            status IN (
                'AVAILABLE',
                'BOOKED'
            )
        ),

    -- 좌석은 반드시 존재하는 공연에 소속되어야 한다.
    -- 공연이 삭제되면 소속 좌석도 삭제되어 고아 좌석 데이터가 남지 않게 한다.
    CONSTRAINT fk_seat_perform
        FOREIGN KEY (perform_id)
        REFERENCES perform_info(perform_id)
        ON DELETE CASCADE,

    -- 같은 공연 안에서는 같은 좌석 번호가 중복되면 안 된다.
    -- 단, 공연이 다르면 같은 seat_no를 사용할 수 있어야 하므로 perform_id와 seat_no 복합 UNIQUE를 사용한다.
    CONSTRAINT uq_perform_seat
        UNIQUE (
            perform_id,
            seat_no
        )
);

-- ---------------------------------------------------------------------------
-- 4. 예약: booking
-- ---------------------------------------------------------------------------
-- 사용자가 특정 공연의 특정 좌석을 예약한 결과를 저장한다.
-- perform_info, users, seat_status를 모두 참조하므로 가장 마지막에 생성한다.
-- 대기열 순번은 Redis에서만 관리하며 booking에는 최종 예약 결과만 저장한다.
CREATE TABLE IF NOT EXISTS booking (
    -- 예약 식별자이다.
    -- 결제, 취소, 운영 로그와 연결할 때 기준 키로 사용할 수 있다.
    booking_id BIGSERIAL PRIMARY KEY,

    -- 예약 대상 공연 식별자이다.
    -- 예약 조회 시 공연 기준 필터링을 빠르고 명확하게 하기 위해 별도 컬럼으로 둔다.
    perform_id BIGINT NOT NULL,

    -- 예약한 회원 식별자이다.
    -- 회원별 예약 내역과 최대 예매 수량 정책 검증에 사용한다.
    user_id BIGINT NOT NULL,

    -- 예약한 좌석 식별자이다.
    -- uq_booking_seat 제약조건으로 같은 좌석의 중복 예약을 차단한다.
    seat_id BIGINT NOT NULL,

    -- 예약 생성 시각이다.
    -- 동시성 분석, 감사, 고객 문의 대응에 필요하다.
    booked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- 예약은 반드시 존재하는 공연에 연결되어야 한다.
    -- 공연 삭제/취소 정책은 운영 요구사항에 따라 별도 취소 처리로 관리할 수 있도록 CASCADE를 두지 않는다.
    CONSTRAINT fk_booking_perform
        FOREIGN KEY (perform_id)
        REFERENCES perform_info(perform_id),

    -- 예약은 반드시 존재하는 회원에 연결되어야 한다.
    -- 회원 삭제 시 예약 감사 이력이 사라지지 않도록 CASCADE를 두지 않는다.
    CONSTRAINT fk_booking_user
        FOREIGN KEY (user_id)
        REFERENCES users(user_id),

    -- 예약은 반드시 존재하는 좌석에 연결되어야 한다.
    -- 좌석 삭제는 운영상 신중해야 하므로 CASCADE를 두지 않는다.
    CONSTRAINT fk_booking_seat
        FOREIGN KEY (seat_id)
        REFERENCES seat_status(seat_id),

    -- 좌석은 한 번만 예약 가능하다.
    -- 대규모 트래픽에서 같은 seat_id로 동시 INSERT가 들어와도 PostgreSQL UNIQUE 제약조건이 최종 중복 예약을 차단한다.
    CONSTRAINT uq_booking_seat
        UNIQUE (seat_id)
);

-- 새로 생성된 핵심 테이블과 sequence에 appuser 권한을 부여한다.
-- appuser가 애플리케이션 런타임에서 공연/좌석/예약 데이터를 읽고 쓸 수 있게 한다.
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO appuser;
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO appuser;
