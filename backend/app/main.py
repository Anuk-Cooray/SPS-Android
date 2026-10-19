from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException

from app.api.billing_routes import router
from app.api.forecast_routes import router as forecast_router
from app.services.forecast_service import ForecastUnavailable
from app.services.payments.base import PaymentError

app = FastAPI(title="Smart Parking Billing — milestone demo", version="0.1.0")
app.include_router(router, prefix="/api/v1")
app.include_router(forecast_router, prefix="/api/v1")


@app.exception_handler(HTTPException)
async def http_error(request: Request, error: HTTPException) -> JSONResponse:
    detail = (
        error.detail
        if isinstance(error.detail, dict)
        else {"code": "HTTP_ERROR", "message": str(error.detail)}
    )
    return JSONResponse(status_code=error.status_code, content={"error": detail})


@app.exception_handler(RequestValidationError)
async def validation_error(
    request: Request, error: RequestValidationError
) -> JSONResponse:
    return JSONResponse(
        status_code=422,
        content={
            "error": {
                "code": "VALIDATION_ERROR",
                "message": "; ".join(
                    f"{'.'.join(map(str, item['loc']))}: {item['msg']}"
                    for item in error.errors()
                ),
            }
        },
    )


@app.get("/api/v1/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.exception_handler(ForecastUnavailable)
async def forecast_unavailable(
    request: Request, error: ForecastUnavailable
) -> JSONResponse:
    return JSONResponse(
        status_code=503,
        content={"error": {"code": "FORECAST_UNAVAILABLE", "message": str(error)}},
    )


@app.exception_handler(PaymentError)
async def payment_error(request: Request, error: PaymentError) -> JSONResponse:
    return JSONResponse(
        status_code=error.status,
        content={"error": {"code": error.code, "message": error.message}},
    )
