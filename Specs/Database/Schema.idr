module Specs.Database.Schema

import Specs.Core.Types
import Specs.Core.TimeTypes

%default total

--------------------------------------------------------------------------------
-- TimescaleDB 스키마 정의
-- 목적: 시계열 데이터 최적화된 테이블 구조 (틱 데이터 포함)
--------------------------------------------------------------------------------

||| PostgreSQL 데이터 타입
public export
data PostgresType
  = PgText
  | PgInteger
  | PgBigInt
  | PgReal
  | PgDoublePrecision
  | PgTimestamp
  | PgTimestampTz     -- Timezone 포함
  | PgBoolean

public export
Show PostgresType where
  show PgText = "TEXT"
  show PgInteger = "INTEGER"
  show PgBigInt = "BIGINT"
  show PgReal = "REAL"
  show PgDoublePrecision = "DOUBLE PRECISION"
  show PgTimestamp = "TIMESTAMP"
  show PgTimestampTz = "TIMESTAMPTZ"
  show PgBoolean = "BOOLEAN"

||| 컬럼 정의 (제약 조건 포함)
public export
record ColumnDef where
  constructor MkColumn
  name : String
  dataType : PostgresType
  notNull : Bool
  primaryKey : Bool
  unique : Bool

||| 기본 컬럼 (제약 조건 없음)
public export
column : String -> PostgresType -> ColumnDef
column name typ = MkColumn name typ False False False

||| NOT NULL 컬럼
public export
notNull : ColumnDef -> ColumnDef
notNull col = { notNull := True } col

||| Primary Key 컬럼
public export
primaryKey : ColumnDef -> ColumnDef
primaryKey col = { primaryKey := True, notNull := True } col

||| 테이블 스키마
public export
record TableSchema where
  constructor MkTable
  tableName : String
  columns : List ColumnDef
  isHypertable : Bool  -- TimescaleDB 하이퍼테이블 여부

||| 종목 마스터 테이블
public export
stocksTable : TableSchema
stocksTable = MkTable "stocks"
  [ primaryKey $ column "code" PgText              -- 종목 코드 (PK)
  , notNull $ column "name" PgText                 -- 종목명
  , notNull $ column "market" PgText               -- KOSPI/KOSDAQ
  , notNull $ column "listing_date" PgTimestampTz  -- 상장일
  , column "delisting_date" PgTimestampTz          -- 상장폐지일 (nullable)
  , notNull $ column "created_at" PgTimestampTz    -- 레코드 생성 시각
  , column "updated_at" PgTimestampTz              -- 레코드 갱신 시각
  ]
  False  -- 일반 테이블

||| 틱 데이터 테이블 (체결 데이터 - 초대용량)
public export
tradesTickTable : TableSchema
tradesTickTable = MkTable "trades_tick"
  [ notNull $ column "timestamp" PgTimestampTz     -- 체결 시각 (마이크로초)
  , notNull $ column "stock_code" PgText           -- 종목 코드
  , notNull $ column "price" PgDoublePrecision     -- 체결가
  , notNull $ column "volume" PgInteger            -- 체결량
  , notNull $ column "ask_bid" PgText              -- 매수/매도 구분 ('ask'/'bid')
  , notNull $ column "created_at" PgTimestampTz    -- 데이터 수집 시각
  ]
  True  -- 하이퍼테이블 (초대용량)

||| 캔들 데이터 테이블 (하이퍼테이블)
public export
candlesTable : Timeframe -> TableSchema
candlesTable tf = MkTable ("candles_" ++ show tf)
  [ notNull $ column "timestamp" PgTimestampTz     -- 시각 (파티션 키)
  , notNull $ column "stock_code" PgText           -- 종목 코드
  , notNull $ column "open" PgDoublePrecision      -- 시가
  , notNull $ column "high" PgDoublePrecision      -- 고가
  , notNull $ column "low" PgDoublePrecision       -- 저가
  , notNull $ column "close" PgDoublePrecision     -- 종가
  , notNull $ column "volume" PgBigInt             -- 거래량
  , column "amount" PgBigInt                       -- 거래대금 (nullable)
  , notNull $ column "created_at" PgTimestampTz    -- 데이터 수집 시각
  ]
  True  -- 하이퍼테이블

||| 기술적 지표 테이블 (하이퍼테이블)
public export
indicatorsTable : Timeframe -> TableSchema
indicatorsTable tf = MkTable ("indicators_" ++ show tf)
  [ notNull $ column "timestamp" PgTimestampTz     -- 시각 (파티션 키)
  , notNull $ column "stock_code" PgText           -- 종목 코드
  , column "rsi" PgDoublePrecision                 -- RSI (nullable)
  , column "macd" PgDoublePrecision                -- MACD
  , column "macd_signal" PgDoublePrecision         -- MACD 시그널
  , column "bb_upper" PgDoublePrecision            -- 볼린저 상단
  , column "bb_middle" PgDoublePrecision           -- 볼린저 중간
  , column "bb_lower" PgDoublePrecision            -- 볼린저 하단
  , notNull $ column "created_at" PgTimestampTz    -- 계산 시각
  ]
  True  -- 하이퍼테이블

