# plaid-wave-sync

Automatically sync bank transactions from [Plaid](https://plaid.com) → [Wave](https://www.waveapps.com) accounting. No manual data entry.

- **Keyword-based categorization** — fast, deterministic, free (no LLM needed)
- **Deduplication** — safe to re-run anytime (uses Plaid transaction IDs)
- **Credit card support** — handles both checking and CC accounts
- **Invoice matching** — auto-marks invoices as paid when deposits match
- **GitHub Actions ready** — runs daily on a schedule, zero infrastructure

---

## Setup (5 minutes)

### Step 1 → Get your API keys

[![Get Plaid Keys](https://img.shields.io/badge/1a-Plaid_Dashboard-0A85FF?style=for-the-badge&logo=data:image/svg+xml;base64,PHN2Zy8+)](https://dashboard.plaid.com/signup)
[![Get Wave Token](https://img.shields.io/badge/1b-Wave_API_Token-1C6DD0?style=for-the-badge)](https://developer.waveapps.com/hc/en-us/articles/360019762711)

You need:
- Plaid: `client_id` and `secret` (trial plan = 10 free bank connections)
- Wave: API access token

### Step 2 → Connect your bank

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/YOUR_USERNAME/plaid-wave-sync?quickstart=1)

Once the terminal opens, run:

```bash
export PLAID_CLIENT_ID=your_id_here
export PLAID_SECRET=your_secret_here
uv run plaid_sync.py --add-bank
```

1. A URL appears — open it in your browser
2. Log into your bank
3. The terminal prints your `access_token` — **save it**

Repeat for each bank account.

> **No Codespaces?** Run the same commands on your local machine. Just needs [uv](https://docs.astral.sh/uv/).

### Step 3 → Find your Wave account names

```bash
export WAVE_ACCESS_TOKEN=your_wave_token_here
uv run plaid_sync.py --dump-accounts
```

Note your **Business ID** and the exact names of your checking/credit card accounts.

### Step 4 → Build your keyword mappings

Edit `keywords.json` to map transaction descriptions → Wave accounts.

See **[KEYWORDS_GUIDE.md](KEYWORDS_GUIDE.md)** for how to use ChatGPT/Claude to generate this from your transaction history in 2 minutes.

### Step 5 → Add secrets to GitHub

[![Add Repository Secrets](https://img.shields.io/badge/5-Add_Secrets_→-181717?style=for-the-badge&logo=github)](../../settings/secrets/actions)

Add these secrets:

| Secret | Value |
|--------|-------|
| `PLAID_CLIENT_ID` | Your Plaid client ID |
| `PLAID_SECRET` | Your Plaid secret |
| `WAVE_ACCESS_TOKEN` | Your Wave API token |
| `WAVE_BUSINESS_ID` | From step 3 output |
| `PLAID_ACCESS_TOKENS` | `Name:access-token:Wave Account Name:type` |

**PLAID_ACCESS_TOKENS format:**
```
MyBank:access-production-xxxxx:Business Checking (001):checking,Chase:access-production-yyyyy:Credit Card (1234):credit_card
```

### Step 6 → Enable the workflow

[![Go to Actions](https://img.shields.io/badge/6-Enable_Actions_→-2088FF?style=for-the-badge&logo=githubactions)](../../actions)

The sync runs daily at 6am UTC. You can also trigger it manually from the Actions tab.

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
| **GitHub Actions** (recommended) | Fork → add secrets → done. Included in `.github/workflows/` |
| **Any VPS / cron** | `0 6 * * * cd /path && uv run plaid_sync.py --days 3` |
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
OnCalendar=*-*-* 06:00:00
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
No. The script is pure keyword matching. [KEYWORDS_GUIDE.md](KEYWORDS_GUIDE.md) shows how to use an LLM as a one-time helper to *build* your keyword file.

## Requirements

- Python 3.11+
- [uv](https://docs.astral.sh/uv/)
- Plaid account (trial = 10 free connections)
- Wave account with API access

## License

MIT
