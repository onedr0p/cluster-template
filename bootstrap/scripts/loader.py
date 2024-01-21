import bcrypt
import netaddr

import validation

def nthhost(value: str, query: int) -> str:
    value = netaddr.IPNetwork(value)
    try:
        nth = int(query)
        if value.size > nth:
            return str(value[nth])
    except ValueError:
        return False
    return value

def encrypt(value: str) -> str:
    return bcrypt.hashpw(value.encode(), bcrypt.gensalt(rounds=10)).decode("ascii")

class Loader:
    def __init__(self, data):
        if data.get("skip_tests", False):
            return
        validation.validate_python_version()
        validation.validate_cli_tools(data)
        validation.validate_distribution(data)
        validation.validate_github(data)
        validation.validate_age(data)
        validation.validate_timezone(data)
        validation.validate_acme_email(data)
        validation.validate_flux_github_webhook_token(data)
        validation.validate_cloudflare(data)
        validation.validate_host_network(data)
        validation.validate_bootstrap_dns_server(data)
        validation.validate_cilium_loadbalancer_mode(data)
        validation.validate_local_storage_path(data)
        validation.validate_cluster_cidrs(data)
        validation.validate_nodes(data)

    def filters(self):
        return [nthhost, encrypt]
