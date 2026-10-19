from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query

from app.core.config import LOT_RATES, is_debug
from app.schemas.forecast import DemandForecastPoint, RetrainResult
from app.services.forecast_service import ForecastService, get_forecast_service

router = APIRouter(prefix="/forecast", tags=["forecast (synthetic demo)"])


@router.get(
    "/demand",
    response_model=list[DemandForecastPoint],
    description="Synthetic occupancy fractions for the next N Colombo hourly boundaries. "
    "The shaded interval is an illustrative training-residual band, not calibrated coverage.",
)
def demand(
    lot_id: Annotated[str, Query(examples=["lot-main"])],
    service: Annotated[ForecastService, Depends(get_forecast_service)],
    horizon_hours: Annotated[int, Query(ge=1, le=168)] = 24,
) -> list[DemandForecastPoint]:
    if lot_id not in LOT_RATES:
        raise HTTPException(
            404, detail={"code": "LOT_NOT_FOUND", "message": "Unknown lot"}
        )
    return service.get_demand(lot_id, horizon_hours)


@router.post(
    "/retrain",
    response_model=RetrainResult,
    description="Development only (DEBUG=true); synchronously retrains on the local synthetic CSV.",
)
def retrain(
    service: Annotated[ForecastService, Depends(get_forecast_service)],
) -> RetrainResult:
    if not is_debug():
        raise HTTPException(
            403,
            detail={
                "code": "DEBUG_REQUIRED",
                "message": "Retraining requires DEBUG=true",
            },
        )
    report = service.retrain()
    return RetrainResult(
        status="retrained",
        synthetic=True,
        model_kind=report["model_kind"],
        lots=sorted(report["lots"]),
    )
