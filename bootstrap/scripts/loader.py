import netaddr, bcrypt

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
    def filters(self):
        return [nthhost, encrypt]
