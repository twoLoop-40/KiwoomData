"""
Time-related types - Implementation of Specs/Core/TimeTypes.idr
"""

from enum import Enum

from pydantic import BaseModel, ConfigDict, Field


class Timeframe(str, Enum):
    """
    Candlestick timeframe
    Idris: data Timeframe = Tick | Min1 | Min5 | Min10 | Min60 | Daily
    """

    TICK = "tick"
    MIN1 = "1min"
    MIN5 = "5min"
    MIN10 = "10min"
    MIN60 = "60min"
    DAILY = "daily"

    def to_minutes(self) -> int:
        """
        Convert timeframe to minutes
        Idris: timeframeToMinutes : Timeframe -> Nat
        """
        mapping = {
            Timeframe.TICK: 0,
            Timeframe.MIN1: 1,
            Timeframe.MIN5: 5,
            Timeframe.MIN10: 10,
            Timeframe.MIN60: 60,
            Timeframe.DAILY: 1440,  # 24 * 60
        }
        return mapping[self]


class WindowSize(str, Enum):
    """
    Sliding window size (for vector embedding)
    Idris: data WindowSize = Small | Medium | Large
    """

    SMALL = "small"  # 60 candles (10 hours for 10-min candles)
    MEDIUM = "medium"  # 90 candles (15 hours)
    LARGE = "large"  # 120 candles (20 hours)

    def to_nat(self) -> int:
        """
        Convert to number of candles
        Idris: windowSizeToNat : WindowSize -> Nat
        """
        mapping = {
            WindowSize.SMALL: 60,
            WindowSize.MEDIUM: 90,
            WindowSize.LARGE: 120,
        }
        return mapping[self]


class DateRange(BaseModel):
    """
    Date range for data collection
    Idris: record DateRange where
        startDate : Integer  -- Unix timestamp
        endDate : Integer    -- Unix timestamp
    """

    start_date: int = Field(..., description="Start date (Unix timestamp in ms)")
    end_date: int = Field(..., description="End date (Unix timestamp in ms)")

    def validate_range(self) -> bool:
        """Ensure start_date < end_date"""
        return self.start_date < self.end_date

    model_config = ConfigDict(frozen=True)


class SlidingWindowConfig(BaseModel):
    """
    Sliding window configuration
    Idris: record SlidingWindowConfig where
        size : WindowSize
        stride : Nat
        timeframe : Timeframe
    """

    size: WindowSize = Field(..., description="Window size (Small/Medium/Large)")
    stride: int = Field(1, ge=1, description="Window stride (default 1)")
    timeframe: Timeframe = Field(..., description="Candlestick timeframe")

    model_config = ConfigDict(frozen=True)


class TradingHours(BaseModel):
    """
    Trading hours definition (Korean stock market)
    Idris: record TradingHours where
        openTime : (Nat, Nat)    -- (9, 0)
        closeTime : (Nat, Nat)   -- (15, 30)
    """

    open_hour: int = Field(..., ge=0, le=23, description="Opening hour (0-23)")
    open_minute: int = Field(..., ge=0, le=59, description="Opening minute (0-59)")
    close_hour: int = Field(..., ge=0, le=23, description="Closing hour (0-23)")
    close_minute: int = Field(..., ge=0, le=59, description="Closing minute (0-59)")

    model_config = ConfigDict(frozen=True)


# Korean market default trading hours (09:00 - 15:30)
# Idris: koreanMarketHours : TradingHours
KOREAN_MARKET_HOURS = TradingHours(
    open_hour=9, open_minute=0, close_hour=15, close_minute=30
)


def candles_per_day(timeframe: Timeframe) -> int:
    """
    Number of candles per trading day
    Idris: candlesPerDay : Timeframe -> Nat

    Korean market: 09:00 - 15:30 = 390 minutes
    """
    trading_minutes = 390  # 6.5 hours

    if timeframe == Timeframe.MIN10:
        return 39  # 390 / 10
    elif timeframe == Timeframe.MIN1:
        return 390
    elif timeframe == Timeframe.DAILY:
        return 1
    else:
        # Generic calculation
        tf_minutes = timeframe.to_minutes()
        if tf_minutes == 0:
            return 0  # Tick data
        return trading_minutes // tf_minutes
