main = lambda data: data.get("template_cloudflare", {}).get("enabled", False) == True
