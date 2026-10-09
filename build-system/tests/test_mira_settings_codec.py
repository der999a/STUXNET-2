#!/usr/bin/env python3
"""Exercise real MiraSettings -> PreferencesEntry -> Postbox decoder on macOS."""
import importlib.util
import platform
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def read(path):
    return (ROOT / path).read_text(encoding="utf-8")

def source():
    spec = importlib.util.spec_from_file_location("store_tests", Path(__file__).with_name("test_mira_stores.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    extract = module.declaration
    settings = read("submodules/TelegramUIPreferences/Sources/MiraSettings.swift")
    postbox = "submodules/Postbox/Sources/"
    # Hashes identify object types in the binary headers. These tests decode
    # through Codable, so the global PostboxCoding type registry is not used.
    fixtures = '''
import Foundation
func murMurHashString32(_ text: String) -> Int32 {
    var hash: UInt32 = 2166136261
    for byte in text.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
    return Int32(bitPattern: hash)
}
func postboxLog(_ text: String) {}
func mdb_cmp_memn(_ lhs: UnsafeRawPointer, _ lhsLength: Int, _ rhs: UnsafeRawPointer, _ rhsLength: Int) -> Int32 {
    let compared = memcmp(lhs, rhs, min(lhsLength, rhsLength))
    return compared == 0 ? (lhsLength == rhsLength ? 0 : (lhsLength < rhsLength ? -1 : 1)) : compared
}
public enum EnginePeer { public typealias Id = PeerId }
'''
    parts = [fixtures, read(postbox + "Coding.swift")]
    for folder in ("Encoder", "Decoder"):
        for path in sorted((ROOT / postbox / "Utils" / folder).glob("AdaptedPostbox*.swift")):
            parts.append(path.read_text(encoding="utf-8"))
    parts.extend([
        extract(read(postbox + "Peer.swift"), "public struct PeerId"),
        extract(read(postbox + "PreferencesEntry.swift"), "public final class PreferencesEntry"),
        read("submodules/TelegramCore/Sources/TelegramEngine/Utils/StringCodingKey.swift"),
        extract(settings, "public struct MiraGhostSettings"),
        extract(settings, "public struct MiraSettings"),
    ])
    parts = [re.sub(r"^import [^\n]+$", "", part, flags=re.MULTILINE) for part in parts]
    result = "import Foundation\n" + "\n".join(parts)
    tests = '''
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    if !condition() { fatalError(name) }
}
func roundTrip(_ value: MiraSettings) {
    let entry = PreferencesEntry(value)!
    let decoded = PreferencesEntry(data: entry.data).get(MiraSettings.self)
    check(decoded == value, "settings round trip")
}
roundTrip(.defaultSettings)
var configured = MiraSettings.defaultSettings
var ghost = MiraGhostSettings.defaultSettings
ghost.setGhostModeEnabled(true)
configured.ghost = ["0": ghost, "12345": .defaultSettings]
configured.ghostByAccount = ["account:456": ghost, "account:789": .defaultSettings]
roundTrip(configured)
struct OldSettings: Encodable { let localPremium: Bool; let ghost: [String: MiraGhostSettings] }
let migrated = PreferencesEntry(OldSettings(localPremium: true, ghost: ["0": ghost]))!.get(MiraSettings.self)!
check(migrated.localPremium && migrated.ghost["0"] == ghost && migrated.ghostByAccount.isEmpty, "legacy settings migrate")
'''
    # Toggle every persisted boolean independently with both empty and populated
    # dictionaries, exactly like each settings action followed by sharedData.
    model = extract(settings, "public struct MiraSettings")
    for name in re.findall(r"public var (\w+): Bool\s*\n", model):
        tests += f"configured.{name}.toggle(); roundTrip(configured)\n"
        tests += f"var empty_{name} = MiraSettings.defaultSettings; empty_{name}.{name}.toggle(); roundTrip(empty_{name})\n"
    tests += '''
configured.fakeStarsBalance = 9000000000
configured.fakeGiftCount = 12345
configured.fakeRatingLevel = 1234
configured.voiceChangerPreset = 13
configured.interfaceFont = 3
configured.avatarCornerStyle = 2
configured.deletedMark = "🧹 удалено"
configured.editedMark = "изменено"
roundTrip(configured)
let encoder = PostboxEncoder()
encoder.encodeString("text", forKey: "first")
encoder.encodeInt64(42, forKey: "second")
encoder.encodeNil(forKey: "third")
let decoder = PostboxDecoder(buffer: MemoryBuffer(data: encoder.makeData()))
check(decoder.decodeInt64ForKey("second", orElse: 0) == 42, "cursor before enumeration")
check(decoder.allKeys == ["first", "second", "third"], "all keys enumerate")
check(decoder.decodeStringForKey("first", orElse: "") == "text", "enumeration preserves cursor")
print("Mira settings codec: every toggle and legacy dictionaries passed")
'''
    return result + tests

def main():
    if platform.system() != "Darwin" or shutil.which("swiftc") is None:
        print("SKIP: settings codec executable requires macOS Swift")
        return 0
    with tempfile.TemporaryDirectory(prefix="mira-settings-test-") as temp:
        directory = Path(temp)
        path = directory / "main.swift"
        path.write_text(source(), encoding="utf-8")
        binary = directory / "codec-test"
        subprocess.run(["swiftc", str(path), "-Onone", "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True, timeout=30)
        # Reinstall the old allKeys trap in the otherwise identical production
        # code. The same default-settings round trip must reproduce the crash.
        baseline = source().replace("return self.decoder.allKeys.compactMap { Key(stringValue: $0) }", "preconditionFailure()")
        path.write_text(baseline, encoding="utf-8")
        subprocess.run(["swiftc", str(path), "-Onone", "-o", str(binary)], check=True)
        old = subprocess.run([str(binary)], capture_output=True, timeout=30)
        if old.returncode >= 0:
            raise RuntimeError("Original allKeys implementation did not reproduce the expected crash")
        print("Original decoder reproduced crash; repaired decoder passed every toggle")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
