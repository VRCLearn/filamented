#!/usr/bin/env python3

import argparse
import json
import re
import shutil
import tempfile
import zipfile
from pathlib import Path


SEMVER_PATTERN = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)
PACKAGE_NAME_PATTERN = re.compile(r"^[0-9A-Za-z][0-9A-Za-z._-]*$")
REPOSITORY_PATTERN = re.compile(r"^[0-9A-Za-z_.-]+/[0-9A-Za-z_.-]+$")
EXCLUDED_ROOT_PATHS = {
    ".git",
    ".github",
    "MIRROR.md",
    "Website",
    "source.json",
}


def parse_arguments():
    parser = argparse.ArgumentParser(description="Build a VPM package ZIP.")
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--author-name", required=True)
    parser.add_argument("--author-email", required=True)
    parser.add_argument("--author-url", required=True)
    parser.add_argument("--github-output", type=Path)
    return parser.parse_args()


def copy_package_source(source, staging):
    for path in source.rglob("*"):
        relative_path = path.relative_to(source)
        if relative_path.parts[0] in EXCLUDED_ROOT_PATHS:
            continue

        destination = staging / relative_path
        if path.is_dir():
            destination.mkdir(parents=True, exist_ok=True)
        elif path.is_file():
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, destination)
        else:
            raise ValueError(f"Unsupported package entry: {path}")


def supplement_manifest(manifest, repository, author):
    package_name = manifest.get("name", "")
    display_name = manifest.get("displayName", "")
    version = manifest.get("version", "")

    if not PACKAGE_NAME_PATTERN.fullmatch(package_name):
        raise ValueError(f"Unsafe or invalid package name: {package_name}")
    if not display_name or "\n" in display_name or "\r" in display_name:
        raise ValueError("package.json has no safe displayName")
    if not SEMVER_PATTERN.fullmatch(version):
        raise ValueError(f"Invalid semantic version: {version}")
    if not REPOSITORY_PATTERN.fullmatch(repository):
        raise ValueError(f"Invalid GitHub repository: {repository}")

    tag = version
    archive_name = f"{package_name}-{version}.zip"
    unitypackage_name = f"{package_name}-{version}.unitypackage"
    package_url = (
        f"https://github.com/{repository}/releases/download/{tag}/{archive_name}"
    )
    existing_author = manifest.get("author")
    if existing_author is None:
        existing_author = {}
    if not isinstance(existing_author, dict):
        raise ValueError("package.json author must be an object")
    manifest["author"] = author | existing_author
    manifest["license"] = manifest.get("license") or "Apache-2.0"
    manifest["url"] = package_url
    return {
        "archive_name": archive_name,
        "display_name": display_name,
        "package_name": package_name,
        "tag": tag,
        "unitypackage_name": unitypackage_name,
        "version": version,
    }


def build_archive(source, output, repository, author):
    source = source.resolve()
    output = output.resolve()
    manifest_path = source / "package.json"
    if not manifest_path.is_file():
        raise ValueError(f"No package.json found at {manifest_path}")

    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="vpm-package-") as temporary_directory:
        staging = Path(temporary_directory)
        copy_package_source(source, staging)

        staged_manifest_path = staging / "package.json"
        manifest = json.loads(staged_manifest_path.read_text(encoding="utf-8"))
        metadata = supplement_manifest(manifest, repository, author)
        staged_manifest_path.write_text(
            json.dumps(manifest, ensure_ascii=False, indent=4) + "\n",
            encoding="utf-8",
        )

        published_manifest_path = output / "package.json"
        shutil.copy2(staged_manifest_path, published_manifest_path)

        archive_path = output / metadata["archive_name"]
        with zipfile.ZipFile(
            archive_path,
            "w",
            compression=zipfile.ZIP_DEFLATED,
            compresslevel=9,
        ) as archive:
            for path in sorted(staging.rglob("*")):
                if path.is_file():
                    archive.write(path, path.relative_to(staging).as_posix())

    with zipfile.ZipFile(archive_path) as archive:
        packaged_manifest = json.loads(archive.read("package.json"))
    required_values = (
        packaged_manifest.get("name"),
        packaged_manifest.get("displayName"),
        packaged_manifest.get("version"),
        packaged_manifest.get("url"),
        (packaged_manifest.get("author") or {}).get("name"),
        (packaged_manifest.get("author") or {}).get("email"),
    )
    if not all(required_values):
        raise ValueError("The generated package is missing required VPM metadata")

    return metadata | {
        "archive_path": str(archive_path),
        "manifest_path": str(published_manifest_path),
    }


def write_github_output(output_path, metadata):
    if not output_path:
        return

    with output_path.open("a", encoding="utf-8") as output_file:
        for key, value in metadata.items():
            value = str(value)
            if "\n" in value or "\r" in value:
                raise ValueError(f"Unsafe multiline GitHub Actions output: {key}")
            output_file.write(f"{key}={value}\n")


def main():
    arguments = parse_arguments()
    author = {
        "name": arguments.author_name,
        "email": arguments.author_email,
        "url": arguments.author_url,
    }
    metadata = build_archive(
        arguments.source,
        arguments.output,
        arguments.repository,
        author,
    )
    write_github_output(arguments.github_output, metadata)
    print(metadata["archive_path"])


if __name__ == "__main__":
    main()
