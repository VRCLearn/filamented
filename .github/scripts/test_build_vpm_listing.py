import hashlib
import importlib.util
import io
import json
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).with_name("build_vpm_listing.py")
SPEC = importlib.util.spec_from_file_location("build_vpm_listing", MODULE_PATH)
BUILD_VPM_LISTING = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILD_VPM_LISTING)

PACKAGE_MODULE_PATH = Path(__file__).with_name("build_vpm_package.py")
PACKAGE_SPEC = importlib.util.spec_from_file_location(
    "build_vpm_package",
    PACKAGE_MODULE_PATH,
)
BUILD_VPM_PACKAGE = importlib.util.module_from_spec(PACKAGE_SPEC)
PACKAGE_SPEC.loader.exec_module(BUILD_VPM_PACKAGE)


def package_archive(version):
    manifest = {
        "name": "s-ilent.filamented",
        "displayName": "Filamented",
        "version": version,
        "description": "Test package",
        "author": {
            "name": "Silent",
            "email": "silent@example.invalid",
        },
    }
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr("package.json", json.dumps(manifest))
    return buffer.getvalue()


class BuildVpmListingTests(unittest.TestCase):
    def test_package_builder_excludes_mirror_files_and_supplements_manifest(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source = root / "source"
            output = root / "output"
            (source / ".github").mkdir(parents=True)
            (source / "Editor").mkdir()
            (source / ".github" / "workflow.yml").write_text("mirror only")
            (source / "Editor" / "tool.cs").write_text("package file")
            (source / "MIRROR.md").write_text("mirror only")
            (source / "source.json").write_text("{}")
            (source / "package.json").write_text(
                json.dumps(
                    {
                        "name": "s-ilent.filamented",
                        "displayName": "Filamented",
                        "version": "1.4.0",
                    }
                )
            )

            metadata = BUILD_VPM_PACKAGE.build_archive(
                source,
                output,
                "VRCLearn/filamented",
                {
                    "name": "Silent",
                    "email": "silent@example.invalid",
                    "url": "https://example.invalid/silent",
                },
            )

            with zipfile.ZipFile(metadata["archive_path"]) as archive:
                names = archive.namelist()
                manifest = json.loads(archive.read("package.json"))

            self.assertIn("Editor/tool.cs", names)
            self.assertNotIn(".github/workflow.yml", names)
            self.assertNotIn("MIRROR.md", names)
            self.assertNotIn("source.json", names)
            self.assertEqual("Apache-2.0", manifest["license"])
            self.assertEqual("Silent", manifest["author"]["name"])
            self.assertEqual("s-ilent.filamented", metadata["package_name"])
            self.assertEqual(
                "s-ilent.filamented-1.4.0.unitypackage",
                metadata["unitypackage_name"],
            )
            self.assertEqual(
                "https://github.com/VRCLearn/filamented/releases/download/"
                "1.4.0/s-ilent.filamented-1.4.0.zip",
                manifest["url"],
            )
            self.assertEqual(output / "package.json", Path(metadata["manifest_path"]))

    def test_read_manifest_adds_download_metadata(self):
        archive = package_archive("1.4.0")
        url = "https://example.invalid/filamented.zip"

        manifest = BUILD_VPM_LISTING.read_manifest(archive, url)

        self.assertEqual(url, manifest["url"])
        self.assertEqual(hashlib.sha256(archive).hexdigest(), manifest["zipSHA256"])

    def test_collect_packages_accepts_only_matching_stable_releases(self):
        archive = package_archive("1.4.0")
        releases = [
            {
                "tag_name": "1.4.0",
                "draft": False,
                "prerelease": False,
                "assets": [
                    {
                        "name": "s-ilent.filamented-1.4.0.unitypackage",
                        "browser_download_url": (
                            "https://example.invalid/filamented.unitypackage"
                        )
                    },
                    {
                        "name": "s-ilent.filamented-1.4.0.zip",
                        "browser_download_url": "https://example.invalid/filamented.zip",
                    },
                ],
            },
            {
                "tag_name": "upstream-archive",
                "draft": False,
                "prerelease": False,
                "assets": [
                    {
                        "name": "s-ilent.filamented-1.4.0.zip",
                        "browser_download_url": "https://example.invalid/source.zip",
                    }
                ],
            },
        ]

        with mock.patch.object(BUILD_VPM_LISTING, "request_bytes", return_value=archive):
            packages = BUILD_VPM_LISTING.collect_packages(
                releases,
                "s-ilent.filamented",
            )

        self.assertEqual(["1.4.0"], list(packages["s-ilent.filamented"]))

    def test_versions_are_ordered_by_semver(self):
        versions = ["1.4.0-beta.2", "1.3.9", "1.4.0", "1.4.0-beta.10"]

        ordered = sorted(versions, key=BUILD_VPM_LISTING.semver_key, reverse=True)

        self.assertEqual(
            ["1.4.0", "1.4.0-beta.10", "1.4.0-beta.2", "1.3.9"],
            ordered,
        )


if __name__ == "__main__":
    unittest.main()
