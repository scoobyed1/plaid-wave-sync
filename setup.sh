#!/usr/bin/env bash
# No set -e — we handle errors explicitly with fallbacks

# ─── Fancy output helpers ─────────────────────────────────────────────────────

BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

spinner() {
    local pid=$1 msg=$2
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}${frames[$i]}${NC} ${msg}"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.1
    done
    wait "$pid" 2>/dev/null
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        printf "\r  ${GREEN}✓${NC} ${msg}\n"
    else
        printf "\r  ${RED}✗${NC} ${msg} (failed)\n"
    fi
    return 0
}

step() {
    echo ""
    echo -e "${BOLD}${CYAN}▶ $1${NC}"
    echo ""
}

success() {
    echo -e "  ${GREEN}✓${NC} $1"
}

warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

info() {
    echo -e "  ${DIM}$1${NC}"
}

# ─── Header ───────────────────────────────────────────────────────────────────

clear
echo ""
echo -e "${BOLD}  ╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}  ║     ${CYAN}plaid-wave-sync${NC}${BOLD} setup              ║${NC}"
echo -e "${BOLD}  ║     Plaid → Wave in 5 minutes           ║${NC}"
echo -e "${BOLD}  ╚══════════════════════════════════════════╝${NC}"
echo ""

# ─── Make repo private ────────────────────────────────────────────────────────

# ─── Make repo private ────────────────────────────────────────────────────────

REPO_OWNER=$(gh repo view --json owner -q '.owner.login' 2>/dev/null || true)
REPO_NAME=$(gh repo view --json name -q '.name' 2>/dev/null || true)
if [ -n "$REPO_OWNER" ] && [ "$REPO_NAME" = "plaid-wave-sync" ]; then
    gh repo edit --visibility private 2>/dev/null && success "Repo set to private" || true
fi

# ─── Step 1: Install dependencies ─────────────────────────────────────────────

step "Step 1/6 · Installing tools"

if command -v plaid &>/dev/null; then
    success "Plaid CLI already installed"
else
    if ! command -v brew &>/dev/null; then
        info "Installing Homebrew (this takes ~60s on first run)..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null &>/tmp/brew-install.log &
        spinner $! "Installing Homebrew"
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" 2>/dev/null || true
    fi
    brew install plaid/plaid-cli/plaid &>/tmp/plaid-install.log &
    spinner $! "Installing Plaid CLI"
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" 2>/dev/null || true
fi

if command -v uv &>/dev/null; then
    success "uv already installed"
else
    curl -LsSf https://astral.sh/uv/install.sh | sh &>/dev/null &
    spinner $! "Installing uv"
    export PATH="$HOME/.local/bin:$PATH"
fi

if ! command -v gh &>/dev/null; then
    (curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null && \
    sudo apt-get update -qq && sudo apt-get install -y -qq gh) &>/tmp/gh-install.log &
    spinner $! "Installing GitHub CLI"
fi

# ─── Step 2: Plaid account ────────────────────────────────────────────────────

step "Step 2/6 · Plaid account"

if [ -f ~/.config/plaid-cli/config.json ] && grep -q '"client_id"' ~/.config/plaid-cli/config.json 2>/dev/null; then
    # Make sure correct team is selected
    TEAM_ID=$(plaid teams list 2>/dev/null | grep '\*' | awk '{print $2}')
    [ -z "$TEAM_ID" ] && TEAM_ID=$(plaid teams list 2>/dev/null | grep -i "Individual" | awk '{print $2}')
    [ -n "$TEAM_ID" ] && plaid teams use "$TEAM_ID" &>/dev/null
    plaid keys fetch &>/dev/null || true
    # Re-export after team switch
    export PLAID_CLIENT_ID=$(grep -o '"client_id": *"[^"]*"' ~/.config/plaid-cli/config.json 2>/dev/null | tail -1 | cut -d'"' -f4)
    export PLAID_SECRET=$(grep -o '"secret": *"[^"]*"' ~/.config/plaid-cli/config.json 2>/dev/null | tail -1 | cut -d'"' -f4)
    if [ -n "$PLAID_CLIENT_ID" ] && [ "$PLAID_CLIENT_ID" != "" ]; then
        success "Already logged in (Client ID: $PLAID_CLIENT_ID)"
    else
        # Config exists but no valid credentials — fall through to login
        unset PLAID_CLIENT_ID PLAID_SECRET
    fi
