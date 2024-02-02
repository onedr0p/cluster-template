main = lambda data: (
    data.get("flux", {})
        .get("github", {})
        .get("webhook", {})
        .get("enabled", False) == True
)
