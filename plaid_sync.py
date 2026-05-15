# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx", "python-dotenv"]
# ///
"""
plaid-wave-sync: Syncs bank transactions from Plaid → Wave accounting.

Supports checking (asset) and credit card (liability) accounts.
Uses Plaid transaction_id as Wave externalId for deduplication.

Usage:
    uv run plaid_sync.py [--days 30] [--dry-run] [--reconcile] [--dump-accounts] [--add-bank] [--debug]

Environment variables:
    PLAID_CLIENT_ID / PLAID_SECRET
    WAVE_ACCESS_TOKEN
    WAVE_BUSINESS_ID          — your Wave business ID (run --dump-accounts to find it)
    PLAID_ACCESS_TOKENS       — comma-separated list: name:token:wave_account:type
                                e.g. "Bluevine:access-prod-xxx:My Checking (001):checking,Chase:access-prod-yyy:Credit Card (1234):credit_card"
"""

import os, sys, time, json, logging, argparse
import httpx
from datetime import datetime, timedelta
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

# ─── Config ───────────────────────────────────────────────────────────────────

PLAID_BASE = "https://production.plaid.com"
WAVE_BASE = "https://gql.waveapps.com/graphql/public"

def load_keywords():
    """Load keyword mappings from keywords.json."""
    kw_path = Path(__file__).parent / "keywords.json"
    if not kw_path.exists():
        log.error(f"keywords.json not found at {kw_path}")
        sys.exit(1)
    with open(kw_path) as f:
        data = json.load(f)
    return data["keywords"], data.get("fallback_expense", "Uncategorized Expense"), data.get("fallback_income", "Other")


def parse_accounts():
    """Parse PLAID_ACCESS_TOKENS env var into account configs."""
    raw = os.environ.get("PLAID_ACCESS_TOKENS", "")
    if not raw:
        return []
    accounts = []
    for entry in raw.split(","):
        parts = entry.strip().split(":")
        if len(parts) < 4:
            log.warning(f"Skipping malformed account entry: {entry}")
            continue
        name, token, wave_account, acct_type = parts[0], parts[1], ":".join(parts[2:-1]), parts[-1]
        accounts.append({"name": name, "token": token, "wave_account": wave_account, "type": acct_type})
    return accounts

# ─── Logging ──────────────────────────────────────────────────────────────────

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("plaid_sync")

# ─── API helpers ──────────────────────────────────────────────────────────────

def retry(fn, retries=3):
    for i in range(retries):
        try:
            return fn()
        except (httpx.TimeoutException, httpx.ConnectError) as e:
            if i == retries - 1:
                raise
            time.sleep(2 ** i)
            log.warning(f"Retry {i+1}: {e}")


def wave_gql(query, variables=None):
    def _call():
        r = httpx.post(WAVE_BASE, json={"query": query, "variables": variables or {}},
                       headers={"Authorization": f"Bearer {os.environ['WAVE_ACCESS_TOKEN']}"}, timeout=30)
        data = r.json()
        if "errors" in data:
            raise RuntimeError(f"Wave GQL: {data['errors']}")
        return data["data"]
    return retry(_call)


def plaid_post(endpoint, payload):
    payload["client_id"] = os.environ["PLAID_CLIENT_ID"]
    payload["secret"] = os.environ["PLAID_SECRET"]
    def _call():
        r = httpx.post(f"{PLAID_BASE}{endpoint}", json=payload, timeout=30)
        r.raise_for_status()
        return r.json()
    return retry(_call)

# ─── Wave ─────────────────────────────────────────────────────────────────────

def get_business_id():
    """Auto-detect business ID if not set."""
    biz_id = os.environ.get("WAVE_BUSINESS_ID")
    if biz_id:
        return biz_id
    data = wave_gql('{ businesses(page:1, pageSize:10) { edges { node { id name isArchived } } } }')
    for e in data["businesses"]["edges"]:
        if not e["node"]["isArchived"]:
            log.info(f"Using Wave business: {e['node']['name']}")
            return e["node"]["id"]
    raise RuntimeError("No active Wave business found")


def load_wave_accounts(biz_id):
    """Returns {name_lower: {id, name, type}} — paginated."""
    result = {}
    page = 1
    while True:
        data = wave_gql("""query($id: ID!, $page: Int!) {
            business(id: $id) {
                accounts(page: $page, pageSize: 50) {
                    pageInfo { totalPages }
                    edges { node { id name type { name } isArchived } }
                }
            }
        }""", {"id": biz_id, "page": page})
        for e in data["business"]["accounts"]["edges"]:
            n = e["node"]
            if not n["isArchived"]:
                key = n["name"].lower()
                if key not in result:
                    result[key] = {"id": n["id"], "name": n["name"], "type": n["type"]["name"]}
        if page >= data["business"]["accounts"]["pageInfo"]["totalPages"]:
            break
        page += 1
    return result