fi

if [ -z "$PLAID_CLIENT_ID" ]; then
    read -p "  Already have a Plaid Developer account? (y/n): " has_account
    if [ "$has_account" != "y" ]; then
        echo ""
        echo -e "  ${BOLD}1.${NC} Create your Plaid account:"
        echo -e "     ${CYAN}https://dashboard.plaid.com/signup${NC}"
        plaid register &>/dev/null || true
        echo ""
        read -p "  Done signing up? Press Enter..."
        echo ""
        echo -e "  ${BOLD}2.${NC} Activate trial plan (10 free connections):"
        echo -e "     ${CYAN}https://dashboard.plaid.com/trial-plan${NC}"
        plaid trial &>/dev/null || true
        echo ""
        read -p "  Done with trial? Press Enter..."
        echo ""
    fi

    echo -e "  ${BOLD}Log in to Plaid:${NC}"
    echo -e "  1. ${BOLD}Cmd+Click${NC} (or Ctrl+Click) the link below"
    echo -e "  2. Log in to Plaid in your browser"
    echo -e "  3. Browser will fail on a localhost URL — ${GREEN}that's expected${NC}"
    echo -e "  4. Copy that URL and paste it here"
    echo ""
    read -p "  Press Enter to start..."

    # Kill any stale plaid login processes
    pkill -f "plaid login" 2>/dev/null || true
    sleep 1

    plaid login &>/tmp/plaid-login.log &
    PLAID_PID=$!
    sleep 2
    grep -o 'https://[^ ]*' /tmp/plaid-login.log | head -1 | xargs -I{} echo -e "\n  ${CYAN}{}${NC}\n"

    read -p "  Paste the failed localhost URL: " callback_url
    if echo "$callback_url" | grep -q "localhost.*callback.*code="; then
        info "Sending callback to plaid login server..."
        curl -s "$callback_url" &>/dev/null &
        CURL_PID=$!
        sleep 5
        kill $CURL_PID 2>/dev/null || true
        kill $PLAID_PID 2>/dev/null || true
        wait $PLAID_PID 2>/dev/null || true
        wait $CURL_PID 2>/dev/null || true

        # Login succeeded — extract credentials from config
        success "Logged in"
        TEAM_ID=$(plaid teams list 2>/dev/null | grep '\*' | awk '{print $2}')
        [ -z "$TEAM_ID" ] && TEAM_ID=$(plaid teams list 2>/dev/null | grep -i "Individual" | awk '{print $2}')
        [ -n "$TEAM_ID" ] && plaid teams use "$TEAM_ID" &>/dev/null
        plaid keys fetch &>/dev/null || true
        export PLAID_CLIENT_ID=$(plaid config 2>/dev/null | grep "Client ID" | awk '{print $NF}')
        export PLAID_SECRET=$(grep -o '"secret": *"[^"]*"' ~/.config/plaid-cli/config.json 2>/dev/null | tail -1 | cut -d'"' -f4)
        success "Client ID: $PLAID_CLIENT_ID"
    else
        wait $PLAID_PID 2>/dev/null || true
        warn "Invalid URL. Let's enter credentials manually instead:"
        echo -e "  ${CYAN}https://dashboard.plaid.com/developers/keys${NC}"
        echo ""
        read -p "  Client ID: " PLAID_CLIENT_ID
        read -p "  Secret (Production): " PLAID_SECRET
        export PLAID_CLIENT_ID PLAID_SECRET
        plaid config set --client-id "$PLAID_CLIENT_ID" --secret "$PLAID_SECRET" --env production 2>/dev/null
        success "Credentials saved"
    fi

    echo ""
    if plaid keys fetch 2>/dev/null; then
        success "API keys saved"
    else
        # Auto-select first team and retry
        FIRST_TEAM=$(plaid teams list 2>/dev/null | awk 'NR==2 {print $2}')
        [ -n "$FIRST_TEAM" ] && plaid teams use "$FIRST_TEAM" 2>/dev/null
        if plaid keys fetch 2>/dev/null; then
            success "API keys saved"
        else
            warn "Couldn't fetch keys. Enter them manually:"
            echo -e "  ${CYAN}https://dashboard.plaid.com/developers/keys${NC}"
            echo ""
            read -p "  Client ID: " PLAID_CLIENT_ID
            read -p "  Secret (Production): " PLAID_SECRET
            export PLAID_CLIENT_ID PLAID_SECRET
            plaid config set --client-id "$PLAID_CLIENT_ID" --secret "$PLAID_SECRET" --env production 2>/dev/null
            success "Credentials saved"
        fi
    fi
