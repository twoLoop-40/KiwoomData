"""
Tests for core types (Specs/Core/Types.idr implementation)
"""

import pytest
from pydantic import ValidationError as PydanticValidationError

from kiwoomdata.core.types import OHLCV, Candle, Market, Stock


def test_ohlcv_valid():
    """Test valid OHLCV creation"""
    ohlcv = OHLCV(open_price=100, high_price=110, low_price=95, close_price=105, volume=1000)
    assert ohlcv.open_price == 100
    assert ohlcv.high_price == 110
    assert ohlcv.low_price == 95
    assert ohlcv.close_price == 105
    assert ohlcv.volume == 1000


def test_ohlcv_high_validation():
    """Test that high price must be >= max(open, close)"""
    # Should fail: high=100 < max(open=105, close=110)=110
    with pytest.raises(PydanticValidationError) as exc_info:
        OHLCV(open_price=105, high_price=100, low_price=95, close_price=110, volume=1000)
    assert "High price" in str(exc_info.value)


def test_ohlcv_low_validation():
    """Test that low price must be <= min(open, close)"""
    # Should fail: low=110 > min(open=105, close=100)=100
    with pytest.raises(PydanticValidationError) as exc_info:
        OHLCV(open_price=105, high_price=115, low_price=110, close_price=100, volume=1000)
    assert "Low price" in str(exc_info.value)


def test_ohlcv_positive_prices():
    """Test that all prices must be positive"""
    with pytest.raises(PydanticValidationError):
        OHLCV(open_price=-100, high_price=110, low_price=95, close_price=105, volume=1000)


def test_stock_code_pattern():
    """Test that stock code must be 6 digits"""
    stock = Stock(code="005930", name="삼성전자", market=Market.KOSPI)
    assert stock.code == "005930"

    # Invalid: not 6 digits
    with pytest.raises(PydanticValidationError):
        Stock(code="12345", name="Invalid", market=Market.KOSPI)


def test_candle_creation():
    """Test candle creation with valid data"""
    ohlcv = OHLCV(open_price=100, high_price=110, low_price=95, close_price=105, volume=1000)
    candle = Candle(stock_code="005930", timestamp=1609459200000, ohlcv=ohlcv)

    assert candle.stock_code == "005930"
    assert candle.timestamp == 1609459200000
    assert candle.ohlcv.open_price == 100
