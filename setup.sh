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

        # Login succeeded — get credentials from config
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

read -p "  Press Enter to connect a bank, 'p' to paste a token, or 'n' to skip: " choice
while [ "$choice" != "n" ]; do
    if [ "$choice" = "p" ]; then
        read -p "  Access token: " manual_token
        read -p "  Account name (e.g. Bluevine): " manual_name
        read -p "  Type (checking or credit_card): " manual_type
        read -p "  Last 4 digits (mask): " manual_mask
        echo "{\"access_token\":\"$manual_token\",\"accounts\":[{\"name\":\"$manual_name\",\"mask\":\"$manual_mask\",\"type\":\"$manual_type\"}]}" >> /tmp/plaid-tokens-all.jsonl
        success "Token saved for matching"
    else
        export PATH="$HOME/.local/bin:$PATH"
        # Ensure credentials are set
        if [ -z "$PLAID_CLIENT_ID" ] || [ -z "$PLAID_SECRET" ]; then
            echo -e "  Enter your Plaid credentials from: ${CYAN}https://dashboard.plaid.com/developers/keys${NC}"
            read -p "  Client ID: " PLAID_CLIENT_ID
            read -p "  Secret (Production): " PLAID_SECRET
            export PLAID_CLIENT_ID PLAID_SECRET
        fi
        uv run plaid_sync.py --add-bank
        ADD_BANK_EXIT=$?
        if [ "$ADD_BANK_EXIT" -ne 0 ]; then
            warn "Failed — likely a credentials mismatch (multiple Plaid teams?)."
            echo -e "  Paste correct keys from: ${CYAN}https://dashboard.plaid.com/developers/keys${NC}"
            echo ""
            read -p "  Client ID: " PLAID_CLIENT_ID
            read -p "  Secret (Production): " PLAID_SECRET
            export PLAID_CLIENT_ID PLAID_SECRET
            if [ -f ~/.config/plaid-cli/config.json ]; then
                python3 -c "
import json
with open('$HOME/.config/plaid-cli/config.json') as f: d=json.load(f)
d.setdefault('environments',{}).setdefault('production',{})['secret']='$PLAID_SECRET'
with open('$HOME/.config/plaid-cli/config.json','w') as f: json.dump(d,f,indent=2)
" 2>/dev/null
            fi
            uv run plaid_sync.py --add-bank || warn "Still failing — check your credentials"
        fi

        # If bank was connected, save token for later matching (after Wave setup)
        if [ -f /tmp/plaid-new-token.txt ]; then
            cat /tmp/plaid-new-token.txt >> /tmp/plaid-tokens-all.jsonl
            rm -f /tmp/plaid-new-token.txt
            success "Bank token saved for matching"
        fi
    fi

    echo ""
    read -p "  Connect another bank? (y/n, or 'p' to paste token): " choice
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

# ─── Match Plaid accounts to Wave accounts ────────────────────────────────────

if [ -f /tmp/plaid-tokens-all.jsonl ]; then
    info "Matching your bank accounts to Wave..."
    export WAVE_ACCESS_TOKEN WAVE_BUSINESS_ID
    uv run scripts/match_accounts.py

    # Handle unmatched accounts interactively
    if [ -f /tmp/plaid-access-tokens.txt ]; then
        PLAID_ACCESS_TOKENS=$(cat /tmp/plaid-access-tokens.txt)
    fi

    # Check for unmatched accounts in the output
    if grep -q "UNMATCHED" /tmp/plaid-access-tokens.txt 2>/dev/null || [ -z "$PLAID_ACCESS_TOKENS" ]; then
        # Show available Wave accounts
        if [ -f /tmp/wave-account-options.txt ]; then
            echo ""
            echo -e "  ${BOLD}Available Wave accounts:${NC}"
            cat /tmp/wave-account-options.txt | awk '{printf "    %d. %s\n", NR, $0}'
            echo ""
        fi
        # Read the jsonl and ask for each
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                ACCT_NAME=$(echo "$line" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['accounts'][0]['name'])" 2>/dev/null)
                ACCT_TOKEN=$(echo "$line" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['access_token'])" 2>/dev/null)
                ACCT_TYPE=$(echo "$line" | python3 -c "import json,sys; d=json.load(sys.stdin); a=d['accounts'][0]; print('credit_card' if a['type']=='credit_card' else 'checking')" 2>/dev/null)
                read -p "  Wave account for '$ACCT_NAME' ($ACCT_TYPE): " wave_name
                if [ -n "$wave_name" ]; then
                    ENTRY="${ACCT_NAME}:${ACCT_TOKEN}:${wave_name}:${ACCT_TYPE}"
                    if [ -z "$PLAID_ACCESS_TOKENS" ]; then
                        PLAID_ACCESS_TOKENS="$ENTRY"
                    else
                        PLAID_ACCESS_TOKENS="${PLAID_ACCESS_TOKENS},${ENTRY}"
                    fi
                fi
            fi
        done < /tmp/plaid-tokens-all.jsonl
    fi

    export PLAID_ACCESS_TOKENS
    rm -f /tmp/plaid-tokens-all.jsonl /tmp/plaid-access-tokens.txt /tmp/wave-account-options.txt
    if [ -n "$PLAID_ACCESS_TOKENS" ]; then
        success "PLAID_ACCESS_TOKENS ready"
    fi
