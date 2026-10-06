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
    private var cache: [String: [MiraMessageEditRecord]] = [:]
    private var didLoad = false
    private var overrideCache: [String: LocalOverrideRecord] = [:]
    private var didLoadOverrides = false

    public init(basePath: String) {
        self.filePath = basePath + "/mira-message-history.jsonl"
        self.overridesFilePath = basePath + "/mira-local-overrides.jsonl"
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
            try? FileManager.default.removeItem(atPath: self.filePath)
            try? FileManager.default.removeItem(atPath: self.overridesFilePath)
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
}
