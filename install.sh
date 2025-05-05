#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Suna Local Setup Installation${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root${NC}"
  exit 1
fi

# Create directories
echo -e "${YELLOW}Creating directories...${NC}"
mkdir -p /etc/suna/backend
mkdir -p /etc/suna/frontend
mkdir -p /etc/suna/models
mkdir -p /var/log/suna

# Install dependencies
echo -e "${YELLOW}Installing dependencies...${NC}"
apt-get update
apt-get install -y python3 python3-pip python3-venv nodejs npm redis-server

# Set up Python virtual environment
echo -e "${YELLOW}Setting up Python virtual environment...${NC}"
python3 -m venv /opt/suna/venv
source /opt/suna/venv/bin/activate

# Install llama-cpp-python with server support
echo -e "${YELLOW}Installing llama-cpp-python...${NC}"
CMAKE_ARGS="-DLLAMA_BLAS=ON -DLLAMA_BLAS_VENDOR=OpenBLAS" pip install llama-cpp-python[server]

# Download Mistral 7B model if not already present
MODEL_PATH="/etc/suna/models/mistral-7b-instruct-v0.2.Q4_K_M.gguf"
if [ ! -f "$MODEL_PATH" ]; then
  echo -e "${YELLOW}Downloading Mistral 7B model...${NC}"
  wget -O "$MODEL_PATH" https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.2-GGUF/resolve/main/mistral-7b-instruct-v0.2.Q4_K_M.gguf
else
  echo -e "${YELLOW}Mistral 7B model already exists, skipping download${NC}"
fi

# Clone Suna repository
echo -e "${YELLOW}Cloning Suna repository...${NC}"
git clone https://github.com/kortix-ai/suna.git /opt/suna/repo

# Install backend dependencies
echo -e "${YELLOW}Installing backend dependencies...${NC}"
cd /opt/suna/repo/backend
pip install -r requirements.txt

# Install frontend dependencies
echo -e "${YELLOW}Installing frontend dependencies...${NC}"
cd /opt/suna/repo/frontend
npm install
npm run build

# Copy configuration files
echo -e "${YELLOW}Copying configuration files...${NC}"
cp -r /opt/suna/repo/backend /opt/suna/
cp -r /opt/suna/repo/frontend /opt/suna/

# Create backend configuration
echo -e "${YELLOW}Creating backend configuration...${NC}"
cat > /etc/suna/backend/.env << EOF
ENV_MODE=LOCAL
OPENAI_API_KEY=sk-dummy-key
OPENAI_API_BASE=http://localhost:8000/v1
SUPABASE_URL=https://dummy.supabase.co
SUPABASE_KEY=dummy-key
REDIS_URL=redis://localhost:6379
EOF

# Create frontend configuration
echo -e "${YELLOW}Creating frontend configuration...${NC}"
cat > /etc/suna/frontend/.env.local << EOF
NEXT_PUBLIC_SUPABASE_URL=https://dummy.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=dummy-key
NEXT_PUBLIC_API_URL=http://localhost:8080
ENV_MODE=LOCAL
EOF

# Modify backend files for local mode
echo -e "${YELLOW}Modifying backend files for local mode...${NC}"

# Modify config.py to add OPENAI_API_BASE property and make API keys optional
sed -i 's/OPENAI_API_KEY: str/OPENAI_API_KEY: Optional[str] = None\n    OPENAI_API_BASE: Optional[str] = None/' /opt/suna/backend/utils/config.py
sed -i 's/TAVILY_API_KEY: str/TAVILY_API_KEY: Optional[str] = None/' /opt/suna/backend/utils/config.py
sed -i 's/SUPABASE_KEY: str/SUPABASE_KEY: Optional[str] = None/' /opt/suna/backend/utils/config.py
sed -i 's/SUPABASE_URL: str/SUPABASE_URL: Optional[str] = None/' /opt/suna/backend/utils/config.py

# Modify LLM service to use local model endpoint
sed -i 's/openai.api_key = config.OPENAI_API_KEY/openai.api_key = config.OPENAI_API_KEY or "sk-dummy-key"\n    if config.OPENAI_API_BASE:\n        openai.api_base = config.OPENAI_API_BASE/' /opt/suna/backend/services/llm.py

