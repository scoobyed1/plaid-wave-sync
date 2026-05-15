# plaid-wave-sync

Automatically sync bank transactions from [Plaid](https://plaid.com) → [Wave](https://www.waveapps.com) accounting. No manual data entry.

- **Keyword-based categorization** — auto-generated from your previous year's general ledger
- **Deduplication** — safe to re-run anytime (uses Plaid transaction IDs)
- **Credit card support** — handles both checking and CC accounts
- **Invoice matching** — auto-marks invoices as paid when deposits match
- **GitHub Actions ready** — runs daily on a schedule, zero infrastructure

---

## Setup (5 minutes)

### Step 1 → Fork this repo

[![Fork this repo](https://img.shields.io/badge/1-Fork_this_repo_→-181717?style=for-the-badge&logo=github)](../../fork)

Click above to create your own copy. Your secrets and config stay private in your fork.

### Step 2 → Open in Codespaces

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/jeffreylsoffer/plaid-wave-sync?quickstart=1)

The setup script runs automatically and walks you through everything:
- Creates your Plaid account & activates trial (10 free bank connections)
- Connects your bank accounts via Plaid Hosted Link
- Shows your Wave accounts and matches them to your banks
- Generates keyword mappings from your Wave general ledger CSV
- Saves all secrets to your repo
- Enables the workflow and triggers a test run

Once setup completes, close the Codespace — everything runs automatically from there.

---

## Usage

```bash
# Preview what would sync
uv run plaid_sync.py --dry-run --days 30

# Sync for real
uv run plaid_sync.py --days 30

# Weekly reconciliation check
uv run plaid_sync.py --reconcile --days 7

# Validate your keyword mappings
uv run plaid_sync.py --dump-accounts
```

## How It Works

```
Plaid (bank)              keywords.json           Wave (accounting)
     │                         │                        │
     │  fetch transactions     │  categorize            │  create entries
     ├────────────────────────►├───────────────────────►│
     │                         │                        │
     │  positive = expense     │  keyword match → acct  │  deduped by
     │  negative = income      │  no match → fallback   │  transaction_id
```

- **Checking accounts**: Plaid positive = money out (expense), negative = money in (income)
- **Credit cards**: Plaid positive = charge (expense), negative = payment/refund
- **Invoices**: Income deposits are auto-matched to open invoices by customer name + amount
- **Duplicates**: Silently skipped via `externalId` — safe to re-run anytime

## Commands

| Flag | Description |
|------|-------------|
| `--days N` | Sync last N days (default: 30) |
| `--dry-run` | Preview without writing to Wave |
| `--reconcile` | Compare Plaid totals for the period |
| `--dump-accounts` | Show Wave accounts + validate keywords |
| `--add-bank` | Connect a new bank via Plaid Hosted Link |
| `--debug` | Verbose logging |

## Deployment Options

| Platform | How |
|----------|-----|
| **GitHub Actions** (recommended) | Fork → setup → done. Runs daily at 9am ET. |
| **Any VPS / cron** | `0 13 * * * cd /path && uv run plaid_sync.py --days 3` (9am ET / 1pm UTC) |
| **Systemd timer** | See below |

<details>
<summary>Systemd timer setup</summary>

```ini
# /etc/systemd/system/plaid-sync.service
[Unit]
Description=Plaid → Wave sync

[Service]
Type=oneshot
WorkingDirectory=/path/to/plaid-wave-sync
EnvironmentFile=/path/to/.env
ExecStart=/usr/local/bin/uv run plaid_sync.py --days 3
```

```ini
# /etc/systemd/system/plaid-sync.timer
[Unit]
Description=Daily plaid sync

[Timer]
OnCalendar=*-*-* 13:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
systemctl enable --now plaid-sync.timer
```
</details>

## FAQ

**What if a transaction doesn't match any keyword?**
Goes to your fallback account (set in `keywords.json`). Review in Wave weekly, add keywords as patterns emerge.

**Is it safe to run multiple times?**
Yes. Duplicates are silently skipped.

**What if my bank token expires?**
The script generates a Plaid Hosted Link URL for re-auth. Open it in any browser, log in, done. Token stays the same.

**Do I need an LLM?**
No. Keywords are auto-generated from your Wave general ledger CSV — the script reads how you've already categorized transactions and builds the mapping. No AI needed.

**What about credit card payments?**
CC payments (transfers between checking and CC) can't be recorded via Wave's API as inter-account transfers. They go to "Uncategorized Expense" for you to recategorize in Wave as a CC payment. All actual CC charges sync correctly as expenses.

## Requirements

- Python 3.11+
- [uv](https://docs.astral.sh/uv/)
- Plaid account (trial = 10 free connections)
- Wave account with API access

## License

MIT
