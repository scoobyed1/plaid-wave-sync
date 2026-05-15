# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx"]
# ///
"""Match Plaid accounts to Wave accounts by mask number."""
import json, os, sys, httpx

tokens = []
with open('/tmp/plaid-tokens-all.jsonl') as f:
    for line in f:
        if line.strip():
            tokens.append(json.loads(line))

wave_accounts = []
biz_id = os.environ.get('WAVE_BUSINESS_ID', '')
wave_token = os.environ.get('WAVE_ACCESS_TOKEN', '')

if not wave_token or not biz_id:
    print(f"  ✗ Missing env vars: WAVE_ACCESS_TOKEN={'set' if wave_token else 'EMPTY'}, WAVE_BUSINESS_ID={'set' if biz_id else 'EMPTY'}")
    sys.exit(1)

page = 1
while True:
    r = httpx.post('https://gql.waveapps.com/graphql/public',
        headers={'Authorization': f'Bearer {wave_token}'},
        json={'query': 'query($id:ID!,$p:Int!){business(id:$id){accounts(page:$p,pageSize:50){pageInfo{totalPages}edges{node{name type{name} isArchived}}}}}',
              'variables': {'id': biz_id, 'page': page}}, timeout=30)
    resp = r.json()
    if 'errors' in resp or 'data' not in resp:
        print(f"  ✗ Wave API error: {resp.get('errors', resp)}")
        sys.exit(1)
    d = resp['data']['business']['accounts']
    for e in d['edges']:
        n = e['node']
        if not n['isArchived'] and n['type']['name'] in ('Assets', 'Liabilities & Credit Cards'):
            wave_accounts.append(n['name'])
    if page >= d['pageInfo']['totalPages']:
        break
    page += 1

entries = []
for t in tokens:
    for acct in t['accounts']:
        mask = acct['mask']
        acct_type = acct['type']
        matched = next((w for w in wave_accounts if mask in w), None)
        if not matched and len(mask) >= 4:
            matched = next((w for w in wave_accounts if mask[-3:] in w), None)
        if matched:
            entries.append(f"{acct['name']}:{t['access_token']}:{matched}:{acct_type}")
            print(f"  ✓ {acct['name']} (mask={mask}) → {matched} ({acct_type})")
        else:
            print(f"  ⚠ {acct['name']} (mask={mask}) — no auto-match")

with open('/tmp/plaid-access-tokens.txt', 'w') as f:
    f.write(','.join(entries))

with open('/tmp/wave-account-options.txt', 'w') as f:
    for w in wave_accounts:
        f.write(w + '\n')
