module Specs.Database.Hypertable

import Specs.Core.TimeTypes
import Specs.Database.Schema

%default total

--------------------------------------------------------------------------------
-- TimescaleDB 하이퍼테이블 설정
-- 목적: 시계열 데이터 최적화 (파티셔닝, 압축, 보존 정책)
--------------------------------------------------------------------------------

||| 하이퍼테이블 설정
public export
record HypertableConfig where
  constructor MkHypertableConfig
  tableName : String
  timeColumn : String           -- 파티션 기준 컬럼
  chunkInterval : Nat           -- 청크 간격 (일 단위)
  compressionEnabled : Bool     -- 압축 활성화
  compressionAfterDays : Nat    -- 며칠 후 압축 (일 단위)

||| 일봉 하이퍼테이블 설정
||| 청크 간격: 30일 (약 1개월)
public export
dailyHypertableConfig : HypertableConfig
dailyHypertableConfig = MkHypertableConfig
  "candles_daily"
  "timestamp"
  30        -- 30일 청크
  True      -- 압축 활성화
  90        -- 90일 후 압축

||| 10분봉 하이퍼테이블 설정
||| 청크 간격: 7일 (약 1주일)
public export
min10HypertableConfig : HypertableConfig
min10HypertableConfig = MkHypertableConfig
  "candles_min10"
  "timestamp"
  7         -- 7일 청크
  True      -- 압축 활성화
  30        -- 30일 후 압축

||| 1분봉 하이퍼테이블 설정
||| 청크 간격: 3일
public export
min1HypertableConfig : HypertableConfig
min1HypertableConfig = MkHypertableConfig
  "candles_min1"
  "timestamp"
  3         -- 3일 청크
  True      -- 압축 활성화
  7         -- 7일 후 압축

||| 데이터 보존 정책
public export
record RetentionPolicy where
  constructor MkRetentionPolicy
  tableName : String
  retentionDays : Nat       -- 보존 기간 (일)
  enabled : Bool

||| 일봉 보존 정책 (무기한)
public export
dailyRetentionPolicy : RetentionPolicy
dailyRetentionPolicy = MkRetentionPolicy
  "candles_daily"
  0         -- 0 = 무기한
  False     -- 삭제 안 함

||| 1분봉 보존 정책 (1년)
public export
min1RetentionPolicy : RetentionPolicy
min1RetentionPolicy = MkRetentionPolicy
  "candles_min1"
  365       -- 1년
  True      -- 자동 삭제

||| 10분봉 보존 정책 (3년)
public export
min10RetentionPolicy : RetentionPolicy
min10RetentionPolicy = MkRetentionPolicy
  "candles_min10"
  1095      -- 3년
  True      -- 자동 삭제

||| 틱 데이터 하이퍼테이블 설정 (초대용량 최적화)
||| 청크: 1일, 압축: 1일 후 즉시 실행
public export
tickHypertableConfig : HypertableConfig
tickHypertableConfig = MkHypertableConfig
  "trades_tick"  -- 테이블명
  "timestamp"
  1              -- 1일 단위 청크 (데이터가 너무 커서 쪼갬)
  True           -- 압축 필수
  1              -- 1일 지나면 바로 압축 (Hot -> Warm 전환 가속)

||| 틱 데이터 보존 정책 (30일)
||| DB에는 '최근 한 달'만 남기고, 나머지는 Parquet 파일로 보관
public export
tickRetentionPolicy : RetentionPolicy
tickRetentionPolicy = MkRetentionPolicy
  "trades_tick"
  30             -- 30일
  True           -- 자동 삭제 (Parquet 백업 믿고 삭제)

||| 압축 설정
public export
record CompressionConfig where
  constructor MkCompressionConfig
  compressAfter : String       -- 예: "7 days" (7일 지나면 압축)
  segmentBy : List String      -- 예: ["stock_code"]
  orderBy : List String        -- 예: ["timestamp DESC"]

