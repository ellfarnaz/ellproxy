# Factory Droid CLI Setup Guide

<div align="center">
  <img src="header.png" width="100%" alt="EllProxy Header" style="border-radius: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.1);">
</div>

This guide explains how to configure Factory AI's Droid CLI to work with EllProxy. This allows you to use your existing AI subscriptions (Claude, Gemini, etc.) with Factory Droids instead of purchasing separate credits.

## Overview

EllProxy integrates with Factory Droid CLI by acting as an OpenAI-compatible endpoint. It intercepts model requests and routes them to your locally authenticated providers.

## Prerequisites

- EllProxy installed and running
- Factory Droid CLI installed
- Active subscription or API access to the models you want to use (e.g., Claude Pro, Gemini)

## Setup Methods

### Method 1: Quick Setup (Recommended)

1. Open EllProxy.
2. Go to the **Quick Setup** tab.
3. Click **Scan** to detect "Droid Factory CLI".
4. If detected, click the **Setup** button (or "Setup All").
5. EllProxy will automatically inject the required configuration into your `~/.factory/config.json`.

### Method 2: Manual Setup

If you prefer to configure it manually, edit your Factory configuration file.

1. Open (or create) `~/.factory/config.json`.
2. Locate the `custom_models` array. If it doesn't exist, create it.
3. Add the following model definitions:

```json
{
  "custom_models": [
    {
      "api_key": "dummy-key",
      "base_url": "http://localhost:8317/v1",
      "model": "ellproxy-default",
      "model_display_name": "EllProxy: Default Model",
      "provider": "openai"
    },
    {
      "api_key": "dummy-key",
      "base_url": "http://localhost:8317/v1",
      "model": "ellproxy-thinking",
      "model_display_name": "EllProxy: Thinking Model",
      "provider": "openai"
    }
  ]
}
```

> **Note:** The `api_key` can be any string (EllProxy ignores it), but it must be present.

## How to Use

Once configured, restart your Droid CLI. You will now see two new models available:

1. **EllProxy: Default Model** (`ellproxy-default`)
   - Uses the model you selected as "Default" in EllProxy's **Models** tab.
   - Best for general coding tasks, quick edits, and standard generation.

2. **EllProxy: Thinking Model** (`ellproxy-thinking`)
   - Uses the model you selected as "Thinking" in EllProxy's **Models** tab.
   - Supports extended reasoning/thinking capabilities.
   - Best for complex architecture, debugging, and difficult logic problems.

## Configuring Models in EllProxy

To change which actual AI model is used:

1. Click the **EllProxy menu bar icon** → **Open Settings**.
2. Go to the **Models** tab.
3. Set your **Default Model** (e.g., `Gemini 2.5 Flash`).
4. Set your **Default Thinking Model** (e.g., `Claude 3.7 Sonnet Thinking`).

Now, when Factory Droids use "EllProxy: Default Model", they are actually using Gemini 2.5 Flash through your personal Google account.

## Troubleshooting

### "Model not found"
- Ensure you have restarted the Droid CLI after updating the config.
- Check that the `base_url` is exactly `http://localhost:8317/v1`.

### "Connection refused"
- Ensure EllProxy is running (check the menu bar icon).
- Verify port 8317 is available.

### "Authentication failed"
- Check the **Services** tab in EllProxy to ensure your providers (Claude, Google, etc.) are connected and authenticated.
