"""
Demo: Complete Data Pipeline

Demonstrates the full workflow:
1. Generate sample stock data
2. Store in SQLite buffer
3. Export to Parquet with year partitioning
4. Read and analyze the data

This simulates real Kiwoom data collection without requiring an API account.
"""

import sys
import locale
from datetime import datetime
from pathlib import Path

# Fix Windows console encoding
if sys.platform == "win32":
    import os
    # Set console to UTF-8
    os.system("chcp 65001 > nul")
    # Set Python stdout to UTF-8
    if sys.stdout.encoding != "utf-8":
        sys.stdout.reconfigure(encoding="utf-8")

from kiwoomdata.utils import SampleDataGenerator
from kiwoomdata.database import SQLiteBuffer, ParquetExporter
from kiwoomdata.core.time_types import Timeframe
from kiwoomdata.validation.deduplication import Deduplicator


def main():
    print("=" * 60)
    print("KiwoomData Pipeline Demo")
    print("=" * 60)
    print()

    # Setup paths
    base_path = Path("data")
    buffer_path = base_path / "buffer.db"
    parquet_path = base_path / "parquet"

    # Clean up old data
    if buffer_path.exists():
        buffer_path.unlink()
        print(f"🗑️  Cleaned up old buffer: {buffer_path}")

    print()
    print("📊 Step 1: Generate Sample Data")
    print("-" * 60)

    generator = SampleDataGenerator(seed=42)

    # Generate sample stocks
    stocks = generator.generate_stocks(count=5)
    print(f"Generated {len(stocks)} sample stocks:")
    for stock in stocks:
        print(f"  - {stock.code}: {stock.name} ({stock.market.value})")

    print()
    print(f"Generating candles for {stocks[0].name} ({stocks[0].code})...")

    # Generate 1 year of 10-minute candles for Samsung Electronics
    # Trading hours: 9:00-15:30 = 390 minutes = 39 candles per day
    # 1 year ≈ 250 trading days = 9,750 candles
    candles = generator.generate_candles(
        stock_code=stocks[0].code,
        start_date=datetime(2024, 1, 2, 9, 0),  # First trading day of 2024
        count=9750,
        timeframe=Timeframe.MIN10,
        base_price=70000,  # Samsung Electronics ~70,000 KRW
    )

    print(f"✅ Generated {len(candles):,} candles (1 year of 10-min data)")
    print(f"   Date range: {candles[0].datetime} → {candles[-1].datetime}")
    print(f"   Price range: {min(c.ohlcv.low_price for c in candles):.2f} → {max(c.ohlcv.high_price for c in candles):.2f} KRW")

    print()
    print("💾 Step 2: Insert into SQLite Buffer")
    print("-" * 60)

    with SQLiteBuffer(buffer_path) as buffer:
        inserted = buffer.insert_candles(candles, Timeframe.MIN10)
        count = buffer.count(Timeframe.MIN10)

        print(f"✅ Inserted {inserted:,} candles into buffer")
        print(f"   Buffer size: {buffer_path.stat().st_size / (1024 * 1024):.2f} MB")
        print(f"   Total candles in buffer: {count:,}")

        print()
        print("🔍 Step 3: Read as Polars DataFrame")
        print("-" * 60)

        df = buffer.read_as_polars(Timeframe.MIN10)
        print(f"✅ Loaded {len(df):,} rows into Polars DataFrame")
        print()
        print("Schema:")
        print(df.schema)
        print()
        print("Sample data (first 5 rows):")
        print(df.head(5))

        print()
        print("🧹 Step 4: Deduplication Check")
        print("-" * 60)

        deduplicator = Deduplicator()
        df_clean, result = deduplicator.remove_duplicates(df)

        print(f"Total rows: {result.total_rows:,}")
        print(f"Unique rows: {result.unique_rows:,}")
        print(f"Duplicates: {result.duplicate_rows:,} ({result.duplicate_rate:.2f}%)")

        if result.duplicate_rows > 0:
            print("⚠️  Duplicates found and removed")
        else:
            print("✅ No duplicates found")

        print()
        print("📦 Step 5: Export to Parquet")
        print("-" * 60)

        exporter = ParquetExporter(parquet_path)
        exported_files = exporter.export_from_dataframe(df_clean, Timeframe.MIN10)

        print(f"✅ Exported to {len(exported_files)} year partition(s):")
        for year, path in sorted(exported_files.items()):
            file_size = path.stat().st_size / (1024 * 1024)
            print(f"   - {year}: {path.name} ({file_size:.2f} MB)")

        print()
        print("📈 Step 6: Get Statistics")
        print("-" * 60)

        stats = exporter.get_stats(Timeframe.MIN10)

        print(f"Total rows: {stats['total_rows']:,}")
        print(f"Total size: {stats['total_size_mb']:.2f} MB")
        print(f"Available years: {stats['years']}")
        min_date, max_date = stats['date_range']
        print(f"Date range: {min_date.date()} → {max_date.date()}")

        print()
        print("🔄 Step 7: Clear Buffer")
        print("-" * 60)

        cleared = buffer.clear(Timeframe.MIN10)
        print(f"✅ Cleared {cleared:,} candles from buffer")
        print(f"   Remaining candles: {buffer.count(Timeframe.MIN10)}")

    print()
    print("📖 Step 8: Read from Parquet")
    print("-" * 60)

    # Read data for specific year
    df_2024 = exporter.read_parquet(Timeframe.MIN10, year=2024)
    print(f"✅ Loaded {len(df_2024):,} rows from Parquet (year=2024)")

    # Sample analysis
    print()
    print("Sample Analysis:")
    print(f"  Average volume: {df_2024['volume'].mean():,.0f}")
    print(f"  Average close price: {df_2024['close_price'].mean():.2f} KRW")
    print(f"  Max high price: {df_2024['high_price'].max():.2f} KRW")
    print(f"  Min low price: {df_2024['low_price'].min():.2f} KRW")

    print()
    print("=" * 60)
    print("✅ Pipeline Demo Complete!")
    print("=" * 60)
    print()
    print("Next steps:")
    print("  1. Check the data/ directory for generated files")
    print("  2. Explore the Parquet files with Polars/DuckDB")
    print("  3. Run Phase B: Vector Embedding Pipeline")
    print()


if __name__ == "__main__":
    main()
