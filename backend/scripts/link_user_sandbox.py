#!/usr/bin/env python3
"""Offline admin-only binding of one Nessie seed to one verified Auth0 subject."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def provision(source, directory, subject, partner=None):
    if not 5 <= len(subject) <= 256:
        raise ValueError("Invalid Auth0 subject")
    if partner == subject:
        raise ValueError("Partner must differ from account owner")
    data = json.loads(source.read_text(encoding="utf-8"))
    accounts = list(data.get("ids", {}).get("accounts", {}).values())
    if len(accounts) != 6 or len(set(accounts)) != 6 or not data.get("app_bills"):
        raise ValueError("Seed must contain six unique Nessie accounts and app-only bills")
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / (hashlib.sha256(subject.encode()).hexdigest() + ".json")
    if target.exists():
        raise ValueError("Auth0 user is already bound; refusing overwrite")
    for candidate in directory.glob("*.json"):
        previous = json.loads(candidate.read_text(encoding="utf-8"))
        prior_accounts = set(previous.get("ids", {}).get("accounts", {}).values())
        if prior_accounts.intersection(accounts):
            raise ValueError("Nessie account IDs must never be shared between users")
    data["owner_sub"] = subject
    if partner:
        data["joint_partner_sub"] = partner
    fd = os.open(str(target), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            json.dump(data, out, indent=2)
            out.write("\n")
    except BaseException:
        target.unlink(missing_ok=True)
        raise
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--subject", required=True, help="Exact Auth0 subject claim")
    parser.add_argument("--partner-sub", default=None)
    parser.add_argument("--source", type=Path, default=ROOT / "seed_manifest.json")
    parser.add_argument("--tenant-dir", type=Path, default=Path(
        os.getenv("TENANT_MANIFEST_DIR", str(ROOT / "private" / "tenants"))))
    args = parser.parse_args()
    try:
        result = provision(args.source, args.tenant_dir, args.subject, args.partner_sub)
        print("Sandbox binding created:", result)
        print("Account data accessible only to the mapped verified Auth0 subject.")
    except (OSError, ValueError) as error:
        print("ERROR:", error, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
