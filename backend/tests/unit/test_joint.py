from dataclasses import replace

import pytest

from app.domain.demo import load_scenario
from app.domain.joint import precheck_joint_payment
from app.domain.models import JointRuleConfig


def test_required_unusual_payment():
    result = precheck_joint_payment(load_scenario("joint"), "demo_actor", "new_payee", 85000,
                                    JointRuleConfig("checking_demo_1"))
    assert result.metrics["requires_partner_review"]
    assert {f.code for f in result.risk_flags} == {"NEW_PAYEE", "AMOUNT_ABOVE_THRESHOLD", "AMOUNT_ABOVE_HISTORY"}


@pytest.mark.parametrize("policy,required", [("never", False), ("unusual", True), ("always", True)])
def test_policy_controls_review(policy, required):
    result = precheck_joint_payment(load_scenario("joint"), "demo_actor", "new_payee", 85000,
                                    JointRuleConfig("checking_demo_1", review_policy=policy))
    assert result.metrics["requires_partner_review"] is required


def test_ordinary_payment_needs_no_unusual_review():
    result = precheck_joint_payment(load_scenario("joint"), "demo_actor", "known_payee", 10000,
                                    JointRuleConfig("checking_demo_1"))
    assert not result.metrics["is_unusual"]
    assert not result.metrics["requires_partner_review"]


def test_external_payment_cannot_be_blocked():
    result = precheck_joint_payment(load_scenario("joint"), "demo_actor", "new_payee", 85000,
                                    JointRuleConfig("checking_demo_1", initiated_in_app=False))
    assert not result.metrics["requires_partner_review"]
    assert not result.requires_approval


def test_unknown_actor_rejected_by_domain_membership_check():
    with pytest.raises(ValueError):
        precheck_joint_payment(load_scenario("joint"), "stranger", "new_payee", 85000,
                               JointRuleConfig("checking_demo_1"))


def test_empty_history_has_no_fabricated_median():
    result = precheck_joint_payment(replace(load_scenario("joint"), joint_history=()), "demo_actor",
                                    "new_payee", 100, JointRuleConfig("checking_demo_1"))
    assert [f.code for f in result.risk_flags] == ["NEW_PAYEE"]
