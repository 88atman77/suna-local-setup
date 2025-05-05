# Suna Local System

A complete, 100% local implementation of the [Suna AI agent framework](https://github.com/kortix-ai/suna) that runs entirely on your own hardware without any external API dependencies. This system replaces all cloud services with local alternatives, centered around a Mistral 7B model served via llama.cpp.

## Features

- **Completely offline operation** - no external API dependencies whatsoever
- Uses Mistral 7B Instruct model via llama.cpp for local AI capabilities
- Replaces all cloud services with local alternatives:
  - Local LLM instead of OpenAI
  - Local FAISS vector store for document retrieval
  - Local mock search instead of Tavily
  - Local mock image generation
  - Local authentication instead of Supabase
  - Local file storage instead of cloud storage
- Optimized for CPU-only operation with minimal resource usage
- Bypasses authentication and database requirements in LOCAL mode
- Includes systemd service files for all components
- Provides scripts for easy installation and management

## Requirements

- Linux VDS with at least 2 CPU cores and 16GB RAM
- At least 10GB of free disk space
- No GPU required

## Quick Start

1. Clone this repository:
```bash
git clone https://github.com/openhands/suna-local-system.git
cd suna-local-system
```

2. Run the installation script:
```bash
sudo ./install.sh
```

3. Start the services:
```bash
sudo ./start-suna.sh
```

4. Access the Suna UI at http://your-server-ip:3000

## Components

- **llama.cpp server**: Serves the Mistral 7B model with an OpenAI-compatible API
- **FAISS vector store**: Local vector database for document retrieval and semantic search
- **Suna backend**: Modified to use local endpoints and bypass database requirements
- **Suna frontend**: Modified to bypass authentication in LOCAL mode
- **Redis server**: Required for agent run streaming
- **Mock services**: Local implementations for web search and image generation

## Configuration

All configuration is handled automatically by the installation script. The main configuration files are:

- `/etc/suna/backend/.env`: Backend configuration
- `/etc/suna/frontend/.env.local`: Frontend configuration
- `/etc/systemd/system/suna-*.service`: Systemd service files

## Scripts

- `install.sh`: Main installation script
- `start-suna.sh`: Start all Suna services
- `stop-suna.sh`: Stop all Suna services
- `scripts/download_model.sh`: Download the Mistral 7B model
- `scripts/setup_environment.sh`: Set up the Python environment
- `scripts/start_llama_server.sh`: Start the llama.cpp server
- `scripts/test_llama_server.py`: Test the llama.cpp server

## Patches

The repository includes patches for the Suna codebase to make it work in a completely local environment:

- `files/backend/thread_manager.py.patch`: Modify thread manager to work without a database
- `files/backend/api.py.patch`: Modify agent API to work in LOCAL mode
- `files/backend/local_search.py`: Replace external API tools with local alternatives

## Performance Optimization

The system is optimized for CPU-only operation with minimal resource usage:

- Mistral 7B model is quantized to 4-bit precision (Q4_K_M)
- llama.cpp is configured to use OpenBLAS for better CPU performance
- Redis is configured with minimal memory usage
- Systemd services are configured for automatic restart and dependency management

## Troubleshooting

### Services Not Starting

Check the status of services:
```bash
systemctl status suna-llama.service
systemctl status suna-backend.service
systemctl status suna-frontend.service
```

View logs:
```bash
journalctl -u suna-llama.service -n 50
journalctl -u suna-backend.service -n 50
```

### High Memory Usage

If the system is running out of memory:
1. Reduce the Redis memory limit
2. Use a more quantized model (Q2_K instead of Q4_K)
3. Reduce the context size in llama.cpp server

### Slow Response Times

If responses are too slow:
1. Adjust the number of threads based on your CPU
2. Consider using a smaller model if necessary

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgements

- [Suna AI](https://github.com/kortix-ai/suna) - The original AI agent framework
- [llama.cpp](https://github.com/ggerganov/llama.cpp) - Efficient inference of LLaMA models
- [Mistral AI](https://mistral.ai/) - Creators of the Mistral 7B model
- [FAISS](https://github.com/facebookresearch/faiss) - Vector similarity search library