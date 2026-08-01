"""Snapshot tests for the rendered output of every valid fixture.

Run from the repo root:
    uv run --locked pytest template/scripts/test_render.py -q

After an intentional template change, refresh the snapshots and review the diff:
    uv run --locked pytest template/scripts/test_render.py --snapshot-update
"""

from pathlib import Path

import json
import os
import shutil
import sys

import attrs
import pytest
import typed_settings as ts

sys.path.insert(0, str(Path(__file__).parent))

from makejinja.app import makejinja  # noqa: E402
from makejinja.config import Config  # noqa: E402
from syrupy.extensions.single_file import SingleFileSnapshotExtension, WriteMode  # noqa: E402

import plugin  # noqa: E402

REPO_ROOT = Path(__file__).parents[2]
VALID = sorted((REPO_ROOT / ".github/template-tests/valid").glob("*.toml"))

# plugin.py resolves these against the working directory. The age values have to
# match the patterns it greps for.
AGE_PUBLIC_KEY = "age1" + "0" * 58
AGE_SECRET_KEY = "AGE-SECRET-KEY-1" + "0" * 42
DEPLOY_KEY = "first-line-of-example-deploy-key\nsecond-line-of-example-deploy-key"
WEBHOOK_TOKEN = "example-webhook-token"
TUNNEL = {
    "AccountTag": "example-account-tag",
    "TunnelID": "example-tunnel-id",
    "TunnelSecret": "ZXhhbXBsZS10dW5uZWwtc2VjcmV0",
}

# The age keys and the derived tunnel token are key-shaped enough to trip secret
# scanners, so they are replaced before anything reaches a committed snapshot.
REDACTIONS = {
    AGE_SECRET_KEY: "<age-secret-key>",
    AGE_PUBLIC_KEY: "<age-public-key>",
}

INPUT_FILES = frozenset({
    "cluster.toml",
    "age.key",
    "deploy.key",
    "flux-webhook-token.txt",
    "cloudflare-tunnel.json",
})


class TextSnapshot(SingleFileSnapshotExtension):
    _write_mode = WriteMode.TEXT
    file_extension = "txt"


@pytest.fixture(scope="session")
def makejinja_config() -> Config:
    # makejinja.toml declares its inputs relative to the repo root.
    cwd = Path.cwd()
    os.chdir(REPO_ROOT)
    try:
        return ts.load(Config, "makejinja", [Path("makejinja.toml")])
    finally:
        os.chdir(cwd)


@pytest.fixture
def snapshot_txt(snapshot):
    return snapshot.use_extension(TextSnapshot)


def _write_inputs(out: Path, fixture: Path) -> None:
    shutil.copy(fixture, out / "cluster.toml")
    (out / "age.key").write_text(
        f"# created: 2020-01-01T00:00:00Z\n"
        f"# public key: {AGE_PUBLIC_KEY}\n"
        f"{AGE_SECRET_KEY}\n"
    )
    (out / "deploy.key").write_text(f"{DEPLOY_KEY}\n")
    (out / "flux-webhook-token.txt").write_text(f"{WEBHOOK_TOKEN}\n")
    (out / "cloudflare-tunnel.json").write_text(json.dumps(TUNNEL))


def _render(config: Config, out: Path, fixture: Path) -> str:
    _write_inputs(out, fixture)

    # Render from inside the output directory: the plugin reads the credential
    # files above from the working directory, and writing anywhere else would
    # scatter rendered output across the repo.
    cwd = Path.cwd()
    os.chdir(out)
    try:
        makejinja(attrs.evolve(config, output=out, data=(out / "cluster.toml",), quiet=True))
    finally:
        os.chdir(cwd)

    redactions = REDACTIONS | {
        plugin.cloudflare_tunnel_secret(str(out / "cloudflare-tunnel.json")): "<tunnel-token>"
    }

    sections = []
    for path in sorted(p for p in out.rglob("*") if p.is_file()):
        name = path.relative_to(out).as_posix()
        if name in INPUT_FILES:
            continue
        content = path.read_text()
        for secret, placeholder in redactions.items():
            content = content.replace(secret, placeholder)
        sections.append(f"===== {name}\n{content}")
    return "\n".join(sections)


@pytest.mark.parametrize("fixture", VALID, ids=lambda p: p.stem)
def test_render_matches_snapshot(fixture: Path, tmp_path: Path, makejinja_config, snapshot_txt):
    assert _render(makejinja_config, tmp_path, fixture) == snapshot_txt


def test_no_credentials_in_snapshots():
    snapshots = Path(__file__).parent / "__snapshots__"
    leaked = [
        f"{path.name}: {secret[:16]}..."
        for path in snapshots.rglob("*.txt")
        for secret in (AGE_SECRET_KEY, AGE_PUBLIC_KEY)
        if secret in path.read_text()
    ]
    assert not leaked
