"""
Tests for rate limiter (Specs/Collector/RateLimit.idr implementation)
"""

import time

from kiwoomdata.collector.rate_limiter import (
    Allowed,
    Denied,
    RateLimitConfig,
    RateLimiter,
)


def test_rate_limiter_allows_within_limit():
    """Test that requests within limit are allowed"""
    config = RateLimitConfig(max_requests_per_second=5, window_size_ms=1000)
    limiter = RateLimiter(config=config)

    # First 5 requests should be allowed
    for i in range(5):
        result = limiter.try_request()
        assert isinstance(result, Allowed), f"Request {i+1} should be allowed"
        limiter = result.new_state


def test_rate_limiter_denies_over_limit():
    """Test that requests over limit are denied"""
    config = RateLimitConfig(max_requests_per_second=5, window_size_ms=1000)
    limiter = RateLimiter(config=config)

    # Make 5 requests (all allowed)
    for _ in range(5):
        result = limiter.try_request()
        assert isinstance(result, Allowed)
        limiter = result.new_state

    # 6th request should be denied
    result = limiter.try_request()
    assert isinstance(result, Denied)
    assert result.wait_time_ms > 0


def test_rate_limiter_wait_and_request():
    """Test blocking wait_and_request method"""
    config = RateLimitConfig(max_requests_per_second=2, window_size_ms=100)
    limiter = RateLimiter(config=config)

    # Make 2 requests quickly
    limiter = limiter.wait_and_request()
    limiter = limiter.wait_and_request()

    # 3rd request will wait (should take ~100ms)
    start = time.time()
    limiter = limiter.wait_and_request()
    elapsed = (time.time() - start) * 1000

    # Should have waited approximately 100ms
    assert elapsed >= 50, f"Should wait, but only took {elapsed}ms"


def test_rate_limiter_functional_pattern():
    """Test functional-style state management"""
    limiter1 = RateLimiter()

    # Get new state
    result = limiter1.try_request()
    assert isinstance(result, Allowed)
    limiter2 = result.new_state

    # Old state is unchanged (immutable pattern)
    assert len(limiter1.recent_requests) == 0
    assert len(limiter2.recent_requests) == 1
