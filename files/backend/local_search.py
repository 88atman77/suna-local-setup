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