||| 동기화 상태 테이블 (Windows ↔ Mac 동기화 추적)
public export
syncStatusTable : TableSchema
syncStatusTable = MkTable "sync_status"
  [ primaryKey $ column "id" PgInteger             -- ID (자동 증가)
  , notNull $ column "source_host" PgText          -- Windows/Mac
  , notNull $ column "target_host" PgText          -- Mac/Windows
  , notNull $ column "table_name" PgText           -- 동기화된 테이블
  , notNull $ column "last_sync_time" PgTimestampTz -- 마지막 동기화 시각
  , notNull $ column "rows_synced" PgBigInt        -- 동기화된 행 수
  , notNull $ column "status" PgText               -- success/partial/failed
  , column "error_message" PgText                  -- 에러 메시지 (nullable)
  , notNull $ column "created_at" PgTimestampTz    -- 레코드 생성 시각
  ]
  False  -- 일반 테이블

||| 전체 스키마 (생성 순서 중요: 외래키 제약 고려)
public export
allTables : List TableSchema
allTables =
  [ stocksTable
  , tradesTickTable          -- 틱 데이터 추가
  , candlesTable Daily
  , candlesTable Min1
  , candlesTable Min10
  , candlesTable Min60
  , indicatorsTable Daily
  , indicatorsTable Min10
  , syncStatusTable
  ]

--------------------------------------------------------------------------------
-- SQL 생성 가이드
--------------------------------------------------------------------------------

export
sqlGuide : String
sqlGuide = """
=== TimescaleDB Schema Implementation (with Tick Data) ===

```sql
-- 1. 종목 마스터 테이블
CREATE TABLE stocks (
    code TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    market TEXT NOT NULL,
    listing_date TIMESTAMPTZ NOT NULL,
    delisting_date TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- 2. 틱 데이터 테이블 (체결 데이터 - 초대용량)
CREATE TABLE trades_tick (
    timestamp TIMESTAMPTZ NOT NULL,
    stock_code TEXT NOT NULL,
    price DOUBLE PRECISION NOT NULL,
    volume INTEGER NOT NULL,
    ask_bid TEXT NOT NULL,  -- 'ask' or 'bid'
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (timestamp, stock_code),
    FOREIGN KEY (stock_code) REFERENCES stocks(code)
);

-- TimescaleDB 하이퍼테이블로 변환 (1일 청크)
SELECT create_hypertable('trades_tick', 'timestamp',
    chunk_time_interval => INTERVAL '1 day'
);

-- 3. 캔들 데이터 테이블 (일봉)
CREATE TABLE candles_daily (
    timestamp TIMESTAMPTZ NOT NULL,
    stock_code TEXT NOT NULL,
    open DOUBLE PRECISION NOT NULL,
    high DOUBLE PRECISION NOT NULL,
    low DOUBLE PRECISION NOT NULL,
    close DOUBLE PRECISION NOT NULL,
    volume BIGINT NOT NULL,
    amount BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (timestamp, stock_code),
    FOREIGN KEY (stock_code) REFERENCES stocks(code)
);

SELECT create_hypertable('candles_daily', 'timestamp');

-- (이하 생략: 10분봉, 1분봉 동일 구조)

-- 4. 동기화 상태 테이블
CREATE TABLE sync_status (
    id SERIAL PRIMARY KEY,
    source_host TEXT NOT NULL,
    target_host TEXT NOT NULL,
    table_name TEXT NOT NULL,
    last_sync_time TIMESTAMPTZ NOT NULL,
    rows_synced BIGINT NOT NULL,
    status TEXT NOT NULL,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

Python 구현:

```python
import psycopg2

class TimescaleDBSchema:
    def __init__(self, connection_string: str):
        self.conn = psycopg2.connect(connection_string)
        self.cursor = self.conn.cursor()

    def create_all_tables(self):
        # 1. 종목 마스터
        self.cursor.execute(\"\"\"
            CREATE TABLE IF NOT EXISTS stocks (
                code TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                market TEXT NOT NULL,
                listing_date TIMESTAMPTZ NOT NULL,
                delisting_date TIMESTAMPTZ,
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                updated_at TIMESTAMPTZ
            )
        \"\"\")

        # 2. 틱 데이터
        self.cursor.execute(\"\"\"
            CREATE TABLE IF NOT EXISTS trades_tick (
                timestamp TIMESTAMPTZ NOT NULL,
                stock_code TEXT NOT NULL,
                price DOUBLE PRECISION NOT NULL,
                volume INTEGER NOT NULL,
                ask_bid TEXT NOT NULL,
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                PRIMARY KEY (timestamp, stock_code),
                FOREIGN KEY (stock_code) REFERENCES stocks(code)
            )
        \"\"\")

        # 하이퍼테이블 변환
        try:
            self.cursor.execute(\"\"\"
                SELECT create_hypertable('trades_tick', 'timestamp',
                    chunk_time_interval => INTERVAL '1 day',
                    if_not_exists => TRUE
                )
            \"\"\")
        except Exception as e:
            print(f"Tick hypertable creation skipped: {e}")

        # 3. 캔들 테이블들
        for timeframe in ['daily', 'min1', 'min10', 'min60']:
            self.create_candles_table(timeframe)

        self.conn.commit()

schema = TimescaleDBSchema("postgresql://user:password@localhost:5432/kiwoom")
schema.create_all_tables()
```

주의사항:
  - 틱 데이터: 1일 청크 (데이터 매우 큼)
  - 틱 데이터: 1일 후 즉시 압축 (Hypertable.idr 참조)
  - 틱 데이터: 30일 후 자동 삭제 (Parquet 백업 후)
"""
