"""Tests for the output rendered from the cluster.toml in the repo root.

Render the tree first:
    mise run configure
    mise run //talos:render
    mise run //template:test-render
"""

from functools import cache
from pathlib import Path

import sys

import pytest
import yaml

sys.path.insert(0, str(Path(__file__).parent))

from validate import load  # noqa: E402

REPO_ROOT = Path(__file__).parents[2]
CONFIG_FILE = REPO_ROOT / "cluster.toml"

# A clean checkout has no cluster.toml; the E2E job always creates one first.
pytestmark = pytest.mark.skipif(not CONFIG_FILE.exists(), reason="no cluster.toml to render from")


# cluster.toml and the machine configs hold secrets, and pytest prints the
# arguments of a failing test, so tests call these instead of taking fixtures.
@cache
def config() -> dict:
    return load(str(CONFIG_FILE))


# The documents of one kind in a node's machine config. PyYAML quotes the
# source in its errors for a string, but not for a stream.
def documents(node: str, kind: str) -> list[dict]:
    with (REPO_ROOT / "talos/rendered" / f"{node}.yaml").open() as stream:
        return [doc for doc in yaml.safe_load_all(stream) if doc.get("kind") == kind]


# Controllers announce kubernetes.api.addr as a Layer 2 VIP unless
# kubernetes.api.vip = false.
def test_api_vip_announced_by_controllers_only():
    api = config()["kubernetes"]["api"]
    for node in config()["nodes"]:
        vips = [doc["name"] for doc in documents(node["name"], "Layer2VIPConfig")]
        assert vips == ([api["addr"]] if api["vip"] and node["controller"] else []), node["name"]