def find_account_id(accounts, name):
    return accounts.get(name.lower())

# ─── Categorization ───────────────────────────────────────────────────────────

def categorize(txn_name, accounts, keywords):
    name_lower = txn_name.lower()
    for keyword, target in keywords.items():
        if keyword in name_lower:
            if target is None:
                return None, None, True
            acct = find_account_id(accounts, target)
            if acct:
                return acct["id"], acct["name"], False
            log.warning(f"  KEYWORD '{keyword}' → '{target}' not found in Wave accounts")
            return None, target, False
    return None, None, False

# ─── Plaid ────────────────────────────────────────────────────────────────────

def fetch_plaid_transactions(access_token, days=30):
    end = datetime.now().strftime("%Y-%m-%d")
    start = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")
    all_txns, offset = [], 0
    while True:
        data = plaid_post("/transactions/get", {
            "access_token": access_token,
            "start_date": start, "end_date": end,
            "options": {"count": 100, "offset": offset},
        })
        if "error_code" in data:
            log.error(f"Plaid error: {data['error_code']} - {data.get('error_message','')}")
            if data["error_code"] == "ITEM_LOGIN_REQUIRED":
                try:
                    url, _ = generate_reauth_link(access_token)
                    log.error(f"  Re-auth needed: {url}")
                except Exception:
                    pass
            return []
        txns = data.get("transactions", [])
        all_txns.extend(txns)
        offset += len(txns)
        if offset >= data.get("total_transactions", 0):
            break
    return all_txns

# ─── Wave transaction creation ────────────────────────────────────────────────

class DuplicateError(Exception):
    pass


def create_wave_transaction(*, description, amount, date, anchor_id, line_id, external_id, acct_type, is_expense, biz_id):
    abs_amount = f"{abs(amount):.2f}"
    if acct_type == "checking":
        anchor_dir = "WITHDRAWAL" if is_expense else "DEPOSIT"
        line_bal = "INCREASE"
    else:
        anchor_dir = "DEPOSIT" if is_expense else "WITHDRAWAL"
        line_bal = "DECREASE" if is_expense else "INCREASE"

    result = wave_gql("""mutation($input: MoneyTransactionCreateInput!) {
        moneyTransactionCreate(input: $input) {
            didSucceed
            inputErrors { path message code }
            transaction { id }
        }
    }""", {"input": {
        "businessId": biz_id,
        "externalId": external_id,
        "date": date,
        "description": description[:255],
        "anchor": {"accountId": anchor_id, "amount": abs_amount, "direction": anchor_dir},
        "lineItems": [{"accountId": line_id, "amount": abs_amount, "balance": line_bal}],
    }})

    r = result["moneyTransactionCreate"]
    if not r["didSucceed"]:
        errs = r.get("inputErrors") or []
        for e in errs:
            path_str = " ".join(e.get("path") or []).lower()
            msg = (e.get("message") or "").lower()
            if "externalid" in path_str or "already exists" in msg:
                raise DuplicateError()
        raise RuntimeError(f"Wave rejected: {errs}")
    return r["transaction"]["id"]

# ─── Invoice matching ──────────────────────────────────────────────────────────

def load_open_invoices(biz_id):
    invoices = []
    page = 1
    while True:
        data = wave_gql("""query($id: ID!, $page: Int!) {
            business(id: $id) {
                invoices(page: $page, pageSize: 50, sort: [CREATED_AT_ASC]) {
                    pageInfo { totalPages }
                    edges { node {
                        id invoiceNumber status
                        total { value } amountDue { value }
                        customer { name }
                        invoiceDate
                    } }
                }
            }
        }""", {"id": biz_id, "page": page})
        for e in data["business"]["invoices"]["edges"]:
            n = e["node"]
            if n["status"] in ("SENT", "VIEWED", "OVERDUE", "PARTIAL"):
                due = float(n["amountDue"]["value"].replace(",", ""))
                if due > 0:
                    invoices.append({
                        "id": n["id"], "number": n["invoiceNumber"],
                        "customer": n["customer"]["name"].lower(),
                        "amount_due": due, "date": n["invoiceDate"],
                    })
        if page >= data["business"]["invoices"]["pageInfo"]["totalPages"]:
            break
        page += 1
    return invoices


def match_invoice(txn_name, amount, open_invoices):
    name_lower = txn_name.lower()
    abs_amount = abs(amount)
    for inv in open_invoices:
        customer_words = inv["customer"].split()
        match_word = next((w for w in customer_words if len(w) > 3), customer_words[0] if customer_words else "")
        if match_word in name_lower and abs(inv["amount_due"] - abs_amount) < 0.01:
            return inv
    return None


