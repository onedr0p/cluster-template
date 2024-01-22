from collections.abc import Callable
from jinja2.utils import import_string
from pathlib import Path
from typing import Any

import bcrypt
import makejinja
import netaddr

import utils

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
    def __init__(self, data: dict[str, Any], config: makejinja.config.Config):
        self.data = data
        self.config = config

        self._excluded_dirs: set[Path] = set()
        for input_path in config.inputs:
            for filter_file in input_path.rglob(".mjfilter.py"):
                filter_func: Callable[[dict[str, Any]], bool] = import_string(
                    f"{filter_file}:main"
                )
                if filter_func(data) is False:
                    self._excluded_dirs.add(filter_file.parent)

        utils.validate(self.data)

    def filters(self) -> makejinja.plugin.Filters:
        return [nthhost, encrypt]

    def path_filters(self) -> makejinja.plugin.PathFilters:
        return [self._mjfilter_func]

    def _mjfilter_func(self, path: Path) -> bool:
        return not any(
            path.is_relative_to(excluded_dir) for excluded_dir in self._excluded_dirs
        )
