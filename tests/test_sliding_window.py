"""
Tests for Sliding Window Extractor

Validates Vect-like guarantees and continuity checks
"""

from datetime import datetime, timedelta

import polars as pl
import pytest

from kiwoomdata.vector import (
    WindowConfig,
    VectorWindowSize,
    SlidingWindowExtractor,
)
from kiwoomdata.utils import SampleDataGenerator
from kiwoomdata.core.time_types import Timeframe


class TestSlidingWindow:
    """Test sliding window extraction with type guarantees"""

    def test_window_config_creation(self):
        """Test WindowConfig creation from enum"""
        config = WindowConfig.from_window_size(
            VectorWindowSize.SMALL,
            timeframe="10min",
            interval_seconds=600,
        )

        assert config.size == 60
        assert config.timeframe == "10min"
        assert config.interval_seconds == 600
        assert config.stride == 1

    def test_window_size_guarantee(self):
        """Test that all windows have exactly the specified size (Vect n)"""
        # Generate continuous data
        generator = SampleDataGenerator(seed=42)
        candles = generator.generate_candles(
            stock_code="005930",
            start_date=datetime(2024, 1, 1, 9, 0),
            count=100,
            timeframe=Timeframe.MIN10,
        )

        # Convert to Polars DataFrame
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

        # Extract windows
        config = WindowConfig(size=60, stride=1, interval_seconds=600)
        extractor = SlidingWindowExtractor(config)

        windows = list(extractor.extract_windows(df))

        # All windows must have exactly size 60
        assert all(len(w) == 60 for w in windows)

        # Should have 41 windows (100 - 60 + 1)
        assert len(windows) == 41

    def test_continuity_check(self):
        """Test that discontinuous windows are rejected"""
        # Create data with a gap
        timestamps = []
        base_time = int(datetime(2024, 1, 1, 9, 0).timestamp() * 1000)

        # First 30 candles (continuous)
        for i in range(30):
            timestamps.append(base_time + i * 600_000)  # 10 minutes = 600,000 ms

        # GAP: Skip 10 candles (1 hour 40 minutes)

        # Next 30 candles (continuous)
        for i in range(40, 70):  # Skip 30-39
            timestamps.append(base_time + i * 600_000)

        df = pl.DataFrame(
            {
                "timestamp": timestamps,
                "stock_code": ["005930"] * 60,
                "open_price": [100.0] * 60,
                "high_price": [101.0] * 60,
                "low_price": [99.0] * 60,
                "close_price": [100.5] * 60,
                "volume": [1000] * 60,
            }
        )

        # Extract windows (size 60)
        config = WindowConfig(size=60, stride=1, interval_seconds=600)
        extractor = SlidingWindowExtractor(config)

        windows = list(extractor.extract_windows(df))

        # Should get 0 windows because there's a gap in the middle
        # (any 60-candle window will span the gap)
        assert len(windows) == 0

    def test_stride_parameter(self):
        """Test stride parameter for overlapping windows"""
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
            }
        )

        # Stride = 10 (every 10th candle)
        config = WindowConfig(size=60, stride=10, interval_seconds=600)
        extractor = SlidingWindowExtractor(config)

        windows = list(extractor.extract_windows(df))

        # With stride=10: (100 - 60) / 10 + 1 = 5 windows
        assert len(windows) == 5

        # Verify windows don't overlap too much
        # First window starts at index 0, second at index 10, etc.
        first_window = windows[0]
        second_window = windows[1]

        # First timestamp of second window should be 10 candles later
        diff = second_window["timestamp"][0] - first_window["timestamp"][0]
        expected_diff = 10 * 600_000  # 10 candles × 10 minutes
        assert diff == expected_diff

    def test_extract_windows_per_stock(self):
        """Test window extraction for multiple stocks"""
        generator = SampleDataGenerator(seed=456)

        # Generate data for 2 stocks
        candles1 = generator.generate_candles(
            stock_code="005930",
            start_date=datetime(2024, 1, 1, 9, 0),
            count=80,
            timeframe=Timeframe.MIN10,
        )

        candles2 = generator.generate_candles(
            stock_code="000660",
            start_date=datetime(2024, 1, 1, 9, 0),
            count=90,
            timeframe=Timeframe.MIN10,
        )

        all_candles = candles1 + candles2

        df = pl.DataFrame(
            {
                "timestamp": [c.timestamp for c in all_candles],
                "stock_code": [c.stock_code for c in all_candles],
                "open_price": [c.ohlcv.open_price for c in all_candles],
            }
        )

        # Extract windows per stock
        config = WindowConfig(size=60, stride=1, interval_seconds=600)
        extractor = SlidingWindowExtractor(config)

        windows_by_stock = extractor.extract_windows_per_stock(df)

        # Should have 2 stocks
        assert len(windows_by_stock) == 2
        assert "005930" in windows_by_stock
        assert "000660" in windows_by_stock

        # Stock 005930: 80 - 60 + 1 = 21 windows
        assert len(windows_by_stock["005930"]) == 21

        # Stock 000660: 90 - 60 + 1 = 31 windows
        assert len(windows_by_stock["000660"]) == 31

        # Each window should only contain one stock
        for windows in windows_by_stock.values():
            for window in windows:
                assert window["stock_code"].n_unique() == 1

    def test_window_stats(self):
        """Test window statistics calculation"""
        generator = SampleDataGenerator(seed=789)
        candles = generator.generate_candles(
            stock_code="005930",
            start_date=datetime(2024, 1, 1, 9, 0),
            count=200,
            timeframe=Timeframe.MIN10,
        )

        df = pl.DataFrame(
            {
                "timestamp": [c.timestamp for c in candles],
                "stock_code": [c.stock_code for c in candles],
            }
        )

        config = WindowConfig(size=60, stride=1, interval_seconds=600)
        extractor = SlidingWindowExtractor(config)

        stats = extractor.get_window_stats(df)

        assert stats["total_candles"] == 200
        assert stats["window_size"] == 60
        assert stats["stride"] == 1
        assert stats["max_possible_windows"] == 141  # 200 - 60 + 1

    def test_empty_dataframe(self):
        """Test behavior with empty DataFrame"""
        df = pl.DataFrame(
            {
                "timestamp": [],
                "stock_code": [],
                "open_price": [],
            }
        )

        config = WindowConfig(size=60)
        extractor = SlidingWindowExtractor(config)

        windows = list(extractor.extract_windows(df))
        assert len(windows) == 0

        stats = extractor.get_window_stats(df)
        assert stats["total_candles"] == 0
        assert stats["max_possible_windows"] == 0

    def test_small_dataframe(self):
        """Test behavior when DataFrame is smaller than window size"""
        generator = SampleDataGenerator(seed=999)
        candles = generator.generate_candles(
            stock_code="005930",
            start_date=datetime(2024, 1, 1, 9, 0),
            count=30,  # Less than window size (60)
            timeframe=Timeframe.MIN10,
        )

        df = pl.DataFrame(
            {
                "timestamp": [c.timestamp for c in candles],
                "stock_code": [c.stock_code for c in candles],
            }
        )

        config = WindowConfig(size=60)
        extractor = SlidingWindowExtractor(config)

        windows = list(extractor.extract_windows(df))
        assert len(windows) == 0  # Not enough data

        stats = extractor.get_window_stats(df)
        assert stats["max_possible_windows"] == 0

    def test_vector_window_sizes(self):
        """Test all VectorWindowSize enum values"""
        for size_enum in VectorWindowSize:
            config = WindowConfig.from_window_size(size_enum)

            assert config.size == size_enum.value

            if size_enum == VectorWindowSize.SMALL:
                assert config.size == 60
            elif size_enum == VectorWindowSize.MEDIUM:
                assert config.size == 90
            elif size_enum == VectorWindowSize.LARGE:
                assert config.size == 120
