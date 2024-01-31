main = lambda data: data.get("distribution") in ['talos'] and (
    data.get("cluster", {})
    .get("nodes", {})
    .get("talos", {})
    .get("schematics", {})
    .get("enabled", False) == True)