def record_invoice_payment(invoice_id, amount, date, payment_account_id):
    result = wave_gql("""mutation($input: InvoicePaymentCreateManualInput!) {
        invoicePaymentCreateManual(input: $input) {
            didSucceed
            inputErrors { path message }
        }
    }""", {"input": {
        "invoiceId": invoice_id,
        "paymentAccountId": payment_account_id,
        "amount": f"{abs(amount):.2f}",
        "paymentDate": date,
        "paymentMethod": "BANK_TRANSFER",
        "exchangeRate": "1",
    }})
    r = result["invoicePaymentCreateManual"]
    if not r["didSucceed"]:
        raise RuntimeError(f"Invoice payment failed: {r.get('inputErrors')}")

# ─── Plaid Hosted Link ────────────────────────────────────────────────────────

def generate_reauth_link(access_token):
    data = plaid_post("/link/token/create", {
        "client_name": "plaid-wave-sync",
        "country_codes": ["US"],
        "language": "en",
        "user": {"client_user_id": "user"},
        "access_token": access_token,
        "hosted_link": {},
    })
    return data.get("hosted_link_url"), data.get("link_token")


def generate_new_link():
    data = plaid_post("/link/token/create", {
        "client_name": "plaid-wave-sync",
        "country_codes": ["US"],
        "language": "en",
        "user": {"client_user_id": "user"},
        "products": ["transactions"],
        "hosted_link": {},
    })
    return data.get("hosted_link_url"), data.get("link_token")


