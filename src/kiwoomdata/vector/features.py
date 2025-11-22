"""
Feature Engineering - Technical indicators and normalization

Specs: Specs/Vector/FeatureEngineering.idr
Purpose: Calculate technical indicators (RSI, MACD, Bollinger) with no NaN guarantee
"""

from enum import Enum
from typing import List

import polars as pl
import pandas as pd
import ta


class Indicator(Enum):
    """Technical indicator types (matches Idris2 spec)"""

    RSI = "rsi"
    MACD = "macd"
    BOLLINGER_BANDS = "bollinger"
    SMA = "sma"
    EMA = "ema"


class FeatureEngineer:
    """
    Feature engineering for time-series candle data

    Design:
    - Polars native operations (fast)
    - Z-Score normalization (better for financial data)
    - NaN elimination (drop_nulls)
    - Technical indicators via ta library

    Implementation follows Specs/Vector/FeatureEngineering.idr
    """

    def __init__(
        self,
        rsi_period: int = 14,
        macd_fast: int = 12,
        macd_slow: int = 26,
        macd_signal: int = 9,
        bb_period: int = 20,
        bb_std: float = 2.0,
        sma_period: int = 20,
        ema_period: int = 12,
    ):
        """
        Initialize feature engineer with indicator parameters

        Args:
            rsi_period: RSI calculation period
            macd_fast: MACD fast EMA period
            macd_slow: MACD slow EMA period
            macd_signal: MACD signal line period
            bb_period: Bollinger Bands period
            bb_std: Bollinger Bands standard deviation multiplier
            sma_period: Simple Moving Average period
            ema_period: Exponential Moving Average period
        """
        self.rsi_period = rsi_period
        self.macd_fast = macd_fast
        self.macd_slow = macd_slow
        self.macd_signal = macd_signal
        self.bb_period = bb_period
        self.bb_std = bb_std
        self.sma_period = sma_period
        self.ema_period = ema_period

    def add_indicators(self, df: pl.DataFrame) -> pl.DataFrame:
        """
        Add technical indicators to DataFrame

        Args:
            df: Polars DataFrame with OHLCV columns

        Returns:
            DataFrame with added indicator columns

        Indicators added:
        - rsi: Relative Strength Index
        - macd: MACD line
        - macd_signal: MACD signal line
        - bb_upper, bb_middle, bb_lower: Bollinger Bands
        - sma_{period}: Simple Moving Average
        - ema_{period}: Exponential Moving Average

        Notes:
        - Uses ta library (requires Pandas conversion)
        - Drops rows with NaN values after calculation
        """
        # Step 1: Polars native indicators (fast)
        df = df.with_columns(
            [
                # SMA
                pl.col("close_price")
                .rolling_mean(self.sma_period)
                .alias(f"sma_{self.sma_period}"),
                # EMA
                pl.col("close_price")
                .ewm_mean(span=self.ema_period, adjust=False)
                .alias(f"ema_{self.ema_period}"),
                # Bollinger Bands middle (same as SMA)
                pl.col("close_price")
                .rolling_mean(self.bb_period)
                .alias("bb_middle"),
                # Bollinger Bands std
                pl.col("close_price").rolling_std(self.bb_period).alias("bb_std"),
            ]
        )

        # Calculate Bollinger upper/lower
        df = df.with_columns(
            [
                (pl.col("bb_middle") + pl.col("bb_std") * self.bb_std).alias(
                    "bb_upper"
                ),
                (pl.col("bb_middle") - pl.col("bb_std") * self.bb_std).alias(
                    "bb_lower"
                ),
            ]
        )

        # Drop temporary bb_std column
        df = df.drop("bb_std")

        # Step 2: ta library indicators (requires Pandas)
        # Convert to Pandas for ta library
        df_pd = df.to_pandas()

        # RSI
        rsi_indicator = ta.momentum.RSIIndicator(
            close=df_pd["close_price"], window=self.rsi_period
        )
        df_pd["rsi"] = rsi_indicator.rsi()

        # MACD
        macd_indicator = ta.trend.MACD(
            close=df_pd["close_price"],
            window_fast=self.macd_fast,
            window_slow=self.macd_slow,
            window_sign=self.macd_signal,
        )
        df_pd["macd"] = macd_indicator.macd()
        df_pd["macd_signal"] = macd_indicator.macd_signal()
        df_pd["macd_diff"] = macd_indicator.macd_diff()

        # Convert back to Polars
        df = pl.from_pandas(df_pd)

        # Step 3: Drop NaN rows (from rolling calculations)
        # CRITICAL: Ensures no NaN in feature vectors
        df = df.drop_nulls()

        return df

    def normalize_zscore(
        self, df: pl.DataFrame, columns: List[str] | None = None
    ) -> pl.DataFrame:
        """
        Apply Z-Score normalization to specified columns

        Formula: (x - mean) / std

        Args:
            df: Input DataFrame
            columns: Columns to normalize (default: OHLCV + indicators)

        Returns:
            DataFrame with additional normalized columns (suffix: _norm)

        Notes:
        - Z-Score is better for financial data than Min-Max
        - Handles outliers better
        - Preserves distribution shape
        """
        if columns is None:
            # Default: normalize OHLCV
            columns = ["open_price", "high_price", "low_price", "close_price", "volume"]

        norm_exprs = []
        for col in columns:
            # Z-Score: (x - mean) / (std + epsilon)
            # Add small epsilon to avoid division by zero
            norm_expr = (
                (pl.col(col) - pl.col(col).mean()) / (pl.col(col).std() + 1e-8)
            ).alias(f"{col}_norm")
            norm_exprs.append(norm_expr)

        df = df.with_columns(norm_exprs)

        return df

    def extract_feature_vector(
        self, df: pl.DataFrame, indicators: List[str] | None = None
    ) -> pl.DataFrame:
        """
        Extract feature vector for machine learning

        Args:
            df: DataFrame with normalized OHLCV and indicators
            indicators: Indicator columns to include

        Returns:
            DataFrame with only feature columns

        Default features (10 total):
        - 5 normalized OHLCV
        - 5 indicators (RSI, MACD, Bollinger upper, SMA, EMA)

        Notes:
        - All values must be non-NaN (checked with assertion)
        - Feature order matters for PCA/embedding
        """
        if indicators is None:
            # Default indicator set (from Idris2 spec)
            indicators = [
                "rsi",
                "macd",
                "bb_upper",
                f"sma_{self.sma_period}",
                f"ema_{self.ema_period}",
            ]

        # Feature columns
        feature_cols = [
            "open_price_norm",
            "high_price_norm",
            "low_price_norm",
            "close_price_norm",
            "volume_norm",
        ] + indicators

        # Select features
        features = df.select(feature_cols)

        # CRITICAL: Verify no NaN (FeatureVector guarantee from spec)
        null_count = features.null_count().sum_horizontal().sum()
        if null_count > 0:
            raise ValueError(
                f"Features contain {null_count} NaN values! "
                "This violates the FeatureVector no-NaN guarantee."
            )

        return features

    def engineer_window(self, window: pl.DataFrame) -> pl.DataFrame:
        """
        Complete feature engineering pipeline for a single window

        Args:
            window: Window DataFrame (60-120 candles)

        Returns:
            Feature DataFrame (shape: [n_candles, n_features])

        Pipeline:
        1. Add technical indicators
        2. Normalize OHLCV with Z-Score
        3. Extract feature vector
        4. Verify no NaN

        Example:
            60 candles × 10 features = 600 dimensions
        """
        # Step 1: Add indicators
        df = self.add_indicators(window)

        # Step 2: Normalize
        df = self.normalize_zscore(df)

        # Step 3: Extract features
        features = self.extract_feature_vector(df)

        return features

    def get_feature_dimension(self) -> int:
        """
        Get total feature dimension

        Returns:
            Number of features per candle

        Example: 5 (OHLCV) + 5 (indicators) = 10
        """
        return 10  # Default: 5 OHLCV + 5 indicators

    def flatten_window_features(self, features: pl.DataFrame) -> List[float]:
        """
        Flatten 2D window features into 1D vector

        Args:
            features: [n_candles, n_features] DataFrame

        Returns:
            Flattened list of floats

        Example:
            Input: [60 candles, 10 features]
            Output: [600 floats]

        Notes:
        - Row-major order (candle1_feat1, candle1_feat2, ..., candle2_feat1, ...)
        - Used for PCA/embedding input
        """
        # Convert to numpy and flatten
        arr = features.to_numpy()
        return arr.flatten().tolist()


# Example usage (for documentation):
# engineer = FeatureEngineer(rsi_period=14, macd_fast=12, macd_slow=26)
# features = engineer.engineer_window(window_df)
# vector = engineer.flatten_window_features(features)  # 600-dim vector
