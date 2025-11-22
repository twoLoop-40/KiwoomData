"""
Tests for Vector Embedding and Similarity Search

Validates PCA reduction and cosine similarity
"""

import tempfile
from pathlib import Path

import numpy as np
import pytest

from kiwoomdata.vector import VectorEmbedder, VectorMetadata


class TestVectorEmbedding:
    """Test vector embedding with PCA and similarity search"""

    def test_embedder_creation(self):
        """Test creating embedder with/without PCA"""
        # With PCA
        embedder_pca = VectorEmbedder(use_pca=True, n_components=64)
        assert embedder_pca.use_pca is True
        assert embedder_pca.n_components == 64
        assert embedder_pca.get_vector_count() == 0

        # Without PCA
        embedder_raw = VectorEmbedder(use_pca=False)
        assert embedder_raw.use_pca is False
        assert embedder_raw.get_vector_dimension() == 600

    def test_pca_training(self):
        """Test PCA model training"""
        embedder = VectorEmbedder(use_pca=True, n_components=64)

        # Generate training data (1000 samples × 600 features)
        np.random.seed(42)
        training_vectors = np.random.randn(1000, 600)

        # Train PCA
        stats = embedder.train_pca(training_vectors)

        # Check statistics
        assert stats["n_components"] == 64
        assert stats["n_samples"] == 1000
        assert 0.0 < stats["explained_variance"] <= 1.0

        # PCA model should be available
        assert embedder.pca_model is not None

    def test_pca_save_load(self):
        """Test saving and loading PCA model"""
        with tempfile.TemporaryDirectory() as tmpdir:
            model_path = Path(tmpdir) / "pca_model.pkl"

            # Train and save
            embedder1 = VectorEmbedder(use_pca=True, n_components=64)
            training_vectors = np.random.randn(500, 600)
            embedder1.train_pca(training_vectors)
            embedder1.save_pca_model(model_path)

            # Load in new embedder
            embedder2 = VectorEmbedder(use_pca=True, n_components=64)
            embedder2.load_pca_model(model_path)

            # Both should produce same embeddings
            test_vector = np.random.randn(600)
            embedded1 = embedder1.embed_vector(test_vector)
            embedded2 = embedder2.embed_vector(test_vector)

            np.testing.assert_array_almost_equal(embedded1, embedded2)

    def test_vector_embedding_with_pca(self):
        """Test embedding vectors with PCA"""
        embedder = VectorEmbedder(use_pca=True, n_components=64)

        # Train PCA
        training_vectors = np.random.randn(200, 600)
        embedder.train_pca(training_vectors)

        # Embed a vector
        raw_vector = np.random.randn(600)
        embedded = embedder.embed_vector(raw_vector)

        # Check dimensions
        assert embedded.shape == (64,)

        # Check no NaN
        assert not np.any(np.isnan(embedded))

    def test_vector_embedding_without_pca(self):
        """Test embedding without PCA (pass-through)"""
        embedder = VectorEmbedder(use_pca=False)

        # Embed a vector
        raw_vector = np.random.randn(600)
        embedded = embedder.embed_vector(raw_vector)

        # Should be same as input
        assert embedded.shape == (600,)
        np.testing.assert_array_equal(embedded, raw_vector)

    def test_insert_and_count(self):
        """Test inserting vectors"""
        embedder = VectorEmbedder(use_pca=False)

        assert embedder.get_vector_count() == 0

        # Insert vectors
        for i in range(10):
            vector = np.random.randn(600)
            embedder.insert_vector(
                vector,
                stock_code=f"00{i:04d}",
                timestamp=1704153600000 + i * 600000,
                window_size=60,
            )

        assert embedder.get_vector_count() == 10

    def test_cosine_similarity_search(self):
        """Test similarity search with cosine similarity"""
        embedder = VectorEmbedder(use_pca=False)

        # Create a base vector
        np.random.seed(123)
        base_vector = np.random.randn(600)

        # Insert base vector
        embedder.insert_vector(
            base_vector,
            stock_code="005930",
            timestamp=1704153600000,
            window_size=60,
        )

        # Insert similar vectors (base + small noise)
        for i in range(5):
            similar_vector = base_vector + np.random.randn(600) * 0.1
            embedder.insert_vector(
                similar_vector,
                stock_code=f"similar_{i}",
                timestamp=1704153600000 + (i + 1) * 600000,
                window_size=60,
            )

        # Insert dissimilar vectors (random)
        for i in range(5):
            dissimilar_vector = np.random.randn(600) * 10
            embedder.insert_vector(
                dissimilar_vector,
                stock_code=f"dissimilar_{i}",
                timestamp=1704153600000 + (i + 6) * 600000,
                window_size=60,
            )

        # Search with base vector
        results = embedder.search_similar(base_vector, top_k=3)

        # Should find itself first
        assert len(results) == 3
        assert results[0].stock_code == "005930"
        assert results[0].similarity > 0.99  # Very similar to itself

        # Next should be similar vectors
        assert "similar" in results[1].stock_code
        assert results[1].similarity > 0.8  # Fairly similar

    def test_similarity_threshold(self):
        """Test minimum similarity threshold"""
        embedder = VectorEmbedder(use_pca=False)

        np.random.seed(456)
        base_vector = np.random.randn(600)

        # Insert various vectors with different similarities
        embedder.insert_vector(base_vector, "base", 1000, 60)
        embedder.insert_vector(
            base_vector + np.random.randn(600) * 0.1, "similar_high", 2000, 60
        )
        embedder.insert_vector(
            base_vector + np.random.randn(600) * 1.0, "similar_medium", 3000, 60
        )
        embedder.insert_vector(
            np.random.randn(600) * 10, "dissimilar", 4000, 60
        )

        # Search with high threshold
        results_high = embedder.search_similar(
            base_vector, top_k=10, min_similarity=0.9
        )

        # Should only get very similar ones
        assert len(results_high) <= 2
        assert all(r.similarity >= 0.9 for r in results_high)

        # Search with low threshold
        results_low = embedder.search_similar(
            base_vector, top_k=10, min_similarity=0.0
        )

        # Should get at least 3 vectors (dissimilar might have negative similarity after normalization)
        assert len(results_low) >= 3

    def test_clear_vectors(self):
        """Test clearing all vectors"""
        embedder = VectorEmbedder(use_pca=False)

        # Insert some vectors
        for i in range(5):
            vector = np.random.randn(600)
            embedder.insert_vector(vector, f"stock_{i}", i * 1000, 60)

        assert embedder.get_vector_count() == 5

        # Clear
        embedder.clear_vectors()
        assert embedder.get_vector_count() == 0

        # Search should return empty
        results = embedder.search_similar(np.random.randn(600), top_k=10)
        assert len(results) == 0

    def test_vector_metadata(self):
        """Test VectorMetadata structure"""
        metadata = VectorMetadata(
            stock_code="005930",
            timestamp=1704153600000,
            window_size=60,
            similarity=0.95,
        )

        assert metadata.stock_code == "005930"
        assert metadata.timestamp == 1704153600000
        assert metadata.window_size == 60
        assert metadata.similarity == 0.95

    def test_nan_handling(self):
        """Test that NaN vectors are rejected"""
        embedder = VectorEmbedder(use_pca=False)

        # Create vector with NaN
        nan_vector = np.random.randn(600)
        nan_vector[0] = np.nan

        # Should raise error
        with pytest.raises(ValueError, match="NaN"):
            embedder.embed_vector(nan_vector)

    def test_dimension_mismatch(self):
        """Test that wrong dimensions are rejected"""
        embedder = VectorEmbedder(use_pca=False)

        # Wrong dimension
        wrong_vector = np.random.randn(100)

        with pytest.raises(ValueError, match="600 dimensions"):
            embedder.embed_vector(wrong_vector)

    def test_pca_not_trained_error(self):
        """Test error when using PCA without training"""
        embedder = VectorEmbedder(use_pca=True)

        # Try to embed without training
        vector = np.random.randn(600)

        with pytest.raises(ValueError, match="PCA model not trained"):
            embedder.embed_vector(vector)

    def test_end_to_end_with_pca(self):
        """
        End-to-end test: train PCA, embed, search

        This simulates the actual usage pattern
        """
        # 1. Create embedder
        embedder = VectorEmbedder(use_pca=True, n_components=64)

        # 2. Train PCA on historical data
        np.random.seed(789)
        historical_vectors = np.random.randn(1000, 600)
        stats = embedder.train_pca(historical_vectors)

        # Random data has low explained variance (no structure)
        # Just check that PCA worked
        assert 0.0 < stats["explained_variance"] <= 1.0

        # 3. Embed and insert new patterns
        for i in range(20):
            raw_vector = np.random.randn(600)
            embedded = embedder.embed_vector(raw_vector)

            assert embedded.shape == (64,)  # Reduced dimension

            embedder.insert_vector(
                embedded,
                stock_code=f"stock_{i:03d}",
                timestamp=1704153600000 + i * 600000,
                window_size=60,
            )

        assert embedder.get_vector_count() == 20

        # 4. Search for similar patterns
        query_raw = np.random.randn(600)
        query_embedded = embedder.embed_vector(query_raw)
        results = embedder.search_similar(query_embedded, top_k=5)

        assert len(results) == 5
        assert all(isinstance(r, VectorMetadata) for r in results)
        assert all(0.0 <= r.similarity <= 1.0 for r in results)

        # Results should be sorted by similarity
        for i in range(len(results) - 1):
            assert results[i].similarity >= results[i + 1].similarity
