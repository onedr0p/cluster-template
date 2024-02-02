main = lambda data: (
    data.get("distribution").get("type", "k3s") in ["k3s"] and
    len(
        list(
            filter(
                lambda item: "controller" in item and item["controller"] is False, data.get("nodes").get("inventory")
            )
        )
    ) > 0
)
