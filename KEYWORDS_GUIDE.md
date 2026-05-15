# Building Your Keyword Mappings

Use any LLM (ChatGPT, Claude, Gemini, etc.) to help build your `keywords.json` from your transaction history.

## Step 1: Get your Wave account names

```bash
uv run plaid_sync.py --dump-accounts
```

Copy the list of account names from the output.

## Step 2: Prompt your LLM

Upload your bank CSV (or Wave's Account Transactions export) along with this prompt:

---

```
I have a script that categorizes bank transactions into accounting categories using keyword matching. I need you to build a keyword mapping for me.

Here are my Wave accounting expense/income account names:
[PASTE YOUR --dump-accounts OUTPUT HERE]

I'm attaching a CSV of my bank transactions / general ledger. Analyze the transaction descriptions and build keyword mappings.

Rules:
- Keywords are lowercase substrings that match against transaction descriptions
- Values must EXACTLY match one of my Wave account names listed above
- Use null for transactions that should be skipped (internal transfers, etc.)
- Be conservative — only map keywords you're confident about
- Use shorter keywords when a vendor always goes to the same category (e.g., "adobe" not "adobe creative cloud")
- Avoid overly generic keywords that could false-match (e.g., don't use "pay" — it matches too many things)
- Group similar vendors under the same keyword when possible
- IMPORTANT: Only map to Expense or Income accounts, NOT to Asset or Liability accounts (like checking or credit card accounts). Wave's API only allows transactions between a balance sheet account and an income/expense account.
- CC payments (e.g., "AUTOPAY", "AUTOMATIC PAYMENT") should be set to null (skip) — they're handled separately
- Refunds show as negative amounts on credit cards — the script automatically treats them as income/credits against the same category. No special handling needed.
- The same keyword (e.g., "spotify") works for both expenses and income — the script determines direction from the transaction amount sign, not the keyword

Output format — valid JSON:
{
  "keywords": {
    "keyword": "Wave Account Name",
    "another": "Wave Account Name",
    "skip this": null
  },
  "fallback_expense": "Uncategorized Expense",
  "fallback_income": "Other"
}

Generate the keywords.json for my transactions.
```

---

> **Tip:** Most LLMs (ChatGPT, Claude, Gemini) accept CSV file uploads directly. Upload the file rather than pasting — it handles thousands of rows better and catches patterns you'd miss manually.

---

## Step 4: Validate

Save the output as `keywords.json` and run:

```bash
uv run plaid_sync.py --dump-accounts
```

The validation section at the bottom will show ✓ or ✗ for each keyword target.

## Step 5: Iterate

Run a dry-run to see how transactions get categorized:

```bash
uv run plaid_sync.py --dry-run --days 90
```

Anything that shows as `UNMATCHED` needs a keyword added. Anything miscategorized needs its keyword fixed. Feed the results back to your LLM:

```
These transactions were uncategorized. Add keywords for them:
[PASTE UNMATCHED LINES]

These were miscategorized. Fix them:
[PASTE WRONG ONES WITH WHAT THEY SHOULD BE]
```

## Tips

- **Start broad, refine later.** Get 80% coverage first, then add specific vendors as you see them.
- **Check for conflicts.** "uber" matches both "Uber" (rideshare) and "Uber Eats" (food). Put "uber eats" BEFORE "uber" in your keywords since the script matches first-found.
- **Review monthly.** New vendors appear. Spend 5 minutes adding keywords when you see patterns in your Uncategorized bucket.
