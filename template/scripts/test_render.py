"""Tests for the output rendered from the cluster.toml in the repo root.

Render the tree first, then run from the repo root:
    mise run configure
    mise run //talos:render
    uv run --locked pytest template/scripts/test_render.py -q
"""

from pathlib import Path

import sys

import pytest
import yaml

sys.path.insert(0, str(Path(__file__).parent))

from validate import load  # noqa: E402

REPO_ROOT = Path(__file__).parents[2]


@pytest.fixture(scope="session")
def config() -> dict:
    return load(str(REPO_ROOT / "cluster.toml"))


# The documents of each node's machine config, keyed by node name.
@pytest.fixture(scope="session")
def machine_configs(config: dict) -> dict[str, list[dict]]:
    return {
        node["name"]: list(yaml.safe_load_all((REPO_ROOT / "talos/rendered" / f"{node['name']}.yaml").read_text()))
        for node in config["nodes"]
    }


# Controllers announce kubernetes.api.addr as a Layer 2 VIP unless
# kubernetes.api.vip = false.
def test_api_vip_announced_by_controllers_only(config: dict, machine_configs: dict[str, list[dict]]):
    api = config["kubernetes"]["api"]
    for node in config["nodes"]:
        vips = [doc["name"] for doc in machine_configs[node["name"]] if doc.get("kind") == "Layer2VIPConfig"]
        assert vips == ([api["addr"]] if api["vip"] and node["controller"] else []), node["name"]
