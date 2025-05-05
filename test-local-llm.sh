#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Testing local LLM setup...${NC}"

# Check if llama.cpp server is running
echo -e "${YELLOW}Checking if llama.cpp server is running...${NC}"
curl -s http://localhost:8000/v1/models > /dev/null
if [ $? -ne 0 ]; then
  echo -e "${RED}llama.cpp server is not running. Starting it...${NC}"
  # Start llama.cpp server in the background
  python3 -m llama_cpp.server --model /etc/suna/models/mistral-7b-instruct-v0.2.Q4_K_M.gguf --host 0.0.0.0 --port 8000 --n_ctx 4096 > /tmp/llama.log 2>&1 &
  LLAMA_PID=$!
  echo -e "${GREEN}llama.cpp server started with PID $LLAMA_PID${NC}"
  echo -e "${YELLOW}Waiting for server to initialize...${NC}"
  sleep 10
else
  echo -e "${GREEN}llama.cpp server is running${NC}"
fi

# Test the LLM directly
echo -e "${YELLOW}Testing LLM directly...${NC}"
curl -s -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-7b-instruct-v0.2.Q4_K_M.gguf",
    "messages": [{"role": "user", "content": "Say hello world"}],
    "temperature": 0.7,
    "max_tokens": 100
  }'

echo -e "\n\n${GREEN}Test completed!${NC}"