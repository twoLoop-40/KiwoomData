"""
Vector module - Sliding windows, feature engineering, and embeddings
"""

from .sliding_window import (
    WindowConfig,
    VectorWindowSize,
    SlidingWindowExtractor,
)
from .features import (
    Indicator,
    FeatureEngineer,
)
from .embedding import (
    VectorMetadata,
    VectorEmbedder,
)

__all__ = [
    "WindowConfig",
    "VectorWindowSize",
    "SlidingWindowExtractor",
    "Indicator",
    "FeatureEngineer",
    "VectorMetadata",
    "VectorEmbedder",
]