# Modify Supabase service to bypass database initialization in LOCAL mode
sed -i '/async def client/,/return self._client/ s/return self._client/if config.ENV_MODE == EnvMode.LOCAL:\n            logger.warning("Running in LOCAL mode without Supabase client")\n            return None\n        return self._client/' /opt/suna/backend/services/supabase.py

# Modify auth_utils.py to bypass authentication in LOCAL mode
sed -i '/async def verify_user_token/,/return user_id/ s/return user_id/if config.ENV_MODE == EnvMode.LOCAL:\n        logger.info("LOCAL mode: Bypassing authentication")\n        return "local-user-123"\n    return user_id/' /opt/suna/backend/utils/auth_utils.py

# Modify agent/run.py to handle LOCAL mode without database access
sed -i 's/model_name = model_name or "gpt-4"/model_name = model_name or "local-mistral"/' /opt/suna/backend/agent/run.py

# Add test_local_llm endpoint to agent/api.py
cat >> /opt/suna/backend/agent/api.py << 'EOF'

@router.post("/test_local_llm")
async def test_local_llm():
    """Test the local LLM endpoint."""
    try:
        from services.llm import make_llm_api_call
        response = await make_llm_api_call(
            model="local-mistral",
            messages=[{"role": "user", "content": "Say hello world"}],
            temperature=0.7,
            max_tokens=100
        )
        return {"status": "success", "response": response}
    except Exception as e:
        return {"status": "error", "message": str(e)}
EOF

# Modify thread_manager.py to handle LOCAL mode
cat > /opt/suna/backend/agentpress/thread_manager.py.patch << 'EOF'
--- thread_manager.py.orig
+++ thread_manager.py
@@ -13,6 +13,8 @@
 """
 
 import json
+import uuid
+from datetime import datetime, timezone
 from typing import List, Dict, Any, Optional, Type, Union, AsyncGenerator, Literal
 from services.llm import make_llm_api_call
 from agentpress.tool import Tool
@@ -24,6 +26,7 @@
 )
 from services.supabase import DBConnection
 from utils.logger import logger
+from utils.config import config, EnvMode
 
 # Type alias for tool choice
 ToolChoice = Literal["auto", "required", "none"]
@@ -71,7 +74,29 @@
                       Defaults to None, stored as an empty JSONB object if None.
         """
         logger.debug(f"Adding message of type '{type}' to thread {thread_id}")
+        
+        # In local mode, we'll use a mock message
+        if config.ENV_MODE == EnvMode.LOCAL:
+            logger.info(f"LOCAL mode: Creating mock message for thread {thread_id}")
+            message_id = str(uuid.uuid4())
+            created_at = datetime.now(timezone.utc).isoformat()
+            return {
+                'message_id': message_id,
+                'thread_id': thread_id,
+                'type': type,
+                'content': content,
+                'is_llm_message': is_llm_message,
+                'metadata': metadata or {},
+                'created_at': created_at
+            }
+        
         client = await self.db.client
