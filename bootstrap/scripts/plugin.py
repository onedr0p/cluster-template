import importlib.util
import sys
from collections.abc import Callable
from pathlib import Path
from typing import Any

from typing import Any
from netaddr import IPNetwork

import makejinja
import validation


# Return the filename of a path without the j2 extension
def basename(value: str) -> str:
    return Path(value).stem


# Return a list of files in the talos patches directory
def talos_patches(value: str) -> list[str]:
    path = Path(f'bootstrap/templates/kubernetes/bootstrap/talos/patches/{value}')
    if not path.is_dir():
        return []
    return [str(f) for f in sorted(path.glob('*.yaml.j2')) if f.is_file()]


# Return the nth host in a CIDR range
def nthhost(value: str, query: int) -> str:
    value = IPNetwork(value)
    try:
        nth = int(query)
        if value.size > nth:
            return str(value[nth])
    except ValueError:
        return False
    return value


def import_filter(file: Path) -> Callable[[dict[str, Any]], bool]:
    module_path = file.relative_to(Path.cwd()).with_suffix("")
    module_name = str(module_path).replace("/", ".")
    spec = importlib.util.spec_from_file_location(module_name, file)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module.main


class Plugin(makejinja.plugin.Plugin):
    def __init__(self, data: dict[str, Any], config: makejinja.config.Config):
        self._data = data
        self._config = config

        self._excluded_dirs: set[Path] = set()
        for input_path in config.inputs:
            for filter_file in input_path.rglob(".mjfilter.py"):
                filter_func = import_filter(filter_file)
                if filter_func(data) is False:
                    self._excluded_dirs.add(filter_file.parent)

        validation.validate(data)


    def filters(self) -> makejinja.plugin.Filters:
        return [basename, nthhost]


    def functions(self) -> makejinja.plugin.Functions:
        return [talos_patches]


    def path_filters(self):
        return [self._mjfilter_func]


    def _mjfilter_func(self, path: Path) -> bool:
        return not any(
            path.is_relative_to(excluded_dir) for excluded_dir in self._excluded_dirs
        )
