#!/usr/bin/env python3
"""
Test script for the llama.cpp server with OpenAI-compatible API
"""

import sys
import json
import requests
from time import time

# Configuration
API_BASE = "http://localhost:8000/v1"
MODEL = "models/mistral-7b-instruct-v0.2.Q4_K_M.gguf"

def test_models_endpoint():
    """Test the models endpoint"""
    print("Testing models endpoint...")
    try:
        response = requests.get(f"{API_BASE}/models")
        if response.status_code == 200:
            models = response.json()
            print(f"✅ Models endpoint working. Available models: {json.dumps(models, indent=2)}")
            return True
        else:
            print(f"❌ Models endpoint failed with status code {response.status_code}")
            print(f"Response: {response.text}")
            return False
    except Exception as e:
        print(f"❌ Error connecting to models endpoint: {str(e)}")
        return False

def test_completion(prompt="Hello, how are you?"):
    """Test the completion endpoint"""
    print(f"\nTesting completion endpoint with prompt: '{prompt}'")
    
    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": "You are a helpful assistant."},
            {"role": "user", "content": prompt}
        ],
        "temperature": 0.7,
        "max_tokens": 100
    }
    
    try:
        start_time = time()
        response = requests.post(f"{API_BASE}/chat/completions", json=payload)
        end_time = time()
        
        if response.status_code == 200:
            result = response.json()
            content = result["choices"][0]["message"]["content"]
            print(f"✅ Completion successful in {end_time - start_time:.2f} seconds")
            print(f"Response: {content}")
            return True
        else:
            print(f"❌ Completion failed with status code {response.status_code}")
            print(f"Response: {response.text}")
            return False
    except Exception as e:
        print(f"❌ Error connecting to completion endpoint: {str(e)}")
        return False

def main():
    """Main function"""
    print("🔍 Testing llama.cpp server with OpenAI-compatible API")
    print(f"API Base: {API_BASE}")
    print(f"Model: {MODEL}")
    print("-" * 50)
    
    models_ok = test_models_endpoint()
    if not models_ok:
        print("\n❌ Models endpoint test failed. Is the server running?")
        sys.exit(1)
    
    completion_ok = test_completion()
    if not completion_ok:
        print("\n❌ Completion test failed.")
        sys.exit(1)
    
    print("\n✅ All tests passed! The llama.cpp server is working correctly.")

if __name__ == "__main__":
    main()