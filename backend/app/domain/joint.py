"""Explain unusual in-app payments. This module cannot authorize a payment."""

from decimal import Decimal
from statistics import median

from .models import RiskFlag, decision, integer, text_id


def precheck_joint_payment(context, actor, payee, amount_cents, rule_config):
    integer(amount_cents, "amount_cents", 1)
    text_id(actor, "actor")
    text_id(payee, "payee")
    membership = next((m for m in context.joint_memberships if m.account_id == rule_config.account_id), None)
    if membership is None or actor not in membership.user_ids:
        raise ValueError("actor is not mapped to selected joint account")
    history = [h for h in context.joint_history if h.account_id == rule_config.account_id]
    flags = []
    if payee not in {h.payee for h in history}:
        flags.append(RiskFlag("NEW_PAYEE"))
    if amount_cents > rule_config.threshold_cents:
        flags.append(RiskFlag("AMOUNT_ABOVE_THRESHOLD", evidence={"threshold_cents": rule_config.threshold_cents}))
    historical_median = median([Decimal(h.amount_cents) for h in history]) if history else None
    if historical_median is not None and Decimal(amount_cents * 10000) > historical_median * rule_config.median_multiple_bps:
        flags.append(RiskFlag("AMOUNT_ABOVE_HISTORY", evidence={"historical_median_cents": historical_median}))
    unusual = bool(flags)
    required = rule_config.initiated_in_app and (rule_config.review_policy == "always" or
                                                rule_config.review_policy == "unusual" and unusual)
    if not rule_config.initiated_in_app:
        flags.append(RiskFlag("EXTERNAL_PAYMENT_NOT_CONTROLLABLE", "info"))
    metrics = {"account_id": rule_config.account_id, "actor": actor, "payee": payee,
               "amount_cents": amount_cents, "is_unusual": unusual,
               "requires_partner_review": required, "review_policy": rule_config.review_policy,
               "initiated_in_app": rule_config.initiated_in_app}
    return decision(context, "joint", metrics, flags, requires_approval=rule_config.initiated_in_app)
