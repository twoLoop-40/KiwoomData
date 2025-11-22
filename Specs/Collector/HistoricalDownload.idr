module Specs.Collector.HistoricalDownload

import Specs.Core.Types
import Specs.Core.TimeTypes
import Specs.Core.ErrorTypes
import Data.List
import Data.Nat

%default total

--------------------------------------------------------------------------------
-- 20년치 과거 데이터 다운로드 전략
-- 목적: Kiwoom API 제약 하에서 전체 데이터 수집 (상장일 고려)
--------------------------------------------------------------------------------

||| 종목별 메타데이터 (상장일 포함)
||| 중요: 상장 전 데이터 요청 방지
public export
record StockMeta where
  constructor MkStockMeta
  code : StockCode
  name : String
  market : Market
  listingDate : Integer  -- 상장일 (Unix timestamp)

||| 다운로드 작업 단위
public export
record DownloadTask where
  constructor MkTask
  stock : StockMeta
  timeframe : Timeframe
  dateRange : DateRange  -- 실제 다운로드할 범위 (상장일 고려됨)

||| 스마트한 작업 생성 (상장일 고려)
||| globalRange.start와 listingDate 중 늦은 날짜를 시작일로 사용
public export
createTasks : List StockMeta -> DateRange -> List Timeframe -> List DownloadTask
createTasks stocks globalRange timeframes =
  -- 각 종목별로 실제 유효한 날짜 범위 계산
  [ MkTask stock tf (MkDateRange (max globalRange.startDate stock.listingDate) globalRange.endDate)
  | stock <- stocks, tf <- timeframes ]

||| 다운로드 진행 상태
public export
record DownloadProgress where
  constructor MkProgress
  totalTasks : Nat               -- 전체 작업 수
  completedTasks : Nat           -- 완료된 작업 수
  currentTask : Maybe DownloadTask  -- 현재 처리 중인 작업
  failedTasks : List (DownloadTask, SystemError)  -- 실패한 작업 + 에러

||| 청크 분할 전략
||| Kiwoom 제약: 일봉 600일, 분봉 900개
public export
record ChunkStrategy where
  constructor MkChunkStrategy
  maxDaysPerChunk : Nat       -- 일봉: 600일
  maxCandlesPerChunk : Nat    -- 분봉: 900개
  overlapDays : Nat           -- 중복 확인용 오버랩 (1일)

||| Kiwoom 기본 청크 전략
public export
kiwoomChunkStrategy : ChunkStrategy
kiwoomChunkStrategy = MkChunkStrategy 600 900 1

||| 저장소 파티셔닝 전략
||| 일봉: 종목당 1파일, 분봉: 연도별 분할
public export
data PartitionStrategy
  = SingleFile          -- 일봉/60분봉용 (종목당 1파일)
  | ByYear              -- 1분/10분봉용 (종목/연도별 파일)
  | ByMonth             -- 틱용 (종목/월별 파일)

public export
Show PartitionStrategy where
  show SingleFile = "SingleFile"
  show ByYear = "ByYear"
  show ByMonth = "ByMonth"

public export
getPartitionStrategy : Timeframe -> PartitionStrategy
getPartitionStrategy Daily = SingleFile
getPartitionStrategy Min60 = SingleFile
getPartitionStrategy Min10 = ByYear
getPartitionStrategy Min5 = ByYear
getPartitionStrategy Min1 = ByYear
getPartitionStrategy Tick = ByMonth

||| 다운로드 우선순위 전략
public export
data DownloadPriority
  = DailyFirst        -- 일봉 먼저 (빠름, 안정적)
  | MinuteFirst       -- 분봉 먼저 (용량 큼)
  | Interleaved       -- 교차 (밸런스)

||| 전체 다운로드 계획
public export
record DownloadPlan where
  constructor MkPlan
  stocks : List StockMeta
  timeframes : List Timeframe      -- [Daily, Min1, Min10]
  globalDateRange : DateRange      -- 20년 (전체 목표 범위)
  priority : DownloadPriority
  chunkStrategy : ChunkStrategy
  batchSize : Nat                  -- 배치당 종목 수 (메모리 관리)

||| 예상 다운로드 시간 계산
||| 2500개 종목 × 3개 타임프레임 × 평균 13개 청크 = 97,500개 API 요청
||| 초당 5회 → 97,500 / 5 = 19,500초 ≈ 5.4시간 (이론상 최소)
public export
estimateDownloadTime : DownloadPlan -> Nat
estimateDownloadTime plan =
  let stockCount = length plan.stocks
      timeframeCount = length plan.timeframes
      avgChunks = 13  -- 20년 / 600일
      totalRequests = stockCount * timeframeCount * avgChunks
      requestsPerSecond = 5
      totalSeconds = totalRequests `div` requestsPerSecond
  in totalSeconds

--------------------------------------------------------------------------------
-- Python 구현 가이드 (메모리 관리 + 파티셔닝)
--------------------------------------------------------------------------------

