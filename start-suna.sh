#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Suna services...${NC}"

# Start Redis server
echo -e "${YELLOW}Starting Redis server...${NC}"
systemctl start redis-server
if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to start Redis server${NC}"
  exit 1
fi

# Start llama.cpp server
echo -e "${YELLOW}Starting llama.cpp server...${NC}"
systemctl start suna-llama
if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to start llama.cpp server${NC}"
  exit 1
fi

# Wait for llama.cpp server to initialize
echo -e "${YELLOW}Waiting for llama.cpp server to initialize (10 seconds)...${NC}"
sleep 10

# Start backend
echo -e "${YELLOW}Starting Suna backend...${NC}"
systemctl start suna-backend
if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to start Suna backend${NC}"
  exit 1
fi

# Wait for backend to initialize
echo -e "${YELLOW}Waiting for backend to initialize (5 seconds)...${NC}"
sleep 5

# Start frontend
echo -e "${YELLOW}Starting Suna frontend...${NC}"
systemctl start suna-frontend
if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to start Suna frontend${NC}"
  exit 1
fi

echo -e "${GREEN}All Suna services started successfully!${NC}"
echo -e "Frontend is available at: ${YELLOW}http://localhost:3000${NC}"
echo -e "To check service status: ${YELLOW}systemctl status suna-frontend suna-backend suna-llama redis-server${NC}"
echo -e "To view logs: ${YELLOW}tail -f /var/log/suna/*.log${NC}"