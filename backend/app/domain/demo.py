"""Reproduce all five decision responses: python -m app.domain.demo."""

import json
from pathlib import Path

from .autopay import preview_autopay
from .emergency import evaluate_emergency
from .forecasts import forecast_bills
from .joint import precheck_joint_payment
from .models import JointRuleConfig, MoneyContext
from .rewards import recommend_cards


SEED_PATH = Path(__file__).resolve().parents[3] / "fixtures" / "seed_profile_v1.json"


def load_scenario(name, path=None):
    path = Path(path) if path else SEED_PATH
    data = json.loads(path.read_text(encoding="utf-8"))
    if data["schema_version"] != 1:
        raise ValueError("unsupported fixture version")
    return MoneyContext.from_dict({**data["common"], **data["scenarios"][name]})


def demo_results():
    return {
        "bills": forecast_bills(load_scenario("bills")).to_dict(),
        "cards": recommend_cards(load_scenario("cards"), 12000, "groceries", preference="utilization").to_dict(),
        "autopay": preview_autopay(load_scenario("autopay"), "card_demo_1", 2900, 46000).to_dict(),
        "joint": precheck_joint_payment(load_scenario("joint"), "demo_actor", "new_payee", 85000,
                                       JointRuleConfig("checking_demo_1")).to_dict(),
        "emergency": evaluate_emergency(load_scenario("emergency"), 100000, allow_savings=True).to_dict(),
    }


if __name__ == "__main__":
    print(json.dumps(demo_results(), indent=2))
