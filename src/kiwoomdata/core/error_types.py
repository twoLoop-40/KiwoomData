"""
Error types - Implementation of Specs/Core/ErrorTypes.idr
"""

from enum import Enum


class ErrorType(str, Enum):
    """Base error type classification"""

    API_ERROR = "api_error"
    VALIDATION_ERROR = "validation_error"
    NETWORK_ERROR = "network_error"
    DATABASE_ERROR = "database_error"
    RATE_LIMIT_ERROR = "rate_limit_error"
    SYNC_ERROR = "sync_error"


class KiwoomError(Exception):
    """
    Base exception for Kiwoom data collection system
    Idris: data KiwoomError
    """

    def __init__(self, error_type: ErrorType, message: str, context: dict | None = None):
        self.error_type = error_type
        self.message = message
        self.context = context or {}
        super().__init__(f"[{error_type.value}] {message}")


class APIError(KiwoomError):
    """
    API-related errors (Kiwoom OpenAPI failures)
    Idris: APIError : KiwoomError
    """

    def __init__(self, message: str, error_code: int | None = None, context: dict | None = None):
        ctx = context or {}
        if error_code is not None:
            ctx["error_code"] = error_code
        super().__init__(ErrorType.API_ERROR, message, ctx)
        self.error_code = error_code


class ValidationError(KiwoomError):
    """
    Data validation errors (Smart Constructor failures)
    Idris: ValidationError : KiwoomError
    """

    def __init__(self, message: str, field: str | None = None, context: dict | None = None):
        ctx = context or {}
        if field:
            ctx["field"] = field
        super().__init__(ErrorType.VALIDATION_ERROR, message, ctx)
        self.field = field


class NetworkError(KiwoomError):
    """
    Network-related errors (SFTP, connection failures)
    Idris: NetworkError : KiwoomError
    """

    def __init__(self, message: str, retry_count: int = 0, context: dict | None = None):
        ctx = context or {}
        ctx["retry_count"] = retry_count
        super().__init__(ErrorType.NETWORK_ERROR, message, ctx)
        self.retry_count = retry_count


class DatabaseError(KiwoomError):
    """
    Database errors (TimescaleDB, SQLite failures)
    Idris: DatabaseError : KiwoomError
    """

    def __init__(self, message: str, query: str | None = None, context: dict | None = None):
        ctx = context or {}
        if query:
            ctx["query"] = query
        super().__init__(ErrorType.DATABASE_ERROR, message, ctx)
        self.query = query


class RateLimitError(KiwoomError):
    """
    Rate limiting errors (exceeded request limit)
    Idris: RateLimitError : KiwoomError
    """

    def __init__(self, message: str, wait_time_ms: int = 0, context: dict | None = None):
        ctx = context or {}
        ctx["wait_time_ms"] = wait_time_ms
        super().__init__(ErrorType.RATE_LIMIT_ERROR, message, ctx)
        self.wait_time_ms = wait_time_ms


class SyncError(KiwoomError):
    """
    Synchronization errors (Windows ↔ Mac transfer failures)
    Idris: SyncError : KiwoomError
    """

    def __init__(
        self, message: str, failed_files: list[str] | None = None, context: dict | None = None
    ):
        ctx = context or {}
        if failed_files:
            ctx["failed_files"] = failed_files
        super().__init__(ErrorType.SYNC_ERROR, message, ctx)
        self.failed_files = failed_files or []
