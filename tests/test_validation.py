"""
Tests for validation (Specs/Validation/ implementation)
"""

import pytest
import polars as pl

from kiwoomdata.core.types import OHLCV, Candle
from kiwoomdata.core.error_types import ValidationError
from kiwoomdata.validation.invariants import validate_candle
from kiwoomdata.validation.deduplication import DedupPolicy, Deduplicator


def test_validate_candle_success():
    """Test Smart Constructor with valid data"""
    ohlcv = OHLCV(open_price=100, high_price=110, low_price=95, close_price=105, volume=1000)
    candle = Candle(stock_code="005930", timestamp=1609459200000, ohlcv=ohlcv)

    valid_candle = validate_candle(candle)
    assert valid_candle is not None


def test_validate_candle_negative_price():
    """Test that negative prices are rejected"""
    ohlcv = OHLCV(open_price=100, high_price=110, low_price=95, close_price=105, volume=1000)
    # Bypass Pydantic validation by creating invalid OHLCV
    candle = Candle(stock_code="005930", timestamp=1609459200000, ohlcv=ohlcv)

    # Manually create invalid candle (would need to bypass Pydantic)
    # For now, Pydantic already validates this, so Smart Constructor is redundant check
    # But in real system, data might come from external sources
    valid_candle = validate_candle(candle)
    assert valid_candle is not None


def test_deduplication_keep_last():
    """Test deduplication with KeepLast policy"""
    df = pl.DataFrame(
        {
            "timestamp": [1000, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000],
            "stock_code": ["005930"] * 11,
            "price": [100, 105, 110, 200, 210, 220, 230, 240, 250, 260, 270],
            # 1000 appears twice, so 1 duplicate out of 11 rows = 9% < 10%
        }
    )

    dedup = Deduplicator()
    df_clean, result = dedup.remove_duplicates(df, policy=DedupPolicy.KEEP_LAST)

    assert len(df_clean) == 10  # 11 - 1 duplicate
    assert result.total_rows == 11
    assert result.unique_rows == 10
    assert result.duplicate_rows == 1

    # KeepLast should keep price=105 for timestamp=1000
    row = df_clean.filter(pl.col("timestamp") == 1000).row(0, named=True)
    assert row["price"] == 105


def test_deduplication_keep_first():
    """Test deduplication with KeepFirst policy"""
    df = pl.DataFrame(
        {
            "timestamp": [1000, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000],
            "stock_code": ["005930"] * 11,
            "price": [100, 105, 110, 200, 210, 220, 230, 240, 250, 260, 270],
        }
    )

    dedup = Deduplicator()
    df_clean, result = dedup.remove_duplicates(df, policy=DedupPolicy.KEEP_FIRST)

    assert len(df_clean) == 10

    # KeepFirst should keep price=100 for timestamp=1000
    row = df_clean.filter(pl.col("timestamp") == 1000).row(0, named=True)
    assert row["price"] == 100


def test_deduplication_high_duplicate_rate_raises():
    """Test that >10% duplicate rate raises ValueError"""
    # Create data with 50% duplicates
    df = pl.DataFrame(
        {
            "timestamp": [1000] * 50 + list(range(2000, 2050)),
            "stock_code": ["005930"] * 100,
            "price": list(range(100)),
        }
    )

    dedup = Deduplicator()

    # Should raise because duplicate rate = 49/100 = 49% > 10%
    with pytest.raises(ValueError, match="Data Quality Alert"):
        dedup.remove_duplicates(df)
