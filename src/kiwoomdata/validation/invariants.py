"""
Data invariants - Implementation of Specs/Validation/Invariants.idr

Smart Constructor pattern: Only valid data can be wrapped in ValidCandle type.
"""

from typing import NewType

from ..core.types import Candle
from ..core.error_types import ValidationError

# Epsilon for floating-point comparison
# Idris: epsilon : Double
EPSILON = 1e-6

# Opaque type: Can only be created via validate_candle()
# Idris: data ValidCandle : Type where MkValidCandle : Candle -> ValidCandle
ValidCandle = NewType("ValidCandle", Candle)


def is_valid_price(price: float) -> bool:
    """
    Price validation (must be > 0)
    Idris: isValidPrice : Double -> Bool
    """
    return price > 0.0


def validate_candle(candle: Candle) -> ValidCandle:
    """
    Smart Constructor for validated candles
    Idris: validateCandle : Candle -> Maybe ValidCandle

    Validates:
    1. All prices are positive (> 0)
    2. High >= max(open, close) - epsilon
    3. Low <= min(open, close) + epsilon
    4. Volume >= 0 (automatically satisfied by Nat type)

    Raises:
        ValidationError: If any invariant is violated

    Returns:
        ValidCandle: Opaque type guaranteeing data integrity
    """
    o = candle.ohlcv.open_price
    h = candle.ohlcv.high_price
    l = candle.ohlcv.low_price
    c = candle.ohlcv.close_price
    v = candle.ohlcv.volume

    # 1. Positive prices
    if not (o > 0 and h > 0 and l > 0 and c > 0):
        raise ValidationError(
            "All prices must be positive",
            field="ohlcv",
            context={"open": o, "high": h, "low": l, "close": c},
        )

    # 2. High price validation (with epsilon tolerance)
    max_oc = max(o, c)
    if h < max_oc - EPSILON:
        raise ValidationError(
            f"High price ({h}) must be >= max(open={o}, close={c}) = {max_oc}",
            field="high_price",
            context={"high": h, "max_oc": max_oc, "epsilon": EPSILON},
        )

    # 3. Low price validation (with epsilon tolerance)
    min_oc = min(o, c)
    if l > min_oc + EPSILON:
        raise ValidationError(
            f"Low price ({l}) must be <= min(open={o}, close={c}) = {min_oc}",
            field="low_price",
            context={"low": l, "min_oc": min_oc, "epsilon": EPSILON},
        )

    # 4. Volume is Nat (>= 0) - checked by Pydantic
    # All checks passed
    return ValidCandle(candle)


def get_raw_candle(valid_candle: ValidCandle) -> Candle:
    """
    Extract raw candle from ValidCandle
    Idris: getRaw : ValidCandle -> Candle

    This is the only way to unwrap a ValidCandle back to Candle.
    """
    return Candle.__wrapped__  # type: ignore
