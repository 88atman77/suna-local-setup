#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Stopping Suna services...${NC}"

# Stop frontend
echo -e "${YELLOW}Stopping Suna frontend...${NC}"
systemctl stop suna-frontend

# Stop backend
echo -e "${YELLOW}Stopping Suna backend...${NC}"
systemctl stop suna-backend

# Stop llama.cpp server
echo -e "${YELLOW}Stopping llama.cpp server...${NC}"
systemctl stop suna-llama

# Stop Redis server
echo -e "${YELLOW}Stopping Redis server...${NC}"
systemctl stop redis-server

echo -e "${GREEN}All Suna services stopped successfully!${NC}"