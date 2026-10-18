import pytest
from scripts.add_nessie_cards import CARDS, find_card, metadata


def test_four_demo_cards_have_no_reused_account_ids_in_metadata():
    assert len(CARDS) == 4
    for index, kind in enumerate(CARDS):
        result = metadata(kind, 'actual-provider-id-' + str(index))
        assert result['account_id'] == 'actual-provider-id-' + str(index)
        assert result['limit_usd'] >= CARDS[kind]['balance']
        assert result['source'] == 'local_app_simulation'
        assert 'Demo' in result['display_name']


def test_reuses_only_unique_owned_credit_cards():
    account = {'_id': 'existing', 'nickname': 'card', 'customer_id': 'owner', 'type': 'Credit Card'}
    assert find_card([account], 'card', 'owner') == account
    assert find_card([account], 'other-card', 'owner') is None
    with pytest.raises(ValueError):
        find_card([account, account], 'card', 'owner')
    with pytest.raises(ValueError):
        find_card([account], 'card', 'different-owner')
    with pytest.raises(ValueError):
        find_card([{**account, 'type': 'Checking'}], 'card', 'owner')
