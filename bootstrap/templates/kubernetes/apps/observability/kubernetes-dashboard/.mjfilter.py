main = lambda data: data.get("addon_kubernetes_dashboard", {}).get("enabled", False) == True
