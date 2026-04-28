#!/usr/bin/env python3
"""
Apple Developer Cert Cleanup
============================
撤銷帳號內超過保留量的 Development 證書，避免 CI 用 -allowProvisioningUpdates
不停申請新 cert 撞配額（Individual paid 帳號上限 5 張）。

策略：
- 列出所有 IOS_DEVELOPMENT / DEVELOPMENT / APPLE_DEVELOPMENT 類型 cert
- 依建立時間從新到舊排序
- 保留最新 1 張（給最近的 CI 用）
- 撤銷其餘超過 3 天的舊 cert
- 「不到 3 天」的不動，避免撤掉正在跑的 CI 的 cert

執行條件：
- 環境變數：API_KEY_ID / API_KEY_BASE64 (.p8 內容 base64) / API_ISSUER_ID
- 必要 Python 套件：pyjwt、cryptography、requests

授權：App Store Connect API JWT (ES256)
"""

import os
import sys
import time
import base64
from datetime import datetime, timedelta, timezone

import jwt          # PyJWT
import requests


KEEP_COUNT = 1            # 保留最新 N 張
REVOKE_OLDER_THAN_DAYS = 3
JWT_LIFETIME_SEC = 1200   # ASC JWT max 20 min


def make_token() -> str:
    key_id = os.environ["API_KEY_ID"]
    issuer_id = os.environ["API_ISSUER_ID"]
    p8_base64 = os.environ["API_KEY_BASE64"]
    private_key = base64.b64decode(p8_base64).decode("utf-8")

    now = int(time.time())
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + JWT_LIFETIME_SEC,
        "aud": "appstoreconnect-v1",
    }
    headers = {"kid": key_id, "typ": "JWT"}
    return jwt.encode(payload, private_key, algorithm="ES256", headers=headers)


def list_dev_certs(token: str) -> list[dict]:
    """列出所有 development 類型 cert（包含舊版 IOS_DEVELOPMENT 與新版 APPLE_DEVELOPMENT）。"""
    url = "https://api.appstoreconnect.apple.com/v1/certificates"
    headers = {"Authorization": f"Bearer {token}"}
    all_certs: list[dict] = []
    page_url = url
    params: dict | None = {"limit": 200}
    while page_url:
        r = requests.get(page_url, headers=headers, params=params, timeout=30)
        r.raise_for_status()
        body = r.json()
        all_certs.extend(body.get("data", []))
        page_url = body.get("links", {}).get("next")
        params = None  # next URL already has params

    # ASC 不支援 multi-value filter[certificateType]，所以拉全部後本地過濾
    dev_types = {"IOS_DEVELOPMENT", "DEVELOPMENT", "APPLE_DEVELOPMENT"}
    return [c for c in all_certs if c["attributes"].get("certificateType") in dev_types]


def revoke_cert(token: str, cert_id: str) -> tuple[bool, str]:
    url = f"https://api.appstoreconnect.apple.com/v1/certificates/{cert_id}"
    headers = {"Authorization": f"Bearer {token}"}
    r = requests.delete(url, headers=headers, timeout=30)
    if r.status_code in (200, 204):
        return True, ""
    return False, f"{r.status_code}: {r.text[:200]}"


def main() -> int:
    token = make_token()
    certs = list_dev_certs(token)
    print(f"Found {len(certs)} development certificate(s)")

    if not certs:
        print("Nothing to clean up")
        return 0

    # ASC API 的 Certificate.attributes 沒有 createdDate；用 expirationDate 反推：
    # cert 通常 1 年到期，所以「expirationDate 越晚 = 建立越新」。
    sorted_certs = sorted(
        certs,
        key=lambda c: c["attributes"].get("expirationDate", ""),
        reverse=True,
    )

    print("\nAll dev certs (newest first by expiration):")
    for c in sorted_certs:
        attr = c["attributes"]
        print(f"  - {c['id']} | {attr.get('name', '')} | "
              f"{attr.get('certificateType', '')} | "
              f"expires={attr.get('expirationDate', 'unknown')}")

    # 「建立超過 3 天」≈「到期 < 365-3=362 天後」
    threshold = datetime.now(timezone.utc) + timedelta(days=365 - REVOKE_OLDER_THAN_DAYS)
    candidates = sorted_certs[KEEP_COUNT:]
    to_revoke: list[dict] = []
    for c in candidates:
        exp_str = c["attributes"].get("expirationDate")
        if not exp_str:
            # 沒 expirationDate 就直接候選撤銷
            to_revoke.append(c)
            continue
        exp = datetime.fromisoformat(exp_str.replace("Z", "+00:00"))
        if exp < threshold:
            to_revoke.append(c)

    print(f"\nWill keep newest {KEEP_COUNT}; revoking {len(to_revoke)} cert(s) "
          f"established more than {REVOKE_OLDER_THAN_DAYS} days ago")

    failures = 0
    for c in to_revoke:
        cid = c["id"]
        attr = c["attributes"]
        print(f"  Revoking {cid} ({attr.get('name', '')}, expires={attr.get('expirationDate', '')})...", end=" ")
        ok, err = revoke_cert(token, cid)
        if ok:
            print("ok")
        else:
            print(f"FAIL ({err})")
            failures += 1

    print(f"\nDone. Revoked {len(to_revoke) - failures} / {len(to_revoke)}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
