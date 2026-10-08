import Foundation
import Postbox
import SwiftSignalKit

public struct MiraMessageEditRecord: Codable, Equatable {
    public let messagePeerId: Int64
    public let messageNamespace: Int32
    public let messageId: Int32
    public let text: String
    public let entities: [MessageTextEntity]
    public let date: Int32
    public let editDate: Int32?

    public init(messagePeerId: Int64, messageNamespace: Int32, messageId: Int32, text: String, entities: [MessageTextEntity], date: Int32, editDate: Int32?) {
        self.messagePeerId = messagePeerId
        self.messageNamespace = messageNamespace
        self.messageId = messageId
        self.text = text
        self.entities = entities
        self.date = date
        self.editDate = editDate
    }
}

public struct LocalOverrideRecord: Codable, Equatable {
    public let messagePeerId: Int64
    public let messageNamespace: Int32
    public let messageId: Int32
    public let text: String
    public let entities: [MessageTextEntity]
    public let date: Int32

    public init(messagePeerId: Int64, messageNamespace: Int32, messageId: Int32, text: String, entities: [MessageTextEntity], date: Int32) {
        self.messagePeerId = messagePeerId
        self.messageNamespace = messageNamespace
        self.messageId = messageId
        self.text = text
        self.entities = entities
        self.date = date
    }
}

public struct FakeMessageRecord: Codable, Equatable {
    public var id: String
    public var messagePeerId: Int64
    public var messageNamespace: Int32
    public var messageId: Int32
    public var text: String
    public var entities: [MessageTextEntity]
    public var date: Int32
    public var outgoing: Bool
    public var authorPeerId: Int64?
    public var authorName: String?

    public init(id: String = UUID().uuidString, messagePeerId: Int64, messageNamespace: Int32 = Namespaces.Message.Local, messageId: Int32 = 0, text: String, entities: [MessageTextEntity] = [], date: Int32, outgoing: Bool, authorPeerId: Int64? = nil, authorName: String? = nil) {
        self.id = id
        self.messagePeerId = messagePeerId
        self.messageNamespace = messageNamespace
        self.messageId = messageId
        self.text = text
        self.entities = entities
        self.date = date
        self.outgoing = outgoing
        self.authorPeerId = authorPeerId
        self.authorName = authorName
    }

    // Deterministic, collision-safe globallyUniqueId for insertion (Swift's hashValue is randomized per launch).
    public var stableUniqueId: Int64 {
        var hash: UInt64 = 14695981039346656037
        for byte in self.id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return Int64(bitPattern: (hash & 0x0000ffffffffffff) | 0x2222000000000000)
    }
}

public final class MiraMessageHistoryStore {
    private static let registryQueue = DispatchQueue(label: "org.telegram.mira.messageHistoryStore.registry")
    private static var registeredStores: [Int64: MiraMessageHistoryStore] = [:]

    public static func register(accountPeerId: PeerId, store: MiraMessageHistoryStore) {
        self.registryQueue.sync {
            self.registeredStores[accountPeerId.toInt64()] = store
        }
    }

    public static func store(for accountPeerId: PeerId) -> MiraMessageHistoryStore? {
        return self.registryQueue.sync {
            return self.registeredStores[accountPeerId.toInt64()]
        }
    }

    private let queue = DispatchQueue(label: "org.telegram.mira.messageHistoryStore", qos: .utility)
    private let filePath: String
    private let overridesFilePath: String
    private let fakeMessagesFilePath: String
    private var cache: [String: [MiraMessageEditRecord]] = [:]
    private var didLoad = false
    private var overrideCache: [String: LocalOverrideRecord] = [:]
    private var didLoadOverrides = false
    private var fakeCache: [FakeMessageRecord] = []
    private var didLoadFakes = false

    private let fakeMessagesChangesPromise = ValuePromise<[FakeMessageRecord]>([], ignoreRepeated: true)

    public init(basePath: String) {
        self.filePath = basePath + "/mira-message-history.jsonl"
        self.overridesFilePath = basePath + "/mira-local-overrides.jsonl"
        self.fakeMessagesFilePath = basePath + "/mira-fake-messages.json"
    }

    private func messageKey(peerId: Int64, namespace: Int32, id: Int32) -> String {
        return "\(peerId):\(namespace):\(id)"
    }

