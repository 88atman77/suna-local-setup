#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

VENV_DIR="../venv"
MODEL_PATH="../models/mistral-7b-instruct-v0.2.Q4_K_M.gguf"
HOST="0.0.0.0"
PORT="8000"
N_CTX="4096"
N_THREADS=$(nproc)

# Check if model exists
if [ ! -f "$MODEL_PATH" ]; then
  echo -e "${RED}Error: Model not found at $MODEL_PATH${NC}"
  echo -e "${YELLOW}Please run download_model.sh first.${NC}"
  exit 1
fi

# Activate virtual environment
echo -e "${YELLOW}Activating virtual environment...${NC}"
source "$VENV_DIR/bin/activate"

# Start llama.cpp server
echo -e "${YELLOW}Starting llama.cpp server with Mistral 7B model...${NC}"
echo -e "${YELLOW}Host: $HOST, Port: $PORT, Context: $N_CTX, Threads: $N_THREADS${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop the server${NC}"

python -m llama_cpp.server \
  --model "$MODEL_PATH" \
  --host "$HOST" \
  --port "$PORT" \
  --n_ctx "$N_CTX" \
  --n_threads "$N_THREADS"