module Specs.Sync.FileExport

import Specs.Core.Types
import Specs.Core.TimeTypes
import Specs.Core.ErrorTypes
import Data.List

%default total

--------------------------------------------------------------------------------
-- SQLite → Parquet 변환 로직
-- 목적: Windows 수집 데이터를 전송 가능한 형식으로 변환
--------------------------------------------------------------------------------

||| 파일 포맷
public export
data FileFormat
  = Parquet     -- 추천 (압축, 컬럼형)
  | CSV         -- 호환성
  | Feather     -- 빠른 I/O

public export
Show FileFormat where
  show Parquet = "Parquet"
  show CSV = "CSV"
  show Feather = "Feather"

||| Parquet 압축 방식
public export
data CompressionCodec
  = Snappy      -- 빠른 압축/해제 (추천)
  | GZIP        -- 높은 압축률
  | LZ4         -- 매우 빠름
  | ZSTD        -- 밸런스 (압축률 + 속도)

public export
Show CompressionCodec where
  show Snappy = "snappy"
  show GZIP = "gzip"
  show LZ4 = "lz4"
  show ZSTD = "zstd"

||| SQLite 타입
public export
data SqlType = SqlText | SqlInteger | SqlReal | SqlBlob

public export
Show SqlType where
  show SqlText = "TEXT"
  show SqlInteger = "INTEGER"
  show SqlReal = "REAL"
  show SqlBlob = "BLOB"

||| 파티션 키 전략
public export
data PartitionKey
  = ByYear      -- 연도별 (분봉 추천)
  | ByMonth     -- 월별 (틱 데이터)
  | None        -- 파티션 없음 (일봉)

public export
Show PartitionKey where
  show ByYear = "year"
  show ByMonth = "month"
  show None = "none"

||| 내보내기 설정
public export
record ExportConfig where
  constructor MkExportConfig
  format : FileFormat
  compression : CompressionCodec
  batchSize : Nat          -- 한 번에 처리할 행 수
  outputDir : String       -- 출력 디렉토리
  partitionStrategy : PartitionKey  -- 파티셔닝 전략

||| 기본 내보내기 설정 (Parquet + Snappy + 연도별 파티션)
public export
defaultExportConfig : ExportConfig
defaultExportConfig = MkExportConfig Parquet Snappy 100000 "C:/KiwoomData/parquet" ByYear

||| 내보내기 작업
public export
record ExportTask where
  constructor MkExportTask
  stockCode : StockCode
  timeframe : Timeframe
  dateRange : DateRange
  outputPath : String

||| 내보내기 결과
public export
record ExportResult where
  constructor MkExportResult
  task : ExportTask
  rowsExported : Nat
  fileSizeBytes : Nat
  compressionRatio : Double  -- 원본 대비 압축률

||| 압축률 계산 헬퍼
public export
calculateCompressionRatio : Nat -> Nat -> Double
calculateCompressionRatio originalSize compressedSize =
  if originalSize == 0
    then 0.0
    else cast compressedSize / cast originalSize

||| SQLite 테이블 스키마 (타입 안전)
public export
record SQLiteSchema where
  constructor MkSchema
  tableName : String
  columns : List (String, SqlType)  -- 타입 안전

||| 캔들 데이터 테이블 스키마
public export
candleTableSchema : Timeframe -> SQLiteSchema
candleTableSchema tf = MkSchema
  ("candles_" ++ show tf)
  [ ("stock_code", SqlText)
  , ("timestamp", SqlInteger)
  , ("open", SqlReal)
  , ("high", SqlReal)
  , ("low", SqlReal)
  , ("close", SqlReal)
  , ("volume", SqlInteger)
  , ("created_at", SqlInteger)  -- 데이터 수집 시각
  ]

||| 증분 내보내기 (마지막 내보내기 이후 데이터만)
public export
record IncrementalExport where
  constructor MkIncrementalExport
  lastExportTime : Integer      -- Unix timestamp
  watermarkColumn : String      -- 증분 기준 컬럼 (created_at)

--------------------------------------------------------------------------------
-- Python 구현 가이드 (Polars + 파티셔닝)
--------------------------------------------------------------------------------

