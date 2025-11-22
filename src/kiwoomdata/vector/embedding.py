"""
Vector Embedding - PCA dimensionality reduction and similarity search

Specs: Specs/Vector/Embedding.idr
Purpose: Reduce 600-dim vectors to 64-dim for efficient similarity search
"""

from dataclasses import dataclass
from pathlib import Path
from typing import List, Tuple
import pickle

import numpy as np
from sklearn.decomposition import PCA


@dataclass(frozen=True)
class VectorMetadata:
    """
    Metadata for vector search results

    Matches Specs/Vector/Embedding.idr VectorMetadata
    """

    stock_code: str
    timestamp: int
    window_size: int
    similarity: float  # Cosine similarity score (0~1)


class VectorEmbedder:
    """
    Vector embedding with PCA dimensionality reduction

    Design:
    - PCA: 600 dimensions → 64 dimensions
    - Cosine similarity for pattern matching
    - Save/load PCA model for consistency
    - In-memory vector storage (simple, no Milvus)

    Implementation follows Specs/Vector/Embedding.idr

    Note: For production with Milvus, see Specs/Vector/Embedding.idr pythonGuide
    """

    RAW_DIM = 600  # 60 candles × 10 features
    REDUCED_DIM = 64  # PCA compressed

    def __init__(self, use_pca: bool = True, n_components: int = 64):
        """
        Initialize vector embedder

        Args:
            use_pca: Whether to use PCA reduction
            n_components: PCA output dimensions (default: 64)
        """
        self.use_pca = use_pca
        self.n_components = n_components
        self.pca_model: PCA | None = None

        # In-memory vector storage
        # Format: [(vector, stock_code, timestamp, window_size), ...]
        self.vectors: List[Tuple[np.ndarray, str, int, int]] = []

    def train_pca(self, training_vectors: np.ndarray) -> dict:
        """
        Train PCA model on training vectors

        Args:
            training_vectors: Shape (n_samples, 600)

        Returns:
            Statistics dict with explained variance

        Example:
            vectors = np.random.randn(1000, 600)  # 1000 samples
            stats = embedder.train_pca(vectors)
            print(f"Explained variance: {stats['explained_variance']:.2%}")
        """
        if training_vectors.shape[1] != self.RAW_DIM:
            raise ValueError(
                f"Training vectors must have {self.RAW_DIM} dimensions, "
                f"got {training_vectors.shape[1]}"
            )

        # Train PCA
        self.pca_model = PCA(n_components=self.n_components)
        self.pca_model.fit(training_vectors)

        # Calculate statistics
        explained_variance = self.pca_model.explained_variance_ratio_.sum()

        return {
            "n_components": self.n_components,
            "explained_variance": explained_variance,
            "n_samples": training_vectors.shape[0],
        }

    def save_pca_model(self, path: str | Path):
        """Save trained PCA model to disk"""
        if self.pca_model is None:
            raise ValueError("PCA model not trained yet")

        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)

        with open(path, "wb") as f:
            pickle.dump(self.pca_model, f)

    def load_pca_model(self, path: str | Path):
        """Load trained PCA model from disk"""
        path = Path(path)

        if not path.exists():
            raise FileNotFoundError(f"PCA model not found: {path}")

        with open(path, "rb") as f:
            self.pca_model = pickle.load(f)

        self.use_pca = True

    def embed_vector(self, raw_vector: np.ndarray) -> np.ndarray:
        """
        Convert raw vector to embedded vector

        Args:
            raw_vector: Shape (600,) raw feature vector

        Returns:
            Embedded vector: Shape (64,) if PCA, else (600,)

        Raises:
            ValueError: If dimensions don't match
        """
        if raw_vector.shape[0] != self.RAW_DIM:
            raise ValueError(
                f"Raw vector must have {self.RAW_DIM} dimensions, "
                f"got {raw_vector.shape[0]}"
            )

        # NaN handling
        if np.any(np.isnan(raw_vector)):
            raise ValueError("Raw vector contains NaN values")

        # Apply PCA if enabled
        if self.use_pca:
            if self.pca_model is None:
                raise ValueError("PCA model not trained/loaded")

            # PCA expects (1, 600) shape
            embedded = self.pca_model.transform(raw_vector.reshape(1, -1))[0]
            return embedded
        else:
            return raw_vector

    def insert_vector(
        self,
        vector: np.ndarray,
        stock_code: str,
        timestamp: int,
        window_size: int = 60,
    ):
        """
        Insert vector into in-memory storage

        Args:
            vector: Embedded vector (64-dim or 600-dim)
            stock_code: Stock code (e.g., "005930")
            timestamp: Window end timestamp (milliseconds)
            window_size: Number of candles in window
        """
        # Normalize vector for cosine similarity
        norm = np.linalg.norm(vector)
        if norm > 0:
            vector = vector / norm

        self.vectors.append((vector, stock_code, timestamp, window_size))

    def search_similar(
        self,
        query_vector: np.ndarray,
        top_k: int = 10,
        min_similarity: float = 0.0,
    ) -> List[VectorMetadata]:
        """
        Search for similar vectors using cosine similarity

        Args:
            query_vector: Query vector (64-dim or 600-dim)
            top_k: Number of results to return
            min_similarity: Minimum similarity threshold (0~1)

        Returns:
            List of VectorMetadata sorted by similarity (descending)

        Algorithm: Cosine Similarity
            similarity = dot(A, B) / (||A|| × ||B||)
            Since vectors are normalized, this simplifies to dot(A, B)
        """
        if len(self.vectors) == 0:
            return []

        # Normalize query vector
        norm = np.linalg.norm(query_vector)
        if norm > 0:
            query_vector = query_vector / norm

        # Calculate cosine similarities
        similarities = []
        for vec, stock_code, timestamp, window_size in self.vectors:
            # Cosine similarity (vectors already normalized)
            similarity = float(np.dot(query_vector, vec))

            # Filter by threshold
            if similarity >= min_similarity:
                similarities.append(
                    VectorMetadata(
                        stock_code=stock_code,
                        timestamp=timestamp,
                        window_size=window_size,
                        similarity=similarity,
                    )
                )

        # Sort by similarity (descending)
        similarities.sort(key=lambda x: x.similarity, reverse=True)

        # Return top_k
        return similarities[:top_k]

    def clear_vectors(self):
        """Clear all stored vectors"""
        self.vectors = []

    def get_vector_count(self) -> int:
        """Get number of stored vectors"""
        return len(self.vectors)

    def get_vector_dimension(self) -> int:
        """Get vector dimension (64 or 600)"""
        if self.use_pca:
            return self.n_components
        else:
            return self.RAW_DIM


# Example usage (for documentation):
# # 1. Create embedder
# embedder = VectorEmbedder(use_pca=True, n_components=64)
#
# # 2. Train PCA (one-time)
# training_vectors = np.random.randn(1000, 600)  # 1000 training samples
# stats = embedder.train_pca(training_vectors)
# embedder.save_pca_model("models/pca_600_to_64.pkl")
#
# # 3. Embed and insert vectors
# raw_vector = np.random.randn(600)  # From feature engineering
# embedded = embedder.embed_vector(raw_vector)
# embedder.insert_vector(embedded, "005930", 1704153600000, 60)
#
# # 4. Search similar patterns
# query_vector = embedder.embed_vector(current_pattern)
# results = embedder.search_similar(query_vector, top_k=10)
# for result in results:
#     print(f"{result.stock_code}: {result.similarity:.4f}")
