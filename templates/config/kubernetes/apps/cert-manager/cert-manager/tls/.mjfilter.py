main = lambda data: data.get("cloudflare", {}).get("enabled", False) == True
