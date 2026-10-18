"""Read-only endpoint checks before historical sandbox seeding."""
from pathlib import Path
import json
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from dotenv import dotenv_values
import httpx
import psycopg
from nessie_links import NessieLinkStore

root = Path(__file__).resolve().parents[1]
config = dotenv_values(root / '.env')
plan = json.loads((root / 'private/provision_users.json').read_text(encoding='utf-8-sig'))
with psycopg.connect(config['TIGERDATA_DATABASE_URL'], connect_timeout=8) as conn:
    conn.execute('SET TRANSACTION READ ONLY')
    row = conn.execute('SELECT accounts FROM cp_nessie_links WHERE owner_key=%s',
                       (NessieLinkStore.key(plan['users'][0]['subject']),)).fetchone()
with httpx.Client(timeout=15) as client:
    for resource in ('purchases', 'withdrawals', 'deposits', 'bills', 'loans'):
        response = client.get(config['NESSIE_BASE_URL'].rstrip('/') + '/accounts/' + row[0]['checking'] + '/' + resource,
                              params={'key': config['NESSIE_API_KEY']})
        try:
            data = response.json()
        except ValueError:
            data = None
        print(resource, 'HTTP', response.status_code, 'rows', len(data) if isinstance(data, list) else 'not-list')
