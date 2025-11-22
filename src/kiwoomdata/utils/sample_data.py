"""
Sample data generator - For testing without Kiwoom API

Generates realistic OHLCV data that satisfies all invariants.
"""

import random
from datetime import datetime, timedelta

from ..core.types import OHLCV, Candle, Market, Stock
from ..core.time_types import Timeframe


class SampleDataGenerator:
    """
    Generate sample stock data for testing

    Based on random walk with realistic OHLCV relationships.
    """

    def __init__(self, seed: int = 42):
        random.seed(seed)

    def generate_stock(self, code: str, name: str, market: Market) -> Stock:
        """Generate a stock"""
        return Stock(code=code, name=name, market=market)

    def generate_ohlcv(
        self, base_price: float = 50000, volatility: float = 0.02
    ) -> OHLCV:
        """
        Generate realistic OHLCV that satisfies all invariants

        Invariants guaranteed:
        - All prices > 0
        - High >= max(Open, Close)
        - Low <= min(Open, Close)
        - Volume >= 0
        """
        # Random walk for open price
        open_price = base_price * (1 + random.uniform(-volatility, volatility))

        # Close with slight drift
        close_price = open_price * (1 + random.uniform(-volatility, volatility))

        # Ensure high >= max(open, close)
        max_oc = max(open_price, close_price)
        high_price = max_oc * (1 + random.uniform(0, volatility / 2))

        # Ensure low <= min(open, close)
        min_oc = min(open_price, close_price)
        low_price = min_oc * (1 - random.uniform(0, volatility / 2))

        # Volume (random but realistic)
        volume = random.randint(100000, 10000000)

        return OHLCV(
            open_price=round(open_price, 2),
            high_price=round(high_price, 2),
            low_price=round(low_price, 2),
            close_price=round(close_price, 2),
            volume=volume,
        )

    def generate_candle(
        self, stock_code: str, timestamp: int, base_price: float = 50000
    ) -> Candle:
        """Generate a single candle"""
        ohlcv = self.generate_ohlcv(base_price=base_price)
        return Candle(stock_code=stock_code, timestamp=timestamp, ohlcv=ohlcv)

    def generate_candles(
        self,
        stock_code: str,
        start_date: datetime,
        count: int,
        timeframe: Timeframe = Timeframe.MIN10,
        base_price: float = 50000,
    ) -> list[Candle]:
        """
        Generate a series of candles with random walk

        Args:
            stock_code: 6-digit stock code
            start_date: Starting datetime
            count: Number of candles to generate
            timeframe: Timeframe (MIN10, DAILY, etc.)
            base_price: Starting price

        Returns:
            List of candles with realistic price movements
        """
        candles = []
        current_time = start_date
        current_price = base_price

        # Time delta based on timeframe
        if timeframe == Timeframe.MIN10:
            delta = timedelta(minutes=10)
        elif timeframe == Timeframe.MIN1:
            delta = timedelta(minutes=1)
        elif timeframe == Timeframe.DAILY:
            delta = timedelta(days=1)
        elif timeframe == Timeframe.MIN60:
            delta = timedelta(hours=1)
        else:
            delta = timedelta(minutes=10)

        for _ in range(count):
            # Generate candle with current price as base
            candle = self.generate_candle(
                stock_code=stock_code,
                timestamp=int(current_time.timestamp() * 1000),
                base_price=current_price,
            )

            candles.append(candle)

            # Update price for next candle (random walk)
            current_price = candle.ohlcv.close_price
            current_time += delta

        return candles

    def generate_stocks(self, count: int = 10) -> list[Stock]:
        """Generate sample stocks"""
        stocks = []

        # KOSPI samples
        kospi_samples = [
            ("005930", "삼성전자"),
            ("000660", "SK하이닉스"),
            ("035420", "NAVER"),
            ("005380", "현대차"),
            ("051910", "LG화학"),
        ]

        # KOSDAQ samples
        kosdaq_samples = [
            ("247540", "에코프로비엠"),
            ("086520", "에코프로"),
            ("091990", "셀트리온헬스케어"),
            ("068270", "셀트리온"),
            ("096770", "SK이노베이션"),
        ]

        for code, name in kospi_samples[:count // 2]:
            stocks.append(self.generate_stock(code, name, Market.KOSPI))

        for code, name in kosdaq_samples[: count - count // 2]:
            stocks.append(self.generate_stock(code, name, Market.KOSDAQ))

        return stocks[:count]


# Example usage:
# generator = SampleDataGenerator()
# stocks = generator.generate_stocks(5)
# candles = generator.generate_candles(
#     stock_code="005930",
#     start_date=datetime(2024, 1, 1),
#     count=100,
#     timeframe=Timeframe.MIN10
# )
