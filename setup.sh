#!/usr/bin/env bash
set -e

echo "═══════════════════════════════════════════════════════"
echo "  plaid-wave-sync setup"
echo "═══════════════════════════════════════════════════════"
echo ""

# Step 1: Plaid account
echo "▶ Step 1: Plaid account"
if plaid config 2>/dev/null | grep -q "client_id"; then
    echo "  ✓ Already logged in"
else
    echo "  Creating Plaid account (opens browser)..."
    plaid register
    echo ""
    echo "  Activating trial plan (10 free connections)..."
    plaid trial
    echo ""
    echo "  Fetching API keys..."
    plaid keys fetch
fi
echo ""

# Step 2: Connect banks
echo "▶ Step 2: Connect your bank accounts"
echo "  This opens Plaid Link in your browser."
echo "  (Codespaces will auto-tunnel the URL)"
echo ""
read -p "  Press Enter to connect a bank (or 's' to skip): " choice
while [ "$choice" != "s" ]; do
    plaid link --products transactions
    echo ""
    read -p "  Press Enter to connect another bank, or 's' when done: " choice
done
echo ""

# Step 3: Show results
echo "▶ Step 3: Your Plaid credentials"
echo ""
plaid config
echo ""
echo "  Your linked accounts:"
plaid item list
echo ""

# Step 4: Wave setup
echo "▶ Step 4: Wave setup"
echo ""
if [ -z "$WAVE_ACCESS_TOKEN" ]; then
    echo "  Get your Wave API token from:"
    echo "  https://developer.waveapps.com/hc/en-us/articles/360019762711"
    echo ""
    read -p "  Paste your Wave token: " WAVE_ACCESS_TOKEN
    export WAVE_ACCESS_TOKEN
fi
echo ""
echo "  Your Wave accounts:"
uv run plaid_sync.py --dump-accounts
echo ""

# Step 5: Build keywords with Copilot
echo "▶ Step 5: Build keyword mappings"
echo ""
echo "  Drop your bank CSV (or Wave transaction export) into this workspace."
echo ""
read -p "  Path to your CSV (or Enter to skip): " csv_path
if [ -n "$csv_path" ] && [ -f "$csv_path" ]; then
    ACCOUNTS_OUTPUT=$(uv run plaid_sync.py --dump-accounts 2>/dev/null | grep -A1000 "^\[")
    echo "  Generating keywords.json with Copilot..."
    gh copilot -p "Read the file $csv_path. These are my Wave account names:

$ACCOUNTS_OUTPUT

Generate a keywords.json file that maps transaction description keywords to Wave account names. Rules:
- Keywords are lowercase substrings matched against transaction descriptions
- Values must exactly match a Wave account name from above
- Use null for internal transfers to skip
- Output valid JSON with keys: keywords, fallback_expense, fallback_income
- Be conservative, only map confident matches

Write the result to keywords.json" --no-confirm
    echo ""
    echo "  ✓ Check keywords.json and edit if needed"
else
    echo "  Skipped. See KEYWORDS_GUIDE.md to build keywords later."
fi
echo ""

# Step 6: Set GitHub secrets automatically
echo "▶ Step 6: Save secrets to your GitHub repo"
echo ""
read -p "  Auto-save secrets to this repo? (y/n): " save_secrets
if [ "$save_secrets" = "y" ]; then
    CLIENT_ID=$(plaid config 2>/dev/null | grep -i client_id | awk '{print $NF}')
    SECRET=$(plaid config 2>/dev/null | grep -i secret | awk '{print $NF}')

    gh secret set PLAID_CLIENT_ID --body "$CLIENT_ID"
    gh secret set PLAID_SECRET --body "$SECRET"
    gh secret set WAVE_ACCESS_TOKEN --body "$WAVE_ACCESS_TOKEN"

    # Get business ID
    BIZ_ID=$(uv run plaid_sync.py --dump-accounts 2>&1 | grep "Business ID" | awk '{print $NF}')
    if [ -n "$BIZ_ID" ]; then
        gh secret set WAVE_BUSINESS_ID --body "$BIZ_ID"
    fi

    echo ""
    echo "  ✓ Secrets saved! You still need to set PLAID_ACCESS_TOKENS manually."
    echo "    Format: Name:access-token:Wave Account Name:type"
    echo ""
    echo "  Get your access tokens:"
    echo "    plaid item list --json"
    echo ""
    read -p "  Paste your PLAID_ACCESS_TOKENS value (or Enter to skip): " tokens
    if [ -n "$tokens" ]; then
        gh secret set PLAID_ACCESS_TOKENS --body "$tokens"
        echo "  ✓ All secrets saved!"
    fi
else
    echo ""
    echo "  Add these manually at: Settings → Secrets → Actions"
    echo ""
    echo "     PLAID_CLIENT_ID"
    echo "     PLAID_SECRET"
    echo "     WAVE_ACCESS_TOKEN"
    echo "     WAVE_BUSINESS_ID"
    echo "     PLAID_ACCESS_TOKENS"
fi

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  ✓ Setup complete!"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Go to Actions tab and enable the workflow."
echo "  Trigger it manually to test, then it runs daily at 6am UTC."
echo ""
