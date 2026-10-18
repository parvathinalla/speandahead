import pytest
from scripts.provision_nessie_users import validate_plan


def plan():
    return {'users': [{'label': 'Primary', 'subject': 'auth0|primary', 'slot': 0},
                      {'label': 'Dependent', 'subject': 'auth0|dependent', 'slot': 1}],
            'joint': {'primary': 'Primary', 'dependent': 'Dependent', 'slot': 2, 'name': 'Joint'}}


def test_distinct_existing_subjects_and_separate_joint_slot():
    users, joint = validate_plan(plan())
    assert len(users) == 2 and joint['slot'] == 2


@pytest.mark.parametrize('fault', ['duplicate_subject', 'shared_slot', 'same_role', 'email'])
def test_invalid_provisioning_plans_rejected(fault):
    data = plan()
    if fault == 'duplicate_subject':
        data['users'][1]['subject'] = data['users'][0]['subject']
    elif fault == 'shared_slot':
        data['joint']['slot'] = 0
    elif fault == 'same_role':
        data['joint']['dependent'] = 'Primary'
    else:
        data['users'][0]['subject'] = 'example@example.invalid'
    with pytest.raises(ValueError):
        validate_plan(data)