export
pythonGuide : String
pythonGuide = """
=== SQLite → Parquet Export Implementation (with Partitioning) ===

추천: Polars (Pandas보다 빠르고 메모리 효율적)

```python
import polars as pl
import sqlite3
from pathlib import Path
from datetime import datetime
from typing import Optional

class ParquetExporter:
    def __init__(self, sqlite_path: str, output_dir: str):
        self.sqlite_path = sqlite_path
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

    def export_table(self, table_name: str, stock_code: str,
                     timeframe: str, incremental: bool = True,
                     partition_by: str = 'year'):
        \"\"\"SQLite 테이블 → Parquet 변환 (파티셔닝 지원)\"\"\"

        # 1. SQLite 연결
        conn = sqlite3.connect(self.sqlite_path)

        # 2. 증분 쿼리 (마지막 내보내기 이후 데이터만)
        if incremental:
            last_export_time = self.get_last_export_time(stock_code, timeframe)
            query = f\"\"\"
                SELECT * FROM {table_name}
                WHERE stock_code = ?
                  AND created_at > ?
                ORDER BY timestamp
            \"\"\"
            params = (stock_code, last_export_time)
        else:
            query = f\"\"\"
                SELECT * FROM {table_name}
                WHERE stock_code = ?
                ORDER BY timestamp
            \"\"\"
            params = (stock_code,)

        # 3. Polars로 직접 로드
        df = pl.read_database(query, conn, params=params)

        if df.height == 0:
            print(f"No new data for {stock_code}")
            return None

        # 4. 파티션 키 컬럼 추가
        # timestamp(ms) → year(str) 파생 컬럼 생성
        if partition_by == 'year':
            df = df.with_columns(
                (pl.col("timestamp") / 1000)
                .cast(pl.Datetime)
                .dt.year()
                .cast(pl.Utf8)
                .alias("year")
            )
        elif partition_by == 'month':
            df = df.with_columns(
                (pl.col("timestamp") / 1000)
                .cast(pl.Datetime)
                .dt.strftime("%Y%m")
                .alias("month")
            )

        # 5. Parquet 저장 (Hive Style 파티셔닝)
        output_path = self.output_dir / stock_code / timeframe

        if partition_by != 'none':
            # 결과: data/005930/10min/year=2024/part-0.parquet
            df.write_parquet(
                output_path,
                compression='snappy',
                partition_by=partition_by,  # <--- 핵심
                use_pyarrow=True,
                statistics=True,  # 통계 정보 포함 (쿼리 최적화)
                row_group_size=100000
            )
        else:
            # 파티션 없음: 단일 파일
            df.write_parquet(
                output_path / f"{stock_code}_{timeframe}.parquet",
                compression='snappy',
                statistics=True
            )

        # 6. 압축률 계산
        original_size = df.estimated_size()
        compressed_size = sum(
            f.stat().st_size
            for f in output_path.rglob('*.parquet')
        )
        ratio = compressed_size / original_size if original_size > 0 else 0

        print(f"Exported {stock_code}: {df.height} rows, "
              f"compression ratio: {ratio:.2%}")

        # 7. 워터마크 갱신
        self.update_watermark(stock_code, timeframe, df['created_at'].max())

        return {
            'rows': df.height,
            'size': compressed_size,
            'ratio': ratio
        }

    def export_all_stocks(self, stocks: list, timeframe: str):
        \"\"\"전체 종목 일괄 내보내기\"\"\"
        results = []

        # 타임프레임에 따른 파티션 전략
        if timeframe in ['1min', '10min']:
            partition_by = 'year'
        elif timeframe == 'tick':
            partition_by = 'month'
        else:  # daily, 60min
            partition_by = 'none'

        for stock in stocks:
            try:
                result = self.export_table(
                    table_name=f'candles_{timeframe}',
                    stock_code=stock,
                    timeframe=timeframe,
                    incremental=True,
                    partition_by=partition_by
                )
                if result:
                    results.append(result)
            except Exception as e:
                print(f"Failed to export {stock}: {e}")
                continue

        total_rows = sum(r['rows'] for r in results)
        total_size = sum(r['size'] for r in results)
        print(f"Total: {total_rows} rows, {total_size / 1024**2:.2f} MB")

        return results

    def get_last_export_time(self, stock_code: str, timeframe: str) -> int:
        \"\"\"마지막 내보내기 시각 조회\"\"\"
        watermark_file = self.output_dir / '.watermarks.json'
        if watermark_file.exists():
            import json
            with open(watermark_file) as f:
                watermarks = json.load(f)
            return watermarks.get(f"{stock_code}_{timeframe}", 0)
        return 0

    def update_watermark(self, stock_code: str, timeframe: str, timestamp: int):
        \"\"\"워터마크 갱신\"\"\"
        watermark_file = self.output_dir / '.watermarks.json'
        import json

        watermarks = {}
        if watermark_file.exists():
            with open(watermark_file) as f:
                watermarks = json.load(f)

        watermarks[f"{stock_code}_{timeframe}"] = timestamp

        with open(watermark_file, 'w') as f:
            json.dump(watermarks, f, indent=2)

# 사용 예제
exporter = ParquetExporter(
    sqlite_path='C:/KiwoomData/kiwoom.db',
    output_dir='C:/KiwoomData/parquet'
)

# 1시간마다 증분 내보내기
import schedule

def hourly_export():
    all_stocks = ['005930', '000660', ...]  # 전체 종목
    exporter.export_all_stocks(all_stocks, timeframe='10min')

schedule.every().hour.do(hourly_export)

while True:
    schedule.run_pending()
    time.sleep(60)
```

파티셔닝 결과 예시:
```
C:/KiwoomData/parquet/
├── 005930/
│   ├── daily/
│   │   └── 005930_daily.parquet  (파티션 없음)
│   └── 10min/
│       ├── year=2020/
│       │   └── part-0.parquet
│       ├── year=2021/
│       │   └── part-0.parquet
│       └── year=2024/
│           └── part-0.parquet
└── 000660/
    └── ...
```

최적화 팁:

1. Polars vs Pandas:
   - Polars: 멀티 스레드, 메모리 효율
   - Pandas: 더 많은 기능, 느림
   - 대용량 데이터 → Polars 추천

2. 파티셔닝 전략:
   - 일봉/60분봉: 파티션 없음 (작은 크기)
   - 1분/10분봉: 연도별 파티션 (쿼리 최적화)
   - 틱: 월별 파티션 (매우 큰 데이터)

3. 압축:
   - Snappy: 빠름 (추천)
   - ZSTD: 압축률 높음 (느림)
   - LZ4: 매우 빠름 (압축률 낮음)

4. 증분 내보내기:
   - created_at 컬럼으로 워터마크 관리
   - 매번 전체 내보내기 X, 새 데이터만 O
"""
