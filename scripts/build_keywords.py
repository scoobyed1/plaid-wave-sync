# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Build keywords.json from a Wave General Ledger CSV export."""
import csv, json, re, sys

VALID_TYPES = ('Accounting Fees', 'Advertising & Promotion', 'Bank Service Charges',
    'Computer – Hardware', 'Computer – Hosting', 'Computer – Internet', 'Computer – Software',
    'Dues & Subscriptions', 'Insurance', 'Meals and Entertainment',
    'Office Supplies', 'Payroll Employer Taxes', 'Payroll Gross Pay',
    'Payroll – Salary & Wages', 'Postage & Delivery', 'Professional Fees',
    'Rent Expense', 'Subcontracted Services', 'Taxes – Corporate Tax',
    'Telephone – Wireless', 'Travel Expense', 'Uncategorized Expense',
    'Vehicle – Fuel', 'Video Gear')

current_account = None
account_transactions = {}

with open(sys.argv[1], encoding='utf-8-sig') as f:
    for row in csv.reader(f):
        if len(row) >= 2 and not row[0] and row[1] and not any(row[2:5]):
            current_account = row[1].strip()
        elif len(row) > 2 and current_account and row[2].strip():
            desc = row[2].strip()
            if desc in ('Starting Balance', 'Totals and Ending Balance', 'Balance Change'):
                continue
            if current_account in VALID_TYPES:
                account_transactions.setdefault(current_account, []).append(desc)

def extract_keyword(desc):
    desc = re.sub(r'\*[A-Za-z0-9]{6,}', '', desc)
    desc = re.sub(r'\s+[A-Z0-9]{8,}', '', desc)
    desc = re.sub(r'\s*#\d+.*$', '', desc)
    desc = re.sub(r',\s*\d+$', '', desc)
    desc = re.sub(r'\s+\d{3,}.*$', '', desc)
    desc = re.sub(r'\*\d[\d-]+', '', desc)
    desc = re.sub(r'\s*PO\s+\d+', '', desc)
    desc = re.sub(r'\s*O\*[\d-]+', '', desc)
    desc = re.sub(r'\s*-\s*(NYC|TIMES|UNION).*$', '', desc)
    desc = re.sub(r'\s*-\s*[A-Z].*$', '', desc)
    desc = re.sub(r'\.COM$', '', desc, flags=re.IGNORECASE)
    desc = re.sub(r'\s+(INC|LLC|LTD|SERVICES|ONLINE|RECURRING|PAY|FILM|FESTIVAL)\.?$', '', desc, flags=re.IGNORECASE)
    desc = desc.strip(' .,*').lower()
    if not desc: return ''
    if 'uber eats' in desc: return 'uber eats'
    if desc.startswith('tst'): return 'tst'
    if 'amazon' in desc: return 'amazon'
    if 'ebay' in desc: return 'ebay'
    if 'spitfire' in desc: return 'spitfire'
    if 'citibik' in desc: return 'citibik'
    parts = desc.split()
    if len(parts) >= 2 and len(parts[0]) <= 3:
        return ' '.join(parts[:2])
    return parts[0]

keyword_counts = {}
for account, descs in account_transactions.items():
    if account not in VALID_TYPES:
        continue
    for desc in descs:
        kw = extract_keyword(desc)
        if not kw or len(kw) < 3:
            continue
        if kw in ('ach', 'wire', 'payment', 'deposit', 'transfer', 'check', 'payroll',
                  'total', 'incoming', 'mobile', 'interest', 'wave', 'before-tax',
                  '(deleted)', 'super'):
            continue
        keyword_counts.setdefault(kw, {}).setdefault(account, 0)
        keyword_counts[kw][account] += 1

keywords = {}
for kw, accounts in keyword_counts.items():
    best_account = max(accounts, key=accounts.get)
    keywords[kw] = best_account

if 'uber eats' in keywords and 'uber' in keywords:
    keywords['uber'] = 'Travel Expense'

for pattern in ('transfer to', 'transfer from', 'chase credit', 'automatic payment', 'autopay'):
    keywords[pattern] = None

output = {
    'keywords': dict(sorted(keywords.items())),
    'fallback_expense': 'Uncategorized Expense',
    'fallback_income': 'Other'
}

with open('keywords.json', 'w') as f:
    json.dump(output, f, indent=2, ensure_ascii=False)

print(f'Generated {len(keywords)} keywords across {len(set(v for v in keywords.values() if v))} categories')
