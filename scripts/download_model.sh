#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

MODEL_DIR="../models"
MODEL_PATH="$MODEL_DIR/mistral-7b-instruct-v0.2.Q4_K_M.gguf"
MODEL_URL="https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.2-GGUF/resolve/main/mistral-7b-instruct-v0.2.Q4_K_M.gguf"

echo -e "${YELLOW}Checking for Mistral 7B model...${NC}"

# Create models directory if it doesn't exist
mkdir -p "$MODEL_DIR"

# Check if model already exists
if [ -f "$MODEL_PATH" ]; then
  echo -e "${GREEN}Model already exists at $MODEL_PATH${NC}"
else
  echo -e "${YELLOW}Downloading Mistral 7B model...${NC}"
  echo -e "${YELLOW}This may take a while depending on your internet connection.${NC}"
  echo -e "${YELLOW}The model is approximately 4.1GB in size.${NC}"
  
  # Try wget first
  if command -v wget &> /dev/null; then
    wget -O "$MODEL_PATH" "$MODEL_URL"
  # If wget is not available, try curl
  elif command -v curl &> /dev/null; then
    curl -L "$MODEL_URL" -o "$MODEL_PATH"
  else
    echo -e "${RED}Error: Neither wget nor curl is available. Please install one of them and try again.${NC}"
    exit 1
  fi
  
  # Check if download was successful
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}Model downloaded successfully to $MODEL_PATH${NC}"
  else
    echo -e "${RED}Error: Failed to download model. Please check your internet connection and try again.${NC}"
    exit 1
  fi
fi