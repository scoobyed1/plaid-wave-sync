# Building Your Keyword Mappings

Use any LLM (ChatGPT, Claude, Gemini, etc.) to help build your `keywords.json` from your transaction history.

## Step 1: Export your transactions

Export a CSV from your bank or download from Plaid. You need the transaction names/descriptions.

## Step 2: Get your Wave account names

```bash
uv run plaid_sync.py --dump-accounts
```

Copy the list of account names from the output.

## Step 3: Prompt your LLM

Paste this prompt into your LLM of choice, replacing the placeholders:

---

```
I have a script that categorizes bank transactions into accounting categories using keyword matching. I need you to build a keyword mapping for me.

Here are my Wave accounting expense/income account names:
[PASTE YOUR --dump-accounts OUTPUT HERE]

Here are my recent bank transaction descriptions (one per line):
[PASTE YOUR TRANSACTION NAMES HERE]

Rules:
- Keywords are lowercase substrings that match against transaction descriptions
- Values must EXACTLY match one of my Wave account names listed above
- Use null for transactions that should be skipped (internal transfers, etc.)
- Be conservative — only map keywords you're confident about
- Use shorter keywords when a vendor always goes to the same category (e.g., "adobe" not "adobe creative cloud")
- Avoid overly generic keywords that could false-match (e.g., don't use "pay" — it matches too many things)

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
