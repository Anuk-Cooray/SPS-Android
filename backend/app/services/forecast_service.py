"""One process-local model cache; no automatic training during API requests."""

from collections.abc import Callable
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from functools import lru_cache
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import RLock
from zoneinfo import ZoneInfo

from app.core.config import LOT_RATES
from app.schemas.forecast import DemandForecastPoint
from ml.generate_synthetic_data import DEFAULT_DATA
from ml.predict import DEFAULT_MODEL, load_bundle, predict
from ml.train_baseline import train

COLOMBO = ZoneInfo("Asia/Colombo")


class ForecastUnavailable(RuntimeError):
    """Model missing or unusable; the API should return a stable 503 error."""


class ForecastService:
    def __init__(
        self,
        model_path: Path = DEFAULT_MODEL,
        data_path: Path = DEFAULT_DATA,
        now: Callable[[], datetime] | None = None,
    ) -> None:
        self.model_path = model_path
        self.data_path = data_path
        self._now = now or (lambda: datetime.now(timezone.utc))
        self._bundle: dict | None = None
        self._lock = RLock()

    @staticmethod
    def _read_model(path: Path) -> dict:
        try:
            bundle = load_bundle(path)
            if bundle["schema_version"] != 1 or bundle["synthetic"] is not True:
                raise ValueError("Expected the milestone synthetic model schema")
            if bundle["model_kind"] not in {"prophet", "gradient_boosting"}:
                raise ValueError("Unsupported model kind")
            if not set(LOT_RATES).issubset(bundle["lots"]):
                raise ValueError("Model must contain all registered lots")
            return bundle
        except Exception as error:
            # Artifact incompatibility must not silently become zero-demand pricing.
            raise ForecastUnavailable(
                "Forecast model unavailable; run the documented training commands"
            ) from error

    def _model(self) -> dict:
        if self._bundle is None:
            self._bundle = self._read_model(self.model_path)
        return self._bundle

    def get_demand(
        self, lot_id: str, horizon_hours: int = 24, start: datetime | None = None
    ) -> list[DemandForecastPoint]:
        if lot_id not in LOT_RATES:
            raise ValueError("Unknown lot")
        if not 1 <= horizon_hours <= 168:
            raise ValueError("Horizon must be between 1 and 168 hours")
        if start is None:
            current = self._now().astimezone(COLOMBO)
            start = current.replace(minute=0, second=0, microsecond=0) + timedelta(
                hours=1
            )
        if start.utcoffset() is None:
            raise ValueError("Forecast start must include a timezone")
        with self._lock:
            bundle = self._model()
            try:
                points = predict(bundle, lot_id, horizon_hours, start)
                return [DemandForecastPoint.model_validate(point) for point in points]
            except Exception as error:
                raise ForecastUnavailable(
                    "Forecast prediction unavailable; regenerate the local model"
                ) from error

    def demand_for_hour(
        self, lot_id: str, timestamp: datetime
    ) -> tuple[Decimal, datetime]:
        if timestamp.utcoffset() is None:
            raise ValueError("Demand timestamp must include a timezone")
        hour = timestamp.astimezone(COLOMBO).replace(minute=0, second=0, microsecond=0)
        point = self.get_demand(lot_id, horizon_hours=1, start=hour)[0]
        # Float occupancy crosses into the Decimal-only monetary engine via text.
        return Decimal(str(point.demand_level)), hour.astimezone(timezone.utc)

    def retrain(self) -> dict:
        # Development operation only. Serialize against inference in this process.
        with self._lock:
            self.model_path.parent.mkdir(parents=True, exist_ok=True)
            with TemporaryDirectory(dir=self.model_path.parent) as directory:
                staging = Path(directory)
                try:
                    report = train(self.data_path, staging)
                    candidate = self._read_model(staging / "baseline.pkl")
                    # Validate prediction before replacing the currently cached model.
                    for lot_id in LOT_RATES:
                        for point in predict(candidate, lot_id, horizon_hours=1):
                            DemandForecastPoint.model_validate(point)
                    (staging / "metrics.json").replace(
                        self.model_path.parent / "metrics.json"
                    )
                    (staging / "forecast_demo.png").replace(
                        self.model_path.parent / "forecast_demo.png"
                    )
                    (staging / "baseline.pkl").replace(self.model_path)
                    self._bundle = candidate
                    return report
                except Exception as error:
                    raise ForecastUnavailable(
                        "Retraining failed; check local history and model dependencies"
                    ) from error


@lru_cache(maxsize=1)
def get_forecast_service() -> ForecastService:
    return ForecastService()
