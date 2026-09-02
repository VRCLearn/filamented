#!/usr/bin/env python3

import argparse
import hashlib
import io
import json
import os
import re
import shutil
import sys
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path


GITHUB_API_VERSION = "2026-03-10"
SEMVER_PATTERN = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)
STABLE_VERSION_PATTERN = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$"
)


def parse_arguments():
    parser = argparse.ArgumentParser(description="Build a VPM repository listing.")
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--website", type=Path, required=True)
    return parser.parse_args()


def request_json(url, token):
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "VRCLearn-VPM-Listing",
        "X-GitHub-Api-Version": GITHUB_API_VERSION,
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"

    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request) as response:
        return json.load(response)


def request_bytes(url):
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "VRCLearn-VPM-Listing"},
    )
    with urllib.request.urlopen(request) as response:
        return response.read()


def list_releases(repository, token):
    releases = []
    page = 1
    encoded_repository = "/".join(
        urllib.parse.quote(part, safe="") for part in repository.split("/", 1)
    )

    while True:
        url = (
            f"https://api.github.com/repos/{encoded_repository}/releases"
            f"?per_page=100&page={page}"
        )
        batch = request_json(url, token)
        releases.extend(batch)
        if len(batch) < 100:
            return releases
        page += 1


def read_manifest(archive_bytes, asset_url):
    with zipfile.ZipFile(io.BytesIO(archive_bytes)) as archive:
        try:
            manifest = json.loads(archive.read("package.json"))
        except KeyError as error:
            raise ValueError(f"{asset_url} has no package.json at its root") from error

    required_fields = ("name", "displayName", "version")
    missing_fields = [field for field in required_fields if not manifest.get(field)]
    author = manifest.get("author") or {}
    if not isinstance(author, dict):
        raise ValueError(f"{asset_url} has an invalid author object")
    if not author.get("name") or not author.get("email"):
        missing_fields.append("author.name/author.email")
    if missing_fields:
        joined_fields = ", ".join(missing_fields)
        raise ValueError(f"{asset_url} is missing required VPM fields: {joined_fields}")

    if not SEMVER_PATTERN.fullmatch(manifest["version"]):
        raise ValueError(
            f"{asset_url} has an invalid semantic version: {manifest['version']}"
        )

    manifest["url"] = asset_url
    manifest["zipSHA256"] = hashlib.sha256(archive_bytes).hexdigest()
    return manifest


def prerelease_key(value):
    if value is None:
        return (1,)

    identifiers = []
    for identifier in value.split("."):
        if identifier.isdigit():
            identifiers.append((0, int(identifier)))
        else:
            identifiers.append((1, identifier))
    return (0, *identifiers)


def semver_key(version):
    match = SEMVER_PATTERN.fullmatch(version)
    if not match:
        raise ValueError(f"Invalid semantic version: {version}")
    major, minor, patch, prerelease = match.groups()
    return int(major), int(minor), int(patch), prerelease_key(prerelease)


def collect_packages(releases, expected_package_name):
    packages = {}

    for release in releases:
        release_tag = release.get("tag_name", "")
        if (
            release.get("draft")
            or release.get("prerelease")
            or not STABLE_VERSION_PATTERN.fullmatch(release_tag)
        ):
            continue

        expected_asset_name = f"{expected_package_name}-{release_tag}.zip"
        for asset in release.get("assets", []):
            if asset.get("name") != expected_asset_name:
                continue
            asset_url = asset.get("browser_download_url", "")

            print(f"Reading {asset_url}")
            archive_bytes = request_bytes(asset_url)
            manifest = read_manifest(archive_bytes, asset_url)
            package_name = manifest["name"]
            version = manifest["version"]
            if package_name != expected_package_name or version != release_tag:
                raise ValueError(
                    f"Release {release_tag} contains {package_name} {version}"
                )
            versions = packages.setdefault(package_name, {})
            if version in versions:
                raise ValueError(f"Duplicate package release: {package_name} {version}")
            versions[version] = manifest

    return packages


def build_listing(config, packages):
    listing_packages = {}
    for package_name in sorted(packages):
        versions = packages[package_name]
        sorted_versions = sorted(versions, key=semver_key, reverse=True)
        listing_packages[package_name] = {
            "versions": {version: versions[version] for version in sorted_versions}
        }

    return {
        "name": config["name"],
        "id": config["id"],
        "url": config["url"],
        "author": config["author"]["name"],
        "packages": listing_packages,
    }


def prepare_output(website, output):
    website = website.resolve()
    output = output.resolve()
    if output == website or website not in output.parents:
        raise ValueError("The output directory must be a child of the website directory")

    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)

    for source in website.iterdir():
        if source == output:
            continue
        target = output / source.name
        if source.is_dir():
            shutil.copytree(source, target)
        else:
            shutil.copy2(source, target)


def main():
    arguments = parse_arguments()
    with arguments.config.open(encoding="utf-8") as config_file:
        config = json.load(config_file)

    repository = os.environ.get("GITHUB_REPOSITORY", config["repository"])
    token = os.environ.get("GITHUB_TOKEN", "")
    releases = list_releases(repository, token)
    packages = collect_packages(releases, config["packageName"])

    listing = build_listing(config, packages)
    prepare_output(arguments.website, arguments.output)
    listing_path = arguments.output / "index.json"
    listing_path.write_text(
        json.dumps(listing, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {listing_path} with {len(packages)} package(s)")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        raise
