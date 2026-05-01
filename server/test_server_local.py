import requests
import json
import sys
import os

SERVER_URL = "http://127.0.0.1:8000/api/parse_schedule"

def test_parse_schedule(image_path):
    if not os.path.exists(image_path):
        print(f"File not found: {image_path}")
        print("Please provide a valid image path to test.")
        return

    print(f"Testing API with image: {image_path}")
    print(f"Connecting to: {SERVER_URL}...\n")

    try:
        with open(image_path, 'rb') as f:
            # We are testing the streaming endpoint, so we use stream=True
            response = requests.post(SERVER_URL, files={'file': f}, stream=True)

        if response.status_code == 200:
            print("Connected! Waiting for stream...\n")
            # Parse NDJSON (Newline Delimited JSON)
            for line in response.iter_lines():
                if line:
                    decoded_line = line.decode('utf-8')
                    try:
                        data = json.loads(decoded_line)
                        status = data.get('status')
                        
                        if status == 'progress':
                            print(f"\n[PROGRESS] {data.get('message')}")
                        elif status == 'generating':
                            # print chunks without newlines to show typing effect
                            print(data.get('message'), end='', flush=True)
                        elif status == 'success':
                            print("\n\n[SUCCESS] Final JSON Data:")
                            print(json.dumps(data.get('data'), indent=2, ensure_ascii=False))
                        elif status == 'error':
                            print(f"\n\n[ERROR] {data.get('message')}")
                    except json.JSONDecodeError:
                        print(f"Failed to parse JSON line: {decoded_line}")
        else:
            print(f"Error {response.status_code}: {response.text}")
            
    except requests.exceptions.ConnectionError:
        print(f"Connection error to {SERVER_URL}.")
        print("Is the FastAPI server running? Run 'uvicorn server:app --host 0.0.0.0 --port 8000'")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python test_server_local.py <path_to_image>")
        # Default test if no image provided to avoid immediate crash, just to remind user
        print("\nExample: python test_server_local.py test_schedule.jpg")
    else:
        test_parse_schedule(sys.argv[1])
