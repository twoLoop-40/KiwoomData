# Code Review: KiwoomData Project

## 1. 개요 및 요약
**KiwoomData** 프로젝트는 Idris2를 이용한 형식 명세(Formal Specification)를 Python 구현체에 매우 효과적으로 반영한 모범적인 사례입니다.
데이터의 무결성, 타입 안전성, 그리고 시스템의 견고함을 최우선으로 고려한 설계가 돋보입니다.
특히 `Smart Constructor`, `Immutable Data Structures`, `Functional Patterns`의 도입은 금융 데이터 처리에 필수적인 신뢰성을 보장합니다.

현재 Phase 4까지 진행된 상태이며, 핵심 타입 정의와 검증 로직이 매우 탄탄하게 구현되어 있습니다.

## 2. 강점 (Strengths)

### 2.1 명세와 구현의 일치 (Specification Alignment)
- `Specs/` 디렉토리의 Idris 명세를 Python 코드의 주석과 로직에 충실히 반영했습니다.
- GADT, Dependent Types와 같은 Idris의 고급 개념을 Python의 `Pydantic`, `NewType`, `Runtime Validation`으로 적절히 번역했습니다.

### 2.2 견고한 데이터 검증 (Robust Validation)
- **Smart Constructor 패턴**: `validate_candle`을 통해서만 `ValidCandle` 타입을 생성할 수 있게 하여, 시스템 내부로 유입되는 데이터의 무결성을 보장합니다.
- **도메인 불변 조건 검사**: `OHLCV` 데이터의 논리적 오류(예: `High < max(Open, Close)`)를 즉시 감지합니다.
- **타입 안전성**: `NewType`과 `Pydantic`을 활용하여 단순 `str`, `float` 등이 아닌 의미 있는 타입을 사용합니다.

### 2.3 함수형 프로그래밍 지향 (Functional Approach)
- **불변 객체**: `ConfigDict(frozen=True)`를 사용하여 데이터 변경으로 인한 사이드 이펙트를 원천 차단했습니다.
- **RateLimiter**: 상태를 변경(Mutation)하는 대신 새로운 상태를 반환하는 함수형 패턴을 사용하여 동시성 문제 발생 가능성을 줄이고 테스트를 용이하게 했습니다.

### 2.4 최신 기술 스택 (Modern Stack)
- `uv`, `ruff`, `mypy` 등 최신 Python 툴체인을 사용하여 개발 경험과 코드 품질을 높였습니다.
- `Polars`와 같은 고성능 라이브러리 채택은 대용량 데이터 처리에 적합한 선택입니다.

## 3. 개선 제안 (Recommendations)

### 3.1 버그 수정: `NewType` 언래핑 (Critical)
`src/kiwoomdata/validation/invariants.py`의 `get_raw_candle` 함수에 잠재적인 런타임 오류가 있습니다.
```python
def get_raw_candle(valid_candle: ValidCandle) -> Candle:
    return Candle.__wrapped__  # type: ignore  <-- Error!
```
`NewType`은 런타임에 메타데이터를 남기지 않으므로 `__wrapped__` 속성이 존재하지 않습니다. `ValidCandle` 인스턴스는 런타임에 `Candle` 인스턴스와 동일하므로 아래와 같이 수정해야 합니다.
```python
def get_raw_candle(valid_candle: ValidCandle) -> Candle:
    return valid_candle  # 런타임에는 이미 Candle 객체임
```

### 3.2 테스트 용이성: 시간 의존성 분리 (Enhancement)
`src/kiwoomdata/collector/rate_limiter.py`에서 `time.time()`을 직접 호출하고 있습니다.
```python
now = time.time() * 1000
```
이는 테스트 시 시간 제어를 어렵게 만듭니다. 시간을 반환하는 함수(Clock)를 의존성 주입(Dependency Injection) 받거나, 메서드 인자로 받도록 수정하면 결정론적인 테스트(Deterministic Testing)가 가능해집니다.

### 3.3 타입 강화 (Minor)
`Stock` 클래스 등에서 `StockCode` 타입을 더 적극적으로 활용할 수 있습니다. 현재 `stock_code: str`로 정의된 필드들을 `stock_code: StockCode`로 변경하여 타입 일관성을 높이는 것을 권장합니다.

## 4. 결론
전반적으로 매우 높은 수준의 코드 품질을 유지하고 있습니다. 제안된 `NewType` 관련 버그만 수정한다면, 데이터 수집 시스템으로서의 신뢰성은 충분히 확보된 것으로 보입니다.
앞으로 구현될 `Kiwoom API Wrapper`와 `DB Integration` 부분에서도 이러한 설계 철학이 유지되기를 기대합니다.

