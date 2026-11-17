#!/usr/bin/env python3
"""Check IPA layout and an unsigned arm64 iPhoneOS Mach-O without Apple tools."""

import plistlib
import stat
import struct
import sys
import zipfile
from pathlib import PurePosixPath


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate(path):
    prefix = "Payload/Crppr.app/"
    with zipfile.ZipFile(path) as archive:
        require(archive.testzip() is None, "Archive checksum failed")
        names = archive.namelist()
        require(len(names) == len(set(names)), "Duplicate archive entries")
        for name in names:
            parts = PurePosixPath(name)
            require(not parts.is_absolute() and ".." not in parts.parts,
                    "Unsafe archive path")
            require(name in ("Payload/", "Payload/Crppr.app/") or name.startswith(prefix),
                    "Unexpected entry outside Payload/Crppr.app")
            require("_CodeSignature" not in parts.parts,
                    "IPA contains a code signature")
            require(parts.name != "embedded.mobileprovision",
                    "IPA unexpectedly contains a provisioning profile")

        info = plistlib.loads(archive.read(prefix + "Info.plist"))
        require(info.get("CFBundlePackageType") == "APPL", "Not an application bundle")
        require(info.get("CFBundleSupportedPlatforms") == ["iPhoneOS"],
                "Expected a device iPhoneOS build, not a simulator build")
        require(info.get("UIDeviceFamily") == [1], "Expected an iPhone application")
        require(bool(info.get("CFBundleIdentifier")), "Missing bundle identifier")
        executable = info.get("CFBundleExecutable", "")
        require(executable and "/" not in executable, "Invalid executable name")
        entry = archive.getinfo(prefix + executable)
        require((entry.external_attr >> 16) & stat.S_IXUSR, "Executable permission is missing")
        binary = archive.read(entry)
        require(len(binary) >= 32, "Executable is too small")
        magic, cpu, _, filetype, count, commands_size, _, _ = struct.unpack_from("<8I", binary)
        require(magic == 0xFEEDFACF and cpu == 0x0100000C,
                "Expected a thin 64-bit arm64 Mach-O executable")
        require(filetype == 2, "Mach-O is not an executable")
        require(commands_size <= len(binary) - 32, "Invalid Mach-O command size")
        offset = 32
        is_ios = False
        for _ in range(count):
            require(offset + 8 <= 32 + commands_size, "Truncated Mach-O load command")
            command, size = struct.unpack_from("<2I", binary, offset)
            require(size >= 8 and offset + size <= 32 + commands_size,
                    "Invalid Mach-O load command")
            require(command != 0x1D, "Executable contains LC_CODE_SIGNATURE")
            if command == 0x32:  # LC_BUILD_VERSION
                require(size >= 24, "Invalid LC_BUILD_VERSION")
                platform = struct.unpack_from("<I", binary, offset + 8)[0]
                require(platform == 2, "Mach-O is not for physical iOS devices")
                is_ios = True
            elif command == 0x25:  # LC_VERSION_MIN_IPHONEOS, older SDK format
                is_ios = True
            offset += size
        require(offset == 32 + commands_size, "Load-command count does not match size")
        require(is_ios, "No physical-iOS platform command found")
    print("Validated: Payload/Crppr.app, arm64, physical iPhoneOS, unsigned.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: python3 scripts/validate-ipa.py path/to/Crppr-unsigned.ipa")
    try:
        validate(sys.argv[1])
    except (OSError, ValueError, KeyError, struct.error, zipfile.BadZipFile,
            plistlib.InvalidFileException) as error:
        sys.exit(f"IPA validation failed: {error}")