fi

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
    
    # Build keywords.json directly from the CSV's existing categorization
    info "Building keywords.json from your existing categorization..."
    uv run scripts/build_keywords.py "$csv_path"

    success "keywords.json generated from your existing categorization"
    info "Review it and tweak if needed. Run 'uv run plaid_sync.py --dump-accounts' to validate."
else
    warn "No CSV found. Export from Wave → Reports → Account Transactions, drop in workspace, re-run."
fi

# ─── Step 6: Save secrets ─────────────────────────────────────────────────────

step "Step 6/6 · Save secrets to GitHub"

read -p "  Auto-save secrets to this repo? (y/n): " save_secrets
if [ "$save_secrets" = "y" ]; then
    CLIENT_ID="${PLAID_CLIENT_ID}"
    SECRET="${PLAID_SECRET}"

    # Test if we have permission, if not re-auth gh
    if ! gh secret set PLAID_CLIENT_ID --body "$CLIENT_ID" 2>/dev/null; then
        info "Need GitHub auth to save secrets (one-time)."
        unset GITHUB_TOKEN
        gh auth login -w -p https --git-protocol https
    fi

    gh secret set PLAID_CLIENT_ID --body "$CLIENT_ID" &>/dev/null && success "Saved PLAID_CLIENT_ID"
    if [ -n "$SECRET" ]; then
        gh secret set PLAID_SECRET --body "$SECRET" &>/dev/null && success "Saved PLAID_SECRET"
    else
        warn "PLAID_SECRET is empty — set it manually"
    fi
    if [ -n "$WAVE_ACCESS_TOKEN" ]; then
        gh secret set WAVE_ACCESS_TOKEN --body "$WAVE_ACCESS_TOKEN" &>/dev/null && success "Saved WAVE_ACCESS_TOKEN"
    else
        warn "WAVE_ACCESS_TOKEN is empty — set it manually"
    fi
    if [ -n "$WAVE_BUSINESS_ID" ]; then
        gh secret set WAVE_BUSINESS_ID --body "$WAVE_BUSINESS_ID" &>/dev/null && success "Saved WAVE_BUSINESS_ID"
    else
        warn "WAVE_BUSINESS_ID is empty — set it manually"
    fi

    echo ""
    if [ -n "$PLAID_ACCESS_TOKENS" ]; then
        gh secret set PLAID_ACCESS_TOKENS --body "$PLAID_ACCESS_TOKENS" &>/dev/null &
        spinner $! "Saving PLAID_ACCESS_TOKENS"
    else
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
    fi
else
    warn "Add secrets manually: Settings → Secrets → Actions"
fi

# ─── Done ─────────────────────────────────────────────────────────────────────

# Enable the Actions workflow
gh workflow enable sync.yml 2>/dev/null && success "GitHub Actions workflow enabled" || true

# Trigger a test run
gh workflow run sync.yml -f days=3 -f dry_run=true 2>/dev/null && success "Test run triggered (dry-run)" || true

# Wait for it to complete and show result
info "Waiting for test run to complete..."
sleep 10
RUN_ID=$(gh run list --workflow=sync.yml -L 1 --json databaseId -q '.[0].databaseId' 2>/dev/null)
if [ -n "$RUN_ID" ]; then
    gh run watch "$RUN_ID" --exit-status 2>/dev/null && success "Test run passed! ✓" || warn "Test run failed — check Actions tab for details"
    REPO_URL=$(gh repo view --json url -q '.url' 2>/dev/null)
    echo -e "  ${CYAN}${REPO_URL}/actions/runs/${RUN_ID}${NC}"
fi

echo ""
echo -e "  ${BOLD}  ╔══════════════════════════════════════════╗${NC}"
echo -e "  ${BOLD}  ║  ${GREEN}✓ Setup complete!${NC}${BOLD}                      ║${NC}"
echo -e "  ${BOLD}  ╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Your sync runs daily at 9am ET automatically."
echo -e "  Trigger manually: ${CYAN}Actions tab → Run workflow${NC}"
echo ""
echo -e "  ${DIM}You can close this Codespace now.${NC}"
echo ""
