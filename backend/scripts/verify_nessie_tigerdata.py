"""Read-only diagnostics. Never print credentials or banking identifiers."""
import json
from pathlib import Path
import sqlite3
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from dotenv import dotenv_values
from psycopg import sql
from psycopg.conninfo import conninfo_to_dict
from tigerdata_store import TigerDataStore
import httpx


def main():
    config = dotenv_values(ROOT / '.env')
    print('Configuration:', {k: config.get(k) for k in (
        'AUTH_MODE', 'DEMO_DATA_MODE', 'DEMO_STORE', 'JOINT_STORE', 'PAYMENT_MODE')})
    print('Credentials present:', {k: bool(config.get(k)) for k in (
        'NESSIE_API_KEY', 'AUTH0_DOMAIN', 'AUTH0_AUDIENCE', 'GEMINI_API_KEY')})
    url = config.get('TIGERDATA_DATABASE_URL', '')
    parsed = conninfo_to_dict(url)
    target = 'xjqzw54az9.xye00m46ck.tsdb.cloud.timescale.com'
    print('Database endpoint:', {k: parsed.get(k) for k in ('host', 'port', 'dbname', 'sslmode')})
    if parsed.get('host') != target or parsed.get('dbname') != 'tsdb' or parsed.get('port') != '31416':
        raise ValueError('Configured database does not match intended service; stopped.')
    with TigerDataStore(url).connect() as conn:
        conn.execute('SET TRANSACTION READ ONLY')
        print('Database/schema:', conn.execute('SELECT current_database(), current_schema()').fetchone())
        tables = conn.execute("SELECT table_name FROM information_schema.tables WHERE table_schema='public' ORDER BY table_name").fetchall()
        for (name,) in tables:
            count = conn.execute(sql.SQL('SELECT COUNT(*) FROM public.{}').format(sql.Identifier(name))).fetchone()[0]
            print('Table:', name, 'rows:', count)
        columns = conn.execute("SELECT column_name,data_type FROM information_schema.columns WHERE table_schema='public' AND table_name='cp_nessie_links' ORDER BY ordinal_position").fetchall()
        print('Mapping columns:', columns)
        print('Mapping constraints:', conn.execute("SELECT constraint_type FROM information_schema.table_constraints WHERE table_schema='public' AND table_name='cp_nessie_links'").fetchall())
        rows = conn.execute('SELECT owner_key,customer_id,accounts FROM public.cp_nessie_links').fetchall()
        manifest_path = ROOT / 'nessie_bulk_manifest.json'
        manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
        print('Private manifest present:', manifest_path.exists(), 'customer slots:', len(manifest.get('customers', {})))
        with httpx.Client(timeout=15, follow_redirects=False) as client:
            base = config.get('NESSIE_BASE_URL', 'https://prod-api.nessieisreal.com').rstrip('/')
            if not base.startswith('https://'):
                raise ValueError('Use HTTPS before sending private Nessie key')
            for index, (owner, customer, accounts) in enumerate(rows):
                shape = isinstance(owner, str) and len(owner) == 64 and all(c in '0123456789abcdef' for c in owner)
                print('Mapping', index, 'hash valid:', shape, 'accounts object:', isinstance(accounts, dict), 'checking present:', isinstance(accounts, dict) and bool(accounts.get('checking')))
                if not isinstance(accounts, dict):
                    continue
                matched = [slot for slot, ident in manifest.get('customers', {}).items() if ident == customer and manifest.get('accounts', {}).get(slot) == accounts]
                print('Matches private seed manifest:', bool(matched))
                response = client.get(base + '/customers/' + customer, params={'key': config.get('NESSIE_API_KEY', '')})
                print('Nessie customer status:', response.status_code)
                for kind, ident in accounts.items():
                    response = client.get(base + '/accounts/' + ident, params={'key': config.get('NESSIE_API_KEY', '')})
                    valid = response.status_code == 200 and response.json().get('customer_id') == customer and response.json().get('_id') == ident
                    print('Nessie account:', kind, 'HTTP:', response.status_code,
                          'ID match:', response.status_code == 200 and response.json().get('_id') == ident,
                          'ownership valid:', valid)
                print('Verified Auth0 identity binding: requires a verified user token; shape/manifest alone is insufficient.')
    path = Path(config.get('DB_PATH') or ROOT / 'creditpilot.sqlite3')
    if path.exists():
        with sqlite3.connect(path.resolve().as_uri() + '?mode=ro', uri=True) as conn:
            for (name,) in conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall():
                if name in ('actions', 'joint_accounts', 'joint_payments'):
                    print('SQLite', name, 'rows:', conn.execute('SELECT COUNT(*) FROM "' + name + '"').fetchone()[0])


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print('Diagnostic stopped:', type(exc).__name__, '(details suppressed to protect secrets)')
        sys.exit(1)
