"""Fail closed on actual IPA contents, not project settings. Requires macOS tools."""
import argparse
import json
import pathlib
import plistlib
import re
import subprocess
import tempfile
import zipfile

BUNDLE = "com.personal.calculatorvault"
IDENTIFIER = "TROLLTROLL." + BUNDLE


def run(*args):
    return subprocess.run(args, check=True, capture_output=True).stdout.decode()


def check(condition, message):
    if not condition:
        raise ValueError(message)


def inspect(ipa):
    with tempfile.TemporaryDirectory() as directory:
        root = pathlib.Path(directory)
        with zipfile.ZipFile(ipa) as archive:
            for name in archive.namelist():
                check(not name.startswith("/") and ".." not in pathlib.PurePosixPath(name).parts,
                      "Unsafe zip path")
            archive.extractall(root)
        apps = list(root.glob("Payload/*.app"))
        check(len(apps) == 1, "Expected exactly one Payload/*.app")
        app = apps[0]
        info = plistlib.loads((app / "Info.plist").read_bytes())
        check(info["CFBundleIdentifier"] == BUNDLE, "Bundle ID changed")
        check(info["CFBundleDisplayName"] == "计算器", "Wrong display name")
        check(info["MinimumOSVersion"] in ("16.0", "16.0.0"), "Wrong minimum OS")
        check(info.get("CFBundleSupportedPlatforms") == ["iPhoneOS"], "Not a device build")
        check(info.get("UIDeviceFamily") == [1], "Expected iPhone target")
        executable = app / info["CFBundleExecutable"]
        check(executable.is_file(), "Missing executable")
        # zipfile doesn't preserve mode bits; restore executable bit for codesign verification.
        executable.chmod(0o755)
        archs = run("lipo", "-archs", str(executable)).strip().split()
        check(archs == ["arm64"], "Expected arm64 only")
        macho = run("otool", "-l", str(executable))
        check(re.search(r"platform\s+(?:2|IOS)\b", macho) is not None, "Not iOS Mach-O")
        check(re.search(r"minos\s+16\.0(?:\.0)?\b", macho) is not None, "Wrong Mach-O minimum OS")
        run("codesign", "--verify", "--deep", "--strict", str(app))
        entitlements = plistlib.loads(subprocess.run(
            ["codesign", "-d", "--entitlements", ":-", str(app)],
            capture_output=True, check=True).stdout)
        check(entitlements.get("com.apple.developer.family-controls") is True,
              "Family Controls entitlement missing from signature")
        check(entitlements.get("application-identifier") == IDENTIFIER, "Wrong signed identity")
        check(entitlements.get("keychain-access-groups") == [IDENTIFIER], "Wrong Keychain group")
        check(entitlements.get("get-task-allow") is False, "Unexpected debugging entitlement")
        allowed = {"application-identifier", "com.apple.developer.team-identifier",
                   "keychain-access-groups", "com.apple.developer.family-controls", "get-task-allow"}
        check(set(entitlements) == allowed, "Unexpected entitlement")
        check(entitlements["com.apple.developer.team-identifier"] == "TROLLTROLL", "Wrong team marker")
        return {"ipa": pathlib.Path(ipa).name, "bundle_id": BUNDLE,
                "minimum_os": info["MinimumOSVersion"], "architectures": archs,
                "signature_verified": True, "signed_entitlements": entitlements,
                "trollstore_installation": "pending-device-validation",
                "family_controls_authorization": "pending-device-validation",
                "actual_hiding_and_shielding": "pending-device-validation"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa")
    parser.add_argument("--report", required=True)
    args = parser.parse_args()
    result = inspect(args.ipa)
    pathlib.Path(args.report).write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
