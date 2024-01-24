main = lambda data: data["bootstrap_distribution"] in ['k0s', 'k3s'] and data.get("addon_longhorn", {}).get("enabled", False) == True
