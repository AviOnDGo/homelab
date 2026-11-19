import os

import requests

webhook_url = os.environ.get("DISCORD_WEBHOOK_URL", "").strip()
if webhook_url:
	data = {"content": "containerServices backup completed"}
	requests.post(webhook_url, json=data, timeout=10)
else:
	print("DISCORD_WEBHOOK_URL is not set; skipping notification.")