fi

# ─── Step 3: Connect banks ────────────────────────────────────────────────────

step "Step 3/6 · Connect your bank accounts"

echo -e "  Connect your bank accounts using Plaid Hosted Link."
echo -e "  ${BOLD}Cmd+Click${NC} (or Ctrl+Click) the URL that appears."
echo ""
warn "Some banks (Chase, Schwab) need OAuth approval (~24hrs)."
info "Check status: https://dashboard.plaid.com/activity/status/oauth-institutions"
info "If you need to come back later, reopen this Codespace and run: ./setup.sh"
echo ""

read -p "  Press Enter to connect a bank (or 's' to skip): " choice
while [ "$choice" != "s" ]; do
    export PATH="$HOME/.local/bin:$PATH"
    # Ensure credentials are set
    if [ -z "$PLAID_CLIENT_ID" ] || [ -z "$PLAID_SECRET" ]; then
        echo -e "  Enter your Plaid credentials from: ${CYAN}https://dashboard.plaid.com/developers/keys${NC}"
        read -p "  Client ID: " PLAID_CLIENT_ID
        read -p "  Secret (Production): " PLAID_SECRET
        export PLAID_CLIENT_ID PLAID_SECRET
    fi
    uv run plaid_sync.py --add-bank
    if [ $? -ne 0 ]; then
        warn "Failed — likely a credentials mismatch (multiple Plaid teams?)."
        echo -e "  Paste correct keys from: ${CYAN}https://dashboard.plaid.com/developers/keys${NC}"
        echo ""
        read -p "  Client ID: " PLAID_CLIENT_ID
        read -p "  Secret (Production): " PLAID_SECRET
        export PLAID_CLIENT_ID PLAID_SECRET
        uv run plaid_sync.py --add-bank || warn "Still failing — check your credentials"
    fi
    echo ""
    read -p "  Connect another bank? (Enter = yes, 's' = done): " choice
done

echo ""
echo -e "  ${BOLD}Your linked accounts:${NC}"
plaid item list 2>/dev/null || true
echo ""

# ─── Step 4: Wave setup ───────────────────────────────────────────────────────

step "Step 4/6 · Wave setup"

if [ -z "$WAVE_ACCESS_TOKEN" ]; then
    echo -e "  Create a Wave app to get your API token:"
    echo -e "  ${CYAN}https://developer-apps.waveapps.com/apps/create/${NC}"
    echo ""
    echo -e "  Fill in:"
    echo -e "    Name:          ${BOLD}plaid-wave-sync${NC}"
    echo -e "    Description:   ${BOLD}Syncs bank transactions from Plaid${NC}"
    echo -e "    Redirect URI:  ${BOLD}http://localhost${NC}"
    echo ""
    echo -e "  After creating, copy the ${BOLD}Full Access Token${NC} from the app page."
    echo ""
    read -p "  Paste your Wave token: " WAVE_ACCESS_TOKEN
    export WAVE_ACCESS_TOKEN
fi

