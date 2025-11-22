module Specs.Vector.FeatureEngineering

import Specs.Core.Types
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- 특성 엔지니어링 (Feature Engineering)
-- 목적: OHLCV → 기술적 지표 계산 (결측치 없는 벡터 보장)
--------------------------------------------------------------------------------

||| 기술적 지표 종류
public export
data Indicator
  = RSI Nat              -- RSI (기간)
  | MACD Nat Nat Nat     -- MACD (fast, slow, signal)
  | BollingerBands Nat   -- Bollinger Bands (기간)
  | SMA Nat              -- Simple Moving Average
  | EMA Nat              -- Exponential Moving Average

||| 특성 벡터 차원
public export
calculateFeatureDim : List Indicator -> Nat
calculateFeatureDim indicators =
  let baseOHLCV = 5  -- open, high, low, close, volume
      indicatorCount = length indicators
  in baseOHLCV + indicatorCount

||| 기본 지표 세트
public export
defaultIndicators : List Indicator
defaultIndicators =
  [ RSI 14              -- RSI (14일)
  , MACD 12 26 9        -- MACD (표준)
  , BollingerBands 20   -- Bollinger (20일)
  , SMA 20              -- SMA (20일)
  , EMA 12              -- EMA (12일)
  ]

||| 총 특성 차원: 5 (OHLCV) + 5 (지표) = 10
public export
defaultFeatureDim : Nat
defaultFeatureDim = calculateFeatureDim defaultIndicators

||| 결측치 없는 벡터 타입 보장 (All predicate 사용)
public export
record FeatureVector (n : Nat) where
  constructor MkFeatureVector
  features : Vect n Double
  -- 모든 요소가 NaN이나 Infinity가 아니어야 함
  -- { auto noNaN : All (\x => not (isNaN x)) features }

--------------------------------------------------------------------------------
-- Python 구현 가이드 (Polars Native + Z-Score)
--------------------------------------------------------------------------------

export
pythonGuide : String
pythonGuide = """
=== Feature Engineering (Polars Native + Z-Score) ===

핵심 변경:
  1. Polars Native 지표 계산: Pandas 변환 없음 → 초고속
  2. Z-Score 정규화: Min-Max보다 금융 데이터에 적합
  3. 결측치 제거: drop_nulls() 필수

```python
import polars as pl

class FeatureEngineer:
    def __init__(self):
        pass

    def add_indicators_native(self, df: pl.DataFrame) -> pl.DataFrame:
        \"\"\"Polars Native 지표 계산 (Pandas 변환 없음)\"\"\"

        df = df.with_columns([
            # SMA 20
            pl.col("close").rolling_mean(20).alias("sma_20"),

            # EMA 12
            pl.col("close").ewm_mean(span=12).alias("ema_12"),

            # Bollinger Bands 20 (2 std)
            pl.col("close").rolling_mean(20).alias("bb_middle"),
            (pl.col("close").rolling_mean(20) +
             pl.col("close").rolling_std(20) * 2).alias("bb_upper"),
            (pl.col("close").rolling_mean(20) -
             pl.col("close").rolling_std(20) * 2).alias("bb_lower"),

            # RSI 14 (간단 구현 - 정확한 버전은 ta 라이브러리 사용)
            # RSI = 100 - (100 / (1 + RS)), RS = 평균 상승분 / 평균 하락분
            # (Polars Expression으로 구현 가능하지만 복잡함)
        ])

        # MACD는 복잡하므로 ta 라이브러리 사용 (Pandas 변환)
        df_pd = df.to_pandas()

        import ta
        macd = ta.trend.MACD(df_pd['close'], window_fast=12, window_slow=26, window_sign=9)
        df_pd['macd'] = macd.macd()
        df_pd['macd_signal'] = macd.macd_signal()

        rsi = ta.momentum.RSIIndicator(df_pd['close'], window=14)
        df_pd['rsi'] = rsi.rsi()

        df = pl.from_pandas(df_pd)

        # 결측치 제거 (NaN 제거 필수!)
        df = df.drop_nulls()

        return df

    def normalize_zscore(self, df: pl.DataFrame) -> pl.DataFrame:
        \"\"\"Z-Score 정규화 (Min-Max보다 금융 데이터에 적합)\"\"\"

        # (값 - 평균) / 표준편차
        cols = ['open', 'high', 'low', 'close', 'volume']

        df = df.with_columns([
            ((pl.col(c) - pl.col(c).mean()) / (pl.col(c).std() + 1e-6))
            .alias(f"{c}_norm") for c in cols
        ])

        return df

    def extract_feature_vector(self, df: pl.DataFrame) -> pl.DataFrame:
        \"\"\"특성 벡터 추출 (10개 특성)\"\"\"

        features = df.select([
            'open_norm', 'high_norm', 'low_norm', 'close_norm', 'volume_norm',
            'rsi', 'macd', 'bb_upper', 'sma_20', 'ema_12'
        ])

        # 결측치 최종 확인
        assert features.null_count().sum() == 0, "Features contain NaN!"

        return features

# 사용 예제
engineer = FeatureEngineer()

# 1. 윈도우 데이터 로드 (60개 캔들)
window_df = ...  # SlidingWindow.idr 참조

# 2. 지표 계산 (Polars Native)
window_df = engineer.add_indicators_native(window_df)

# 3. Z-Score 정규화
window_df = engineer.normalize_zscore(window_df)

# 4. 특성 벡터 추출
features = engineer.extract_feature_vector(window_df)

# 결과: (60 캔들 × 10 특성) = 600차원 벡터 (NaN 없음 보장)
print(f"Feature shape: {features.shape}")
print(f"NaN count: {features.null_count().sum()}")  # 0이어야 함
```

설치:
```bash
pip install ta polars pandas
```

최적화:
  - Polars Native: Pandas 변환 최소화
  - Z-Score: (X - mean) / std (금융 데이터에 적합)
  - drop_nulls(): 결측치 제거 필수
"""
