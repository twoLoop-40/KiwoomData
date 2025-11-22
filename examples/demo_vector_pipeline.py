"""
Demo: Vector Embedding Pipeline (Phase B)

Demonstrates the complete workflow:
1. Generate sample candle data
2. Extract sliding windows
3. Calculate technical indicators
4. Create feature vectors
5. Train PCA and embed
6. Search for similar patterns

This is the core of pattern-based algorithmic trading.
"""

import sys
from datetime import datetime
from pathlib import Path

# Fix Windows console encoding
if sys.platform == "win32":
    import os
    os.system("chcp 65001 > nul")
    if sys.stdout.encoding != "utf-8":
        sys.stdout.reconfigure(encoding="utf-8")

import polars as pl
import numpy as np

from kiwoomdata.utils import SampleDataGenerator
from kiwoomdata.core.time_types import Timeframe
from kiwoomdata.vector import (
    WindowConfig,
    VectorWindowSize,
    SlidingWindowExtractor,
    FeatureEngineer,
    VectorEmbedder,
)


def main():
    print("=" * 70)
    print("Vector Embedding Pipeline Demo (Phase B)")
    print("=" * 70)
    print()

    # Setup
    models_dir = Path("models")
    models_dir.mkdir(exist_ok=True)

    print("📊 Step 1: Generate Sample Stock Data")
    print("-" * 70)

    generator = SampleDataGenerator(seed=42)

    # Generate 1 year of 10-minute candles for 3 stocks
    stocks = ["005930", "000660", "035420"]  # Samsung, SK Hynix, NAVER
    all_candles = []

    for stock_code in stocks:
        candles = generator.generate_candles(
            stock_code=stock_code,
            start_date=datetime(2024, 1, 2, 9, 0),
            count=500,  # ~5 days of data
            timeframe=Timeframe.MIN10,
            base_price=70000 if stock_code == "005930" else 50000,
        )
        all_candles.extend(candles)
        print(f"✅ Generated {len(candles)} candles for {stock_code}")

    print(f"\nTotal candles: {len(all_candles):,}")

    # Convert to DataFrame
    df = pl.DataFrame(
        {
            "timestamp": [c.timestamp for c in all_candles],
            "stock_code": [c.stock_code for c in all_candles],
            "open_price": [c.ohlcv.open_price for c in all_candles],
            "high_price": [c.ohlcv.high_price for c in all_candles],
            "low_price": [c.ohlcv.low_price for c in all_candles],
            "close_price": [c.ohlcv.close_price for c in all_candles],
            "volume": [c.ohlcv.volume for c in all_candles],
        }
    )

    print()
    print("🪟 Step 2: Extract Sliding Windows")
    print("-" * 70)

    # Configure window extractor
    window_config = WindowConfig.from_window_size(
        VectorWindowSize.SMALL,  # 60 candles
        timeframe="10min",
        interval_seconds=600,
        stride=10,  # Every 10th candle (reduce overlap)
    )

    extractor = SlidingWindowExtractor(window_config)

    # Extract windows per stock
    windows_by_stock = extractor.extract_windows_per_stock(df)

    total_windows = sum(len(windows) for windows in windows_by_stock.values())
    print(f"✅ Extracted {total_windows} windows:")
    for stock_code, windows in windows_by_stock.items():
        print(f"   - {stock_code}: {len(windows)} windows")

    print()
    print("🔧 Step 3: Feature Engineering")
    print("-" * 70)

    engineer = FeatureEngineer(
        rsi_period=14,
        macd_fast=12,
        macd_slow=26,
        sma_period=20,
        ema_period=12,
    )

    # Process first window as example
    example_stock = stocks[0]
    example_window = windows_by_stock[example_stock][0]

    print(f"Processing window for {example_stock}...")
    print(f"Window shape: {example_window.shape}")

    # Full feature engineering pipeline
    features = engineer.engineer_window(example_window)

    print(f"✅ Features calculated: {features.shape}")
    print(f"   Columns: {list(features.columns)}")
    print(f"   No NaN: {features.null_count().sum_horizontal().sum() == 0}")

    # Flatten to 1D vector
    feature_vector = engineer.flatten_window_features(features)
    print(f"   Flattened vector: {len(feature_vector)} dimensions")

    print()
    print("🤖 Step 4: Train PCA Model")
    print("-" * 70)

    # Create embedder
    embedder = VectorEmbedder(use_pca=True, n_components=64)

    # Generate training vectors from all windows
    print("Generating training vectors from all windows...")
    training_vectors = []

    for stock_code, windows in windows_by_stock.items():
        for window in windows:  # Use all windows for training
            try:
                features = engineer.engineer_window(window)
                # After indicator calculation, some rows are dropped
                # We need at least 60 rows, but accept what we have
                if len(features) > 0:
                    # Pad or truncate to exactly 600 dimensions
                    vector = engineer.flatten_window_features(features)
                    # Ensure 600 dimensions (60 candles × 10 features)
                    if len(vector) >= 600:
                        training_vectors.append(vector[:600])
                    elif len(vector) >= 100:  # At least 10 candles worth
                        # Pad with zeros
                        padded = vector + [0.0] * (600 - len(vector))
                        training_vectors.append(padded)
            except Exception:
                continue  # Skip windows with issues

    if len(training_vectors) == 0:
        print("❌ No training vectors generated")
        return

    training_array = np.array(training_vectors)
    print(f"Training vectors: {training_array.shape}")

    # Train PCA
    stats = embedder.train_pca(training_array)
    print(f"✅ PCA trained:")
    print(f"   Components: {stats['n_components']}")
    print(f"   Explained variance: {stats['explained_variance']:.2%}")
    print(f"   Training samples: {stats['n_samples']}")

    # Save model
    model_path = models_dir / "pca_600_to_64.pkl"
    embedder.save_pca_model(model_path)
    print(f"   Model saved: {model_path}")

    print()
    print("📥 Step 5: Embed and Insert Vectors")
    print("-" * 70)

    inserted_count = 0

    for stock_code, windows in windows_by_stock.items():
        for window in windows:
            try:
                # Feature engineering
                features = engineer.engineer_window(window)

                if len(features) == 0:
                    continue

                # Get vector (pad/truncate to 600)
                vector_raw = engineer.flatten_window_features(features)

                if len(vector_raw) >= 600:
                    vector_raw = vector_raw[:600]
                elif len(vector_raw) >= 100:  # At least 10 candles
                    vector_raw = vector_raw + [0.0] * (600 - len(vector_raw))
                else:
                    continue  # Too short

                vector_raw_np = np.array(vector_raw)

                # Embed with PCA
                vector_embedded = embedder.embed_vector(vector_raw_np)

                # Insert
                timestamp = window["timestamp"][-1]  # Last timestamp
                embedder.insert_vector(
                    vector_embedded,
                    stock_code=stock_code,
                    timestamp=timestamp,
                    window_size=60,
                )

                inserted_count += 1

            except Exception:
                continue

    print(f"✅ Inserted {inserted_count} vectors into embedder")
    print(f"   Vector dimension: {embedder.get_vector_dimension()}")

    print()
    print("🔍 Step 6: Search for Similar Patterns")
    print("-" * 70)

    # Pick a random pattern as query
    query_stock = stocks[0]
    query_window = windows_by_stock[query_stock][5]  # 6th window

    print(f"Query: {query_stock} window at index 5")

    # Generate query vector
    query_features = engineer.engineer_window(query_window)
    query_raw_list = engineer.flatten_window_features(query_features)

    # Pad/truncate to 600
    if len(query_raw_list) >= 600:
        query_raw_list = query_raw_list[:600]
    else:
        query_raw_list = query_raw_list + [0.0] * (600 - len(query_raw_list))

    query_raw = np.array(query_raw_list)
    query_embedded = embedder.embed_vector(query_raw)

    # Search for similar patterns
    results = embedder.search_similar(query_embedded, top_k=10, min_similarity=0.8)

    print(f"\n✅ Found {len(results)} similar patterns:")
    print()
    print(f"{'Rank':<6} {'Stock':<10} {'Timestamp':<15} {'Similarity':<12}")
    print("-" * 70)

    for i, result in enumerate(results, 1):
        # Convert timestamp to readable format
        dt = datetime.fromtimestamp(result.timestamp / 1000)
        print(
            f"{i:<6} {result.stock_code:<10} "
            f"{dt.strftime('%Y-%m-%d %H:%M'):<15} "
            f"{result.similarity:.4f}"
        )

    print()
    print("=" * 70)
    print("✅ Vector Embedding Pipeline Complete!")
    print("=" * 70)
    print()
    print("Summary:")
    print(f"  - Generated: {len(all_candles):,} candles for {len(stocks)} stocks")
    print(f"  - Extracted: {total_windows} windows (60 candles each)")
    print(f"  - Trained: PCA model (600 → 64 dims, {stats['explained_variance']:.1%} variance)")
    print(f"  - Embedded: {inserted_count} pattern vectors")
    print(f"  - Searched: Found {len(results)} similar patterns")
    print()
    print("Next steps:")
    print("  1. Collect real data from Kiwoom API")
    print("  2. Scale to 2,500 stocks × 20 years")
    print("  3. Deploy Milvus on Mac for production search")
    print("  4. Build backtesting engine")
    print()


if __name__ == "__main__":
    main()
