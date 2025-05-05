#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

VENV_DIR="../venv"

echo -e "${YELLOW}Setting up Python virtual environment...${NC}"

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
  echo -e "${RED}Error: Python 3 is not installed. Please install Python 3 and try again.${NC}"
  exit 1
fi

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
  echo -e "${YELLOW}Creating virtual environment at $VENV_DIR...${NC}"
  python3 -m venv "$VENV_DIR"
  if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to create virtual environment. Please install python3-venv and try again.${NC}"
    exit 1
  fi
else
  echo -e "${GREEN}Virtual environment already exists at $VENV_DIR${NC}"
fi

# Activate virtual environment
echo -e "${YELLOW}Activating virtual environment...${NC}"
source "$VENV_DIR/bin/activate"

# Install required packages
echo -e "${YELLOW}Installing required packages...${NC}"
echo -e "${YELLOW}This may take a while...${NC}"

# Install llama-cpp-python with server support
echo -e "${YELLOW}Installing llama-cpp-python with server support...${NC}"
pip install --upgrade pip
CMAKE_ARGS="-DLLAMA_BLAS=ON -DLLAMA_BLAS_VENDOR=OpenBLAS" pip install llama-cpp-python[server]

# Install other dependencies
echo -e "${YELLOW}Installing other dependencies...${NC}"
pip install fastapi uvicorn redis faiss-cpu sentence-transformers

echo -e "${GREEN}Environment setup complete!${NC}"
echo -e "To activate the environment, run: ${YELLOW}source $VENV_DIR/bin/activate${NC}"