export
pythonGuide : String
pythonGuide = """
=== Advanced Historical Download Implementation ===

핵심 개선사항:
  1. 상장일 고려 (불필요한 요청 방지)
  2. 배치 처리 (메모리 누수 방지)
  3. 파티셔닝 저장 (Polars 사용)
  4. 진행 상태 저장 (중단 후 재개)

```python
import polars as pl
import sys
import json
from pathlib import Path
from datetime import datetime, timedelta
from typing import List, Dict

class HistoricalDownloader:
    def __init__(self, kiwoom_api, rate_limiter, save_dir='data'):
        self.api = kiwoom_api
        self.limiter = rate_limiter
        self.save_dir = Path(save_dir)
        self.progress_file = self.save_dir / 'progress.json'

    def get_stock_meta(self, stock_code: str) -> Dict:
        \"\"\"종목 메타데이터 조회 (상장일 포함)\"\"\"
        name = self.api.GetMasterCodeName(stock_code)
        listing_date = self.api.GetMasterListedStockDate(stock_code)  # YYYYMMDD
        market = self.api.GetMasterStockState(stock_code)

        return {
            'code': stock_code,
            'name': name,
            'listing_date': listing_date,
            'market': market
        }

    def create_tasks(self, stocks: List[str], global_start: str, global_end: str):
        \"\"\"스마트 작업 생성 (상장일 고려)\"\"\"
        tasks = []

        for stock in stocks:
            meta = self.get_stock_meta(stock)

            # 실제 시작일 = max(전역 시작일, 상장일)
            real_start = max(global_start, meta['listing_date'])

            # 상장일이 목표 범위 이후면 스킵
            if real_start > global_end:
                continue

            tasks.append({
                'stock': meta,
                'timeframe': 'daily',
                'start': real_start,
                'end': global_end
            })

        return tasks

    def run_batch(self, batch_size: int = 50):
        \"\"\"배치 단위 실행 (메모리 관리)\"\"\"
        # 1. 진행 상태 로드
        progress = self.load_progress()

        # 2. 할 일 필터링
        all_tasks = self.create_tasks(
            stocks=get_all_stock_codes(),
            global_start='20050101',
            global_end='20250101'
        )
        remaining = [t for t in all_tasks if t['stock']['code'] not in progress['completed']]

        # 3. 배치 추출
        current_batch = remaining[:batch_size]

        if not current_batch:
            print("모든 작업 완료!")
            sys.exit(0)

        # 4. 배치 처리
        for task in current_batch:
            try:
                self.download_and_save(task)
                progress['completed'].append(task['stock']['code'])
                self.save_progress(progress)
            except Exception as e:
                progress['failed'].append({
                    'stock': task['stock']['code'],
                    'error': str(e)
                })
                self.save_progress(progress)

        # 5. 배치 완료 후 프로세스 종료 (메모리 초기화)
        print(f"배치 완료: {len(current_batch)}개 처리")
        sys.exit(1)  # 배치 스크립트가 재시작하도록 유도

    def download_and_save(self, task: Dict):
        \"\"\"다운로드 및 파티셔닝 저장\"\"\"
        stock_code = task['stock']['code']
        timeframe = task['timeframe']

        # 다운로드 (청크 분할 자동)
        df = self.download_with_chunks(
            stock_code,
            task['start'],
            task['end'],
            timeframe
        )

        # Polars로 변환
        df_pl = pl.from_pandas(df)

        # 파티셔닝 전략에 따라 저장
        if timeframe == 'daily':
            # 일봉: 단일 파일
            df_pl.write_parquet(
                self.save_dir / f"{stock_code}_daily.parquet",
                compression='snappy'
            )
        else:
            # 분봉: 연도별 파티션
            df_pl = df_pl.with_columns(
                pl.col("date").str.slice(0, 4).alias("year")
            )
            df_pl.write_parquet(
                self.save_dir / stock_code / timeframe,
                partition_by="year",
                compression='snappy'
            )

    def download_with_chunks(self, stock_code: str, start: str, end: str, timeframe: str):
        \"\"\"청크 분할 다운로드\"\"\"
        chunks = self.split_date_range(start, end, chunk_days=600)
        all_data = []

        for chunk_start, chunk_end in chunks:
            self.limiter = self.limiter.wait_and_request()

            df = self.api.GetDailyStockDataAsDataFrame(
                stock_code,
                start=chunk_start,
                end=chunk_end
            )
            all_data.append(df)

        # 중복 제거
        import pandas as pd
        combined = pd.concat(all_data).drop_duplicates()
        return combined

    def split_date_range(self, start: str, end: str, chunk_days: int):
        \"\"\"날짜 범위를 청크로 분할\"\"\"
        start_dt = datetime.strptime(start, '%Y%m%d')
        end_dt = datetime.strptime(end, '%Y%m%d')
        chunks = []

        current = start_dt
        while current < end_dt:
            chunk_end = min(current + timedelta(days=chunk_days), end_dt)
            chunks.append((
                current.strftime('%Y%m%d'),
                chunk_end.strftime('%Y%m%d')
            ))
            current = chunk_end + timedelta(days=1)

        return chunks

    def load_progress(self) -> Dict:
        if self.progress_file.exists():
            with open(self.progress_file) as f:
                return json.load(f)
        return {'completed': [], 'failed': []}

    def save_progress(self, progress: Dict):
        with open(self.progress_file, 'w') as f:
            json.dump(progress, f, indent=2)

# 배치 실행 스크립트 (run_batch.bat)
'''
@echo off
:loop
python download.py
if %errorlevel% equ 0 goto end
timeout /t 5
goto loop
:end
echo 모든 다운로드 완료!
'''

# 실행
downloader = HistoricalDownloader(kiwoom, rate_limiter)
downloader.run_batch(batch_size=50)
```

메모리 관리 전략:
  - Kiwoom OCX는 장시간 실행 시 메모리 누수 발생
  - 50~100 종목 처리 후 sys.exit(1)로 프로세스 종료
  - 배치 파일(.bat)이 자동으로 재시작
  - 진행 상태는 JSON 파일로 저장

파티셔닝 전략:
  - 일봉/60분봉: 종목당 1파일 (작은 크기)
  - 1분/10분봉: 연도별 파티션 (큰 크기)
  - Polars 사용 (Pandas보다 빠름)

예상 시간:
  - 2500 종목 × (일봉 + 1분봉 + 10분봉)
  - 총 6~12시간 (초당 5회 제한 고려)
"""
