main = lambda data: data.get("bootstrap_cloudflare", {}).get("enabled", False) == True
