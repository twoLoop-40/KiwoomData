module Specs.Validation.Invariants

import Specs.Core.Types

%default total

--------------------------------------------------------------------------------
-- 불변 조건 (Invariants) - Smart Constructor 패턴
-- 목적: 데이터 무결성 보장 (검증된 데이터만 타입으로 표현)
--------------------------------------------------------------------------------

||| 검증된 캔들 타입 (Opaque Type)
||| 생성자는 export 안 함 → 오직 validateCandle을 통해서만 생성 가능
public export
data ValidCandle : Type where
  MkValidCandle : Candle -> ValidCandle

||| ValidCandle에서 원본 데이터를 꺼내는 함수
public export
getRaw : ValidCandle -> Candle
getRaw (MkValidCandle c) = c

||| 허용 오차 (Floating Point Epsilon)
epsilon : Double
epsilon = 0.000001

||| 가격 검증 (> 0)
public export
isValidPrice : Double -> Bool
isValidPrice price = price > 0.0

||| 검증 로직 (Smart Constructor)
||| 입력: 일반 Candle → 출력: Maybe ValidCandle
public export
validateCandle : Candle -> Maybe ValidCandle
validateCandle c =
  let o = c.ohlcv.openPrice
      h = c.ohlcv.highPrice
      l = c.ohlcv.lowPrice
      cl = c.ohlcv.closePrice
      v = c.ohlcv.volume

      -- 가격은 양수여야 함
      positivePrices = o > 0 && h > 0 && l > 0 && cl > 0

      -- 고가는 시가/종가보다 크거나 같아야 함 (오차 허용)
      maxOC = if o > cl then o else cl
      highValid = h >= maxOC - epsilon

      -- 저가는 시가/종가보다 작거나 같아야 함 (오차 허용)
      minOC = if o < cl then o else cl
      lowValid = l <= minOC + epsilon

      -- 거래량은 0 이상 (Nat이라 자동 보장되지만 명시적으로)
      volValid = True  -- Nat은 항상 >= 0
  in
    if positivePrices && highValid && lowValid && volValid
      then Just (MkValidCandle c)
      else Nothing

--------------------------------------------------------------------------------
-- Python 구현 가이드 (Polars Epsilon & Logging)
--------------------------------------------------------------------------------

export
pythonGuide : String
pythonGuide = """
=== Robust Validation Implementation (Epsilon + Quality Monitoring) ===

핵심 변경:
  1. Epsilon: 부동소수점 비교 시 1e-6 오차 허용
  2. Data Quality Metric: 불량 데이터 비율 모니터링
  3. Alert: 불량률 10% 이상 시 파이프라인 중단

```python
import polars as pl

class DataValidator:
    def __init__(self, epsilon: float = 1e-6):
        self.epsilon = epsilon

    def validate_ohlcv(self, df: pl.DataFrame) -> pl.DataFrame:
        \"\"\"OHLCV 불변 조건 검증 (Epsilon 적용)\"\"\"

        initial_count = len(df)

        # 1. 가격 양수 체크
        is_positive = (
            (pl.col('open') > 0) &
            (pl.col('high') > 0) &
            (pl.col('low') > 0) &
            (pl.col('close') > 0)
        )

        # 2. High/Low 논리 정합성 (Epsilon 적용)
        is_logical = (
            (pl.col('high') >=
             pl.max_horizontal(['open', 'close']) - self.epsilon) &
            (pl.col('low') <=
             pl.min_horizontal(['open', 'close']) + self.epsilon)
        )

        # 3. 필터링
        valid_df = df.filter(is_positive & is_logical)

        # 4. 데이터 품질 리포트
        dropped_count = initial_count - len(valid_df)
        if dropped_count > 0:
            drop_rate = (dropped_count / initial_count) * 100
            print(f"⚠️ Validation dropped {dropped_count} rows "
                  f"({drop_rate:.2f}%)")

            # [중요] 불량률이 너무 높으면 파이프라인 중단
            if drop_rate > 10.0:
                raise ValueError(
                    f"Data Quality Alert: Too many invalid rows "
                    f"({drop_rate:.2f}%). Check data source!"
                )

        return valid_df

# 사용 예제
validator = DataValidator(epsilon=1e-6)

# 검증
df = pl.read_database("SELECT * FROM candles_min10", connection)
valid_df = validator.validate_ohlcv(df)

print(f"Total: {len(df)}, Valid: {len(valid_df)}, "
      f"Invalid: {len(df) - len(valid_df)}")
```

불량률 기준:
  - < 1%: 정상 (네트워크 노이즈 등)
  - 1~10%: 경고 (데이터 소스 확인)
  - > 10%: 중단 (파이프라인 이상)
"""
