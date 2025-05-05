# Suna Local Setup Documentation

This document provides detailed information about the Suna local setup, including architecture, configuration, and troubleshooting.

## Architecture

The Suna local setup consists of the following components:

1. **llama.cpp server**: Serves the Mistral 7B model with an OpenAI-compatible API on port 8000
2. **Redis server**: Required for agent run streaming and message passing
3. **Suna backend**: Modified to use the local LLM endpoint and bypass database requirements, runs on port 8080
4. **Suna frontend**: Modified to bypass authentication in LOCAL mode, runs on port 3000

### Component Diagram

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Browser   │────▶│   Frontend  │────▶│   Backend   │────▶│  llama.cpp  │
│             │◀────│  (port 3000)│◀────│ (port 8080) │◀────│ (port 8000) │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
                                              │
                                              │
                                              ▼
                                        ┌─────────────┐
                                        │    Redis    │
                                        │ (port 6379) │
                                        └─────────────┘
```

## Installation

The installation script (`install.sh`) performs the following steps:

1. Creates necessary directories
2. Installs system dependencies
3. Sets up a Python virtual environment
4. Installs llama-cpp-python with server support
5. Downloads the Mistral 7B model
6. Clones the Suna repository
7. Installs backend and frontend dependencies
8. Creates configuration files
9. Modifies Suna code for local operation
10. Creates systemd service files
11. Creates start and stop scripts

## Configuration

### Backend Configuration

The backend configuration is stored in `/etc/suna/backend/.env`:

```
ENV_MODE=LOCAL
OPENAI_API_KEY=sk-dummy-key
OPENAI_API_BASE=http://localhost:8000/v1
SUPABASE_URL=https://dummy.supabase.co
SUPABASE_KEY=dummy-key
REDIS_URL=redis://localhost:6379
```

### Frontend Configuration

The frontend configuration is stored in `/etc/suna/frontend/.env.local`:

```
NEXT_PUBLIC_SUPABASE_URL=https://dummy.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=dummy-key
NEXT_PUBLIC_API_URL=http://localhost:8080
ENV_MODE=LOCAL
```

### Systemd Services

The following systemd services are created:

- `suna-llama.service`: Runs the llama.cpp server
- `suna-backend.service`: Runs the Suna backend
- `suna-frontend.service`: Runs the Suna frontend

## Code Modifications

The following modifications are made to the Suna codebase:

### Backend Modifications

1. **config.py**: 
   - Added `OPENAI_API_BASE` property
   - Made all API keys optional with default values
   - Added support for LOCAL mode configuration

2. **llm.py**: 
   - Modified to use the local model endpoint
   - Added fallback to dummy API key when none is provided

3. **supabase.py**: 
   - Modified to bypass database initialization in LOCAL mode
   - Added handling for null client in database operations

4. **auth_utils.py**: 
   - Modified to bypass authentication in LOCAL mode
   - Added automatic user ID generation for local sessions

5. **agent/run.py**: 
   - Modified to use local-mistral as the default model
   - Added support for LOCAL mode operation without database

6. **agent/api.py**:
   - Added test_local_llm endpoint for testing the local LLM
   - Modified stream_agent_run to bypass authentication in LOCAL mode
   - Updated update_agent_run_status to skip database updates in LOCAL mode

7. **thread_manager.py**:
   - Modified add_message to handle LOCAL mode with mock messages
   - Added handling for null database client

8. **tools/local_search.py**:
   - Created a new local search tool to replace external search APIs
   - Implemented predefined responses based on query keywords

### Frontend Modifications

1. **AuthProvider.tsx**: 
   - Modified to automatically create a mock user session in LOCAL mode
   - Added bypass for authentication flows when in LOCAL mode

2. **layout.tsx**: 
   - Modified to bypass API health check in LOCAL mode
   - Added automatic success response for health checks

## Usage

### Starting Suna

To start all Suna services:

```bash
start-suna.sh
```

This will start the services in the following order:
1. Redis server
2. llama.cpp server
3. Suna backend
4. Suna frontend

### Stopping Suna

To stop all Suna services:

```bash
stop-suna.sh
```

This will stop the services in the reverse order.

### Accessing Suna

Once all services are running, you can access the Suna UI at:

```
http://your-server-ip:3000
```

## Troubleshooting

### Checking Service Status

To check the status of all services:

```bash
systemctl status redis-server suna-llama suna-backend suna-frontend
```

### Viewing Logs

Logs are stored in `/var/log/suna/`:

```bash
tail -f /var/log/suna/llama.log
tail -f /var/log/suna/backend.log
tail -f /var/log/suna/frontend.log
```

### Common Issues

1. **llama.cpp server fails to start**
   - Check if the model file exists at `/etc/suna/models/mistral-7b-instruct-v0.2.Q4_K_M.gguf`
   - Check if there's enough memory available

2. **Backend fails to connect to llama.cpp server**
   - Check if the llama.cpp server is running: `systemctl status suna-llama`
   - Check if the port 8000 is accessible: `curl http://localhost:8000/v1/models`

3. **Frontend shows "API Health Check Failed"**
   - Check if the backend is running: `systemctl status suna-backend`
   - Check if the port 8080 is accessible: `curl http://localhost:8080/api/health`

## Performance Optimization

The setup is optimized for CPU-only operation with minimal resource usage. However, you can further optimize performance:

1. **Adjust llama.cpp parameters**:
   - Modify `/etc/systemd/system/suna-llama.service` to add parameters like `--n_threads` to match your CPU core count

2. **Use a smaller model**:
   - Replace the Mistral 7B model with a smaller model like Mistral 7B in 4-bit quantization

3. **Adjust context window size**:
   - Modify the `--n_ctx` parameter in the llama.cpp server service to use a smaller context window (default is 4096)

## Security Considerations

This setup is designed for local use and has several security limitations:

1. Authentication is bypassed in LOCAL mode
2. No encryption for API communication
3. Services run as root

For production use, consider:
1. Enabling proper authentication
2. Setting up HTTPS
3. Running services as non-root users
4. Implementing proper access controls