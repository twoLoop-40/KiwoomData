"""
Core types module - Specs/Core/Types.idr implementation
"""

from .types import (
    Market,
    OHLCV,
    Stock,
    Candle,
    TechnicalIndicators,
    MarketDataPoint,
    StockCode,
)
from .time_types import (
    Timeframe,
    DateRange,
    WindowSize,
    SlidingWindowConfig,
    TradingHours,
    KOREAN_MARKET_HOURS,
)
from .error_types import (
    KiwoomError,
    APIError,
    ValidationError,
    NetworkError,
    DatabaseError,
)

__all__ = [
    # Types
    "Market",
    "OHLCV",
    "Stock",
    "Candle",
    "TechnicalIndicators",
    "MarketDataPoint",
    "StockCode",
    # Time Types
    "Timeframe",
    "DateRange",
    "WindowSize",
    "SlidingWindowConfig",
    "TradingHours",
    "KOREAN_MARKET_HOURS",
    # Error Types
    "KiwoomError",
    "APIError",
    "ValidationError",
    "NetworkError",
    "DatabaseError",
]
