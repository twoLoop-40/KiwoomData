"""
Validation module - Data validation with Smart Constructor pattern
"""

from .invariants import ValidCandle, validate_candle
from .deduplication import DedupPolicy, DeduplicationResult, Deduplicator

__all__ = [
    "ValidCandle",
    "validate_candle",
    "DedupPolicy",
    "DeduplicationResult",
    "Deduplicator",
]
