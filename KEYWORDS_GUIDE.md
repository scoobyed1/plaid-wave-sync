# Generate keywords.json

**DO NOT run any terminal commands. DO NOT parse the CSV programmatically. Just read it and write the JSON file.**

## Task

1. Read the CSV file in this workspace (the `.csv` file with "Account Transactions" in the name)
2. Look at the "Description" column to find vendor/transaction names
3. Write a `keywords.json` file to the workspace root

## Output Format

Write `keywords.json` with this exact structure:

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

- Keywords are **lowercase** substrings (e.g., "adobe" matches "ADOBE *800-833-6687")
- Values must **exactly** match an account name from the list below
- Only use Expense or Income accounts (NOT Asset, Equity, or Liability)
- Use `null` ONLY for internal transfers and CC payments (money moving between your own accounts)
- Do NOT use `null` for income/deposits — leave those unmapped so they fall to the "Other" fallback
- Do NOT map client/customer names (e.g., companies that pay you invoices) — those are handled separately by invoice matching
- Do NOT invent vendors that aren't in the CSV — only map what you actually see
- Use short keywords — just the vendor name (e.g., "adobe" not "adobe *800-833-6687")
- Do NOT use generic words that match too broadly (e.g., don't use "pay", "payment", "deposit")
- **Map every vendor you can identify** — if the category is obvious from the name, include it
- A vendor that is BOTH a client (pays you) AND a service (you pay them) is fine to map — the script determines expense vs income from the transaction amount, not the keyword
- When in doubt between two categories, pick the more specific one

## Category Guidance

- SaaS, cloud services, apps → **Computer – Software**
- Web hosting, GPU, servers → **Computer – Hosting**
- Phone/cell service → **Telephone – Wireless**
- Camera, audio, video equipment → **Video Gear**
- Flights, trains, rideshare, hotels, parking → **Travel Expense**
- Restaurants, food delivery, coffee → **Meals and Entertainment**
- Tickets, shows, events, museums → **Meals and Entertainment**
- Shipping, mail → **Postage & Delivery**
- Legal filings, accountants, consultants → **Professional Fees**
- Payroll withdrawals → **Payroll – Salary & Wages**
- Tax payments → **Taxes – Corporate Tax** or **Payroll Employer Taxes**
- Insurance premiums → **Insurance**
- Internal transfers, CC autopay → **null** (skip)

## Wave Account Names (use ONLY these as values)

```
[Expenses]
  Accounting Fees
  Advertising & Promotion
  Computer – Hardware
  Computer – Hosting
  Computer – Internet
  Computer – Software
  Dues & Subscriptions
  Insurance
  Meals and Entertainment
  Office Supplies
  Payroll Employer Taxes
  Payroll Gross Pay
  Payroll – Salary & Wages
  Postage & Delivery
  Professional Fees
  Rent Expense
  Subcontracted Services
  Taxes – Corporate Tax
  Telephone – Wireless
  Travel Expense
  Uncategorized Expense
  Vehicle – Fuel
  Video Gear

[Income]
  Interest
  Other
  Uncategorized Income
```
