# Generate keywords.json

**DO NOT run any terminal commands. DO NOT parse the CSV programmatically. Just read it and write the JSON file.**

## Task

1. Read the CSV file in this workspace (the `.csv` file with "Account Transactions" in the name)
2. Look at the "Description" column to find recurring vendor/transaction names
3. Write a `keywords.json` file mapping those vendors to the Wave accounts below

## Output

Write `keywords.json` to the workspace root with this exact structure:

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

## Wave Account Names (use ONLY these as values)

Only use accounts from the Expenses and Income sections:

### Expenses
- Accounting Fees
- Advertising & Promotion
- Computer – Hardware
- Computer – Hosting
- Computer – Internet
- Computer – Software
- Dues & Subscriptions
- Insurance
- Meals and Entertainment
- Office Supplies
- Payroll Employer Taxes
- Payroll Gross Pay
- Payroll – Salary & Wages
- Postage & Delivery
- Professional Fees
- Rent Expense
- Subcontracted Services
- Telephone – Wireless
- Travel Expense
- Uncategorized Expense
- Vehicle – Fuel
- Video Gear

### Income
- Freelance Income
- Interest
- Other
- Uncategorized Income

## Rules

- Keywords are **lowercase** substrings (e.g., "adobe" matches "ADOBE *800-833-6687")
- Values must **exactly** match an account name from the list above
- Use `null` for transfers, CC payments, and internal movements (e.g., "transfer", "autopay", "payment - thank")
- Be conservative — only map vendors you see multiple times or are obvious
- Use short keywords (e.g., "adobe" not "adobe creative cloud")
- Do NOT use generic words that match too broadly (e.g., don't use "pay")