def poll_link_result(link_token, timeout=600, interval=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        data = plaid_post("/link/token/get", {"link_token": link_token})
        for session in data.get("link_sessions", []):
            results = session.get("results", {})
            items = results.get("item_add_results", [])
            if items:
                return items[0].get("public_token")
            on_success = session.get("on_success")
            if on_success and on_success.get("public_token"):
                return on_success["public_token"]
        time.sleep(interval)
    return None


def exchange_public_token(public_token):
    data = plaid_post("/item/public_token/exchange", {"public_token": public_token})
    return data.get("access_token"), data.get("item_id")

# ─── Reconciliation ───────────────────────────────────────────────────────────

def reconcile(accounts_cfg, days):
    log.info(f"\n{'='*60}\nRECONCILIATION (last {days} days)\n{'='*60}")
    for acct_cfg in accounts_cfg:
        txns = fetch_plaid_transactions(acct_cfg["token"], days)
        plaid_out = sum(t["amount"] for t in txns if t["amount"] > 0 and not t["pending"])
        plaid_in = sum(abs(t["amount"]) for t in txns if t["amount"] < 0 and not t["pending"])
        log.info(f"\n  {acct_cfg['name']}:")
        log.info(f"    Transactions: {len(txns)}")
        log.info(f"    Money out: ${plaid_out:.2f}")
        log.info(f"    Money in:  ${plaid_in:.2f}")
        log.info(f"    Net:       ${plaid_in - plaid_out:.2f}")

# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Sync Plaid → Wave")
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--reconcile", action="store_true")
    parser.add_argument("--dump-accounts", action="store_true")
    parser.add_argument("--add-bank", action="store_true", help="Connect a new bank via Hosted Link")
    parser.add_argument("--debug", action="store_true")
    args = parser.parse_args()

    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)

    for var in ("PLAID_CLIENT_ID", "PLAID_SECRET", "WAVE_ACCESS_TOKEN"):
        if not os.environ.get(var):
            if var == "WAVE_ACCESS_TOKEN" and args.add_bank:
                continue
            log.error(f"Missing env var: {var}")
            sys.exit(1)

    # ── Add bank mode ─────────────────────────────────────────────────────────
    if args.add_bank:
        url, link_token = generate_new_link()
        print(f"\nOpen this link to connect a new bank:\n  {url}\n")
        print("Waiting for you to complete... (Ctrl+C to cancel)")
        public_token = poll_link_result(link_token)
        if public_token:
            access_token, item_id = exchange_public_token(public_token)
            print(f"\n✓ Connected! Add to PLAID_ACCESS_TOKENS:")
            print(f"  YourBank:{access_token}:Wave Account Name:checking")
            print(f"  item_id: {item_id}")
        else:
            print("\n✗ Timed out.")
        return

    biz_id = get_business_id()
    wave_accounts = load_wave_accounts(biz_id)
    log.info(f"Loaded {len(wave_accounts)} Wave accounts")

    if args.dump_accounts:
        print(f"\nWave Business ID: {biz_id}\n")
        by_type = {}
        for info in wave_accounts.values():
            by_type.setdefault(info["type"], []).append(info["name"])
        for t in sorted(by_type):
            print(f"[{t}]")
            for n in sorted(by_type[t]):
                print(f"  {n}")
            print()

        keywords, _, _ = load_keywords()
        print(f"{'='*60}\nKeyword validation:")
        targets = sorted(set(v for v in keywords.values() if v))
        for t in targets:
            found = find_account_id(wave_accounts, t)
            status = f"✓ → {found['name']}" if found else "✗ NOT FOUND"
            print(f"  {t:40s} {status}")
        return

    accounts_cfg = parse_accounts()
    if not accounts_cfg:
        log.error("No accounts configured. Set PLAID_ACCESS_TOKENS env var.")
        log.error("Format: Name:access-token:Wave Account Name:checking")
        sys.exit(1)

    if args.reconcile:
        reconcile(accounts_cfg, args.days)
        return

    keywords, fallback_expense, fallback_income = load_keywords()
    open_invoices = load_open_invoices(biz_id)
    if open_invoices:
        log.info(f"Open invoices: {len(open_invoices)}")

    # ── Sync ──────────────────────────────────────────────────────────────────
    created = skipped = errors = 0

    for acct_cfg in accounts_cfg:
        acct_type = acct_cfg["type"]
        wallet = find_account_id(wave_accounts, acct_cfg["wave_account"])
        if not wallet:
            log.error(f"Wave account '{acct_cfg['wave_account']}' not found! Run --dump-accounts")
            errors += 1
            continue

        log.info(f"\n{'='*60}\n{acct_cfg['name']} → {wallet['name']} ({acct_type})\n{'='*60}")

        txns = fetch_plaid_transactions(acct_cfg["token"], args.days)
        log.info(f"Fetched {len(txns)} transactions")

        for txn in txns:
            name = txn.get("name", "").strip()
            amount = float(txn["amount"])
            date = txn["date"]
            txn_id = txn["transaction_id"]

            if not name or txn.get("pending"):
                skipped += 1
                continue

            name_lower = name.lower()
            # CC payment on the CC side — skip to avoid double-counting
            # The checking side records it as Uncategorized Expense for manual recategorization
            if acct_type == "credit_card" and any(k in name_lower for k in ("automatic payment", "payment - thank", "online payment")):
                log.debug(f"  SKIP cc-payment (CC side): {name}")
                skipped += 1
                continue

            is_expense = amount > 0
            line_id, matched, skip = categorize(name, wave_accounts, keywords)

            if skip:
                log.debug(f"  SKIP: {name}")
                skipped += 1
                continue

            if not line_id:
                fallback = fallback_expense if is_expense else fallback_income
                fallback_acct = find_account_id(wave_accounts, fallback)
                if fallback_acct:
                    line_id = fallback_acct["id"]
                    matched = f"UNCATEGORIZED → {fallback_acct['name']}"
                    log.info(f"  UNMATCHED → {fallback}: {name} | ${abs(amount):.2f}")
                else:
                    log.error(f"  NO MATCH: {name} | ${abs(amount):.2f}")
                    errors += 1
                    continue

            direction = "EXPENSE" if is_expense else "INCOME"
            log.info(f"  {direction}: {name} | ${abs(amount):.2f} → {matched}")

            invoice_matched = None
            if not is_expense and acct_type == "checking" and open_invoices:
                invoice_matched = match_invoice(name, amount, open_invoices)
                if invoice_matched:
                    log.info(f"    📎 Matched invoice #{invoice_matched['number']}")

            if args.dry_run:
                skipped += 1
                continue

            try:
                if invoice_matched:
                    record_invoice_payment(invoice_matched["id"], amount, date, wallet["id"])
                    open_invoices.remove(invoice_matched)
                    log.info(f"    ✓ Invoice #{invoice_matched['number']} marked paid")
                    created += 1
                else:
                    wave_id = create_wave_transaction(
                        description=name, amount=amount, date=date,
                        anchor_id=wallet["id"], line_id=line_id,
                        external_id=txn_id, acct_type=acct_type,
                        is_expense=is_expense, biz_id=biz_id,
                    )
                    log.info(f"    ✓ {wave_id[:30]}")
                    created += 1
            except DuplicateError:
                log.debug(f"    ⊘ duplicate")
                skipped += 1
            except Exception as e:
                log.error(f"    ✗ {e}")
                errors += 1

    log.info(f"\n{'='*60}\nDone: created={created} skipped={skipped} errors={errors}\n{'='*60}")
    if errors >= 3:
        sys.exit(1)


if __name__ == "__main__":
    main()
