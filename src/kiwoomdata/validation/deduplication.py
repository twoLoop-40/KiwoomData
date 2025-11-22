"""
Deduplication - Implementation of Specs/Validation/Deduplication.idr

Deterministic duplicate removal based on (timestamp, stock_code).
"""

from dataclasses import dataclass
from enum import Enum

import polars as pl


class DedupPolicy(str, Enum):
    """
    Deduplication policy
    Idris: data DedupPolicy = KeepFirst | KeepLast
    """

    KEEP_FIRST = "first"  # Keep original data (immutable)
    KEEP_LAST = "last"  # Keep latest data (update)


@dataclass(frozen=True)
class DeduplicationResult:
    """
    Deduplication result statistics
    Idris: record DeduplicationResult where
        totalRows : Nat
        uniqueRows : Nat
        duplicateRows : Nat
    """

    total_rows: int
    unique_rows: int
    duplicate_rows: int

    @property
    def duplicate_rate(self) -> float:
        """Calculate duplicate rate (0.0 - 1.0)"""
        if self.total_rows == 0:
            return 0.0
        return self.duplicate_rows / self.total_rows


class Deduplicator:
    """
    Deterministic deduplication for Polars DataFrames
    Idris: Python implementation guide from Specs/Validation/Deduplication.idr
    """

    def remove_duplicates(
        self, df: pl.DataFrame, policy: DedupPolicy = DedupPolicy.KEEP_LAST
    ) -> tuple[pl.DataFrame, DeduplicationResult]:
        """
        Remove duplicates based on (timestamp, stock_code)

        IMPORTANT: Sorts data first for deterministic results!

        Args:
            df: Polars DataFrame with columns: timestamp, stock_code
            policy: KeepFirst (preserve original) or KeepLast (use latest)

        Returns:
            (cleaned_df, stats): Deduplicated DataFrame and statistics

        Raises:
            ValueError: If duplicate rate > 10% (data quality alert)
        """
        total = len(df)

        # 1. Sort for determinism (CRITICAL!)
        # If data is not sorted, results will vary across runs
        sort_cols = ["timestamp"]
        if "created_at" in df.columns:
            sort_cols.append("created_at")

        df_sorted = df.sort(sort_cols, descending=False)

        # 2. Remove duplicates
        if policy == DedupPolicy.KEEP_LAST:
            # Last = most recent data
            df_unique = df_sorted.unique(subset=["timestamp", "stock_code"], keep="last")
        else:  # KEEP_FIRST
            # First = original data
            df_unique = df_sorted.unique(subset=["timestamp", "stock_code"], keep="first")

        # 3. Statistics
        unique = len(df_unique)
        duplicates = total - unique

        result = DeduplicationResult(
            total_rows=total, unique_rows=unique, duplicate_rows=duplicates
        )

        # 4. Data quality check
        if duplicates > 0:
            dup_rate = result.duplicate_rate * 100
            print(
                f"⚠️ Deduplication: Total={total}, Unique={unique}, "
                f"Duplicates={duplicates} ({dup_rate:.2f}%)"
            )

            # CRITICAL: If duplicate rate > 10%, something is wrong
            if dup_rate > 10.0:
                raise ValueError(
                    f"Data Quality Alert: Too many duplicates ({dup_rate:.2f}%). "
                    f"Check data source!"
                )

        return df_unique, result
