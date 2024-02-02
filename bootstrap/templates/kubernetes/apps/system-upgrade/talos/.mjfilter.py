main = lambda data: (
    data.get("distribution", {}).get("type", "k3s") in ["talos"] and
        data.get("distribution", {})
            .get("talos", {})
            .get("schematics", {})
            .get("enabled", False) == True
)
