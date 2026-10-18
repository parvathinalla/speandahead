"""Shared domain contract. Money is cents; rates are integer basis points.

Dataclasses are usable independently and by FastAPI/Pydantic adapters. The API
must construct this context from authorized backend data, never client balances.
"""

from dataclasses import asdict, dataclass, fields
from datetime import date, datetime, timezone
from decimal import Decimal
from hashlib import sha256
import json
from typing import Any


def integer(value: int, name: str, minimum: int | None = 0) -> None:
    if type(value) is not int or (minimum is not None and value < minimum):
        raise ValueError(f"{name} must be an integer >= {minimum}")


def text_id(value: str, name: str = "id") -> None:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{name} must be nonempty text")


def utc(value: datetime) -> datetime:
    if not isinstance(value, datetime) or value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("timestamps must be timezone-aware")
    return value.astimezone(timezone.utc)


def calendar_date(value: date) -> None:
    if type(value) is not date:
        raise ValueError("schedule values must be dates, not datetimes")


def source(value: str) -> None:
    if value not in {"nessie", "fixture", "user_input"}:
        raise ValueError("unknown source")


@dataclass(frozen=True)
class AccountSnapshot:
    id: str
    available_cents: int
    reserve_cents: int = 0
    source: str = "fixture"

    def __post_init__(self):
        text_id(self.id)
        integer(self.available_cents, "available_cents", None)
        integer(self.reserve_cents, "reserve_cents")
        source(self.source)


@dataclass(frozen=True)
class Bill:
    id: str
    account_id: str
    due_on: date
    amount_cents: int
    status: str = "unpaid"
    reflected_in_available: bool = False
    source: str = "fixture"

    def __post_init__(self):
        text_id(self.id)
        text_id(self.account_id, "account_id")
        calendar_date(self.due_on)
        integer(self.amount_cents, "amount_cents")
        if self.status not in {"unpaid", "pending", "paid", "canceled"}:
            raise ValueError("invalid bill status")
        if type(self.reflected_in_available) is not bool:
            raise ValueError("reflected_in_available must be boolean")
        source(self.source)


@dataclass(frozen=True)
class CashFlow:
    id: str
    account_id: str
    on: date
    amount_cents: int
    confirmed: bool = True
    reflected_in_available: bool = False
    bill_id: str | None = None

    def __post_init__(self):
        text_id(self.id)
        text_id(self.account_id, "account_id")
        calendar_date(self.on)
        integer(self.amount_cents, "amount_cents")
        if type(self.confirmed) is not bool or type(self.reflected_in_available) is not bool:
            raise ValueError("cash flow flags must be boolean")


@dataclass(frozen=True)
class RewardRule:
    category: str
    rate_bps: int
    remaining_cap_cents: int | None = None
    fallback_rate_bps: int = 0

    def __post_init__(self):
        text_id(self.category, "category")
        integer(self.rate_bps, "rate_bps")
        integer(self.fallback_rate_bps, "fallback_rate_bps")
        if max(self.rate_bps, self.fallback_rate_bps) > 10000:
            raise ValueError("reward rate exceeds 100%")
        if self.remaining_cap_cents is not None:
            integer(self.remaining_cap_cents, "remaining_cap_cents")


@dataclass(frozen=True)
class CardProfile:
    id: str
    limit_cents: int
    balance_cents: int
    close_estimate: date | None = None
    projected_charges_cents: int = 0
    rules: tuple[RewardRule, ...] = ()
    eligible: bool = True
    excluded_categories: tuple[str, ...] = ()
    source: str = "fixture"

    def __post_init__(self):
        text_id(self.id)
        integer(self.limit_cents, "limit_cents")
        integer(self.balance_cents, "balance_cents", None)  # posted refunds can create credit
        integer(self.projected_charges_cents, "projected_charges_cents")
        if self.close_estimate is not None:
            calendar_date(self.close_estimate)
        if type(self.eligible) is not bool:
            raise ValueError("eligible must be boolean")
        if len({r.category for r in self.rules}) != len(self.rules):
            raise ValueError("duplicate reward categories")
        source(self.source)


