class AppError(Exception):
    """Base application error — carries HTTP status, machine code, and human detail."""

    def __init__(self, status_code: int, code: str, detail: str) -> None:
        self.status_code = status_code
        self.code = code
        self.detail = detail
        super().__init__(detail)


class NotFoundError(AppError):
    def __init__(self, detail: str = "Not found") -> None:
        super().__init__(404, "not_found", detail)


class UnauthorizedError(AppError):
    def __init__(self, detail: str = "Unauthorized") -> None:
        super().__init__(401, "unauthorized", detail)


class ForbiddenError(AppError):
    def __init__(self, detail: str = "Forbidden") -> None:
        super().__init__(403, "forbidden", detail)


class ConflictError(AppError):
    def __init__(self, detail: str = "Conflict") -> None:
        super().__init__(409, "conflict", detail)


class RateLimitError(AppError):
    def __init__(self, detail: str = "Rate limit exceeded") -> None:
        super().__init__(429, "rate_limit_exceeded", detail)


class ValidationFailedError(AppError):
    def __init__(self, detail: str = "Validation failed") -> None:
        super().__init__(422, "validation_failed", detail)


class UnsupportedMediaTypeError(AppError):
    def __init__(self, detail: str = "Unsupported media type") -> None:
        super().__init__(415, "unsupported_media_type", detail)


class FileTooLargeError(AppError):
    def __init__(self, detail: str = "File too large") -> None:
        super().__init__(413, "file_too_large", detail)
