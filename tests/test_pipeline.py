"""
Integration tests for the complete data pipeline

Pipeline:
  Sample Data → SQLite Buffer → Polars → Parquet Export
"""

import tempfile
from pathlib import Path
from datetime import datetime, timedelta

import pytest

from kiwoomdata.utils import SampleDataGenerator
from kiwoomdata.database import SQLiteBuffer, ParquetExporter
from kiwoomdata.core.time_types import Timeframe
from kiwoomdata.validation.deduplication import Deduplicator


class TestDataPipeline:
    """Test the complete data collection and export pipeline"""

    def test_sample_to_sqlite_to_parquet(self):
        """
        Complete pipeline test:
        1. Generate sample data
        2. Insert into SQLite buffer
        3. Export to Parquet
        4. Verify data integrity
        """
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)

            # Step 1: Generate sample data
            generator = SampleDataGenerator(seed=42)
            candles = generator.generate_candles(
                stock_code="005930",
                start_date=datetime(2024, 1, 1, 9, 0),
                count=100,
                timeframe=Timeframe.MIN10,
                base_price=70000,
            )

            assert len(candles) == 100

            # Step 2: Insert into SQLite buffer
            buffer_path = tmp_path / "buffer.db"
            with SQLiteBuffer(buffer_path) as buffer:
                inserted = buffer.insert_candles(candles, Timeframe.MIN10)
                assert inserted == 100
                assert buffer.count(Timeframe.MIN10) == 100

                # Step 3: Read as Polars and export to Parquet
                df = buffer.read_as_polars(Timeframe.MIN10)
                assert len(df) == 100

                exporter = ParquetExporter(tmp_path / "parquet")
                exported_files = exporter.export_from_dataframe(df, Timeframe.MIN10)

                assert 2024 in exported_files
                assert exported_files[2024].exists()

                # Step 5: Clear buffer after export
                cleared = buffer.clear(Timeframe.MIN10)
                assert cleared == 100
                assert buffer.count(Timeframe.MIN10) == 0

            # Step 4: Verify data integrity (after buffer closed)
            df_loaded = exporter.read_parquet(Timeframe.MIN10, year=2024)
            assert len(df_loaded) == 100

            # Check schema
            assert "timestamp" in df_loaded.columns
            assert "stock_code" in df_loaded.columns
            assert "open_price" in df_loaded.columns
            assert "volume" in df_loaded.columns

            # Check data matches
            assert df_loaded["stock_code"].unique().to_list() == ["005930"]

    def test_multi_year_partitioning(self):
        """Test that data spanning multiple years gets partitioned correctly"""
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)

            generator = SampleDataGenerator(seed=123)

            # Generate data for 2023 (full year, no overlap)
            candles_2023 = generator.generate_candles(
                stock_code="000660",
                start_date=datetime(2023, 1, 1, 9, 0),
                count=30,  # 30 days in 2023
                timeframe=Timeframe.DAILY,
                base_price=120000,
            )

            # Generate data for 2024 (full year, no overlap)
            candles_2024 = generator.generate_candles(
                stock_code="000660",
                start_date=datetime(2024, 1, 1, 9, 0),
                count=30,  # 30 days in 2024
                timeframe=Timeframe.DAILY,
                base_price=125000,
            )

            # Insert both into buffer
            with SQLiteBuffer(tmp_path / "buffer.db") as buffer:
                buffer.insert_candles(candles_2023, Timeframe.DAILY)
                buffer.insert_candles(candles_2024, Timeframe.DAILY)

                assert buffer.count(Timeframe.DAILY) == 60

                # Export to Parquet
                df = buffer.read_as_polars(Timeframe.DAILY)
                exporter = ParquetExporter(tmp_path / "parquet")
                exported_files = exporter.export_from_dataframe(df, Timeframe.DAILY)

                # Check both years exist
                assert 2023 in exported_files
                assert 2024 in exported_files

            # Verify partition data (after buffer closed)
            df_2023 = exporter.read_parquet(Timeframe.DAILY, year=2023)
            df_2024 = exporter.read_parquet(Timeframe.DAILY, year=2024)

            assert len(df_2023) == 30
            assert len(df_2024) == 30

            # Verify year filtering works
            years = exporter.get_available_years(Timeframe.DAILY)
            assert years == [2023, 2024]

    def test_append_and_deduplication(self):
        """
        Test that appending to existing Parquet files deduplicates correctly
        """
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)

            generator = SampleDataGenerator(seed=456)

            # First batch: 50 candles
            candles_batch1 = generator.generate_candles(
                stock_code="035420",
                start_date=datetime(2024, 1, 1, 9, 0),
                count=50,
                timeframe=Timeframe.MIN10,
            )

            exporter = ParquetExporter(tmp_path / "parquet")

            # Export first batch
            with SQLiteBuffer(tmp_path / "buffer.db") as buffer:
                buffer.insert_candles(candles_batch1, Timeframe.MIN10)
                df1 = buffer.read_as_polars(Timeframe.MIN10)
                exporter.export_from_dataframe(df1, Timeframe.MIN10)

            # Check initial export
            df_loaded = exporter.read_parquet(Timeframe.MIN10, year=2024)
            assert len(df_loaded) == 50

            # Second batch with 5 overlapping + 10 new = 15 total
            candles_batch2 = generator.generate_candles(
                stock_code="035420",
                start_date=datetime(2024, 1, 1, 9, 0) + timedelta(minutes=45 * 10),  # Start from 45th candle (overlap last 5)
                count=15,
                timeframe=Timeframe.MIN10,
            )

            # Export second batch
            with SQLiteBuffer(tmp_path / "buffer.db") as buffer:
                buffer.insert_candles(candles_batch2, Timeframe.MIN10)
                df2 = buffer.read_as_polars(Timeframe.MIN10)
                exporter.export_from_dataframe(df2, Timeframe.MIN10)

            # Check deduplication: 50 original + 10 new = 60 total (5 duplicates removed)
            df_final = exporter.read_parquet(Timeframe.MIN10, year=2024)
            assert len(df_final) == 60  # Duplicates removed

    def test_stats_and_metrics(self):
        """Test statistics reporting"""
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)

            generator = SampleDataGenerator(seed=789)
            candles = generator.generate_candles(
                stock_code="005380",
                start_date=datetime(2024, 6, 1, 9, 0),
                count=1000,
                timeframe=Timeframe.MIN10,
            )

            with SQLiteBuffer(tmp_path / "buffer.db") as buffer:
                buffer.insert_candles(candles, Timeframe.MIN10)

                df = buffer.read_as_polars(Timeframe.MIN10)
                exporter = ParquetExporter(tmp_path / "parquet")
                exporter.export_from_dataframe(df, Timeframe.MIN10)

            # Get stats (after buffer closed)
            stats = exporter.get_stats(Timeframe.MIN10)

            assert stats["total_rows"] == 1000
            assert stats["total_size_mb"] > 0
            assert stats["years"] == [2024]
            assert stats["date_range"][0] is not None
            assert stats["date_range"][1] is not None

            # Verify date range
            min_date, max_date = stats["date_range"]
            assert min_date.year == 2024
            assert max_date.year == 2024
            assert min_date < max_date

    def test_validation_in_pipeline(self):
        """
        Test that validation (deduplication) works in the pipeline
        """
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)

            generator = SampleDataGenerator(seed=999)
            candles = generator.generate_candles(
                stock_code="051910",
                start_date=datetime(2024, 3, 1, 9, 0),
                count=100,
                timeframe=Timeframe.MIN10,
            )

            # Manually add duplicates
            duplicate_candles = candles[:10]  # Duplicate first 10
            all_candles = candles + duplicate_candles

            with SQLiteBuffer(tmp_path / "buffer.db") as buffer:
                buffer.insert_candles(all_candles, Timeframe.MIN10)

                # Should have 110 in buffer (100 + 10 duplicates)
                assert buffer.count(Timeframe.MIN10) == 110

                # Read and deduplicate
                df = buffer.read_as_polars(Timeframe.MIN10)
                deduplicator = Deduplicator()
                df_clean, result = deduplicator.remove_duplicates(df)

                # Should clean to 100 unique
                assert len(df_clean) == 100
                assert result.duplicate_rows == 10

                # Export cleaned data
                exporter = ParquetExporter(tmp_path / "parquet")
                exporter.export_from_dataframe(df_clean, Timeframe.MIN10)

            # Verify Parquet has only unique data (after buffer closed)
            df_loaded = exporter.read_parquet(Timeframe.MIN10, year=2024)
            assert len(df_loaded) == 100
