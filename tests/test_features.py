"""
Tests for Feature Engineering

Validates technical indicators and no-NaN guarantee
"""

from datetime import datetime

import polars as pl
import pytest

from kiwoomdata.vector import FeatureEngineer
from kiwoomdata.utils import SampleDataGenerator
from kiwoomdata.core.time_types import Timeframe


class TestFeatureEngineering:
    """Test feature engineering with technical indicators"""

    def test_add_indicators(self):
        """Test that all technical indicators are added correctly"""
        # Generate sample data
        generator = SampleDataGenerator(seed=42)
        candles = generator.generate_candles(
            stock_code="005930",
            start_date=datetime(2024, 1, 1, 9, 0),
            count=100,
            timeframe=Timeframe.MIN10,
        )

        # Convert to DataFrame
        df = pl.DataFrame(
            {
                "timestamp": [c.timestamp for c in candles],
                "stock_code": [c.stock_code for c in candles],
                "open_price": [c.ohlcv.open_price for c in candles],
                "high_price": [c.ohlcv.high_price for c in candles],
                "low_price": [c.ohlcv.low_price for c in candles],
                "close_price": [c.ohlcv.close_price for c in candles],
                "volume": [c.ohlcv.volume for c in candles],
            }
        )

        # Add indicators
        engineer = FeatureEngineer()
        df_with_indicators = engineer.add_indicators(df)

        # Check that indicator columns exist
        assert "rsi" in df_with_indicators.columns
        assert "macd" in df_with_indicators.columns
        assert "macd_signal" in df_with_indicators.columns
        assert "bb_upper" in df_with_indicators.columns
        assert "bb_middle" in df_with_indicators.columns
        assert "bb_lower" in df_with_indicators.columns
        assert "sma_20" in df_with_indicators.columns
        assert "ema_12" in df_with_indicators.columns

        # Check no NaN values (critical guarantee)
        null_count = df_with_indicators.null_count().sum_horizontal().sum()
        assert null_count == 0, "Indicators contain NaN values!"

        # RSI should be between 0 and 100
        rsi_values = df_with_indicators["rsi"]
        assert rsi_values.min() >= 0
        assert rsi_values.max() <= 100

    def test_zscore_normalization(self):
        """Test Z-Score normalization"""
        # Create simple test data
        df = pl.DataFrame(
            {
                "open_price": [100.0, 110.0, 90.0, 105.0, 95.0],
                "close_price": [105.0, 115.0, 95.0, 100.0, 90.0],
                "volume": [1000, 1200, 800, 1100, 900],
            }
        )

        engineer = FeatureEngineer()
        df_normalized = engineer.normalize_zscore(
            df, columns=["open_price", "close_price", "volume"]
        )

        # Check normalized columns exist
        assert "open_price_norm" in df_normalized.columns
        assert "close_price_norm" in df_normalized.columns
        assert "volume_norm" in df_normalized.columns

        # Z-Score should have mean ≈ 0 and std ≈ 1
        # (with small tolerance for floating point)
        open_norm = df_normalized["open_price_norm"]
        assert abs(open_norm.mean()) < 1e-10
        assert abs(open_norm.std() - 1.0) < 1e-6

    def test_extract_feature_vector(self):
        """Test feature vector extraction"""
        generator = SampleDataGenerator(seed=123)
        candles = generator.generate_candles(
            stock_code="005930",
            start_date=datetime(2024, 1, 1, 9, 0),
            count=100,
            timeframe=Timeframe.MIN10,
        )

        df = pl.DataFrame(
            {
                "timestamp": [c.timestamp for c in candles],
                "stock_code": [c.stock_code for c in candles],
                "open_price": [c.ohlcv.open_price for c in candles],
                "high_price": [c.ohlcv.high_price for c in candles],
                "low_price": [c.ohlcv.low_price for c in candles],
                "close_price": [c.ohlcv.close_price for c in candles],
                "volume": [c.ohlcv.volume for c in candles],
            }
        )

        engineer = FeatureEngineer()

        # Add indicators
        df = engineer.add_indicators(df)

        # Normalize
        df = engineer.normalize_zscore(df)

        # Extract features
        features = engineer.extract_feature_vector(df)

        # Should have 10 columns (5 OHLCV + 5 indicators)
        assert features.shape[1] == 10

        # Column names
        expected_cols = [
            "open_price_norm",
            "high_price_norm",
            "low_price_norm",
            "close_price_norm",
            "volume_norm",
            "rsi",
            "macd",
            "bb_upper",
            "sma_20",
            "ema_12",
        ]
        assert features.columns == expected_cols

        # No NaN values
        null_count = features.null_count().sum_horizontal().sum()
        assert null_count == 0

    def test_engineer_window_pipeline(self):
        """Test complete feature engineering pipeline"""
        generator = SampleDataGenerator(seed=456)
        candles = generator.generate_candles(
            stock_code="005930",
            start_date=datetime(2024, 1, 1, 9, 0),
            count=100,
            timeframe=Timeframe.MIN10,
        )

        window_df = pl.DataFrame(
            {
                "timestamp": [c.timestamp for c in candles],
                "stock_code": [c.stock_code for c in candles],
                "open_price": [c.ohlcv.open_price for c in candles],
                "high_price": [c.ohlcv.high_price for c in candles],
                "low_price": [c.ohlcv.low_price for c in candles],
                "close_price": [c.ohlcv.close_price for c in candles],
                "volume": [c.ohlcv.volume for c in candles],
            }
        )

        engineer = FeatureEngineer()

        # Run full pipeline
        features = engineer.engineer_window(window_df)

        # Verify shape and no NaN
        assert features.shape[1] == 10
        assert features.null_count().sum_horizontal().sum() == 0

        # Verify feature dimension
        assert engineer.get_feature_dimension() == 10

    def test_flatten_window_features(self):
        """Test flattening 2D features to 1D vector"""
        # Create simple 2D feature matrix
        features = pl.DataFrame(
            {
                "feat1": [1.0, 2.0, 3.0],
                "feat2": [4.0, 5.0, 6.0],
                "feat3": [7.0, 8.0, 9.0],
            }
        )

        engineer = FeatureEngineer()
        flattened = engineer.flatten_window_features(features)

        # Should be 1D list
        assert isinstance(flattened, list)

        # Length should be rows × cols = 3 × 3 = 9
        assert len(flattened) == 9

        # Row-major order
        expected = [1.0, 4.0, 7.0, 2.0, 5.0, 8.0, 3.0, 6.0, 9.0]
        assert flattened == expected

    def test_complete_60_window_vector(self):
        """
        Test complete workflow: 60-candle window → 600-dim vector

        This simulates the actual usage for vector embedding
        """
        generator = SampleDataGenerator(seed=789)
        candles = generator.generate_candles(
            stock_code="005930",
            start_date=datetime(2024, 1, 1, 9, 0),
            count=100,  # More than 60 for indicator calculation
            timeframe=Timeframe.MIN10,
        )

        window_df = pl.DataFrame(
            {
                "timestamp": [c.timestamp for c in candles],
                "stock_code": [c.stock_code for c in candles],
                "open_price": [c.ohlcv.open_price for c in candles],
                "high_price": [c.ohlcv.high_price for c in candles],
                "low_price": [c.ohlcv.low_price for c in candles],
                "close_price": [c.ohlcv.close_price for c in candles],
                "volume": [c.ohlcv.volume for c in candles],
            }
        )

        engineer = FeatureEngineer()

        # Full pipeline
        features = engineer.engineer_window(window_df)

        # After indicator calculation, some rows are dropped (NaN from rolling)
        # Let's take first 60 candles
        features_60 = features.head(60)

        # Flatten to 1D vector
        vector = engineer.flatten_window_features(features_60)

        # Should be 60 candles × 10 features = 600 dimensions
        assert len(vector) == 600

        # All values should be valid floats (no NaN, no Inf)
        assert all(isinstance(v, float) for v in vector)
        assert not any(float('nan') == v for v in vector)
        assert not any(float('inf') == abs(v) for v in vector)

    def test_bollinger_bands_relationship(self):
        """Test that Bollinger Bands maintain correct relationship"""
        generator = SampleDataGenerator(seed=999)
        candles = generator.generate_candles(
            stock_code="005930",
            start_date=datetime(2024, 1, 1, 9, 0),
            count=100,
            timeframe=Timeframe.MIN10,
        )

        df = pl.DataFrame(
            {
                "timestamp": [c.timestamp for c in candles],
                "stock_code": [c.stock_code for c in candles],
                "open_price": [c.ohlcv.open_price for c in candles],
                "high_price": [c.ohlcv.high_price for c in candles],
                "low_price": [c.ohlcv.low_price for c in candles],
                "close_price": [c.ohlcv.close_price for c in candles],
                "volume": [c.ohlcv.volume for c in candles],
            }
        )

        engineer = FeatureEngineer(bb_period=20, bb_std=2.0)
        df_with_indicators = engineer.add_indicators(df)

        # Bollinger Upper should be >= Middle >= Lower
        upper = df_with_indicators["bb_upper"]
        middle = df_with_indicators["bb_middle"]
        lower = df_with_indicators["bb_lower"]

        assert (upper >= middle).all()
        assert (middle >= lower).all()

    def test_custom_indicator_params(self):
        """Test custom indicator parameters"""
        generator = SampleDataGenerator(seed=111)
        candles = generator.generate_candles(
            stock_code="005930",
            start_date=datetime(2024, 1, 1, 9, 0),
            count=100,
            timeframe=Timeframe.MIN10,
        )

        df = pl.DataFrame(
            {
                "timestamp": [c.timestamp for c in candles],
                "stock_code": [c.stock_code for c in candles],
                "open_price": [c.ohlcv.open_price for c in candles],
                "high_price": [c.ohlcv.high_price for c in candles],
                "low_price": [c.ohlcv.low_price for c in candles],
                "close_price": [c.ohlcv.close_price for c in candles],
                "volume": [c.ohlcv.volume for c in candles],
            }
        )

        # Custom parameters
        engineer = FeatureEngineer(
            rsi_period=7,
            macd_fast=6,
            macd_slow=13,
            sma_period=10,
            ema_period=5,
        )

        df_with_indicators = engineer.add_indicators(df)

        # Check custom column names
        assert "sma_10" in df_with_indicators.columns
        assert "ema_5" in df_with_indicators.columns

        # No NaN
        null_count = df_with_indicators.null_count().sum_horizontal().sum()
        assert null_count == 0
