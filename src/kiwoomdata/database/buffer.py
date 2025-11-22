"""
SQLite Buffer - Implementation of temporary data storage

Specs: Specs/Database/Schema.idr concept
Purpose: Buffer data before exporting to Parquet
"""

import sqlite3
from pathlib import Path

import polars as pl

from ..core.types import Candle
from ..core.time_types import Timeframe


class SQLiteBuffer:
    """
    SQLite buffer for temporary candle storage

    Design:
    - Fast INSERT (no indexes during collection)
    - Batch export to Parquet (1 hour intervals)
    - Automatic schema creation
    - Type-safe using Pydantic models
    """

    def __init__(self, db_path: str | Path = "data/buffer.db"):
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(str(self.db_path))
        self._create_schema()

    def _create_schema(self) -> None:
        """
        Create candles table

        Schema matches Specs/Database/Schema.idr:
        - timestamp (INTEGER) - Unix timestamp in ms
        - stock_code (TEXT) - 6-digit code
        - open_price, high_price, low_price, close_price (REAL)
        - volume (INTEGER)
        - timeframe (TEXT) - '10min', 'daily', etc.
        - created_at (INTEGER) - Collection timestamp
        """
        cursor = self.conn.cursor()

        cursor.execute("""
            CREATE TABLE IF NOT EXISTS candles (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp INTEGER NOT NULL,
                stock_code TEXT NOT NULL,
                open_price REAL NOT NULL,
                high_price REAL NOT NULL,
                low_price REAL NOT NULL,
                close_price REAL NOT NULL,
                volume INTEGER NOT NULL,
                timeframe TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                CHECK (open_price > 0),
                CHECK (high_price > 0),
                CHECK (low_price > 0),
                CHECK (close_price > 0),
                CHECK (volume >= 0)
            )
        """)

        self.conn.commit()

    def insert_candle(self, candle: Candle, timeframe: Timeframe) -> None:
        """Insert a single candle"""
        cursor = self.conn.cursor()

        cursor.execute(
            """
            INSERT INTO candles (
                timestamp, stock_code,
                open_price, high_price, low_price, close_price, volume,
                timeframe, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
            (
                candle.timestamp,
                candle.stock_code,
                candle.ohlcv.open_price,
                candle.ohlcv.high_price,
                candle.ohlcv.low_price,
                candle.ohlcv.close_price,
                candle.ohlcv.volume,
                timeframe.value,
                int(candle.datetime.timestamp() * 1000),
            ),
        )

        self.conn.commit()

    def insert_candles(self, candles: list[Candle], timeframe: Timeframe) -> int:
        """
        Insert multiple candles (batch)

        Returns:
            Number of inserted rows
        """
        cursor = self.conn.cursor()

        data = [
            (
                c.timestamp,
                c.stock_code,
                c.ohlcv.open_price,
                c.ohlcv.high_price,
                c.ohlcv.low_price,
                c.ohlcv.close_price,
                c.ohlcv.volume,
                timeframe.value,
                int(c.datetime.timestamp() * 1000),
            )
            for c in candles
        ]

        cursor.executemany(
            """
            INSERT INTO candles (
                timestamp, stock_code,
                open_price, high_price, low_price, close_price, volume,
                timeframe, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
            data,
        )

        self.conn.commit()
        return len(candles)

    def read_as_polars(
        self, timeframe: Timeframe | None = None, limit: int | None = None
    ) -> pl.DataFrame:
        """
        Read candles as Polars DataFrame

        Args:
            timeframe: Filter by timeframe (None = all)
            limit: Limit number of rows (None = all)

        Returns:
            Polars DataFrame with candles
        """
        query = "SELECT * FROM candles"

        if timeframe:
            query += f" WHERE timeframe = '{timeframe.value}'"

        query += " ORDER BY timestamp"

        if limit:
            query += f" LIMIT {limit}"

        return pl.read_database(query, self.conn)

    def count(self, timeframe: Timeframe | None = None) -> int:
        """Count candles in buffer"""
        cursor = self.conn.cursor()

        if timeframe:
            cursor.execute(
                "SELECT COUNT(*) FROM candles WHERE timeframe = ?", (timeframe.value,)
            )
        else:
            cursor.execute("SELECT COUNT(*) FROM candles")

        return cursor.fetchone()[0]

    def clear(self, timeframe: Timeframe | None = None) -> int:
        """
        Clear buffer (after export)

        Args:
            timeframe: Clear specific timeframe (None = all)

        Returns:
            Number of deleted rows
        """
        cursor = self.conn.cursor()

        if timeframe:
            cursor.execute("DELETE FROM candles WHERE timeframe = ?", (timeframe.value,))
        else:
            cursor.execute("DELETE FROM candles")

        self.conn.commit()
        return cursor.rowcount

    def close(self) -> None:
        """Close database connection"""
        self.conn.close()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()


# Example usage:
# buffer = SQLiteBuffer("data/buffer.db")
# buffer.insert_candles(candles, Timeframe.MIN10)
# df = buffer.read_as_polars(Timeframe.MIN10)
# buffer.clear(Timeframe.MIN10)
