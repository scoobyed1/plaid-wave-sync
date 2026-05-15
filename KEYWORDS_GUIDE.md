# Keywords Guide

Keywords are auto-generated during setup from your Wave general ledger CSV. This file documents the format for manual editing.

## Format

```json
{
  "keywords": {
    "vendor keyword": "Wave Account Name",
    "another vendor": "Wave Account Name",
    "transfer keyword": null
  },
  "fallback_expense": "Uncategorized Expense",
  "fallback_income": "Other"
}
```

## Rules

- Keywords are **lowercase** substrings matched against transaction descriptions
- Values must **exactly** match a Wave account name (run `uv run plaid_sync.py --dump-accounts` to see them)
- Only use Expense or Income accounts (NOT Asset, Equity, or Liability)
- Use `null` for internal transfers and CC payments only
- Shorter keywords are better (e.g., "adobe" not "adobe creative cloud")

## Validate

```bash
uv run plaid_sync.py --dump-accounts   # shows ✓/✗ for each keyword target
uv run plaid_sync.py --dry-run --days 90  # shows what would be categorized
```

## Regenerate

To rebuild from a new CSV export:

```bash
uv run scripts/build_keywords.py "path/to/your.csv"
```
