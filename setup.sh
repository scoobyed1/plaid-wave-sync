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

# Step 5: Summary
echo "═══════════════════════════════════════════════════════"
echo "  ✓ Setup complete!"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Next steps:"
echo "  1. Edit keywords.json (see KEYWORDS_GUIDE.md)"
echo "  2. Add these secrets to your GitHub fork:"
echo "     → Settings → Secrets → Actions"
echo ""
echo "     PLAID_CLIENT_ID     = (from 'plaid config' above)"
echo "     PLAID_SECRET        = (from 'plaid config' above)"
echo "     WAVE_ACCESS_TOKEN   = $WAVE_ACCESS_TOKEN"
echo "     WAVE_BUSINESS_ID    = (from --dump-accounts above)"
echo "     PLAID_ACCESS_TOKENS = (see README for format)"
echo ""
echo "  3. Get your access tokens in the right format:"
echo "     plaid item list --json"
echo ""