@dataclass(frozen=True)
class JointPayment:
    account_id: str
    payee: str
    amount_cents: int

    def __post_init__(self):
        text_id(self.account_id)
        text_id(self.payee, "payee")
        integer(self.amount_cents, "amount_cents", 1)


@dataclass(frozen=True)
class JointMembership:
    account_id: str
    user_ids: tuple[str, ...]

    def __post_init__(self):
        text_id(self.account_id)
        if len(set(self.user_ids)) != len(self.user_ids) or len(self.user_ids) < 2:
            raise ValueError("joint membership requires distinct users")
        for user in self.user_ids:
            text_id(user, "user_id")


@dataclass(frozen=True)
class JointRuleConfig:
    account_id: str
    threshold_cents: int = 50000
    median_multiple_bps: int = 30000
    review_policy: str = "unusual"
    initiated_in_app: bool = True

    def __post_init__(self):
        text_id(self.account_id)
        integer(self.threshold_cents, "threshold_cents", 1)
        integer(self.median_multiple_bps, "median_multiple_bps", 10000)
        if self.review_policy not in {"never", "unusual", "always"}:
            raise ValueError("invalid review policy")
        if type(self.initiated_in_app) is not bool:
            raise ValueError("initiated_in_app must be boolean")


@dataclass(frozen=True)
class MoneyContext:
    snapshot_id: str
    captured_at: datetime
    checking: tuple[AccountSnapshot, ...]
    savings: tuple[AccountSnapshot, ...] = ()
    bills: tuple[Bill, ...] = ()
    cards: tuple[CardProfile, ...] = ()
    safety_buffer_cents: int = 0
    future_income: tuple[CashFlow, ...] = ()
    approved_outflows: tuple[CashFlow, ...] = ()
    joint_memberships: tuple[JointMembership, ...] = ()
    joint_history: tuple[JointPayment, ...] = ()
    source_flags: tuple[str, ...] = ("fixture",)
    currency: str = "USD"
    complete: bool = True
    evaluated_at: datetime | None = None

    def __post_init__(self):
        text_id(self.snapshot_id)
        object.__setattr__(self, "captured_at", utc(self.captured_at))
        object.__setattr__(self, "evaluated_at", utc(self.evaluated_at or self.captured_at))
        if self.evaluated_at < self.captured_at:
            raise ValueError("evaluation precedes snapshot")
        integer(self.safety_buffer_cents, "safety_buffer_cents")
        if self.currency != "USD":
            raise ValueError("only USD is supported")
        if type(self.complete) is not bool or not self.source_flags:
            raise ValueError("complete must be boolean and source_flags nonempty")
        groups = (self.checking + self.savings, self.cards, self.bills,
                  self.future_income + self.approved_outflows)
        for group in groups:
            if len({item.id for item in group}) != len(group):
                raise ValueError("duplicate resource id")
        account_ids = {a.id for a in self.checking + self.savings}
        for item in (*self.bills, *self.future_income, *self.approved_outflows,
                     *self.joint_memberships, *self.joint_history):
            if item.account_id not in account_ids:
                raise ValueError("unknown cash account")
        if len({m.account_id for m in self.joint_memberships}) != len(self.joint_memberships):
            raise ValueError("duplicate joint membership")
        bill_map = {b.id: b for b in self.bills}
        linked = set()
        for flow in self.future_income:
            if flow.bill_id is not None:
                raise ValueError("income cannot reference a bill")
        for flow in self.approved_outflows:
            if not flow.confirmed:
                raise ValueError("approved outflows must be confirmed")
            if flow.bill_id is not None:
                bill = bill_map.get(flow.bill_id)
                if bill is None or flow.bill_id in linked:
                    raise ValueError("unknown or multiply scheduled bill")
                if (bill.account_id, bill.amount_cents) != (flow.account_id, flow.amount_cents):
                    raise ValueError("linked bill/outflow mismatch")
                linked.add(flow.bill_id)

    @classmethod
    def from_dict(cls, data: dict) -> "MoneyContext":
        """Parse the canonical fixture/wire shape; reject unknown fields."""
        unknown = set(data) - {f.name for f in fields(cls)}
        if unknown:
            raise ValueError(f"unknown context fields: {sorted(unknown)}")
        values = dict(data)
        for key in ("captured_at", "evaluated_at"):
            if values.get(key) is not None:
                values[key] = datetime.fromisoformat(values[key])
        for key in ("checking", "savings"):
            values[key] = tuple(AccountSnapshot(**a) for a in values.get(key, []))
        values["bills"] = tuple(Bill(**{**b, "due_on": date.fromisoformat(b["due_on"])})
                                for b in values.get("bills", []))
        for key in ("future_income", "approved_outflows"):
            values[key] = tuple(CashFlow(**{**f, "on": date.fromisoformat(f["on"])})
                                for f in values.get(key, []))
        cards = []
        for card in values.get("cards", []):
            card = dict(card)
            card["rules"] = tuple(RewardRule(**r) for r in card.get("rules", []))
            card["excluded_categories"] = tuple(card.get("excluded_categories", []))
            if card.get("close_estimate"):
                card["close_estimate"] = date.fromisoformat(card["close_estimate"])
            cards.append(CardProfile(**card))
        values["cards"] = tuple(cards)
        values["joint_history"] = tuple(JointPayment(**h) for h in values.get("joint_history", []))
        values["joint_memberships"] = tuple(JointMembership(**{**m, "user_ids": tuple(m["user_ids"])})
                                            for m in values.get("joint_memberships", []))
        values["source_flags"] = tuple(values.get("source_flags", ("fixture",)))
        return cls(**values)


