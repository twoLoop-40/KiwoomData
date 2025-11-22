module Specs.Validation.Continuity

import Specs.Core.TimeTypes

%default total

--------------------------------------------------------------------------------
-- 날짜 연속성 검증 (Market Calendar Aware)
-- 목적: 데이터 누락 감지 (휴장일 고려)
--------------------------------------------------------------------------------

||| 결측 유형 정의
public export
data GapType
  = MissingDay        -- 하루 통째로 없음 (심각)
  | MissingCandles    -- 장중 데이터 일부 누락 (네트워크 이슈 등)

public export
record DataGap where
  constructor MkGap
  gapType : GapType
  startTime : Integer
  endTime : Integer

||| 연속성 리포트
public export
record ContinuityReport where
  constructor MkReport
  totalExpected : Nat
  totalActual : Nat
  gaps : List DataGap

||| 완벽한 연속성 확인
public export
isPerfect : ContinuityReport -> Bool
isPerfect report = length report.gaps == 0

--------------------------------------------------------------------------------
-- Python 구현 가이드 (Market Calendar + Polars Upsample)
--------------------------------------------------------------------------------

export
pythonGuide : String
pythonGuide = """
=== Advanced Continuity Check (Calendar Aware) ===

필수 라이브러리:
```bash
pip install pandas_market_calendars
```

핵심 로직:
  1. Market Calendar: 실제 휴장일 정보
  2. Polars Upsample: 시계열 구멍 고속 탐지

```python
import polars as pl
import pandas_market_calendars as mcal
from datetime import time

class ContinuityValidator:
    def __init__(self):
        # 한국 거래소 달력 로드
        self.krx = mcal.get_calendar('XKRX')

    def get_market_schedule(self, start_date, end_date):
        \"\"\"실제 개장일 리스트 추출\"\"\"
        schedule = self.krx.schedule(start_date=start_date, end_date=end_date)
        return schedule.index.to_list()  # DatetimeIndex

    def check_intraday_continuity(self, df: pl.DataFrame, timeframe_min: int):
        \"\"\"장중 10분봉/1분봉 연속성 검증 (Upsample 활용)\"\"\"

        # 1. 데이터가 있는 날짜만 추출
        dates = df['timestamp'].dt.date().unique()

        gaps = []

        for date in dates:
            # 해당 날짜의 데이터만 필터링
            daily_df = df.filter(pl.col('timestamp').dt.date() == date)

            # 2. Upsample (빈 시간 채우기)
            # 09:00 ~ 15:30 사이를 timeframe 간격으로 채움
            full_range = daily_df.upsample(
                time_column="timestamp",
                every=f"{timeframe_min}m"
            )

            # 3. 장 운영 시간 필터 (09:00~15:30)
            full_range = full_range.filter(
                (pl.col('timestamp').dt.hour() >= 9) &
                (pl.col('timestamp').dt.hour() < 16)
            )

            # 4. Null 찾기 (원래 없던 데이터)
            missing = full_range.filter(pl.col('close').is_null())

            if len(missing) > 0:
                print(f"⚠️ Missing candles on {date}: {len(missing)} ea")
                gaps.append((date, len(missing)))

        return gaps

# 사용 예제
validator = ContinuityValidator()

# 주말/공휴일 자동 제외하고 검증
gaps = validator.check_intraday_continuity(df, 10)

if len(gaps) == 0:
    print("✅ Perfect continuity!")
else:
    print(f"⚠️ {len(gaps)} days with gaps")
```
"""
