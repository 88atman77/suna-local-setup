#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

VENV_DIR="../venv"
SUNA_DIR="../suna"
PATCHES_DIR="../patches"

# Activate virtual environment
echo -e "${YELLOW}Activating virtual environment...${NC}"
source "$VENV_DIR/bin/activate"

# Clone Suna repository if it doesn't exist
if [ ! -d "$SUNA_DIR" ]; then
  echo -e "${YELLOW}Cloning Suna repository...${NC}"
  git clone https://github.com/kortix-ai/suna.git "$SUNA_DIR"
  if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to clone Suna repository. Please check your internet connection and try again.${NC}"
    exit 1
  fi
else
  echo -e "${GREEN}Suna repository already exists at $SUNA_DIR${NC}"
fi

# Create backend configuration
echo -e "${YELLOW}Creating backend configuration...${NC}"
mkdir -p "$SUNA_DIR/backend/config"
cat > "$SUNA_DIR/backend/.env" << EOF
ENV_MODE=LOCAL
OPENAI_API_KEY=sk-dummy-key
OPENAI_API_BASE=http://localhost:8000/v1
SUPABASE_URL=https://dummy.supabase.co
SUPABASE_KEY=dummy-key
REDIS_URL=redis://localhost:6379
EOF

# Create frontend configuration
echo -e "${YELLOW}Creating frontend configuration...${NC}"
cat > "$SUNA_DIR/frontend/.env.local" << EOF
NEXT_PUBLIC_SUPABASE_URL=https://dummy.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=dummy-key
NEXT_PUBLIC_API_URL=http://localhost:8080
ENV_MODE=LOCAL
EOF

# Apply patches
echo -e "${YELLOW}Applying patches to Suna...${NC}"

# Modify config.py to add OPENAI_API_BASE property
echo -e "${YELLOW}Modifying config.py...${NC}"
sed -i 's/OPENAI_API_KEY: str/OPENAI_API_KEY: str\n    OPENAI_API_BASE: Optional[str] = None/' "$SUNA_DIR/backend/utils/config.py"

# Modify LLM service to use local model endpoint
echo -e "${YELLOW}Modifying LLM service...${NC}"
sed -i 's/openai.api_key = config.OPENAI_API_KEY/openai.api_key = config.OPENAI_API_KEY\n    if config.OPENAI_API_BASE:\n        openai.api_base = config.OPENAI_API_BASE/' "$SUNA_DIR/backend/services/llm.py"

# Modify Supabase service to bypass database initialization in LOCAL mode
echo -e "${YELLOW}Modifying Supabase service...${NC}"
sed -i '/async def client/,/return self._client/ s/return self._client/if config.ENV_MODE == EnvMode.LOCAL:\n            logger.warning("Running in LOCAL mode without Supabase client")\n            return None\n        return self._client/' "$SUNA_DIR/backend/services/supabase.py"

# Modify auth_utils.py to bypass authentication in LOCAL mode
echo -e "${YELLOW}Modifying auth_utils.py...${NC}"
sed -i '/async def verify_user_token/,/return user_id/ s/return user_id/if config.ENV_MODE == EnvMode.LOCAL:\n        logger.info("LOCAL mode: Bypassing authentication")\n        return "local-user-123"\n    return user_id/' "$SUNA_DIR/backend/utils/auth_utils.py"

# Modify agent/run.py to handle LOCAL mode without database access
echo -e "${YELLOW}Modifying agent/run.py...${NC}"
sed -i 's/model_name = model_name or "gpt-4"/model_name = model_name or "local-mistral"/' "$SUNA_DIR/backend/agent/run.py"

# Create patches directory if it doesn't exist
mkdir -p "$PATCHES_DIR"

# Create patch for thread_manager.py
echo -e "${YELLOW}Creating patch for thread_manager.py...${NC}"
cat > "$PATCHES_DIR/thread_manager.patch" << 'EOF'
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

# Create patch for agent/api.py
echo -e "${YELLOW}Creating patch for agent/api.py...${NC}"
cat > "$PATCHES_DIR/agent_api.patch" << 'EOF'
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

# Create patch for web_search.py and image_generation.py
echo -e "${YELLOW}Creating patch for tools...${NC}"
cat > "$PATCHES_DIR/tools.patch" << 'EOF'
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

# Apply patches
echo -e "${YELLOW}Applying patches...${NC}"
cd "$SUNA_DIR"
patch -p0 < "$PATCHES_DIR/thread_manager.patch"
patch -p0 < "$PATCHES_DIR/agent_api.patch"
patch -p0 < "$PATCHES_DIR/tools.patch"

# Create local vector store implementation
echo -e "${YELLOW}Creating local vector store implementation...${NC}"
mkdir -p "$SUNA_DIR/backend/services/vector_store"
cat > "$SUNA_DIR/backend/services/vector_store/__init__.py" << 'EOF'
from .local_vector_store import LocalVectorStore

__all__ = ["LocalVectorStore"]
EOF

cat > "$SUNA_DIR/backend/services/vector_store/local_vector_store.py" << 'EOF'
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

# Install backend dependencies
echo -e "${YELLOW}Installing backend dependencies...${NC}"
cd "$SUNA_DIR/backend"
pip install -r requirements.txt
pip install faiss-cpu sentence-transformers

# Modify frontend AuthProvider.tsx
echo -e "${YELLOW}Modifying frontend AuthProvider.tsx...${NC}"
cd "$SUNA_DIR/frontend"
sed -i '/const { session, error } = await supabase.auth.getSession()/a\\n  // In LOCAL mode, create a mock session\n  if (process.env.ENV_MODE === "LOCAL" && !session?.user) {\n    console.log("LOCAL mode: Creating mock user session");\n    setSession({\n      user: { id: "local-user-123", email: "local@example.com" },\n      access_token: "mock-token",\n      refresh_token: "mock-refresh-token"\n    });\n    setLoading(false);\n    return;\n  }' src/components/AuthProvider.tsx

# Modify dashboard layout
echo -e "${YELLOW}Modifying dashboard layout...${NC}"
sed -i '/const { data: healthData, error: healthError } = await fetch/a\\n  // In LOCAL mode, bypass API health check\n  if (process.env.ENV_MODE === "LOCAL") {\n    console.log("LOCAL mode: Bypassing API health check");\n    return { props: {} };\n  }' src/app/\(dashboard\)/layout.tsx

echo -e "${GREEN}Suna setup complete!${NC}"