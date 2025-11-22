"""
Core data types - Implementation of Specs/Core/Types.idr

Maps Idris2 types to Python/Pydantic models with validation.
"""

from datetime import datetime
from enum import Enum
from typing import NewType

from pydantic import BaseModel, ConfigDict, Field, model_validator

# Type alias for stock code (6-digit string)
# Idris: StockCode : Type = String
StockCode = NewType("StockCode", str)


class Market(str, Enum):
    """
    Market classification
    Idris: data Market = KOSPI | KOSDAQ
    """

    KOSPI = "KOSPI"
    KOSDAQ = "KOSDAQ"


class OHLCV(BaseModel):
    """
    OHLCV candlestick data
    Idris: record OHLCV where
        openPrice : Double
        highPrice : Double
        lowPrice : Double
        closePrice : Double
        volume : Nat
    """

    open_price: float = Field(..., gt=0, description="Opening price (must be > 0)")
    high_price: float = Field(..., gt=0, description="High price (must be > 0)")
    low_price: float = Field(..., gt=0, description="Low price (must be > 0)")
    close_price: float = Field(..., gt=0, description="Closing price (must be > 0)")
    volume: int = Field(..., ge=0, description="Trading volume (must be >= 0)")

    @model_validator(mode="after")
    def validate_ohlcv_invariants(self) -> "OHLCV":
        """Validate OHLCV invariants with epsilon tolerance"""
        epsilon = 1e-6

        # High >= max(open, close)
        max_oc = max(self.open_price, self.close_price)
        if self.high_price < max_oc - epsilon:
            raise ValueError(
                f"High price {self.high_price} must be >= "
                f"max(open={self.open_price}, close={self.close_price})={max_oc}"
            )

        # Low <= min(open, close)
        min_oc = min(self.open_price, self.close_price)
        if self.low_price > min_oc + epsilon:
            raise ValueError(
                f"Low price {self.low_price} must be <= "
                f"min(open={self.open_price}, close={self.close_price})={min_oc}"
            )

        return self

    model_config = ConfigDict(frozen=True)  # Immutable (like Idris records)


class Stock(BaseModel):
    """
    Stock information
    Idris: record Stock where
        code : StockCode
        name : String
        market : Market
    """

    code: str = Field(..., pattern=r"^\d{6}$", description="6-digit stock code")
    name: str = Field(..., min_length=1, description="Stock name")
    market: Market = Field(..., description="Market classification (KOSPI/KOSDAQ)")

    model_config = ConfigDict(frozen=True)


class Candle(BaseModel):
    """
    Candlestick data (single timeframe)
    Idris: record Candle where
        stock : StockCode
        timestamp : Integer  -- Unix timestamp
        ohlcv : OHLCV
    """

    stock_code: str = Field(..., pattern=r"^\d{6}$", description="6-digit stock code")
    timestamp: int = Field(..., description="Unix timestamp in milliseconds")
    ohlcv: OHLCV = Field(..., description="OHLCV data")

    @property
    def datetime(self) -> datetime:
        """Convert Unix timestamp (ms) to datetime"""
        return datetime.fromtimestamp(self.timestamp / 1000)

    model_config = ConfigDict(frozen=True)


class TechnicalIndicators(BaseModel):
    """
    Technical indicators (RSI, MACD, Bollinger Bands, etc.)
    Idris: record TechnicalIndicators where
        rsi : Maybe Double
        macd : Maybe Double
        macd_signal : Maybe Double
        bb_upper : Maybe Double
        bb_lower : Maybe Double
    """

    rsi: float | None = Field(None, ge=0, le=100, description="RSI (0-100)")
    macd: float | None = Field(None, description="MACD value")
    macd_signal: float | None = Field(None, description="MACD signal line")
    bb_upper: float | None = Field(None, description="Bollinger Band upper")
    bb_lower: float | None = Field(None, description="Bollinger Band lower")

    model_config = ConfigDict(frozen=True)


class MarketDataPoint(BaseModel):
    """
    Complete market data point (OHLCV + technical indicators)
    Idris: record MarketDataPoint where
        candle : Candle
        indicators : TechnicalIndicators
    """

    candle: Candle = Field(..., description="Candlestick data")
    indicators: TechnicalIndicators = Field(..., description="Technical indicators")

    model_config = ConfigDict(frozen=True)
