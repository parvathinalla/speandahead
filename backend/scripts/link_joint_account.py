"""Admin-only linking of verified Auth0 users to a Nessie sandbox joint account.

Run from the repository root; recipients JSON contains [{id,name,account_id}].
No user-facing endpoint can assign primary status or change bank account IDs.
"""
import argparse
import json
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import main
from joint_accounts import initialize
from joint_pg import JointPostgres
from nessie_links import NessieLinkStore


def valid_account_id(value):
    # Nessie deployments return either legacy hex IDs or canonical UUIDs.
    return isinstance(value, str) and bool(re.fullmatch(
        r'(?:[a-fA-F0-9]{24}|[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12})', value))


def provision(connection, account_id, primary, dependent, name, recipients):
    initialize(connection)
    if primary == dependent or not all(re.fullmatch(r"[^\s|]+\|[^\s]+", s) for s in (primary, dependent)):
        raise ValueError("Provide two distinct verified Auth0 subject IDs")
    if not valid_account_id(account_id):
        raise ValueError("Invalid Nessie joint account ID")
    if not recipients or len({r['id'] for r in recipients}) != len(recipients):
        raise ValueError("Supply unique linked recipient IDs")
    for r in recipients:
        if not r.get('id') or not r.get('name') or not valid_account_id(r.get('account_id')):
            raise ValueError("Each recipient needs id, name and a Nessie account_id")
        if r['account_id'].lower() == account_id.lower():
            raise ValueError("A recipient cannot be the payer account")
    primary_key = NessieLinkStore.key(primary) if getattr(connection, 'is_joint_postgres', False) else primary
    dependent_key = NessieLinkStore.key(dependent) if getattr(connection, 'is_joint_postgres', False) else dependent
    connection.execute('BEGIN IMMEDIATE')
    for subject in (primary_key, dependent_key):
        if connection.execute('SELECT 1 FROM joint_accounts WHERE primary_sub=? OR dependent_sub=?',
                              (subject, subject)).fetchone():
            raise ValueError("User already belongs to a joint account; refusing overwrite")
    connection.execute('''INSERT INTO joint_accounts
        (account_id,name,primary_sub,dependent_sub,recipients) VALUES(?,?,?,?,?)''',
        (account_id, name, primary_key, dependent_key, json.dumps(recipients)))
    connection.commit()


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--account-id', required=True)
    p.add_argument('--primary-sub', required=True)
    p.add_argument('--dependent-sub', required=True)
    p.add_argument('--name', default='Joint checking')
    p.add_argument('--recipients', type=Path, required=True)
    args = p.parse_args()
    if main.JOINT_STORE == 'tigerdata':
        main.joint_pg_store().initialize()
    connection = main.joint_db()
    try:
        provision(connection, args.account_id, args.primary_sub, args.dependent_sub,
                  args.name, json.loads(args.recipients.read_text(encoding='utf-8')))
        print('Joint membership linked. Primary must configure the approval limit in the app.')
    finally:
        connection.close()
