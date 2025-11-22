"""
Parquet Exporter - Export buffer data to partitioned Parquet files

Specs: Specs/Sync/FileExport.idr
Purpose: Export SQLite buffer to year-partitioned Parquet for long-term storage
"""

from pathlib import Path
from datetime import datetime

import polars as pl

from ..core.time_types import Timeframe


class ParquetExporter:
    """
    Export candle data to Parquet with Hive-style partitioning

    Design:
    - Year-based partitioning (data/parquet/year=2024/...)
    - Compression: Snappy (good balance of speed/size)
    - Schema enforced by Polars
    - Incremental exports (append mode)
    """

    def __init__(self, base_path: str | Path = "data/parquet"):
        self.base_path = Path(base_path)
        self.base_path.mkdir(parents=True, exist_ok=True)

    def export_from_dataframe(
        self,
        df: pl.DataFrame,
        timeframe: Timeframe,
    ) -> dict[int, Path]:
        """
        Export DataFrame to year-partitioned Parquet files

        Args:
            df: Polars DataFrame with candles (must have 'timestamp' column)
            timeframe: Timeframe for organizing files

        Returns:
            Dictionary mapping year -> file path

        Example:
            {2024: Path("data/parquet/year=2024/10min.parquet")}
        """
        if len(df) == 0:
            return {}

        # Add year column for partitioning
        df = df.with_columns(
            pl.from_epoch("timestamp", time_unit="ms")
            .dt.year()
            .alias("year")
        )

        # Group by year
        exported_files = {}

        for year_group in df.partition_by("year", as_dict=True).items():
            year_key, year_df = year_group

            # Extract year from tuple key (Polars returns (2024,) not 2024)
            year = year_key[0] if isinstance(year_key, tuple) else year_key

            # Remove year column before saving (it's in the path)
            year_df = year_df.drop("year")

            # Create year partition directory
            year_path = self.base_path / f"year={year}"
            year_path.mkdir(parents=True, exist_ok=True)

            # File path: data/parquet/year=2024/10min.parquet
            file_path = year_path / f"{timeframe.value}.parquet"

            # Check if file exists (append vs create)
            if file_path.exists():
                # Append mode: read existing, concat, deduplicate
                existing_df = pl.read_parquet(file_path)
                combined_df = pl.concat([existing_df, year_df])

                # Deduplicate by (timestamp, stock_code), keep last
                combined_df = combined_df.unique(
                    subset=["timestamp", "stock_code"],
                    keep="last"
                ).sort("timestamp")

                combined_df.write_parquet(
                    file_path,
                    compression="snappy",
                )
            else:
                # Create mode: just write
                year_df.sort("timestamp").write_parquet(
                    file_path,
                    compression="snappy",
                )

            exported_files[year] = file_path

        return exported_files

    def read_parquet(
        self,
        timeframe: Timeframe,
        year: int | None = None,
    ) -> pl.DataFrame:
        """
        Read Parquet files (optionally filtered by year)

        Args:
            timeframe: Timeframe to read
            year: Specific year (None = all years)

        Returns:
            Polars DataFrame with candles
        """
        if year is not None:
            # Read specific year
            year_path = self.base_path / f"year={year}" / f"{timeframe.value}.parquet"

            if not year_path.exists():
                return pl.DataFrame()

            return pl.read_parquet(year_path)
        else:
            # Read all years
            pattern = str(self.base_path / f"year=*/{timeframe.value}.parquet")

            try:
                return pl.read_parquet(pattern)
            except FileNotFoundError:
                return pl.DataFrame()

    def get_available_years(self, timeframe: Timeframe) -> list[int]:
        """
        Get list of years with data for given timeframe

        Returns:
            Sorted list of years (e.g., [2020, 2021, 2024])
        """
        years = []

        for year_dir in self.base_path.glob("year=*"):
            if not year_dir.is_dir():
                continue

            year_str = year_dir.name.split("=")[1]

            # Check if timeframe file exists
            timeframe_file = year_dir / f"{timeframe.value}.parquet"
            if timeframe_file.exists():
                years.append(int(year_str))

        return sorted(years)

    def get_stats(self, timeframe: Timeframe) -> dict:
        """
        Get statistics about stored data

        Returns:
            {
                "total_rows": 1000000,
                "total_size_mb": 50.5,
                "years": [2020, 2021, 2024],
                "date_range": (min_date, max_date)
            }
        """
        years = self.get_available_years(timeframe)

        if not years:
            return {
                "total_rows": 0,
                "total_size_mb": 0.0,
                "years": [],
                "date_range": (None, None),
            }

        # Read all data
        df = self.read_parquet(timeframe)

        # Calculate size
        total_size = 0
        for year in years:
            year_path = self.base_path / f"year={year}" / f"{timeframe.value}.parquet"
            if year_path.exists():
                total_size += year_path.stat().st_size

        # Date range
        min_ts = df["timestamp"].min()
        max_ts = df["timestamp"].max()

        min_date = datetime.fromtimestamp(min_ts / 1000) if min_ts else None
        max_date = datetime.fromtimestamp(max_ts / 1000) if max_ts else None

        return {
            "total_rows": len(df),
            "total_size_mb": round(total_size / (1024 * 1024), 2),
            "years": years,
            "date_range": (min_date, max_date),
        }


# Example usage:
# exporter = ParquetExporter("data/parquet")
# buffer = SQLiteBuffer("data/buffer.db")
# df = buffer.read_as_polars(Timeframe.MIN10)
# files = exporter.export_from_dataframe(df, Timeframe.MIN10)
# buffer.clear(Timeframe.MIN10)