@dataclass(frozen=True)
class RiskFlag:
    code: str
    severity: str = "warning"
    evidence: dict[str, Any] | None = None


@dataclass(frozen=True)
class DecisionOption:
    id: str
    label: str
    projected_effects: dict[str, Any]
    constraints: tuple[str, ...] = ()
    enabled: bool = True


def json_value(value):
    if isinstance(value, Decimal):
        return str(value)  # preserve precision; cents remain JSON integers
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    raise TypeError(f"unsupported JSON value: {type(value)}")


@dataclass(frozen=True)
class DecisionResult:
    scenario_id: str
    snapshot_id: str
    captured_at: datetime
    calculated_at: datetime
    feature: str
    status: str
    metrics: dict[str, Any]
    risk_flags: tuple[RiskFlag, ...]
    options: tuple[DecisionOption, ...]
    recommendation_option_id: str | None
    explanation_inputs: dict[str, Any]
    requires_approval: bool
    source_flags: tuple[str, ...]
    sandbox_only: bool = True

    def to_dict(self) -> dict:
        return json.loads(json.dumps(asdict(self), default=json_value))


def decision(context, feature, metrics, flags=(), options=(), recommendation=None,
             requires_approval=False):
    flags = list(flags)
    options = tuple(options)
    if not context.complete:
        flags.append(RiskFlag("INCOMPLETE_SNAPSHOT", "error"))
    if any(f.severity == "error" for f in flags):
        options = tuple(DecisionOption(o.id, o.label, o.projected_effects,
                                      o.constraints + ("RESOLVE_DATA_ERRORS",), False) for o in options)
        recommendation = None
    payload = {"context": asdict(context), "feature": feature, "metrics": metrics,
               "options": [asdict(o) for o in options], "flags": [asdict(f) for f in flags]}
    key = sha256(json.dumps(payload, sort_keys=True, default=json_value).encode()).hexdigest()[:24]
    status = "unavailable" if any(f.severity == "error" for f in flags) else "warning" if flags else "ok"
    return DecisionResult(key, context.snapshot_id, context.captured_at, context.evaluated_at,
                          feature, status, metrics, tuple(flags), options, recommendation,
                          {"facts": metrics, "reason_codes": [f.code for f in flags]},
                          requires_approval, context.source_flags)
