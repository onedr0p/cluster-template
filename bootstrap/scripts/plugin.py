from typing import Any
import bcrypt
import makejinja
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

class Plugin(makejinja.plugin.Plugin):
    def __init__(self, data: dict[str, Any]):
        validation.validate(data)

    def filters(self) -> makejinja.plugin.Filters:
        return [nthhost, encrypt]
