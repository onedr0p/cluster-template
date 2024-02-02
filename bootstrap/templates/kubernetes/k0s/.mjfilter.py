main = lambda data: data.get("distribution", {}).get("type", "k3s") in ["k0s"]
