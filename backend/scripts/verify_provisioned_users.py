"""Read-only administrative data-path check; does not replace a real Auth0 login."""
import argparse
import asyncio
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


async def run(plan):
    import main
    from fastapi import HTTPException
    from joint_accounts import membership
    if (main.AUTH_MODE, main.DATA_MODE, main.JOINT_STORE, main.PAYMENT_MODE) != ('auth0', 'nessie', 'tigerdata', 'simulate'):
        raise ValueError('Unexpected backend configuration')
    all_ids = set()
    gateway = main.NessieGateway()
    for user in plan['users']:
        mapped = main.manifest(user['subject'])
        accounts = await main.accounts(gateway, mapped)
        main.forecast_from(accounts, mapped)
        cards = main.card_rules(mapped, accounts)
        for kind in cards:
            await main.calculate_autopay(main.AutopayRequest(account=kind), gateway, user['subject'])
        identifiers = {account['_id'] for account in accounts.values()}
        if all_ids & identifiers:
            raise ValueError('Personal accounts overlap between users')
        all_ids |= identifiers
        connection = main.joint_db()
        try:
            try:
                joint = membership(connection, user['subject'])
                role = joint['role']
            except HTTPException as exc:
                if exc.status_code != 403:
                    raise
                role = 'individual'
            expected = ('primary' if user['label'] == plan['joint']['primary'] else
                        'dependent' if user['label'] == plan['joint']['dependent'] else 'individual')
            if role != expected:
                raise ValueError('Unexpected joint role')
        finally:
            connection.close()
        print(user['label'] + ': mapping resolved; Nessie ownership validated; dashboard data assembled; role=' + role)
        print('Credit cards:', len(cards), '; AutoPay previews passed:', len(cards))
    with main.joint_pg_store().store.connect() as connection:
        connection.execute('SET TRANSACTION READ ONLY')
        print('Exact rows (slots, links, memberships, payments):', connection.execute(
            'SELECT (SELECT COUNT(*) FROM cp_nessie_slots),(SELECT COUNT(*) FROM cp_nessie_links),'
            '(SELECT COUNT(*) FROM cp_joint_accounts),(SELECT COUNT(*) FROM cp_joint_payments)').fetchone())
    print('Real Auth0 browser login/JWT remains a separate end-to-end check. No transfers performed.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', type=Path, required=True)
    args = parser.parse_args()
    try:
        asyncio.run(run(json.loads(args.plan.read_text(encoding='utf-8-sig'))))
    except Exception as exc:
        print('Verification stopped:', type(exc).__name__, '(private details suppressed)')
        sys.exit(1)