    private func loadIfNeeded() {
        if self.didLoad {
            return
        }
        self.didLoad = true
        guard let data = FileManager.default.contents(atPath: self.filePath), let content = String(data: data, encoding: .utf8) else {
            return
        }
        let decoder = JSONDecoder()
        for line in content.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8), let record = try? decoder.decode(MiraMessageEditRecord.self, from: lineData) else {
                continue
            }
            let key = self.messageKey(peerId: record.messagePeerId, namespace: record.messageNamespace, id: record.messageId)
            self.cache[key, default: []].append(record)
        }
    }

    public func edits(for messageId: MessageId) -> [MiraMessageEditRecord] {
        return self.queue.sync {
            self.loadIfNeeded()
            return self.cache[self.messageKey(peerId: messageId.peerId.toInt64(), namespace: messageId.namespace, id: messageId.id)] ?? []
        }
    }

    public func hasEdits(messageId: MessageId) -> Bool {
        return self.queue.sync {
            self.loadIfNeeded()
            return self.cache[self.messageKey(peerId: messageId.peerId.toInt64(), namespace: messageId.namespace, id: messageId.id)]?.isEmpty == false
        }
    }

    public func appendEdit(_ record: MiraMessageEditRecord) {
        self.queue.async {
            self.loadIfNeeded()
            let key = self.messageKey(peerId: record.messagePeerId, namespace: record.messageNamespace, id: record.messageId)
            self.cache[key, default: []].append(record)
            guard let data = try? JSONEncoder().encode(record), var line = String(data: data, encoding: .utf8) else {
                return
            }
            line.append("\n")
            guard let lineData = line.data(using: .utf8) else {
                return
            }
            if let handle = FileHandle(forWritingAtPath: self.filePath) {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: self.filePath), let size = attributes[.size] as? UInt64 {
                    handle.seek(toFileOffset: size)
                    handle.write(lineData)
                }
                handle.closeFile()
            } else {
                try? lineData.write(to: URL(fileURLWithPath: self.filePath), options: [.atomic])
            }
        }
    }

    public func clear() {
        self.queue.async {
            self.cache.removeAll()
            self.overrideCache.removeAll()
            self.fakeCache.removeAll()
            try? FileManager.default.removeItem(atPath: self.filePath)
            try? FileManager.default.removeItem(atPath: self.overridesFilePath)
            try? FileManager.default.removeItem(atPath: self.fakeMessagesFilePath)
            self.fakeMessagesChangesPromise.set(self.fakeCache)
        }
    }

    private func loadOverridesIfNeeded() {
        if self.didLoadOverrides {
            return
        }
        self.didLoadOverrides = true
        guard let data = FileManager.default.contents(atPath: self.overridesFilePath), let content = String(data: data, encoding: .utf8) else {
            return
        }
        let decoder = JSONDecoder()
        for line in content.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8), let record = try? decoder.decode(LocalOverrideRecord.self, from: lineData) else {
                continue
            }
            let key = self.messageKey(peerId: record.messagePeerId, namespace: record.messageNamespace, id: record.messageId)
            self.overrideCache[key] = record
        }
    }

    private func persistOverrides() {
        let encoder = JSONEncoder()
        var content = ""
        for record in self.overrideCache.values.sorted(by: { $0.date < $1.date }) {
            guard let data = try? encoder.encode(record), let line = String(data: data, encoding: .utf8) else {
                continue
            }
            content.append(line)
            content.append("\n")
        }
        if content.isEmpty {
            try? FileManager.default.removeItem(atPath: self.overridesFilePath)
        } else {
            try? content.data(using: .utf8)?.write(to: URL(fileURLWithPath: self.overridesFilePath), options: [.atomic])
        }
    }

    public func `override`(for messageId: MessageId) -> LocalOverrideRecord? {
        return self.queue.sync {
            self.loadOverridesIfNeeded()
            return self.overrideCache[self.messageKey(peerId: messageId.peerId.toInt64(), namespace: messageId.namespace, id: messageId.id)]
        }
    }

    public func setOverride(_ record: LocalOverrideRecord) {
        self.queue.sync {
            self.loadOverridesIfNeeded()
            let key = self.messageKey(peerId: record.messagePeerId, namespace: record.messageNamespace, id: record.messageId)
            self.overrideCache[key] = record
            self.persistOverrides()
        }
    }

    public func removeOverride(messageId: MessageId) {
        self.queue.sync {
            self.loadOverridesIfNeeded()
            let key = self.messageKey(peerId: messageId.peerId.toInt64(), namespace: messageId.namespace, id: messageId.id)
            if self.overrideCache.removeValue(forKey: key) != nil {
                self.persistOverrides()
            }
        }
    }

    public func allOverrides(in peerId: PeerId) -> [LocalOverrideRecord] {
        return self.queue.sync {
            self.loadOverridesIfNeeded()
            let peerIdValue = peerId.toInt64()
            return self.overrideCache.values.filter { $0.messagePeerId == peerIdValue }.sorted(by: { $0.date < $1.date })
        }
    }

    private func loadFakesIfNeeded() {
        if self.didLoadFakes {
            return
        }
        self.didLoadFakes = true
        if let data = FileManager.default.contents(atPath: self.fakeMessagesFilePath), let records = try? JSONDecoder().decode([FakeMessageRecord].self, from: data) {
            // Older/corrupt files must not be allowed to feed invalid namespaces or duplicate
            // identifiers into message deletion and context-menu lookups.
            var seenIds = Set<String>()
            self.fakeCache = records.filter { record in
                guard !record.id.isEmpty, record.messageNamespace == Namespaces.Message.Local else {
                    return false
                }
                guard !seenIds.contains(record.id) else {
                    return false
                }
                seenIds.insert(record.id)
                return true
            }
        }
        self.fakeMessagesChangesPromise.set(self.fakeCache)
    }

    private func saveFakesLocked() {
        guard let data = try? JSONEncoder().encode(self.fakeCache) else {
            return
        }
        try? data.write(to: URL(fileURLWithPath: self.fakeMessagesFilePath), options: [.atomic])
    }

    public func fakeMessages(in peerId: PeerId) -> [FakeMessageRecord] {
        return self.queue.sync {
            self.loadFakesIfNeeded()
            let peerIdValue = peerId.toInt64()
            return self.fakeCache.filter { $0.messagePeerId == peerIdValue }
        }
    }

    public func fakeMessage(messageId: MessageId) -> FakeMessageRecord? {
        return self.queue.sync {
            self.loadFakesIfNeeded()
            let peerIdValue = messageId.peerId.toInt64()
            return self.fakeCache.first(where: { $0.messagePeerId == peerIdValue && $0.messageNamespace == messageId.namespace && $0.messageId == messageId.id && $0.messageId != 0 })
        }
    }

    public func fakeMessage(id: String) -> FakeMessageRecord? {
        return self.queue.sync {
            self.loadFakesIfNeeded()
            return self.fakeCache.first(where: { $0.id == id })
        }
    }

    public var fakeMessagesChanges: Signal<[FakeMessageRecord], NoError> {
        return Signal { [weak self] subscriber in
            guard let self else {
                return EmptyDisposable
            }
            let disposable = self.fakeMessagesChangesPromise.get().start(next: { value in
                subscriber.putNext(value)
            })
            self.queue.async {
                self.loadFakesIfNeeded()
            }
            return disposable
        }
    }

    public func addFakeMessage(_ record: FakeMessageRecord) {
        self.queue.async {
            self.loadFakesIfNeeded()
            self.fakeCache.removeAll(where: { $0.id == record.id })
            self.fakeCache.append(record)
            self.saveFakesLocked()
            self.fakeMessagesChangesPromise.set(self.fakeCache)
        }
    }

    public func removeFakeMessage(id: String) {
        self.queue.async {
            self.loadFakesIfNeeded()
            self.fakeCache.removeAll(where: { $0.id == id })
            self.saveFakesLocked()
            self.fakeMessagesChangesPromise.set(self.fakeCache)
        }
    }

    public func removeFakeMessages(ids: [String]) {
        guard !ids.isEmpty else {
            return
        }
        self.queue.async {
            self.loadFakesIfNeeded()
            let idSet = Set(ids)
            self.fakeCache.removeAll(where: { idSet.contains($0.id) })
            self.saveFakesLocked()
            self.fakeMessagesChangesPromise.set(self.fakeCache)
        }
    }
}
