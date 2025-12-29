#!/bin/bash

# Universal AI Model Curl Tester (Auto-Discovery Mode)
# Automatically fetches models from local proxy and tests them for thinking capabilities.

# ============================================================================
# CONFIGURATION
# ============================================================================

BASE_URL="http://localhost:8317"
MODELS_ENDPOINT="$BASE_URL/v1/models"
CHAT_ENDPOINT="$BASE_URL/v1/chat/completions"
TEST_PROMPT="Explain why the sky is blue using simple reasoning."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed.${NC}"
    exit 1
fi

echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          Auto-Discovery AI Model Tester                       ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Base URL:${NC} $BASE_URL"
echo ""

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

detect_provider() {
    local model="$1"
    # Simple heuristic to guess provider from model name
    if [[ "$model" == *"deepseek"* ]]; then echo "deepseek"
    elif [[ "$model" == *"qwen"* ]]; then echo "qwen"
    elif [[ "$model" == *"gemini"* ]]; then echo "google"
    elif [[ "$model" == *"grok"* ]]; then echo "xai"
    elif [[ "$model" == *"claude"* ]]; then echo "anthropic"
    elif [[ "$model" == *"gpt"* ]] || [[ "$model" == *"o1"* ]] || [[ "$model" == *"o3"* ]]; then echo "openai"
    elif [[ "$model" == *"minimax"* ]]; then echo "minimax"
    elif [[ "$model" == *"glm"* ]]; then echo "glm"
    elif [[ "$model" == *"moonshot"* ]]; then echo "moonshot"
    else echo "unknown"
    fi
}

get_extra_params() {
    local provider="$1"
    local model="$2"
    
    case "$provider" in
        deepseek)
            # DeepSeek-reasoner usually needs thinking enabled if it's not implied
            if [[ "$model" == *"chat"* ]] || [[ "$model" == *"v3"* ]]; then
                echo ',"thinking":{"type":"enabled"}'
            else
                echo ''
            fi
            ;;
        google)
            # Gemini 3 might need thinkingLevel
            if [[ "$model" == *"gemini-3"* ]] && [[ "$model" != *"deep-think"* ]]; then
                 echo ',"thinkingLevel":"high"'
            else
                 echo ''
            fi
            ;;
        xai)
            if [[ "$model" == *"mini"* ]]; then
                echo ',"reasoning_effort":"high"'
            else
                echo ''
            fi
            ;;
        glm)
            if [[ "$model" == *"glm-4.6"* ]] || [[ "$model" == *"glm-4.7"* ]]; then
                echo ',"thinking":{"type":"enabled"}'
            elif [[ "$model" == *"glm-4.5"* ]]; then
                echo ',"chat_template_kwargs":{"enable_thinking":true}'
            else
                echo ''
            fi
            ;;
        *)
            echo ''
            ;;
    esac
}

test_model() {
    local model_id="$1"
    local provider=$(detect_provider "$model_id")
    local extra_params=$(get_extra_params "$provider" "$model_id")
    
    echo -e "${BLUE}Testing Model:${NC} $model_id ${CYAN}($provider)${NC}"
    
    local request_body=$(cat <<EOF
{
  "model": "$model_id",
  "messages": [
    {
      "role": "user",
      "content": "$TEST_PROMPT"
    }
  ]$extra_params
}
EOF
)

    local response=$(curl -s --max-time 60 "$CHAT_ENDPOINT" \
        -H "Content-Type: application/json" \
        -d "$request_body" 2>&1)

    if [ $? -ne 0 ]; then
        echo -e "${RED}  ✗ Request failed or timed out${NC}"
        return
    fi
    
    # Check for API error
    local error_msg=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
    if [ -n "$error_msg" ]; then
        echo -e "${RED}  ✗ API Error: $error_msg${NC}"
        return
    fi

    # Check for thinking
    local reasoning_content=$(echo "$response" | jq -r '.choices[0].message.reasoning_content // empty' 2>/dev/null)
    local thinking_result=$(echo "$response" | jq -r '.choices[0].message.thinkingResult.summary // empty' 2>/dev/null)
    local reasoning_details=$(echo "$response" | jq -r '.choices[0].message.reasoning_details[0].text // empty' 2>/dev/null)
    
    # Check for <think> tag
    local content=$(echo "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
    local has_think_tag=0
    # Check for either <think> or </think> (some models skip the opening tag)
    if echo "$content" | grep -q "<think>" || echo "$content" | grep -q "</think>"; then
        has_think_tag=1
    fi
    
    # Determine result and print content
    if [ -n "$reasoning_content" ]; then
        echo -e "${GREEN}  ✓ Supported (Standard reasoning_content)${NC}"
    elif [ -n "$thinking_result" ]; then
         echo -e "${GREEN}  ✓ Supported (Google thinkingResult)${NC}"
    elif [ -n "$reasoning_details" ]; then
         echo -e "${GREEN}  ✓ Supported (MiniMax reasoning_details)${NC}"
    elif [ "$has_think_tag" -eq 1 ]; then
         echo -e "${GREEN}  ✓ Supported (<think> tags)${NC}"
         
         # Extract thinking content logic
         local thinking_text=""
         if echo "$content" | grep -q "<think>"; then
             thinking_text=$(echo "$content" | sed -n '/<think>/,/<\/think>/p' | sed 's/<think>//;s/<\/think>//')
         else
             # Case: Missing opening <think>, but has </think>
             thinking_text=$(echo "$content" | awk -F'</think>' '{print $1}')
         fi
         
         if [ -n "$thinking_text" ]; then
             echo -e "${YELLOW}    Thinking Preview:${NC}"
             echo "$thinking_text" | head -c 200 | tr -d '\n'
             echo "..."
         fi
    else
         echo -e "${YELLOW}  - No specific thinking structure detected${NC}"
    fi
    echo ""
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

echo "Fetching models from $MODELS_ENDPOINT..."
MODELS_JSON=$(curl -s "$MODELS_ENDPOINT")

if [ -z "$MODELS_JSON" ]; then
    echo -e "${RED}Error: Failed to fetch models. Is the server running?${NC}"
    exit 1
fi

# Parse models list
# We assume standard OpenAI format: {"data": [{"id": "model1"}, ...]}
MODEL_IDS=$(echo "$MODELS_JSON" | jq -r '.data[].id' 2>/dev/null)

if [ -z "$MODEL_IDS" ]; then
    echo -e "${RED}Error: No IDs found in response or invalid JSON.${NC}"
    echo "Response preview: ${MODELS_JSON:0:100}..."
    exit 1
fi

COUNT=$(echo "$MODEL_IDS" | wc -l | xargs)
echo -e "Found ${GREEN}$COUNT${NC} models."
echo "Starting tests..."
echo "---------------------------------------------------"

IFS=$'\n'
for model_id in $MODEL_IDS; do
    test_model "$model_id"
done

echo "---------------------------------------------------"
echo -e "${GREEN}All tests completed.${NC}"