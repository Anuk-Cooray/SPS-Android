"""Occupancy fractions from the synthetic demo model; not monetary values."""

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, model_validator


class DemandForecastPoint(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "ts": "2026-10-19T02:30:00Z",
                "yhat": 0.7,
                "yhat_lower": 0.6,
                "yhat_upper": 0.8,
                "demand_level": 0.7,
            }
        }
    )
    ts: AwareDatetime
    yhat: float = Field(ge=0, le=1, allow_inf_nan=False)
    yhat_lower: float = Field(ge=0, le=1, allow_inf_nan=False)
    yhat_upper: float = Field(ge=0, le=1, allow_inf_nan=False)
    demand_level: float = Field(ge=0, le=1, allow_inf_nan=False)

    @model_validator(mode="after")
    def ordered_band(self) -> "DemandForecastPoint":
        if not self.yhat_lower <= self.yhat <= self.yhat_upper:
            raise ValueError("Forecast band must enclose the point prediction")
        return self


class RetrainResult(BaseModel):
    status: str
    synthetic: bool
    model_kind: str
    lots: list[str]
