"""
Rate Limiter - Implementation of Specs/Collector/RateLimit.idr

Type-safe rate limiting for Kiwoom API (5 requests/second limit).
Uses functional pattern: returns new state instead of mutating.
"""

import time
from collections import deque
from dataclasses import dataclass
from typing import Deque


@dataclass(frozen=True)
class RateLimitConfig:
    """
    Rate limit configuration
    Idris: record RateLimitConfig where
        maxRequestsPerSecond : Nat
        windowSizeMs : Nat
    """

    max_requests_per_second: int = 5
    window_size_ms: int = 1000


# Kiwoom API default rate limit (5 req/sec)
# Idris: kiwoomRateLimit : RateLimitConfig
KIWOOM_RATE_LIMIT = RateLimitConfig(max_requests_per_second=4, window_size_ms=1000)
# Note: Using 4 instead of 5 for safety margin


@dataclass(frozen=True)
class Allowed:
    """
    Request allowed - contains new state
    Idris: Allowed RateLimiterState
    """

    new_state: "RateLimiter"


@dataclass(frozen=True)
class Denied:
    """
    Request denied - contains wait time and current state
    Idris: Denied Nat RateLimiterState
    """

    wait_time_ms: float
    current_state: "RateLimiter"


# Union type for rate limit result
# Idris: data RateLimitResult = Allowed RateLimiterState | Denied Nat RateLimiterState
RateLimitResult = Allowed | Denied


class RateLimiter:
    """
    Rate limiter with functional state management
    Idris: record RateLimiterState where
        recentRequests : List RequestTimestamp
        config : RateLimitConfig

    Note: This is NOT frozen to allow mutation, but try_request() returns a NEW RateLimiter
    for functional-style usage.
    """

    def __init__(
        self,
        config: RateLimitConfig = KIWOOM_RATE_LIMIT,
        recent_requests: Deque[float] | None = None,
    ):
        self.config = config
        self.recent_requests: Deque[float] = recent_requests or deque()

    def try_request(self) -> RateLimitResult:
        """
        Try to make a request (type-safe functional version)
        Idris: tryRequest : Integer -> RateLimiterState -> RateLimitResult

        Returns:
            Allowed(new_state): Request approved, use new_state for next call
            Denied(wait_time_ms, current_state): Request denied, wait and retry
        """
        now = time.time() * 1000  # milliseconds
        window_start = now - self.config.window_size_ms

        # Remove old requests outside the window
        while self.recent_requests and self.recent_requests[0] < window_start:
            self.recent_requests.popleft()

        # Check if we can make a request
        if len(self.recent_requests) < self.config.max_requests_per_second:
            # Allowed: Create new state with this request added
            new_requests = deque(self.recent_requests)
            new_requests.append(now)
            new_limiter = RateLimiter(config=self.config, recent_requests=new_requests)
            return Allowed(new_state=new_limiter)
        else:
            # Denied: Calculate wait time
            oldest = self.recent_requests[0]
            wait_time = max(0, (oldest + self.config.window_size_ms) - now)
            return Denied(wait_time_ms=wait_time, current_state=self)

    def can_make_request(self) -> bool:
        """
        Check if request can be made (no side effects)
        Idris: canMakeRequest : Integer -> RateLimiterState -> Bool
        """
        result = self.try_request()
        return isinstance(result, Allowed)

    def calculate_wait_time(self) -> float:
        """
        Calculate wait time in milliseconds
        Idris: calculateWaitTime : Integer -> RateLimiterState -> Nat
        """
        result = self.try_request()
        if isinstance(result, Allowed):
            return 0
        else:
            return result.wait_time_ms

    def wait_and_request(self) -> "RateLimiter":
        """
        Blocking: Wait until allowed, then return new state
        Python-specific helper (not in Idris spec)

        Returns:
            New RateLimiter state after request is approved
        """
        while True:
            result = self.try_request()
            if isinstance(result, Allowed):
                return result.new_state
            else:
                time.sleep(result.wait_time_ms / 1000.0)


# Example usage (functional style):
# limiter = RateLimiter()
# for stock_code in all_stocks:
#     result = limiter.try_request()
#     if isinstance(result, Allowed):
#         data = fetch_data(stock_code)
#         limiter = result.new_state  # Update state
#     else:
#         time.sleep(result.wait_time_ms / 1000.0)
#         # Retry...

# Or blocking style:
# limiter = RateLimiter()
# for stock_code in all_stocks:
#     limiter = limiter.wait_and_request()
#     data = fetch_data(stock_code)
