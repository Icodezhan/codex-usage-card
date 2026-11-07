"""Build the fork's macOS installer from the pinned upstream release ZIP."""

import argparse
import hashlib
from io import BytesIO
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = "CodexUsageCard-macOS-0.9.5"
UPSTREAM_SHA256 = "7f2a8256738e4d03359a028f18f265518593beed452c4b6279013976ec11ba8c"
VERSION = "0.9.5-macos.1"
PRODUCT = f"CodexUsageCard-macOS-{VERSION}"


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("upstream_zip", type=Path)
    args = parser.parse_args()
    upstream_bytes = args.upstream_zip.read_bytes()
    if sha256(upstream_bytes) != UPSTREAM_SHA256:
        parser.error("SHA-256 does not match the upstream v0.9.5 Beta release")

    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    target = dist / f"{PRODUCT}.zip"
    agent = (ROOT / "macos" / "agent.cjs").read_bytes()
    with ZipFile(BytesIO(upstream_bytes)) as source, ZipFile(target, "w", ZIP_DEFLATED) as output:
        checksums = []
        for entry in source.infolist():
            name = entry.filename.removeprefix(f"{UPSTREAM}/")
            if name == "SHA256SUMS.txt":
                continue
            data = source.read(entry)
            if name == "agent.cjs":
                data = agent
            elif name == "manage.cjs":
                data = data.replace(b"const VERSION='0.9.5';", f"const VERSION='{VERSION}';".encode("ascii"), 1)
            entry.filename = f"{PRODUCT}/{name}"
            output.writestr(entry, data)
            checksums.append(f"{sha256(data)}  {name}\n")
        output.writestr(f"{PRODUCT}/SHA256SUMS.txt", "".join(checksums))

    digest = sha256(target.read_bytes())
    target.with_suffix(".zip.sha256").write_text(f"{digest}  {target.name}\n", encoding="ascii")
    print(f"{target}\nSHA-256 {digest}")


if __name__ == "__main__":
    main()
