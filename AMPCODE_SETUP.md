# Amp CLI Setup Guide

<div align="center">
  <img src="header.png" width="100%" alt="EllProxy Header" style="border-radius: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.1);">
</div>

This guide explains how to configure Amp CLI to work with EllProxy, enabling you to use both Factory and Amp through a single proxy server.

## Overview

EllProxy integrates with Amp CLI by:
- Routing Amp management requests (login, settings) to ampcode.com
- Routing Amp model requests through CLIProxyAPI
- Automatically falling back to ampcode.com for models you haven't authenticated locally

## Prerequisites

- EllProxy installed and running
- Amp CLI installed (`amp --version` to verify)

## Setup Steps

### 1. Configure Amp URL

Edit or create `~/.config/amp/settings.json`:

```bash
mkdir -p ~/.config/amp
cat > ~/.config/amp/settings.json << 'EOF'
{
  "amp.url": "http://localhost:8317"
}
EOF
```

This tells Amp CLI to use EllProxy instead of connecting directly to ampcode.com.

### 2. Login to Amp

Run the Amp login command:

```bash
amp login
```

This will:
1. Open your browser to `http://localhost:8317/api/auth/cli-login`
2. EllProxy forwards the request to ampcode.com
3. You complete the login in your browser
4. Amp CLI saves your API key to `~/.local/share/amp/secrets.json`

### 3. Fix the Secrets File Format

After login, the secrets file will have URL-specific keys that CLIProxyAPI can't read. You need to add a simple `apiKey` field.

**Open the secrets file:**

```bash
cat ~/.local/share/amp/secrets.json
```

You'll see something like:

```json
{
  "apiKey@https://ampcode.com/": "sgamp_user_01XXXXX...",
  "apiKey@http://localhost:8317": "sgamp_user_01XXXXX..."
}
```

**Edit the file to add the `apiKey` field:**

```bash
nano ~/.local/share/amp/secrets.json
```

Add a new line with just `apiKey` (copy the value from one of the existing keys):

```json
{
  "apiKey@https://ampcode.com/": "sgamp_user_01XXXXX...",
  "apiKey@http://localhost:8317": "sgamp_user_01XXXXX...",
  "apiKey": "sgamp_user_01XXXXX..."
}
```

**Important:** The value should be identical to the other keys - just copy/paste it.

**Or use this one-liner to do it automatically:**

```bash
python3 << 'EOF'
import json
import os

secrets_file = os.path.expanduser('~/.local/share/amp/secrets.json')

with open(secrets_file, 'r') as f:
    data = json.load(f)

# Get the API key from any URL-specific key
api_key = data.get('apiKey@https://ampcode.com/', data.get('apiKey@http://localhost:8317', ''))

if api_key and 'apiKey' not in data:
    data['apiKey'] = api_key
    with open(secrets_file, 'w') as f:
        json.dump(data, f, indent=2)
    print('✅ Added apiKey field to secrets.json')
elif 'apiKey' in data:
    print('✅ apiKey field already exists')
else:
    print('❌ No API key found in secrets.json')
EOF
```

### 4. Restart EllProxy

For CLIProxyAPI to pick up the new API key:

1. Quit EllProxy from the menu bar
2. Launch EllProxy again

## Usage

Now you can use Amp CLI normally:

```bash
# Interactive mode
amp

# Direct prompt
amp "Write a hello world in Python"

# With specific mode
amp --mode smart "Explain quantum computing"
```

## How It Works

### Request Routing

```
Amp CLI
  ↓
  http://localhost:8317 (ThinkingProxy)
  ↓
  ├─ /auth/cli-login → /api/auth/cli-login → ampcode.com (login)
  ├─ /provider/* → /api/provider/* → CLIProxyAPI:8318 (model requests)
  └─ /api/* → ampcode.com (management requests)
```

### Model Fallback

When Amp requests a model:

1. **Local OAuth available?** (e.g., you ran `--codex-login` for GPT models)
   - ✅ Uses your ChatGPT Plus/Pro subscription (no Amp credits)
   
2. **No local OAuth?**
   - ✅ Falls back to ampcode.com using your Amp API key
   - Uses Amp credits

**Example:**
- If you've authenticated Claude (`--claude-login`), Claude models use your subscription
- Gemini models without local OAuth will use Amp credits

## Troubleshooting

### "auth_unavailable: no auth available"

**Problem:** CLIProxyAPI can't find the Amp API key.

**Solutions:**
1. Verify `~/.local/share/amp/secrets.json` has the `apiKey` field (see Step 3)
2. Restart EllProxy to reload the secrets file
3. Check permissions: `ls -la ~/.local/share/amp/secrets.json` (should be readable)

### "Unable to connect"

**Problem:** Amp can't reach the proxy.

**Solutions:**
1. Verify EllProxy is running (check menu bar)
2. Verify `AMP_URL` is set: `echo $AMP_URL` (should show `http://localhost:8317`)
3. Test the proxy: `curl http://localhost:8317/api/user` (should redirect or return HTML)

### "404 page not found" in browser during login

**Problem:** Path rewriting isn't working.

**Solutions:**
1. Make sure you're using the latest EllProxy build
2. Manually add `/api/` to the URL in the browser if needed

### Expired OAuth Tokens

If you have local OAuth tokens that have expired (e.g., old Google/Gemini auth), remove them:

```bash
# List current tokens
ls -la ~/.cli-proxy-api/*.json

# Remove expired token (example)
rm ~/.cli-proxy-api/ran@example.com-*.json

# Restart EllProxy
killall CLIProxyMenuBar
# Then launch EllProxy again
```

## Authenticating Local Providers (Optional)

To use your own subscriptions instead of Amp credits for specific models:

### Google/Gemini Models
```bash
/Applications/EllProxy.app/Contents/Resources/cli-proxy-api \
  -config /Applications/EllProxy.app/Contents/Resources/config.yaml \
  -login
```

### ChatGPT/OpenAI Models
```bash
/Applications/EllProxy.app/Contents/Resources/cli-proxy-api \
  -config /Applications/EllProxy.app/Contents/Resources/config.yaml \
  -codex-login
```

### Claude/Anthropic Models
```bash
/Applications/EllProxy.app/Contents/Resources/cli-proxy-api \
  -config /Applications/EllProxy.app/Contents/Resources/config.yaml \
  -claude-login
```

After authenticating, restart EllProxy. Those models will now use your subscriptions instead of Amp credits.

## Benefits

✅ **One proxy for everything** - Factory, Amp, and any other tool  
✅ **Smart fallback** - Uses your subscriptions when available, Amp credits when not  
✅ **Seamless integration** - Amp works exactly as before, just through the proxy  
✅ **Cost optimization** - Maximize use of existing subscriptions, minimize Amp credits  

## Additional Resources

- [Amp CLI Documentation](https://ampcode.com/manual)
- [CLIProxyAPI Amp Integration](https://github.com/router-for-me/CLIProxyAPI/blob/main/docs/amp-cli-integration.md)
- [Factory Setup Guide](FACTORY_SETUP.md)
