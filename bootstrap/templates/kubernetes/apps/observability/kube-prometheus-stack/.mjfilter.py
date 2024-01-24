main = lambda data: data.get("addon_kube_prometheus_stack", {}).get("enabled", False) == True
