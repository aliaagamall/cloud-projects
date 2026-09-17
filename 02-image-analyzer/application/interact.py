import base64
import json
import subprocess
import sys
from pathlib import Path

import requests


PROJECT_ROOT = Path(__file__).resolve().parent.parent
TERRAFORM_DIR = PROJECT_ROOT / "terraform"


def get_api_url():
    result = subprocess.run(
        [
            "terraform",
            f"-chdir={TERRAFORM_DIR}",
            "output",
            "-raw",
            "friendly_endpoint",
        ],
        capture_output=True,
        text=True,
        check=True,
    )

    return result.stdout.strip()


def analyze_image(image_path):
    api_url = get_api_url()

    image_bytes = Path(image_path).read_bytes()
    image_base64 = base64.b64encode(image_bytes).decode("utf-8")

    payload = {
        "image": image_base64
    }

    response = requests.post(
        api_url,
        json=payload,
        timeout=60,
    )

    print(f"API URL: {api_url}")
    print(f"HTTP status: {response.status_code}")
    print(json.dumps(response.json(), indent=2))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python application/interact.py <image-path>")
        sys.exit(1)

    analyze_image(sys.argv[1])