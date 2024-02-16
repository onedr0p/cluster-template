main = lambda data: (
    data.get("bootstrap_distribution", "k3s") in ["k3s"] and
    len(
        list(
            filter(
                lambda item: "controller" in item and item["controller"] is False, data.get("bootstrap_node_inventory")
            )
        )
    ) > 0
)
