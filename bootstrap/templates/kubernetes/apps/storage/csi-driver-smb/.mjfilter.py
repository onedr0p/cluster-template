main = lambda data: data.get("addon_csi_driver_smb", {}).get("enabled", False) == True
