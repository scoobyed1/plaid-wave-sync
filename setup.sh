#!/usr/bin/env bash
set -e

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
    return $exit_code
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

# ─── Step 2: Plaid account ────────────────────────────────────────────────────

step "Step 2/6 · Plaid account"

if plaid config 2>/dev/null | grep -q "client_id"; then
    success "Already logged in to Plaid"
else
    read -p "  Already have a Plaid Developer account? (y/n): " has_account
    if [ "$has_account" = "y" ]; then
        echo ""
        echo -e "  ${BOLD}Here's what will happen:${NC}"
        echo -e "  1. A login link will appear below — click it"
        echo -e "  2. Log in to Plaid in your browser"
        echo -e "  3. Your browser will try to go to a localhost URL and ${BOLD}fail${NC} — ${GREEN}that's expected!${NC}"
        echo -e "  4. Copy the URL from your browser's address bar"
        echo -e "  5. Paste it back here"
        echo ""
        read -p "  Ready? Press Enter to start..."
        echo ""

        # Run plaid login in background (it starts a server on port 41001)
        plaid login &>/tmp/plaid-login.log &
        PLAID_PID=$!
        sleep 2

        # Show the auth URL
        AUTH_URL=$(grep -o 'https://dashboard.plaid.com[^ ]*' /tmp/plaid-login.log | head -1)
        if [ -n "$AUTH_URL" ]; then
            echo -e "  ${CYAN}$AUTH_URL${NC}"
        else
            cat /tmp/plaid-login.log
        fi
        echo ""
        read -p "  Paste the localhost URL your browser failed on: " callback_url

        if [ -n "$callback_url" ]; then
            # Hit the local plaid login server with the callback
            curl -s "$callback_url" &>/dev/null
            sleep 2
        fi
        wait $PLAID_PID 2>/dev/null

        plaid keys fetch &>/dev/null &
        spinner $! "Fetching API keys"
    else
        echo -e "  ${BOLD}1.${NC} Create your Plaid account:"
        plaid register 2>/dev/null || true
        echo ""
        read -p "  Done signing up? Press Enter to continue..."
        echo ""

        echo -e "  ${BOLD}2.${NC} Activate trial plan (10 free bank connections):"
        plaid trial 2>/dev/null || true
        echo ""
        read -p "  Done with trial signup? Press Enter to continue..."
        echo ""

        echo -e "  ${BOLD}3.${NC} Grab your API keys from:"
        echo -e "     ${CYAN}https://dashboard.plaid.com/developers/keys${NC}"
        echo ""
        read -p "  Client ID: " plaid_client_id
        read -p "  Secret (Production): " plaid_secret
        plaid config set --client-id "$plaid_client_id" --secret "$plaid_secret" --env production 2>/dev/null
        success "Credentials saved"
    fi
fi

# ─── Step 3: Connect banks ────────────────────────────────────────────────────

step "Step 3/6 · Connect your bank accounts"

echo -e "  This opens Plaid Link. Codespaces will tunnel the URL automatically."
echo ""
warn "Some banks (Chase, Schwab) need OAuth approval (~24hrs)."
info "Check status: https://dashboard.plaid.com/activity/status/oauth-institutions"
echo ""

read -p "  Press Enter to connect a bank (or 's' to skip): " choice
while [ "$choice" != "s" ]; do
    plaid link --products transactions
    echo ""
    success "Bank connected!"
    echo ""
    read -p "  Press Enter to connect another, or 's' when done: " choice
done

echo ""
echo -e "  ${BOLD}Your linked accounts:${NC}"
plaid item list 2>/dev/null || true
echo ""

# ─── Step 4: Wave setup ───────────────────────────────────────────────────────

step "Step 4/6 · Wave setup"

if [ -z "$WAVE_ACCESS_TOKEN" ]; then
    echo -e "  Get your Wave API token from:"
    echo -e "  ${CYAN}https://developer.waveapps.com/hc/en-us/articles/360019762711${NC}"
    echo ""
    read -p "  Paste your Wave token: " WAVE_ACCESS_TOKEN
    export WAVE_ACCESS_TOKEN
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
echo -e "  Drag the CSV into the ${BOLD}imports/${NC} folder. This folder is gitignored."
echo ""
read -p "  Path to CSV (e.g. imports/transactions.csv) or Enter to skip: " csv_path

if [ -n "$csv_path" ] && [ -f "$csv_path" ]; then
    ACCOUNTS_OUTPUT=$(uv run plaid_sync.py --dump-accounts 2>/dev/null | grep -A1000 "^\[")
    info "Generating keywords.json with Copilot..."
    gh copilot -p "Read the file $csv_path. These are my Wave account names:

$ACCOUNTS_OUTPUT

Generate a keywords.json file mapping transaction keywords to Wave account names. Rules:
- Keywords are lowercase substrings
- Values must exactly match a Wave account name from above
- Only map to Expense or Income accounts (NOT Asset/Liability)
- CC payments should be null (skip)
- Refunds are handled automatically
- Use null for internal transfers
- Output valid JSON: {keywords: {...}, fallback_expense: '...', fallback_income: '...'}

Write the result to keywords.json" --no-confirm 2>/dev/null &
    spinner $! "Generating keywords with Copilot"
    success "Check keywords.json and edit if needed"
else
    warn "Skipped. See KEYWORDS_GUIDE.md to build keywords later."
fi

# ─── Step 6: Save secrets ─────────────────────────────────────────────────────

step "Step 6/6 · Save secrets to GitHub"

read -p "  Auto-save secrets to this repo? (y/n): " save_secrets
if [ "$save_secrets" = "y" ]; then
    CLIENT_ID=$(plaid config 2>/dev/null | grep -i client_id | awk '{print $NF}')
    SECRET=$(plaid config 2>/dev/null | grep -i secret | awk '{print $NF}')

    gh secret set PLAID_CLIENT_ID --body "$CLIENT_ID" &>/dev/null &
    spinner $! "Saving PLAID_CLIENT_ID"

    gh secret set PLAID_SECRET --body "$SECRET" &>/dev/null &
    spinner $! "Saving PLAID_SECRET"

    gh secret set WAVE_ACCESS_TOKEN --body "$WAVE_ACCESS_TOKEN" &>/dev/null &
    spinner $! "Saving WAVE_ACCESS_TOKEN"

    BIZ_ID=$(uv run plaid_sync.py --dump-accounts 2>&1 | grep "Business ID" | awk '{print $NF}')
    if [ -n "$BIZ_ID" ]; then
        gh secret set WAVE_BUSINESS_ID --body "$BIZ_ID" &>/dev/null &
        spinner $! "Saving WAVE_BUSINESS_ID"
    fi

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
