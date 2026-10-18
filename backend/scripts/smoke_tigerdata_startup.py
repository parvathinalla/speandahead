"""Safe configured-service startup/restart smoke test; never executes payments."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


def run():
    import main
    from fastapi.testclient import TestClient
    from psycopg.conninfo import conninfo_to_dict
    details = conninfo_to_dict(main.joint_pg_store().store.url)
    if details.get('host') != 'xjqzw54az9.xye00m46ck.tsdb.cloud.timescale.com':
        raise ValueError('Unexpected database service')
    if (main.AUTH_MODE, main.DATA_MODE, main.JOINT_STORE, main.PAYMENT_MODE) != (
            'auth0', 'nessie', 'tigerdata', 'simulate'):
        raise ValueError('Unexpected application mode')
    for attempt in range(2):
        with TestClient(main.app) as client:
            assert client.get('/health').status_code == 200
            assert client.get('/api/dashboard').status_code == 401
            assert client.get('/api/dashboard', headers={'X-Demo-User': 'another-user'}).status_code == 401
            print('Startup/restart', attempt + 1, ': health OK; unauthenticated and spoofed-subject requests rejected')
    connection = main.joint_db()
    try:
        assert connection.execute('SELECT COALESCE(SUM(amount_cents),0) AS reserved FROM cp_joint_payments').fetchone()['reserved'] == 0
        print('Live PostgreSQL reservation dictionary lookup passed')
    finally:
        connection.close()
    with main.joint_pg_store().store.connect() as conn:
        conn.execute('SET TRANSACTION READ ONLY')
        print('Persisted application counts (links, memberships, payments):', conn.execute(
            'SELECT (SELECT COUNT(*) FROM cp_nessie_links),'
            '(SELECT COUNT(*) FROM cp_joint_accounts),(SELECT COUNT(*) FROM cp_joint_payments)').fetchone())


if __name__ == '__main__':
    try:
        run()
    except Exception as exc:
        print('Smoke test failed:', type(exc).__name__, '(details suppressed)')
        sys.exit(1)
