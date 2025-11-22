module Specs.Database.Indexing

import Specs.Database.Schema

%default total

--------------------------------------------------------------------------------
-- 인덱스 전략 (틱 데이터 포함)
-- 목적: 쿼리 성능 최적화
--------------------------------------------------------------------------------

||| 인덱스 타입
public export
data IndexType
  = BTree       -- 기본 인덱스 (범위 쿼리)
  | Hash        -- 해시 인덱스 (등식 쿼리)
  | GIN         -- Generalized Inverted Index (배열, JSON)
  | BRIN        -- Block Range Index (시계열 최적화)

public export
Show IndexType where
  show BTree = "BTREE"
  show Hash = "HASH"
  show GIN = "GIN"
  show BRIN = "BRIN"

||| 인덱스 정의
public export
record IndexDef where
  constructor MkIndex
  indexName : String
  tableName : String
  columns : List String     -- 인덱스 컬럼
  indexType : IndexType
  unique : Bool             -- UNIQUE 인덱스 여부

||| 기본 인덱스 (BTree, non-unique)
public export
index : String -> String -> List String -> IndexDef
index name table cols = MkIndex name table cols BTree False

||| UNIQUE 인덱스
public export
uniqueIndex : IndexDef -> IndexDef
uniqueIndex idx = { unique := True } idx

||| BRIN 인덱스 (시계열 최적화)
public export
brinIndex : IndexDef -> IndexDef
brinIndex idx = { indexType := BRIN } idx

||| 종목 코드 + 시간 인덱스 (가장 중요)
||| 쿼리: WHERE stock_code = ? AND timestamp > ?
public export
candlesStockTimeIndex : String -> IndexDef
candlesStockTimeIndex tableName =
  index
    ("idx_" ++ tableName ++ "_stock_time")
    tableName
    ["stock_code", "timestamp DESC"]

||| 시간 범위 인덱스 (BRIN - 시계열 최적화)
||| 쿼리: WHERE timestamp BETWEEN ? AND ?
public export
candlesTimeRangeIndex : String -> IndexDef
candlesTimeRangeIndex tableName =
  brinIndex $ index
    ("idx_" ++ tableName ++ "_time_brin")
    tableName
    ["timestamp"]

||| 종목 코드 인덱스
||| 쿼리: WHERE stock_code = ?
public export
stockCodeIndex : String -> IndexDef
stockCodeIndex tableName =
  index
    ("idx_" ++ tableName ++ "_stock")
    tableName
    ["stock_code"]

||| 전체 인덱스 목록
public export
allIndexes : List IndexDef
allIndexes =
  -- 틱 데이터 인덱스
  [ candlesStockTimeIndex "trades_tick"
  , candlesTimeRangeIndex "trades_tick"

  -- 캔들 테이블 인덱스
  , candlesStockTimeIndex "candles_daily"
  , candlesTimeRangeIndex "candles_daily"
  , candlesStockTimeIndex "candles_min10"
  , candlesTimeRangeIndex "candles_min10"
  , candlesStockTimeIndex "candles_min1"
  , candlesTimeRangeIndex "candles_min1"

  -- 지표 테이블 인덱스
  , candlesStockTimeIndex "indicators_min10"

  -- 동기화 상태 테이블 인덱스
  , index "idx_sync_status_table" "sync_status" ["table_name", "last_sync_time DESC"]
  , index "idx_sync_status_host" "sync_status" ["source_host", "target_host"]
  ]

--------------------------------------------------------------------------------
-- SQL 구현 가이드
--------------------------------------------------------------------------------

export
sqlGuide : String
sqlGuide = """
=== Index Strategy Implementation (with Tick Data) ===

```sql
-- 1. 틱 데이터 인덱스 (초대용량 최적화)
CREATE INDEX idx_trades_tick_stock_time
ON trades_tick (stock_code, timestamp DESC);

CREATE INDEX idx_trades_tick_time_brin
ON trades_tick USING BRIN (timestamp);

-- 2. 캔들 테이블 인덱스
CREATE INDEX idx_candles_daily_stock_time
ON candles_daily (stock_code, timestamp DESC);

CREATE INDEX idx_candles_daily_time_brin
ON candles_daily USING BRIN (timestamp);

-- (이하 생략: 10분봉, 1분봉 동일)

-- 3. 인덱스 사용 통계 확인
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan DESC;
```

Python 구현:

```python
import psycopg2

class IndexManager:
    def __init__(self, connection_string: str):
        self.conn = psycopg2.connect(connection_string)
        self.cursor = self.conn.cursor()

    def create_all_indexes(self):
        # 1. 틱 데이터 인덱스
        self.create_index('idx_trades_tick_stock_time', 'trades_tick',
                          ['stock_code', 'timestamp DESC'])
        self.create_index('idx_trades_tick_time_brin', 'trades_tick',
                          ['timestamp'], index_type='BRIN')

        # 2. 캔들 테이블 인덱스
        for timeframe in ['daily', 'min10', 'min1']:
            table = f'candles_{timeframe}'
            self.create_index(f'idx_{table}_stock_time', table,
                              ['stock_code', 'timestamp DESC'])
            self.create_index(f'idx_{table}_time_brin', table,
                              ['timestamp'], index_type='BRIN')

        print("All indexes created successfully")

manager = IndexManager("postgresql://user:password@localhost:5432/kiwoom")
manager.create_all_indexes()
```

틱 데이터 쿼리 최적화:
  - BRIN 인덱스: 작은 크기로 큰 테이블 커버
  - (stock_code, timestamp) 복합 인덱스: 종목별 시간 범위 쿼리 최적화
"""
