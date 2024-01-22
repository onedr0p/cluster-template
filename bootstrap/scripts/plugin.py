from bcrypt import hashpw
from collections.abc import Callable
from jinja2.utils import import_string
from netaddr import IPNetwork
from pathlib import Path
from typing import Any
from utils import validate

import makejinja

def nthhost(value: str, query: int) -> str:
    value = IPNetwork(value)
    try:
        nth = int(query)
        if value.size > nth:
            return str(value[nth])
    except ValueError:
        return False
    return value

def encrypt(value: str) -> str:
    return hashpw(value.encode(), bcrypt.gensalt(rounds=10)).decode("ascii")

class Plugin(makejinja.plugin.Plugin):
    def __init__(self, data: dict[str, Any], config: makejinja.config.Config):

        self._excluded_dirs: set[Path] = set()

        for input_path in config.inputs:
            for filter_file in input_path.rglob(".mjfilter"):
                filter_func: Callable[[dict[str, Any]], bool] = import_string(
                    f"{filter_file}:main"
                )
                if filter_func(data) is False:
                    self._excluded_dirs.add(filter_file.parent)

        validate(data)

    def filters(self) -> makejinja.plugin.Filters:
        return [nthhost, encrypt]

    def path_filters(self) -> makejinja.plugin.PathFilters:
        return [self._mjfilter_func]

    def _mjfilter_func(self, path: Path) -> bool:
        return not any(
            path.is_relative_to(excluded_dir) for excluded_dir in self._excluded_dirs
        )