||| 기본 압축 설정 (종목별 세그먼트, 시간 순 정렬)
public export
defaultCompressionConfig : CompressionConfig
defaultCompressionConfig = MkCompressionConfig
  "7 days"                 -- 7일 후 압축
  ["stock_code"]           -- 종목별로 세그먼트
  ["timestamp DESC"]       -- 최신순 정렬

||| 틱 데이터 압축 설정 (즉시 압축)
public export
tickCompressionConfig : CompressionConfig
tickCompressionConfig = MkCompressionConfig
  "1 day"                  -- 1일 후 즉시 압축
  ["stock_code"]
  ["timestamp DESC"]

--------------------------------------------------------------------------------
-- SQL 구현 가이드
--------------------------------------------------------------------------------

export
sqlGuide : String
sqlGuide = """
=== TimescaleDB Hypertable Configuration ===

```sql
-- 1. 하이퍼테이블 생성
-- (테이블 생성 후 호출)

-- 일봉: 30일 청크
SELECT create_hypertable('candles_daily', 'timestamp',
    chunk_time_interval => INTERVAL '30 days'
);

-- 10분봉: 7일 청크
SELECT create_hypertable('candles_min10', 'timestamp',
    chunk_time_interval => INTERVAL '7 days'
);

-- 1분봉: 3일 청크
SELECT create_hypertable('candles_min1', 'timestamp',
    chunk_time_interval => INTERVAL '3 days'
);

-- 2. 압축 정책 설정
-- 오래된 데이터 자동 압축 (읽기 전용으로 변경)

-- 일봉: 90일 후 압축
ALTER TABLE candles_daily SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'stock_code',
    timescaledb.compress_orderby = 'timestamp DESC'
);

SELECT add_compression_policy('candles_daily', INTERVAL '90 days');

-- 10분봉: 30일 후 압축
ALTER TABLE candles_min10 SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'stock_code',
    timescaledb.compress_orderby = 'timestamp DESC'
);

SELECT add_compression_policy('candles_min10', INTERVAL '30 days');

-- 1분봉: 7일 후 압축
ALTER TABLE candles_min1 SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'stock_code',
    timescaledb.compress_orderby = 'timestamp DESC'
);

SELECT add_compression_policy('candles_min1', INTERVAL '7 days');

-- 3. 데이터 보존 정책 (자동 삭제)
-- 오래된 데이터 자동 삭제로 디스크 절약

-- 틱 데이터: 30일 후 삭제 (Parquet 백업 후)
SELECT add_retention_policy('trades_tick', INTERVAL '30 days');

-- 1분봉: 1년 후 삭제
SELECT add_retention_policy('candles_min1', INTERVAL '365 days');

-- 10분봉: 3년 후 삭제
SELECT add_retention_policy('candles_min10', INTERVAL '1095 days');

-- 일봉: 삭제 안 함 (무기한 보존)
-- (정책 추가 안 함)

-- 4. 틱 데이터 하이퍼테이블 설정 (추가)
-- 1일 단위 청크 생성
SELECT create_hypertable('trades_tick', 'timestamp',
    chunk_time_interval => INTERVAL '1 day'
);

-- 1일 후 즉시 압축 (디스크 절약 핵심)
ALTER TABLE trades_tick SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'stock_code',
    timescaledb.compress_orderby = 'timestamp DESC'
);
SELECT add_compression_policy('trades_tick', INTERVAL '1 day');

-- 4. 청크 상태 확인
SELECT chunk_name, range_start, range_end, is_compressed
FROM timescaledb_information.chunks
WHERE hypertable_name = 'candles_min10'
ORDER BY range_start DESC;

-- 5. 압축률 확인
SELECT
    pg_size_pretty(before_compression_total_bytes) as before,
    pg_size_pretty(after_compression_total_bytes) as after,
    ROUND(100.0 * after_compression_total_bytes / before_compression_total_bytes, 2) as ratio
FROM timescaledb_information.hypertable_compression_stats('candles_min10');
```

Python 구현:

```python
import psycopg2
from typing import List

class HypertableManager:
    def __init__(self, connection_string: str):
        self.conn = psycopg2.connect(connection_string)
        self.cursor = self.conn.cursor()

    def create_hypertable(self, table_name: str, time_column: str,
                          chunk_interval_days: int):
        \"\"\"하이퍼테이블 생성\"\"\"
        self.cursor.execute(f\"\"\"
            SELECT create_hypertable(
                '{table_name}',
                '{time_column}',
                chunk_time_interval => INTERVAL '{chunk_interval_days} days',
                if_not_exists => TRUE
            )
        \"\"\")
        self.conn.commit()
        print(f"Hypertable created: {table_name}")

    def enable_compression(self, table_name: str,
                           segment_by: List[str],
                           order_by: List[str],
                           compress_after_days: int):
        \"\"\"압축 활성화 및 정책 설정\"\"\"

        # 압축 설정
        segment_by_str = ', '.join(segment_by)
        order_by_str = ', '.join(order_by)

        self.cursor.execute(f\"\"\"
            ALTER TABLE {table_name} SET (
                timescaledb.compress,
                timescaledb.compress_segmentby = '{segment_by_str}',
                timescaledb.compress_orderby = '{order_by_str}'
            )
        \"\"\")

        # 자동 압축 정책
        self.cursor.execute(f\"\"\"
            SELECT add_compression_policy(
                '{table_name}',
                INTERVAL '{compress_after_days} days'
            )
        \"\"\")

        self.conn.commit()
        print(f"Compression enabled for {table_name}")

    def add_retention_policy(self, table_name: str, retention_days: int):
        \"\"\"데이터 보존 정책 (자동 삭제)\"\"\"
        self.cursor.execute(f\"\"\"
            SELECT add_retention_policy(
                '{table_name}',
                INTERVAL '{retention_days} days'
            )
        \"\"\")
        self.conn.commit()
        print(f"Retention policy added for {table_name}: {retention_days} days")

    def setup_all_hypertables(self):
        \"\"\"전체 하이퍼테이블 설정\"\"\"

        # 1. 일봉
        self.create_hypertable('candles_daily', 'timestamp', 30)
        self.enable_compression('candles_daily', ['stock_code'],
                                ['timestamp DESC'], 90)

        # 2. 10분봉
        self.create_hypertable('candles_min10', 'timestamp', 7)
        self.enable_compression('candles_min10', ['stock_code'],
                                ['timestamp DESC'], 30)
        self.add_retention_policy('candles_min10', 1095)  # 3년

        # 3. 1분봉
        self.create_hypertable('candles_min1', 'timestamp', 3)
        self.enable_compression('candles_min1', ['stock_code'],
                                ['timestamp DESC'], 7)
        self.add_retention_policy('candles_min1', 365)  # 1년

        print("All hypertables configured successfully")

    def get_compression_stats(self, table_name: str):
        \"\"\"압축률 통계 조회\"\"\"
        self.cursor.execute(f\"\"\"
            SELECT
                pg_size_pretty(before_compression_total_bytes) as before,
                pg_size_pretty(after_compression_total_bytes) as after,
                ROUND(100.0 * after_compression_total_bytes /
                      before_compression_total_bytes, 2) as ratio
            FROM timescaledb_information.hypertable_compression_stats('{table_name}')
        \"\"\")
        result = self.cursor.fetchone()
        if result:
            print(f"{table_name}: Before={result[0]}, After={result[1]}, "
                  f"Ratio={result[2]}%")

# 사용 예제
manager = HypertableManager("postgresql://user:password@localhost:5432/kiwoom")
manager.setup_all_hypertables()
manager.get_compression_stats('candles_min10')
```

최적화 팁:

1. 청크 크기:
   - 너무 작으면: 메타데이터 오버헤드
   - 너무 크면: 쿼리 성능 저하
   - 권장: 메모리의 25% 정도

2. 압축:
   - segment_by: 자주 필터링하는 컬럼 (stock_code)
   - order_by: 자주 정렬하는 컬럼 (timestamp DESC)
   - 압축률: 보통 5~10배

3. 보존 정책:
   - 1분봉: 1년 (용량 큼)
   - 10분봉: 3년 (중간)
   - 일봉: 무기한 (용량 작음)
"""