+        if client is None:
+            logger.warning(f"No database client available, creating mock message for thread {thread_id}")
+            message_id = str(uuid.uuid4())
+            created_at = datetime.now(timezone.utc).isoformat()
+            return {
+                'message_id': message_id,
EOF

# Apply the patch
patch -p0 /opt/suna/backend/agentpress/thread_manager.py < /opt/suna/backend/agentpress/thread_manager.py.patch || true

# Modify agent/api.py to skip database status check in LOCAL mode
sed -i '/async def stream_agent_run/a \    # In LOCAL mode, bypass authentication and database checks\n    if config.ENV_MODE == EnvMode.LOCAL:\n        logger.info("LOCAL mode: Bypassing authentication and database checks for streaming")\n        user_id = "local-user-123"' /opt/suna/backend/agent/api.py

# Modify update_agent_run_status function to handle LOCAL mode
sed -i '/async def update_agent_run_status/a \    # In LOCAL mode, skip database updates\n    if config.ENV_MODE == EnvMode.LOCAL:\n        logger.info(f"LOCAL mode: Skipping database update for agent run {run_id}")\n        return' /opt/suna/backend/agent/api.py

# Replace any external search tools with local alternatives
echo -e "${YELLOW}Replacing external search tools with local alternatives...${NC}"
# Create a mock search tool that returns predefined results
cat > /opt/suna/backend/tools/local_search.py << 'EOF'
"""Local search tool that returns predefined results."""

from typing import List, Dict, Any, Optional
from agentpress.tool import Tool

class LocalSearchTool(Tool):
    """A local search tool that returns predefined results."""
    
    name = "local_search"
    description = "Search for information locally without using external APIs"
    
    async def search(self, query: str, max_results: int = 3) -> List[Dict[str, Any]]:
        """Search for information locally.
        
        Args:
            query: The search query
            max_results: Maximum number of results to return
            
        Returns:
            A list of search results
        """
        # Return predefined results based on query keywords
        results = []
        
        if "weather" in query.lower():
            results.append({
                "title": "Local Weather Information",
                "content": "The weather is currently sunny with a temperature of 22°C.",
                "url": "http://localhost/weather"
            })
        elif "news" in query.lower():
            results.append({
                "title": "Local News",
                "content": "This is a local news article about recent events.",
                "url": "http://localhost/news"
            })
        else:
            results.append({
                "title": "Local Information",
                "content": f"This is local information about: {query}",
                "url": "http://localhost/info"
            })
            
        return results[:max_results]
EOF

# Replace Tavily search with local search in agent/run.py
sed -i 's/from tools.tavily_search import TavilySearchTool/from tools.local_search import LocalSearchTool/' /opt/suna/backend/agent/run.py
sed -i 's/thread_manager.add_tool(TavilySearchTool)/thread_manager.add_tool(LocalSearchTool)/' /opt/suna/backend/agent/run.py

# Disable all external API tools and services
echo -e "${YELLOW}Disabling external API tools and services...${NC}"

# Create a patch file to disable external API tools
cat > /tmp/disable_external_apis.patch << 'EOF'
--- a/backend/agent/tools/web_search.py
+++ b/backend/agent/tools/web_search.py
@@ -1,6 +1,7 @@
 from typing import Dict, Any, List, Optional
 from agentpress.tool import Tool
 from utils.logger import logger
+from utils.config import config, EnvMode
 
 class WebSearchTool(Tool):
     """Tool for searching the web using Tavily API."""
@@ -13,6 +14,10 @@
         self.api_key = kwargs.get("api_key")
         
     async def _execute(self, query: str, max_results: Optional[int] = 3) -> Dict[str, Any]:
+        # In LOCAL mode, return mock results
+        if config.ENV_MODE == EnvMode.LOCAL:
+            logger.info(f"LOCAL mode: Returning mock web search results for query: {query}")
+            return {"results": [{"title": "Mock search result", "content": f"This is a mock search result for: {query}", "url": "https://example.com"}]}
         try:
             from tavily import TavilyClient
             client = TavilyClient(api_key=self.api_key)
--- a/backend/agent/tools/image_generation.py
+++ b/backend/agent/tools/image_generation.py
@@ -1,6 +1,7 @@
 from typing import Dict, Any, List, Optional
 from agentpress.tool import Tool
 from utils.logger import logger
+from utils.config import config, EnvMode
 import base64
 import os
 import json
@@ -15,6 +16,11 @@
         self.api_key = kwargs.get("api_key")
         
     async def _execute(self, prompt: str, size: str = "1024x1024", quality: str = "standard", n: int = 1) -> Dict[str, Any]:
+        # In LOCAL mode, return mock results
+        if config.ENV_MODE == EnvMode.LOCAL:
+            logger.info(f"LOCAL mode: Returning mock image generation results for prompt: {prompt}")
+            return {"images": ["data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="]}
+
         try:
             import openai
             openai.api_key = self.api_key
EOF

# Apply the patch
cd /opt/suna
patch -p0 < /tmp/disable_external_apis.patch

# Create a local vector store implementation
mkdir -p /opt/suna/backend/services/vector_store
cat > /opt/suna/backend/services/vector_store/__init__.py << 'EOF'
from .local_vector_store import LocalVectorStore

__all__ = ["LocalVectorStore"]
EOF

cat > /opt/suna/backend/services/vector_store/local_vector_store.py << 'EOF'
"""
Local vector store implementation using FAISS
"""
import os
import json
import numpy as np
from typing import List, Dict, Any, Optional
from utils.logger import logger

try:
    import faiss
    from sentence_transformers import SentenceTransformer
    FAISS_AVAILABLE = True
except ImportError:
    FAISS_AVAILABLE = False
    logger.warning("FAISS or sentence_transformers not available. Install with: pip install faiss-cpu sentence-transformers")

class LocalVectorStore:
    """Local vector store implementation using FAISS and sentence-transformers"""
    
    def __init__(self, index_path: str = "/etc/suna/vector_store"):
        self.index_path = index_path
        self.index_file = os.path.join(index_path, "faiss_index.bin")
        self.metadata_file = os.path.join(index_path, "metadata.json")
        self.dimension = 384  # Default for all-MiniLM-L6-v2
        
        # Create directory if it doesn't exist
        os.makedirs(index_path, exist_ok=True)
        
        if not FAISS_AVAILABLE:
            logger.error("FAISS or sentence-transformers not available. Vector store will not work.")
            return
            
        # Load or create index
        if os.path.exists(self.index_file) and os.path.exists(self.metadata_file):
            self.index = faiss.read_index(self.index_file)
            with open(self.metadata_file, 'r') as f:
                self.metadata = json.load(f)
        else:
            self.index = faiss.IndexFlatL2(self.dimension)
            self.metadata = []
            
        # Initialize the model
        self.model = SentenceTransformer('all-MiniLM-L6-v2')
        
    def _get_embedding(self, text: str) -> np.ndarray:
        """Get embedding for text"""
        if not FAISS_AVAILABLE:
            return np.zeros(self.dimension)
        return self.model.encode(text)
        
    def add_texts(self, texts: List[str], metadatas: Optional[List[Dict[str, Any]]] = None) -> List[str]:
        """Add texts to the vector store"""
        if not FAISS_AVAILABLE:
            logger.error("FAISS not available. Cannot add texts.")
            return ["error"] * len(texts)
            
        if not texts:
            return []
            
        # Generate IDs
        ids = [f"id_{len(self.metadata) + i}" for i in range(len(texts))]
        
        # Get embeddings
        embeddings = [self._get_embedding(text) for text in texts]
        embeddings_np = np.array(embeddings).astype('float32')
        
        # Add to index
        self.index.add(embeddings_np)
        
        # Add metadata
        for i, text in enumerate(texts):
            metadata = {
                "id": ids[i],
                "text": text,
                "custom": metadatas[i] if metadatas and i < len(metadatas) else {}
            }
            self.metadata.append(metadata)
            
        # Save index and metadata
        faiss.write_index(self.index, self.index_file)
        with open(self.metadata_file, 'w') as f:
            json.dump(self.metadata, f)
            
        return ids
        
    def similarity_search(self, query: str, k: int = 4) -> List[Dict[str, Any]]:
        """Search for similar texts"""
        if not FAISS_AVAILABLE:
            logger.error("FAISS not available. Cannot perform search.")
            return []
            
        if self.index.ntotal == 0:
            return []
            
        # Get query embedding
        query_embedding = self._get_embedding(query)
        query_embedding_np = np.array([query_embedding]).astype('float32')
        
        # Search
        distances, indices = self.index.search(query_embedding_np, min(k, self.index.ntotal))
        
        # Get results
        results = []
        for i, idx in enumerate(indices[0]):
            if idx < len(self.metadata):
                result = self.metadata[idx].copy()
                result["distance"] = float(distances[0][i])
                results.append(result)
                
        return results
EOF

# Install FAISS and sentence-transformers
pip install faiss-cpu sentence-transformers

# Create a directory for the vector store
mkdir -p /etc/suna/vector_store

# Modify thread_manager.py to handle LOCAL mode
cat > /tmp/thread_manager.patch << 'EOF'
--- a/backend/agentpress/thread_manager.py
+++ b/backend/agentpress/thread_manager.py
@@ -11,6 +11,8 @@
 """
 
 import json
+import uuid
+from datetime import datetime, timezone
 from typing import List, Dict, Any, Optional, Type, Union, AsyncGenerator, Literal
 from services.llm import make_llm_api_call
 from agentpress.tool import Tool
@@ -22,6 +24,7 @@
 )
 from services.supabase import DBConnection
 from utils.logger import logger
+from utils.config import config, EnvMode
 
 # Type alias for tool choice
 ToolChoice = Literal["auto", "required", "none"]
@@ -71,7 +74,29 @@
                       Defaults to None, stored as an empty JSONB object if None.
         """
         logger.debug(f"Adding message of type '{type}' to thread {thread_id}")
+        
+        # In local mode, we'll use a mock message
+        if config.ENV_MODE == EnvMode.LOCAL:
+            logger.info(f"LOCAL mode: Creating mock message for thread {thread_id}")
+            message_id = str(uuid.uuid4())
+            created_at = datetime.now(timezone.utc).isoformat()
+            return {
+                'message_id': message_id,
+                'thread_id': thread_id,
+                'type': type,
+                'content': content,
+                'is_llm_message': is_llm_message,
+                'metadata': metadata or {},
+                'created_at': created_at
+            }
+        
         client = await self.db.client
+        if client is None:
+            logger.warning(f"No database client available, creating mock message for thread {thread_id}")
+            message_id = str(uuid.uuid4())
+            created_at = datetime.now(timezone.utc).isoformat()
+            return {
+                'message_id': message_id,
+                'thread_id': thread_id,
+                'type': type,
+                'content': content,
+                'is_llm_message': is_llm_message,
+                'metadata': metadata or {},
+                'created_at': created_at
+            }
         
         # Prepare data for insertion
         data_to_insert = {
@@ -97,6 +122,17 @@
 
     async def get_llm_messages(self, thread_id: str) -> List[Dict[str, Any]]:
         """Get all messages for a thread."""
+        # In local mode, return an empty list
+        if config.ENV_MODE == EnvMode.LOCAL:
+            logger.info(f"LOCAL mode: Returning empty message list for thread {thread_id}")
+            return []
+            
+        client = await self.db.client
+        if client is None:
+            logger.warning(f"No database client available, returning empty message list for thread {thread_id}")
+            return []
+            
+        # Rest of the method...
EOF

cd /opt/suna
patch -p0 < /tmp/thread_manager.patch

# Modify agent/api.py to handle LOCAL mode in streaming endpoint
cat > /tmp/agent_api.patch << 'EOF'
--- a/backend/agent/api.py
+++ b/backend/agent/api.py
@@ -15,6 +15,7 @@
 from utils.auth_utils import verify_user_token
 from utils.logger import logger
 from utils.config import config, EnvMode
+import uuid
 
 router = APIRouter()
 
@@ -120,6 +121,13 @@
     thread_id: str = Form(...),
     project_id: str = Form(...),
 ):
+    # In LOCAL mode, use default values
+    if config.ENV_MODE == EnvMode.LOCAL:
+        if not thread_id or thread_id == "undefined":
+            thread_id = f"local-thread-{uuid.uuid4()}"
+        if not project_id or project_id == "undefined":
+            project_id = "local-project-123"
+    
     # Verify user token
     try:
         user_id = await verify_user_token(token)
@@ -127,6 +135,11 @@
         logger.error(f"Invalid token: {str(e)}")
         raise HTTPException(status_code=401, detail="Invalid token")
 
+    # In LOCAL mode, skip database status check
+    if config.ENV_MODE == EnvMode.LOCAL:
+        logger.info(f"LOCAL mode: Bypassing database status check for agent run")
+        return StreamingResponse(stream_agent_run(thread_id, project_id, user_id, message, model_name))
+
     # Check if thread exists and belongs to user
     supabase = DBConnection()
     client = await supabase.client
@@ -151,6 +164,12 @@
 
 async def update_agent_run_status(thread_id: str, status: str, error: Optional[str] = None):
     """Update the status of an agent run in the database."""
+    # In LOCAL mode, skip database updates
+    if config.ENV_MODE == EnvMode.LOCAL:
+        logger.info(f"LOCAL mode: Skipping database update for agent run status: {status}")
+        return
+        
+    # Normal database update logic
     supabase = DBConnection()
     client = await supabase.client
     if not client:
EOF

cd /opt/suna
patch -p0 < /tmp/agent_api.patch

# Modify frontend AuthProvider.tsx to automatically create mock user session in LOCAL mode
sed -i '/const { session, error } = await supabase.auth.getSession()/a\\n  // In LOCAL mode, create a mock session\n  if (process.env.ENV_MODE === "LOCAL" && !session?.user) {\n    console.log("LOCAL mode: Creating mock user session");\n    setSession({\n      user: { id: "local-user-123", email: "local@example.com" },\n      access_token: "mock-token",\n      refresh_token: "mock-refresh-token"\n    });\n    setLoading(false);\n    return;\n  }' /opt/suna/frontend/src/components/AuthProvider.tsx

# Modify dashboard layout to bypass API health check in LOCAL mode
sed -i '/const { data: healthData, error: healthError } = await fetch/a\\n  // In LOCAL mode, bypass API health check\n  if (process.env.ENV_MODE === "LOCAL") {\n    console.log("LOCAL mode: Bypassing API health check");\n    return { props: {} };\n  }' /opt/suna/frontend/src/app/\(dashboard\)/layout.tsx

# Create systemd service files
echo -e "${YELLOW}Creating systemd service files...${NC}"

# llama.cpp server service
cat > /etc/systemd/system/suna-llama.service << EOF
[Unit]
Description=llama.cpp server for Suna
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/suna
ExecStart=/opt/suna/venv/bin/python -m llama_cpp.server --model /etc/suna/models/mistral-7b-instruct-v0.2.Q4_K_M.gguf --host 0.0.0.0 --port 8000 --n_ctx 4096
Restart=on-failure
StandardOutput=append:/var/log/suna/llama.log
StandardError=append:/var/log/suna/llama.log

[Install]
WantedBy=multi-user.target
EOF

# Backend service
cat > /etc/systemd/system/suna-backend.service << EOF
[Unit]
Description=Suna Backend
After=network.target suna-llama.service redis-server.service
Requires=suna-llama.service redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/suna/backend
Environment="ENV_MODE=LOCAL"
Environment="OPENAI_API_KEY=sk-dummy-key"
Environment="OPENAI_API_BASE=http://localhost:8000/v1"
Environment="SUPABASE_URL=https://dummy.supabase.co"
Environment="SUPABASE_KEY=dummy-key"
Environment="REDIS_URL=redis://localhost:6379"
ExecStart=/opt/suna/venv/bin/python api.py
Restart=on-failure
StandardOutput=append:/var/log/suna/backend.log
StandardError=append:/var/log/suna/backend.log

[Install]
WantedBy=multi-user.target
EOF

# Frontend service
cat > /etc/systemd/system/suna-frontend.service << EOF
[Unit]
Description=Suna Frontend
After=network.target suna-backend.service
Requires=suna-backend.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/suna/frontend
Environment="NEXT_PUBLIC_SUPABASE_URL=https://dummy.supabase.co"
Environment="NEXT_PUBLIC_SUPABASE_ANON_KEY=dummy-key"
Environment="NEXT_PUBLIC_API_URL=http://localhost:8080"
Environment="ENV_MODE=LOCAL"
ExecStart=/usr/bin/npm start
Restart=on-failure
StandardOutput=append:/var/log/suna/frontend.log
StandardError=append:/var/log/suna/frontend.log

[Install]
WantedBy=multi-user.target
EOF

# Create start and stop scripts
echo -e "${YELLOW}Creating start and stop scripts...${NC}"

cat > /usr/local/bin/start-suna.sh << EOF
#!/bin/bash
systemctl start redis-server
systemctl start suna-llama
sleep 10
systemctl start suna-backend
sleep 5
systemctl start suna-frontend
echo "Suna services started. Frontend available at http://localhost:3000"
EOF

cat > /usr/local/bin/stop-suna.sh << EOF
#!/bin/bash
systemctl stop suna-frontend
systemctl stop suna-backend
systemctl stop suna-llama
systemctl stop redis-server
echo "Suna services stopped"
EOF

chmod +x /usr/local/bin/start-suna.sh
chmod +x /usr/local/bin/stop-suna.sh

# Enable services
echo -e "${YELLOW}Enabling services...${NC}"
systemctl enable redis-server
systemctl enable suna-llama
systemctl enable suna-backend
systemctl enable suna-frontend

echo -e "${GREEN}Installation complete!${NC}"
echo -e "To start Suna, run: ${YELLOW}start-suna.sh${NC}"
echo -e "To stop Suna, run: ${YELLOW}stop-suna.sh${NC}"
echo -e "Frontend will be available at: ${YELLOW}http://your-server-ip:3000${NC}"