echo ""
# Check for multiple businesses
BIZ_LIST=$(WAVE_ACCESS_TOKEN="$WAVE_ACCESS_TOKEN" uv run --with httpx python3 -c "
import os, httpx
r = httpx.post('https://gql.waveapps.com/graphql/public',
    headers={'Authorization': f'Bearer {os.environ[\"WAVE_ACCESS_TOKEN\"]}'},
    json={'query': '{ businesses(page:1, pageSize:10) { edges { node { id name isArchived } } } }'},
    timeout=30)
for e in r.json()['data']['businesses']['edges']:
    if not e['node']['isArchived']:
        print(f\"{e['node']['id']}|{e['node']['name']}\")
" 2>/dev/null)

BIZ_COUNT=$(echo "$BIZ_LIST" | wc -l | tr -d ' ')
if [ "$BIZ_COUNT" -gt "1" ]; then
    echo -e "  ${BOLD}Multiple Wave businesses found:${NC}"
    echo "$BIZ_LIST" | awk -F'|' '{printf "    %d. %s\n", NR, $2}'
    echo ""
    read -p "  Which one? (number): " biz_num
    export WAVE_BUSINESS_ID=$(echo "$BIZ_LIST" | sed -n "${biz_num}p" | cut -d'|' -f1)
    success "Selected: $(echo "$BIZ_LIST" | sed -n "${biz_num}p" | cut -d'|' -f2)"
else
    export WAVE_BUSINESS_ID=$(echo "$BIZ_LIST" | head -1 | cut -d'|' -f1)
fi

echo ""
uv run plaid_sync.py --dump-accounts 2>/dev/null | head -30
echo ""

# ─── Step 5: Keywords ─────────────────────────────────────────────────────────

step "Step 5/6 · Build keyword mappings"

echo -e "  Export your transaction history from Wave:"
echo -e "  ${CYAN}Wave → Reports → Account Transactions (General Ledger) → Export CSV${NC}"
echo -e "  (Set date range to last 12 months)"
echo ""
echo -e "  Then drag the CSV into the ${BOLD}imports/${NC} folder:"
echo -e "  Open the Explorer panel (${BOLD}Cmd+Shift+E${NC} on Mac, ${BOLD}Ctrl+Shift+E${NC} on Windows)"
echo -e "  and drop your file into the ${BOLD}imports${NC} folder."
echo ""
read -p "  Path to CSV (drag file into terminal, or Enter to auto-find): " csv_path
csv_path=$(echo "$csv_path" | tr -d "'" | tr -d '"')

# Auto-find CSV if not specified
if [ -z "$csv_path" ]; then
    csv_path=$(find . imports/ -maxdepth 1 -name "*.csv" 2>/dev/null | head -1)
    [ -n "$csv_path" ] && info "Found: $csv_path"
fi

if [ -n "$csv_path" ] && [ -f "$csv_path" ]; then
    export PATH="$HOME/.local/bin:$PATH"
    
    # Get client names and accounts from Wave, then extract clean descriptions
    ACCOUNTS_OUTPUT=$(uv run plaid_sync.py --dump-accounts 2>/dev/null | grep -E "^\[|^  " | grep -v "Accounts Receivable\|Transfer Clearing\|Payroll Clearing\|Cash on Hand\|Wave Payroll\|Owner")

    uv run --with httpx python3 -c "
import csv, os, sys, httpx

# Get client names from Wave invoices
clients = set()
biz_id = os.environ.get('WAVE_BUSINESS_ID', '')
token = os.environ.get('WAVE_ACCESS_TOKEN', '')
if biz_id and token:
    try:
        r = httpx.post('https://gql.waveapps.com/graphql/public',
            headers={'Authorization': f'Bearer {token}'},
            json={'query': 'query(\$id:ID!){business(id:\$id){invoices(page:1,pageSize:100){edges{node{customer{name}}}}}}',
                  'variables': {'id': biz_id}}, timeout=30)
        for e in r.json().get('data',{}).get('business',{}).get('invoices',{}).get('edges',[]):
            clients.add(e['node']['customer']['name'].lower())
    except: pass

# Patterns that indicate internal/non-expense transactions
skip_prefixes = ('Starting Balance', 'Totals and Ending Balance', 'Balance Change', 
                 'Description', 'DESCRIPTION', 'Total employee', 'Total net pay', 
                 'Total employer', 'Total gross pay', '(Deleted)', 'Before-tax deduction',
                 'Payroll tax liabilities', 'Payroll period ending', 'Incoming Wire',
                 'Incoming International', 'Mobile Deposit', 'Interest earned',
                 'Transfer from transfer clearing', 'Transfer to', 'Transfer from',
                 'AUTOMATIC PAYMENT', 'CHASE CREDIT CRD')
skip_contains = ('Editor', 'Camera Op', 'Lighting', 'Travel Day', 'Audio', 'Photographer',
                 'Directing', 'Additional', 'Media Management', 'Post Coordinator',
                 'Music Sync', 'Kit Fee', 'DP Fee', 'Transportation', '- Bill ',
                 'ACH Pmt', 'ACH payment to', 'PAYMENTS', ', SALE')

with open(sys.argv[1]) as f:
    seen = set()
    for row in csv.reader(f):
        if len(row) > 2:
            desc = row[2].strip()
            if not desc or desc in seen:
                continue
            if any(desc.startswith(p) for p in skip_prefixes):
                continue
            if any(s in desc for s in skip_contains):
                continue
            # Skip invoice headers (Client Name - Number)
            parts = desc.split(' - ')
            if len(parts) == 2 and parts[1].strip().replace('A','').replace('B','').isdigit():
                continue
            # Skip if it matches a known client name
            desc_lower = desc.lower()
            if any(c in desc_lower for c in clients if len(c) > 3):
                continue
            seen.add(desc)
            print(desc)
" "$csv_path" 2>/dev/null > imports/unique_descriptions.txt

    DESC_COUNT=$(wc -l < imports/unique_descriptions.txt | tr -d ' ')
    success "Extracted $DESC_COUNT vendor transactions (filtered clients, transfers, payroll)"

    CLIENTS=$(WAVE_ACCESS_TOKEN="$WAVE_ACCESS_TOKEN" WAVE_BUSINESS_ID="${WAVE_BUSINESS_ID}" uv run --with httpx python3 -c "
import os, httpx
biz = os.environ.get('WAVE_BUSINESS_ID','')
r = httpx.post('https://gql.waveapps.com/graphql/public',
    headers={'Authorization': f'Bearer {os.environ[\"WAVE_ACCESS_TOKEN\"]}'},
    json={'query': '''query(\$id:ID!){business(id:\$id){invoices(page:1,pageSize:100){edges{node{customer{name}}}}}}''',
          'variables': {'id': biz}}, timeout=30)
names = set()
for e in r.json().get('data',{}).get('business',{}).get('invoices',{}).get('edges',[]):
    names.add(e['node']['customer']['name'])
for n in sorted(names):
    print(n)
" 2>/dev/null)

    cat > KEYWORDS_GUIDE.md <<EOF
# Generate keywords.json

**DO NOT run any terminal commands. Just read the file and write the JSON.**

## Task

1. Read \`imports/unique_descriptions.txt\` — each line is a transaction description from the bank
2. For each one, decide which Wave account it belongs to
3. Write a \`keywords.json\` file to the workspace root

## Output Format

\`\`\`json
{
  "keywords": {
    "vendor keyword": "Wave Account Name",
    "another vendor": "Wave Account Name",
    "transfer keyword": null
  },
  "fallback_expense": "Uncategorized Expense",
  "fallback_income": "Other"
}
\`\`\`

## CLIENTS — do NOT map these (invoice matching handles them)

\`\`\`
${CLIENTS}
\`\`\`

These are customers who pay invoices. If you see them in the descriptions, SKIP them.

## Rules

- Keywords are **lowercase** substrings (e.g., "adobe" matches "ADOBE *800-833-6687")
- Values must **exactly** match an account name from the list below
- Only use Expense or Income accounts (NOT Asset, Equity, or Liability)
- Use \`null\` ONLY for internal transfers and CC payments (money moving between own accounts)
- Do NOT use \`null\` for income/deposits — leave unmapped to fall to "Other" fallback
- Do NOT map any client names listed above
- Only map OUTGOING payments. If a name only appears as incoming money, skip it.
- Use short keywords — just the core vendor name
- Do NOT use overly broad keywords (e.g., "pay", "payment", "deposit", or a person's first name)
- **Map every identifiable vendor** — if the category is obvious, include it
- When in doubt, pick the more specific category

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
- Bank fees → **Bank Service Charges**
- Internal transfers, CC autopay → **null**

## Wave Account Names (use ONLY these as values)

\`\`\`
${ACCOUNTS_OUTPUT}
\`\`\`
EOF

    echo ""
    success "Generated KEYWORDS_GUIDE.md with your accounts + client list"
    echo ""
    echo -e "  ${BOLD}→ Open Copilot Chat (Cmd+Shift+I) and type:${NC}"
    echo ""
    echo -e "    ${CYAN}Follow #file:KEYWORDS_GUIDE.md${NC}"
    echo ""
    read -p "  Press Enter when Copilot has generated keywords.json..."
    success "Check keywords.json and edit if needed"
else
    warn "No CSV found. Drop one in the workspace and re-run, or see KEYWORDS_GUIDE.md."
fi

# ─── Step 6: Save secrets ─────────────────────────────────────────────────────

step "Step 6/6 · Save secrets to GitHub"

read -p "  Auto-save secrets to this repo? (y/n): " save_secrets
if [ "$save_secrets" = "y" ]; then
    CLIENT_ID="${PLAID_CLIENT_ID:-$(plaid config 2>/dev/null | grep 'Client ID' | awk '{print $NF}')}"
    SECRET="${PLAID_SECRET:-$(grep -o '"secret": *"[^"]*"' ~/.config/plaid-cli/config.json 2>/dev/null | tail -1 | cut -d'"' -f4)}"

    # Test if we have permission, if not re-auth gh
    if ! gh secret set PLAID_CLIENT_ID --body "$CLIENT_ID" 2>/dev/null; then
        info "Need GitHub auth to save secrets (one-time)."
        unset GITHUB_TOKEN
        gh auth login -w
    fi

    gh secret set PLAID_CLIENT_ID --body "$CLIENT_ID" &>/dev/null && success "Saved PLAID_CLIENT_ID"
    gh secret set PLAID_SECRET --body "$SECRET" &>/dev/null && success "Saved PLAID_SECRET"
    gh secret set WAVE_ACCESS_TOKEN --body "$WAVE_ACCESS_TOKEN" &>/dev/null && success "Saved WAVE_ACCESS_TOKEN"
    [ -n "$WAVE_BUSINESS_ID" ] && gh secret set WAVE_BUSINESS_ID --body "$WAVE_BUSINESS_ID" &>/dev/null && success "Saved WAVE_BUSINESS_ID"

    echo ""
    info "Last one — your Plaid access tokens."
    info "Format: Name:access-token:Wave Account Name:type"
    info "Example: MyBank:access-prod-xxx:Business Checking (001):checking"
    echo ""
    echo -e "  Get tokens with: ${CYAN}plaid item list --json${NC}"
    echo ""
    read -p "  Paste PLAID_ACCESS_TOKENS (or Enter to skip): " tokens
    if [ -n "$tokens" ]; then
        gh secret set PLAID_ACCESS_TOKENS --body "$tokens" &>/dev/null &
        spinner $! "Saving PLAID_ACCESS_TOKENS"
    fi
else
    warn "Add secrets manually: Settings → Secrets → Actions"
fi

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}  ╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}  ║  ${GREEN}✓ Setup complete!${NC}${BOLD}                      ║${NC}"
echo -e "${BOLD}  ╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Next: Go to the ${BOLD}Actions${NC} tab and enable the workflow."
echo -e "  Trigger it manually to test. It runs daily at 6am UTC."
echo ""
echo -e "  ${DIM}You can close this Codespace now — everything runs automatically.${NC}"
echo ""
