module Specs.Collector.RateLimit

import Data.List

%default total

--------------------------------------------------------------------------------
-- API Rate Limiting 로직
-- 목적: Kiwoom API 초당 5회 제한 준수 (타입 안전)
--------------------------------------------------------------------------------

||| Rate Limit 설정
public export
record RateLimitConfig where
  constructor MkRateLimit
  maxRequestsPerSecond : Nat  -- 초당 최대 요청 (5)
  windowSizeMs : Nat          -- 측정 윈도우 (1000ms)

||| Kiwoom API 기본 Rate Limit
public export
kiwoomRateLimit : RateLimitConfig
kiwoomRateLimit = MkRateLimit 5 1000

||| 요청 시간 기록
public export
record RequestTimestamp where
  constructor MkTimestamp
  requestTime : Integer  -- Unix timestamp (milliseconds)

||| Rate Limiter 상태
public export
record RateLimiterState where
  constructor MkLimiterState
  recentRequests : List RequestTimestamp  -- 최근 요청들
  config : RateLimitConfig

||| Rate Limit 검사 결과 (타입 안전)
||| Allowed는 갱신된 상태를 포함, Denied는 대기시간과 기존 상태 포함
public export
data RateLimitResult
  = Allowed RateLimiterState      -- 승인 (갱신된 상태 반환)
  | Denied Nat RateLimiterState   -- 거절 (대기시간 ms, 기존 상태 유지)

||| 요청 시도 (타입 안전 버전)
||| 현재 시간을 받아 허용/거절 결정 + 상태 갱신
public export
tryRequest : Integer -> RateLimiterState -> RateLimitResult
tryRequest currentTime state =
  let windowStart = currentTime - cast state.config.windowSizeMs
      recentCount = length $ filter (\r => r.requestTime >= windowStart) state.recentRequests
  in if recentCount < state.config.maxRequestsPerSecond
       then
         -- 승인: 새 요청 기록하고 갱신된 상태 반환
         let newRequest = MkTimestamp currentTime
             filtered = filter (\r => r.requestTime >= windowStart) state.recentRequests
             newState = { recentRequests := newRequest :: filtered } state
         in Allowed newState
       else
         -- 거절: 대기시간 계산
         let oldestInWindow = head' $ filter (\r => r.requestTime >= windowStart) state.recentRequests
             waitTime = case oldestInWindow of
                          Nothing => 0
                          Just oldest => cast $ (oldest.requestTime + cast state.config.windowSizeMs) - currentTime
         in Denied waitTime state

||| 요청 가능 여부만 확인 (부작용 없음)
public export
canMakeRequest : Integer -> RateLimiterState -> Bool
canMakeRequest currentTime state =
  let windowStart = currentTime - cast state.config.windowSizeMs
      recentCount = length $ filter (\r => r.requestTime >= windowStart) state.recentRequests
  in recentCount < state.config.maxRequestsPerSecond

||| 대기 시간 계산 (밀리초)
public export
calculateWaitTime : Integer -> RateLimiterState -> Nat
calculateWaitTime currentTime state =
  case tryRequest currentTime state of
    Allowed _ => 0
    Denied waitTime _ => waitTime

--------------------------------------------------------------------------------
-- Python 구현 가이드 (타입 안전 버전)
--------------------------------------------------------------------------------

export
pythonGuide : String
pythonGuide = """
=== Python Rate Limiter Implementation (Type-Safe) ===

```python
import time
from collections import deque
from typing import Deque, Union
from dataclasses import dataclass

@dataclass
class Allowed:
    new_state: 'RateLimiter'

@dataclass
class Denied:
    wait_time_ms: float
    current_state: 'RateLimiter'

RateLimitResult = Union[Allowed, Denied]

class RateLimiter:
    def __init__(self, max_per_second: int = 5, window_ms: int = 1000):
        self.max_per_second = max_per_second
        self.window_ms = window_ms
        self.requests: Deque[float] = deque()

    def try_request(self) -> RateLimitResult:
        now = time.time() * 1000  # milliseconds
        window_start = now - self.window_ms

        # 오래된 요청 제거
        while self.requests and self.requests[0] < window_start:
            self.requests.popleft()

        if len(self.requests) < self.max_per_second:
            # 승인: 새 상태 생성
            new_limiter = RateLimiter(self.max_per_second, self.window_ms)
            new_limiter.requests = self.requests.copy()
            new_limiter.requests.append(now)
            return Allowed(new_state=new_limiter)
        else:
            # 거절: 대기 시간 계산
            oldest = self.requests[0]
            wait_time = max(0, (oldest + self.window_ms) - now)
            return Denied(wait_time_ms=wait_time, current_state=self)

    def wait_and_request(self):
        \\\"\\\"\\\"차단 방식: 허용될 때까지 대기 후 새 상태 반환\\\"\\\"\\\"
        while True:
            result = self.try_request()
            if isinstance(result, Allowed):
                return result.new_state
            else:
                time.sleep(result.wait_time_ms / 1000.0)

# 사용 예제 (함수형 스타일)
limiter = RateLimiter(max_per_second=5)

for stock_code in all_stocks:
    result = limiter.try_request()

    if isinstance(result, Allowed):
        # 요청 허용됨
        data = kiwoom_api.get_data(stock_code)
        limiter = result.new_state  # 상태 갱신
    else:
        # 거절됨 → 대기
        time.sleep(result.wait_time_ms / 1000.0)
        # 재시도...

# 또는 간단한 차단 방식
limiter = RateLimiter(max_per_second=5)
for stock_code in all_stocks:
    limiter = limiter.wait_and_request()
    data = kiwoom_api.get_data(stock_code)
```

최적화 팁:
  - 병렬 처리 금지 (OpenAPI는 단일 연결만 지원)
  - 안전 마진: 초당 4.5회로 제한 권장 (max_per_second=4)
  - 재시도 로직: 429 에러 시 exponential backoff
  - 상태 불변성: 매 요청마다 새 limiter 객체 반환 (함수형 패턴)
"""
