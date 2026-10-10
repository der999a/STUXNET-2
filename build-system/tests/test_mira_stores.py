#!/usr/bin/env python3
"""Small executable regression suite for the local Mira stores.

The iOS target cannot be built on the Windows development host, while these
stores have a useful Foundation-only core.  This runner extracts the production
declarations, supplies narrow Postbox/SwiftSignalKit doubles, and compiles one
temporary Swift executable on macOS. It uses the real SwiftSignalKit promise,
subscriber and disposable implementations and the real Postbox PeerId codec.
Only unrelated account, media and entity types are fixtures.
"""

from __future__ import annotations

import platform
import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HISTORY = ROOT / "submodules/TelegramCore/Sources/State/MiraMessageHistoryStore.swift"
GIFTS = ROOT / "submodules/TelegramCore/Sources/State/MiraFakeGiftsStore.swift"
PEER = ROOT / "submodules/Postbox/Sources/Peer.swift"
SIGNALS = ROOT / "submodules/SSignalKit/SwiftSignalKit/Source"


def declaration(source: str, start: str, end: str | None = None) -> str:
    """Extract a balanced top-level declaration or a bounded source range."""
    begin = source.find(start)
    if begin < 0:
        raise RuntimeError(f"production anchor missing: {start}")
    if end is not None:
        finish = source.find(end, begin)
        if finish < 0:
            raise RuntimeError(f"production end anchor missing: {end}")
        return source[begin:finish]
    brace = source.find("{", begin)
    if brace < 0:
        raise RuntimeError(f"declaration has no body: {start}")
    depth = 0
    in_string = False
    escaped = False
    for index in range(brace, len(source)):
        char = source[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[begin:index + 1]
    raise RuntimeError(f"unterminated declaration: {start}")


def remove_declaration(source: str, start: str) -> str:
    """Remove one balanced declaration/method from an extracted declaration."""
    removed = declaration(source, start)
    return source.replace(removed, "", 1)


DOUBLES = r'''
import Foundation
import Dispatch

public struct MessageTextEntity: Codable, Equatable { public init() {} }
public enum Namespaces {
    public enum Message { public static let Local: Int32 = 1 }
    public enum Peer {
        public static let CloudUser = PeerId.Namespace._internalFromInt32Value(0)
        public static let CloudGroup = PeerId.Namespace._internalFromInt32Value(1)
        public static let CloudChannel = PeerId.Namespace._internalFromInt32Value(2)
        public static let SecretChat = PeerId.Namespace._internalFromInt32Value(3)
    }
}
public struct MessageId { public let peerId: PeerId; public let namespace: Int32; public let id: Int32; public init(peerId: PeerId, namespace: Int32, id: Int32) { self.peerId = peerId; self.namespace = namespace; self.id = id } }
public struct StarGift: Codable, Equatable { public init() {} }
public enum StarGiftReference { case peer(PeerId, Int64) }
'''


def source_for_harness() -> str:
    history = HISTORY.read_text(encoding="utf-8")
    gifts = GIFTS.read_text(encoding="utf-8")
    peer = PEER.read_text(encoding="utf-8")
    history_record = declaration(history, "public struct MiraMessageEditRecord")
    history_local = declaration(history, "public struct LocalOverrideRecord")
    history_kind = declaration(history, "public enum FakeMessageKind")
    history_media = declaration(history, "public struct FakeMessageMedia")
    history_fake = declaration(history, "public struct FakeMessageRecord")
    history_store = declaration(history, "public final class MiraMessageHistoryStore")
    peer_id = declaration(peer, "public struct PeerId")
    # The store only needs the production packed-value constructor and encoder.
    # Buffer helpers pull in the full Postbox binary-buffer graph, so keep those
    # methods out of this Foundation-only executable harness.
    for method in (
        "    public static func encodeArrayToBuffer",
        "    public static func decodeArrayFromBuffer",
        "    public func encodeToBuffer"
    ):
        peer_id = remove_declaration(peer_id, method)
    gift_model = declaration(gifts, "public struct MiraFakeGift")
    gift_store = declaration(gifts, "public final class MiraFakeGiftsStore", "extension MiraFakeGiftsStore")
    # Leave account/network projections out of this Foundation persistence test.
    # Their production implementations are compiled by the full app build.
    account_clear = declaration(gift_store, "    public func clear(account: Account)")
    gift_store = gift_store.replace(account_clear, "")
    signal_sources = [
        (SIGNALS / name).read_text(encoding="utf-8")
        for name in (
            "Atomic.swift", "Bag.swift", "Disposable.swift",
            "Subscriber.swift", "Signal.swift", "Signal_Take.swift",
            "Promise.swift",
        )
    ]
    return "\n".join([DOUBLES, *signal_sources, peer_id, history_record,
                       history_local, history_kind, history_media, history_fake, history_store,
                       gift_model, gift_store])


TEST_MAIN = r'''
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
func waitUntil(_ condition: @escaping () -> Bool) {
    let deadline = Date().addingTimeInterval(3.0)
    while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    require(condition(), "timed out")
}
func userId(_ id: Int64) -> PeerId {
    return PeerId(namespace: ._internalFromInt32Value(0), id: ._internalFromInt64Value(id))
}
let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mira-store-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }

let gifts = MiraFakeGiftsStore(basePath: root.path)
let eventLock = NSLock()
var giftEvents: [[MiraFakeGift]] = []
func lastGiftCount() -> Int? { eventLock.lock(); defer { eventLock.unlock() }; return giftEvents.last?.count }
let giftSubscription = gifts.changes.start(next: { value in _ = gifts.list(); eventLock.lock(); giftEvents.append(value); eventLock.unlock() })
defer { giftSubscription.dispose() }
let gift = MiraFakeGift(id: "g1", kind: .regular, giftId: 7, date: 10)
gifts.upsert(gift)
waitUntil { gifts.list().count == 1 && lastGiftCount() == 1 }
gifts.upsert(MiraFakeGift(id: "g2", kind: .regular, giftId: 8, date: 11))
waitUntil { gifts.list().count == 2 && lastGiftCount() == 2 }
eventLock.lock(); let giftCounts = giftEvents.map { $0.count }; eventLock.unlock()
require(giftCounts == [0, 1, 2], "gift notifications are ordered")
let persistedGifts = MiraFakeGiftsStore(basePath: root.path)
require(persistedGifts.list().map(\.id) == ["g1", "g2"], "gift persistence round trip")
var loadedGiftCount: Int?
let loadedGiftSubscription = persistedGifts.changes.start(next: { value in
    _ = persistedGifts.list()
    eventLock.lock(); loadedGiftCount = value.count; eventLock.unlock()
})
defer { loadedGiftSubscription.dispose() }
waitUntil { eventLock.lock(); defer { eventLock.unlock() }; return loadedGiftCount == 2 }
gifts.upsert(MiraFakeGift(id: "g1", kind: .regular, giftId: 9, date: 12))
require(gifts.list().count == 2 && gifts.list().first?.giftId == 9, "upsert replaces stable id")
let localReference = StarGiftReference.peer(userId(42), gift.stableSavedId)
require(gifts.isLocalReference(localReference, accountPeerId: userId(42)), "synthetic reference stays local")
require(!gifts.isLocalReference(localReference, accountPeerId: userId(43)), "synthetic reference is account scoped")
gifts.remove(id: "g1")
require(gifts.list().map(\.id) == ["g2"], "gift removal drains before read")
require(gifts.isLocalReference(localReference, accountPeerId: userId(42)), "deleted synthetic reference remains local")
gifts.clear(); waitUntil { gifts.list().isEmpty }
require(MiraFakeGiftsStore(basePath: root.path).list().isEmpty, "gift clear survives reload")
try! JSONEncoder().encode([gift]).write(to: root.appendingPathComponent("mira-fake-gifts.json"))
let unloadedGiftStore = MiraFakeGiftsStore(basePath: root.path)
unloadedGiftStore.clear()
require(unloadedGiftStore.list().isEmpty, "gift clear before initial load")

let record = FakeMessageRecord(id: "m1", messagePeerId: userId(42).toInt64(), text: "hello", date: 1, outgoing: false)
let media = FakeMessageMedia(kind: .video, resource: "local://clip.mp4", duration: -4, width: -1, stars: -2)
let mediaRecord = FakeMessageRecord(id: "media", messagePeerId: userId(42).toInt64(), text: "caption", date: 2, outgoing: true, kind: .video, media: media)
require(!record.isRead && mediaRecord.isRead, "fake message read defaults follow direction")
require(mediaRecord.kind == .video && mediaRecord.media?.duration == 0 && mediaRecord.media?.width == 0 && mediaRecord.media?.stars == 0, "media metadata is normalized")
let decodedMediaRecord = try! JSONDecoder().decode(FakeMessageRecord.self, from: JSONEncoder().encode(mediaRecord))
require(decodedMediaRecord == mediaRecord, "media metadata persists")
let history = MiraMessageHistoryStore(basePath: root.path)
var historyEvents: [[FakeMessageRecord]] = []
func lastHistoryId() -> String? { eventLock.lock(); defer { eventLock.unlock() }; return historyEvents.last?.first?.id }
let historySubscription = history.fakeMessagesChanges.start(next: { value in _ = history.fakeMessages(in: userId(42)); eventLock.lock(); historyEvents.append(value); eventLock.unlock() })
defer { historySubscription.dispose() }
history.addFakeMessage(record)
waitUntil { history.fakeMessages(in: userId(42)).count == 1 && lastHistoryId() == "m1" }
require(history.setFakeMessageRead(id: "m1", isRead: true), "fake message read marker updates")
waitUntil { history.fakeMessage(id: "m1")?.isRead == true }
history.addFakeMessage(record)
require(history.fakeMessages(in: userId(42)).count == 1, "duplicate fake id is ignored")
var editedRecord = record
editedRecord.text = "edited"
editedRecord.date = 99
require(history.updateFakeMessage(editedRecord), "existing fake message updates")
require(history.fakeMessage(id: "m1")?.text == "edited" && history.fakeMessage(id: "m1")?.date == 99, "fake message edit is visible")
var invalidEdit = editedRecord
invalidEdit.messageNamespace = 99
require(!history.updateFakeMessage(invalidEdit), "invalid fake message edit is rejected")
require(MiraMessageHistoryStore(basePath: root.path).fakeMessage(id: "m1")?.text == "edited", "fake message edit persists")
require(MiraMessageHistoryStore(basePath: root.path).fakeMessage(id: "m1")?.isRead == true, "fake message read marker persists")
let bulk = (0..<1200).map { FakeMessageRecord(id: "bulk-\($0)", messagePeerId: userId(42).toInt64(), text: "row \($0)", date: Int32($0), outgoing: false) }
history.addFakeMessages(bulk)
require(history.fakeMessages(in: userId(42)).count == 1201, "bulk insertion preserves every record")
require(MiraMessageHistoryStore(basePath: root.path).fakeMessages(in: userId(42)).count == 1201, "bulk journal survives reload")

let legacy = FakeMessageRecord(id: "legacy", messagePeerId: userId(42).toInt64(), text: "legacy", date: 2, outgoing: false)
let invalid = FakeMessageRecord(id: "invalid", messagePeerId: Int64.max, text: "bad", date: 3, outgoing: false)
let legacyData = try! JSONEncoder().encode([legacy, invalid])
try! legacyData.write(to: root.appendingPathComponent("mira-fake-messages.json"), options: .atomic)
struct Journal: Encodable { let records: [FakeMessageRecord]; let removedIds: [String] }
let journal = try! JSONEncoder().encode(Journal(records: [legacy], removedIds: []))
var journalData = Data([10]); journalData.append(journal); journalData.append(Data([10, 123, 10]))
try! journalData.write(to: root.appendingPathComponent("mira-fake-messages.jsonl"))
let reloaded = MiraMessageHistoryStore(basePath: root.path)
waitUntil { reloaded.fakeMessages(in: userId(42)).count == 1 }
require(reloaded.fakeMessages(in: userId(42)).first?.id == "legacy", "legacy plus truncated journal recovery")
require(reloaded.fakeMessage(id: "invalid") == nil, "invalid packed PeerId filtered before construction")
reloaded.removeFakeMessage(id: "legacy")
require(reloaded.fakeMessages(in: userId(42)).isEmpty, "message removal drained")
let afterRemoval = MiraMessageHistoryStore(basePath: root.path)
require(afterRemoval.fakeMessages(in: userId(42)).isEmpty, "journal deletion survives reload")
afterRemoval.addFakeMessage(record)
afterRemoval.clear()
waitUntil { afterRemoval.fakeMessages(in: userId(42)).isEmpty }
let afterClear = MiraMessageHistoryStore(basePath: root.path)
require(afterClear.fakeMessages(in: userId(42)).isEmpty, "clear survives reload")
for id in [userId(1), userId(0x00ffffffffffffff), PeerId(namespace: ._internalFromInt32Value(3), id: ._internalFromInt64Value(-42)), PeerId(namespace: ._internalFromInt32Value(2), id: ._internalFromInt64Value(123456789))] {
    require(MiraMessageHistoryStore.peerId(fromPackedValue: id.toInt64())?.toInt64() == id.toInt64(), "packed PeerId round trip")
}
require(MiraMessageHistoryStore.peerId(fromPackedValue: Int64.max) == nil, "invalid packed PeerId rejected")
let rawSender = Int64(9876543210)
require(MiraFakeGift.peerId(fromStoredValue: rawSender, isPacked: false) == userId(rawSender), "large raw gift user id remains a user")
require(MiraFakeGift.peerId(fromStoredValue: userId(rawSender).toInt64(), isPacked: true) == userId(rawSender), "packed gift sender round trip")
require(MiraFakeGift.peerId(fromStoredValue: Int64.max, isPacked: false) == nil, "invalid raw gift user id rejected")
let senderGift = MiraFakeGift(id: "sender-date", kind: .regular, fromPeerId: rawSender, fromPeerIdIsPacked: false, date: 1700000042)
let decodedSenderGift = try! JSONDecoder().decode(MiraFakeGift.self, from: JSONEncoder().encode(senderGift))
require(decodedSenderGift.fromPeerIdIsPacked == false && decodedSenderGift.date == 1700000042, "sender format and exact seconds persist")
print("Mira store regressions passed")
'''


def main() -> int:
    if platform.system() != "Darwin":
        print("SKIP: Mira store executable regression requires macOS Swift", file=sys.stderr)
        return 0
    swiftc = shutil.which("swiftc")
    if swiftc is None:
        print("SKIP: swiftc is unavailable", file=sys.stderr)
        return 0
    with tempfile.TemporaryDirectory(prefix="mira-store-test-") as temp:
        temp_path = Path(temp)
        source = temp_path / "main.swift"
        binary = temp_path / "mira-store-test"
        source.write_text(source_for_harness() + "\n" + TEST_MAIN, encoding="utf-8")
        compile_result = subprocess.run([swiftc, str(source), "-Onone", "-o", str(binary)], text=True, capture_output=True)
        if compile_result.returncode:
            print(compile_result.stdout, file=sys.stdout)
            print(compile_result.stderr, file=sys.stderr)
            return compile_result.returncode
        # A queue deadlock should fail the job, rather than leave CI hanging.
        result = subprocess.run([str(binary)], text=True, timeout=20)
        return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
