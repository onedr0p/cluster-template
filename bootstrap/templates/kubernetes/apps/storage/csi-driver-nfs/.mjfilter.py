main = lambda data: data.get("addon_csi_driver_nfs", {}).get("enabled", False) == True
