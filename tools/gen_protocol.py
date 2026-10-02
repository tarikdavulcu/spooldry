#!/usr/bin/env python3
"""Generate firmware (C++) and iOS (Swift) protocol constants from the single
source of truth protocol/spooldry-ble-v1.json.

Run from the repository root:  python3 tools/gen_protocol.py
CI runs it with --check to make sure the generated files are up to date.
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPEC = json.loads((ROOT / "protocol" / "spooldry-ble-v1.json").read_text())

CPP_OUT = ROOT / "esp32" / "SpoolDry" / "src" / "core" / "ProtocolConstants.h"
SWIFT_OUT = ROOT / "ios" / "Packages" / "SpoolDryKit" / "Sources" / "SpoolDryKit" / "Protocol" / "ProtocolConstants.swift"

HEADER = "GENERATED FILE - DO NOT EDIT. Source: protocol/spooldry-ble-v1.json (tools/gen_protocol.py)"


SWIFT_KEYWORDS = {"internal", "default", "public", "private", "static", "class", "struct", "enum", "case",
                  "switch", "return", "import", "init", "self", "protocol", "extension", "operator", "func"}


def camel(name: str) -> str:
    parts = name.lower().split("_")
    return parts[0] + "".join(p.capitalize() for p in parts[1:])


def swift_case(name: str) -> str:
    c = camel(name)
    return f"`{c}`" if c in SWIFT_KEYWORDS else c


def enum_cpp(name, items, typ="uint8_t"):
    lines = [f"enum class {name} : {typ} {{"]
    for it in items:
        lines.append(f"    {it['name']} = {it['value']},")
    lines.append("};")
    return "\n".join(lines)


def gen_cpp() -> str:
    fv = [int(x) for x in SPEC["firmwareVersion"].split(".")]
    lim = SPEC["limits"]
    out = [f"// {HEADER}", "#pragma once", "#include <stdint.h>", "", "namespace spooldry {", ""]
    out.append(f"constexpr uint8_t kProtocolVersion = {SPEC['protocolVersion']};")
    out.append(f"constexpr uint8_t kHardwareRevision = {SPEC['hardwareRevision']};")
    out.append(f"constexpr uint8_t kFirmwareMajor = {fv[0]};")
    out.append(f"constexpr uint8_t kFirmwareMinor = {fv[1]};")
    out.append(f"constexpr uint8_t kFirmwarePatch = {fv[2]};")
    out.append(f'constexpr const char* kFirmwareVersionString = "{SPEC["firmwareVersion"]}";')
    out.append(f'constexpr const char* kAdvertisedNamePrefix = "{SPEC["advertisedNamePrefix"]}";')
    out.append("")
    out.append(f'constexpr const char* kServiceUUID = "{SPEC["service"]["uuid"]}";')
    for c in SPEC["characteristics"]:
        out.append(f'constexpr const char* kChar{c["id"][0].upper() + c["id"][1:]}UUID = "{c["uuid"]}";')
    out.append("")
    for c in SPEC["characteristics"]:
        out.append(f'constexpr uint8_t kSize{c["id"][0].upper() + c["id"][1:]} = {c["size"]};')
    out.append("")
    out.append(enum_cpp("DeviceState", SPEC["states"]))
    out.append(enum_cpp("Opcode", SPEC["opcodes"]))
    out.append(enum_cpp("ResponseType", SPEC["responseTypes"]))
    out.append(enum_cpp("ResultCode", SPEC["resultCodes"]))
    out.append(enum_cpp("ErrorCode", SPEC["errorCodes"]))
    out.append(enum_cpp("FanMode", SPEC["fanModes"]))
    out.append(enum_cpp("EndReason", SPEC["endReasons"]))
    out.append(enum_cpp("Material", SPEC["materials"]))
    out.append("")
    out.append("namespace StatusFlag {")
    for f in SPEC["statusFlags"]:
        out.append(f"constexpr uint8_t {f['name']} = 1u << {f['bit']};")
    out.append("}  // namespace StatusFlag")
    out.append("namespace Capability {")
    for f in SPEC["capabilities"]:
        out.append(f"constexpr uint16_t {f['name']} = 1u << {f['bit']};")
    out.append("}  // namespace Capability")
    out.append("")
    out.append(f"constexpr int16_t kMinTargetCentiC = {lim['minTargetCentiC']};")
    out.append(f"constexpr int16_t kMaxTargetCentiC = {lim['maxTargetCentiC']};")
    out.append(f"constexpr uint32_t kMinDurationSec = {lim['minDurationSec']}u;")
    out.append(f"constexpr uint32_t kMaxDurationSec = {lim['maxDurationSec']}u;")
    out.append(f"constexpr int16_t kInvalidTemperature = INT16_MIN;")
    out.append(f"constexpr uint16_t kInvalidHumidity = {lim['invalidHumidity']}u;")
    out.append(f"constexpr uint32_t kUnknownRemaining = {lim['unknownRemaining']}u;")
    out.append(f"constexpr uint8_t kMaterialCount = {len(SPEC['materials'])};")
    out.append("")
    out.append("}  // namespace spooldry")
    return "\n".join(out) + "\n"


def enum_swift(name, items, doc=None):
    lines = []
    if doc:
        lines.append(f"/// {doc}")
    lines.append(f"public enum {name}: UInt8, CaseIterable, Sendable, Codable {{")
    for it in items:
        lines.append(f"    case {swift_case(it['name'])} = {it['value']}")
    lines.append("}")
    return "\n".join(lines)


def gen_swift() -> str:
    lim = SPEC["limits"]
    out = [f"// {HEADER}", "import Foundation", ""]
    out.append("public enum SpoolDryProtocol {")
    out.append(f"    public static let protocolVersion: UInt8 = {SPEC['protocolVersion']}")
    out.append(f'    public static let referenceFirmwareVersion = "{SPEC["firmwareVersion"]}"')
    out.append(f'    public static let advertisedNamePrefix = "{SPEC["advertisedNamePrefix"]}"')
    out.append(f'    public static let serviceUUID = "{SPEC["service"]["uuid"]}"')
    out.append(f"    public static let minTargetCentiC: Int16 = {lim['minTargetCentiC']}")
    out.append(f"    public static let maxTargetCentiC: Int16 = {lim['maxTargetCentiC']}")
    out.append(f"    public static let minDurationSec: UInt32 = {lim['minDurationSec']}")
    out.append(f"    public static let maxDurationSec: UInt32 = {lim['maxDurationSec']}")
    out.append("    public static let invalidTemperature: Int16 = Int16.min")
    out.append(f"    public static let invalidHumidity: UInt16 = {lim['invalidHumidity']}")
    out.append(f"    public static let unknownRemaining: UInt32 = {lim['unknownRemaining']}")
    out.append("}")
    out.append("")
    out.append("/// GATT characteristics of the SpoolDry Device Service.")
    out.append("public enum SpoolDryCharacteristic: String, CaseIterable, Sendable {")
    for c in SPEC["characteristics"]:
        out.append(f'    case {c["id"]} = "{c["uuid"]}"')
    out.append("")
    out.append("    public var expectedSize: Int {")
    out.append("        switch self {")
    for c in SPEC["characteristics"]:
        out.append(f"        case .{c['id']}: return {c['size']}")
    out.append("        }")
    out.append("    }")
    out.append("")
    out.append("    public var displayName: String {")
    out.append("        switch self {")
    for c in SPEC["characteristics"]:
        out.append(f'        case .{c["id"]}: return "{c["name"]}"')
    out.append("        }")
    out.append("    }")
    out.append("}")
    out.append("")
    out.append(enum_swift("DeviceState", SPEC["states"], "Shared device/link state machine. 0-2 are app-side link states."))
    out.append("")
    out.append(enum_swift("Opcode", SPEC["opcodes"]))
    out.append("")
    out.append(enum_swift("ResponseType", SPEC["responseTypes"]))
    out.append("")
    out.append(enum_swift("ResultCode", SPEC["resultCodes"]))
    out.append("")
    out.append(enum_swift("DeviceErrorCode", SPEC["errorCodes"]))
    out.append("")
    out.append(enum_swift("FanMode", SPEC["fanModes"]))
    out.append("")
    out.append(enum_swift("SessionEndReason", SPEC["endReasons"]))
    out.append("")
    out.append(enum_swift("MaterialCode", SPEC["materials"]))
    out.append("")
    out.append("public struct StatusFlags: OptionSet, Sendable, Hashable, Codable {")
    out.append("    public let rawValue: UInt8")
    out.append("    public init(rawValue: UInt8) { self.rawValue = rawValue }")
    for f in SPEC["statusFlags"]:
        out.append(f"    public static let {camel(f['name'])} = StatusFlags(rawValue: 1 << {f['bit']})")
    out.append("}")
    out.append("")
    out.append("public struct DeviceCapabilities: OptionSet, Sendable, Hashable, Codable {")
    out.append("    public let rawValue: UInt16")
    out.append("    public init(rawValue: UInt16) { self.rawValue = rawValue }")
    for f in SPEC["capabilities"]:
        out.append(f"    public static let {camel(f['name'])} = DeviceCapabilities(rawValue: 1 << {f['bit']})")
    out.append("}")
    return "\n".join(out) + "\n"


def main() -> int:
    check = "--check" in sys.argv
    results = {CPP_OUT: gen_cpp(), SWIFT_OUT: gen_swift()}
    stale = []
    for path, content in results.items():
        if check:
            if not path.exists() or path.read_text() != content:
                stale.append(str(path.relative_to(ROOT)))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
            print(f"wrote {path.relative_to(ROOT)}")
    if stale:
        print("Out of date: " + ", ".join(stale))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
