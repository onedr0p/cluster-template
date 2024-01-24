main = lambda data: data.get("bootstrap_distribution") in ['k0s', 'k3s'] and data.get("addon_longhorn", {}).get("enabled", False) == True
