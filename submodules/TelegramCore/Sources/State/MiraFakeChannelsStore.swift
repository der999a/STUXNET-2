import Foundation
import SwiftSignalKit
import Postbox

/// A channel that exists only in the local Stuxnet projection.  Its identity
/// is intentionally a string instead of PeerId: fake channels must never be
/// serialised as Telegram peers or sent to the network.
public struct MiraFakeChannel: Codable, Equatable, Identifiable {
    public enum Visibility: String, Codable {
        case publicChannel
        case privateChannel
    }

    public enum Role: String, Codable {
        case owner
        case administrator
        case member
    }

    public struct Post: Codable, Equatable, Identifiable {
        public let id: String
        public var text: String
        public var mediaPath: String?
        public var views: Int64
        public var stars: Int64
        public var reactions: [String: Int64]
        /// Local comment counter used by the channel preview. Optional keeps
        /// older channel snapshots readable without a migration rewrite.
        public var comments: Int64?
        /// Stars assigned through local channel reactions. Optional for
        /// backwards-compatible decoding of the original post schema.
        public var starReactions: Int64?
        public var date: Int32

        public init(id: String = UUID().uuidString,
                    text: String,
                    mediaPath: String? = nil,
                    views: Int64 = 0,
                    stars: Int64 = 0,
                    reactions: [String: Int64] = [:],
                    comments: Int64? = nil,
                    starReactions: Int64? = nil,
                    date: Int32 = MiraFakeChannel.currentTimestamp()) {
            self.id = id
            self.text = text
            self.mediaPath = mediaPath
            self.views = max(0, views)
            self.stars = max(0, stars)
            self.reactions = reactions
            self.comments = comments.map { max(0, $0) }
            self.starReactions = starReactions.map { max(0, $0) }
            self.date = date
        }
    }

    public let id: String
    public var title: String
    public var about: String
    public var avatarPath: String?
    public var visibility: Visibility
    public var username: String?
    public var inviteLink: String?
    public var subscribers: Int64
    public var role: Role
    /// Text shown next to the local account in the channel member list.
    public var adminTag: String?
    /// Optional label rendered for the selected local role (for example
    /// "Owner" or "Editor"). It is deliberately separate from `role`, so a
    /// custom tag does not change the role semantics used by the editor.
    public var roleLabel: String?
    /// Display-only owner identity for a channel constructor. These values
    /// never become Telegram peers or network requests.
    public var ownerName: String?
    public var ownerUsername: String?
    public var starsBalance: Int64
    public var posts: [Post]
    public let createdAt: Int32
    public var updatedAt: Int32

    public init(id: String = UUID().uuidString,
                title: String,
                about: String = "",
                avatarPath: String? = nil,
                visibility: Visibility = .publicChannel,
                username: String? = nil,
                inviteLink: String? = nil,
                subscribers: Int64 = 0,
                role: Role = .owner,
                adminTag: String? = nil,
                roleLabel: String? = nil,
                ownerName: String? = nil,
                ownerUsername: String? = nil,
                starsBalance: Int64 = 0,
                posts: [Post] = [],
                createdAt: Int32 = MiraFakeChannel.currentTimestamp(),
                updatedAt: Int32? = nil) {
        self.id = id
        self.title = title
        self.about = about
        self.avatarPath = avatarPath
        self.visibility = visibility
        self.username = username
        self.inviteLink = inviteLink
        self.subscribers = max(0, subscribers)
        self.role = role
        self.adminTag = adminTag
        self.roleLabel = roleLabel
        self.ownerName = ownerName
        self.ownerUsername = ownerUsername
        self.starsBalance = max(0, starsBalance)
        self.posts = posts
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    public static func currentTimestamp() -> Int32 {
        return Int32(Date().timeIntervalSince1970)
    }
}

public struct MiraFakeChannelsSnapshot: Codable, Equatable {
    public static let currentSchemaVersion = 2
    public let schemaVersion: Int
    public let channels: [MiraFakeChannel]

    public init(schemaVersion: Int = MiraFakeChannelsSnapshot.currentSchemaVersion,
                channels: [MiraFakeChannel] = []) {
        self.schemaVersion = schemaVersion
        self.channels = channels
    }
}

/// Durable account-local fake channel state.  The store is deliberately
/// independent from Postbox and Telegram peers, making it safe to migrate
/// when Telegram changes its channel API or peer representations.
public final class MiraFakeChannelsStore {
    private static let registryQueue = DispatchQueue(label: "org.telegram.mira.fakeChannels.registry")
    private static var registeredStores: [Int64: MiraFakeChannelsStore] = [:]

    public static func register(accountPeerId: PeerId, store: MiraFakeChannelsStore) {
        self.registryQueue.sync {
            self.registeredStores[accountPeerId.toInt64()] = store
        }
    }

    public static func store(for accountPeerId: PeerId) -> MiraFakeChannelsStore? {
        return self.registryQueue.sync { self.registeredStores[accountPeerId.toInt64()] }
    }

    private let queue = DispatchQueue(label: "org.telegram.mira.fakeChannels", qos: .utility)
    private let publicationQueue = DispatchQueue(label: "org.telegram.mira.fakeChannels.publication", qos: .utility)
    private let filePath: String
    private var channelsCache: [MiraFakeChannel] = []
    private var didLoad = false
    private var needsMigrationWrite = false
    private var readOnly = false
    private let changesPromise = ValuePromise<[MiraFakeChannel]>([], ignoreRepeated: true)

    public init(basePath: String) {
        self.filePath = basePath + "/mira-fake-channels.json"
    }

    private func loadIfNeeded() {
        guard !self.didLoad else { return }
        self.didLoad = true
        guard let data = FileManager.default.contents(atPath: self.filePath) else {
            self.publishLocked()
            return
        }

        if let snapshot = try? JSONDecoder().decode(MiraFakeChannelsSnapshot.self, from: data) {
            self.channelsCache = snapshot.channels
            if snapshot.schemaVersion > MiraFakeChannelsSnapshot.currentSchemaVersion {
                self.readOnly = true
            } else {
                self.needsMigrationWrite = snapshot.schemaVersion < MiraFakeChannelsSnapshot.currentSchemaVersion
            }
        } else if let legacy = try? JSONDecoder().decode([MiraFakeChannel].self, from: data) {
            // Early local builds wrote the array directly. Keep those channels
            // usable and upgrade them to the versioned envelope on next write.
            self.channelsCache = legacy
            self.needsMigrationWrite = true
        } else {
            self.readOnly = true
        }
        if self.needsMigrationWrite {
            self.persistLocked()
            self.needsMigrationWrite = false
        }
        self.publishLocked()
    }

    private func persistLocked() {
        let snapshot = MiraFakeChannelsSnapshot(channels: self.channelsCache)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let url = URL(fileURLWithPath: self.filePath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic])
    }

    private func publishLocked() {
        let value = self.channelsCache
        self.publicationQueue.async { [weak self] in self?.changesPromise.set(value) }
    }

    public var changes: Signal<[MiraFakeChannel], NoError> {
        return Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            let disposable = self.changesPromise.get().start(next: { value in
                subscriber.putNext(value)
            })
            self.queue.async { self.loadIfNeeded() }
            return disposable
        }
    }

    public func list() -> [MiraFakeChannel] {
        return self.queue.sync { self.loadIfNeeded(); return self.channelsCache }
    }

    public var isReadOnly: Bool {
        return self.queue.sync { self.loadIfNeeded(); return self.readOnly }
    }

    public func channel(id: String) -> MiraFakeChannel? {
        return self.queue.sync { self.loadIfNeeded(); return self.channelsCache.first(where: { $0.id == id }) }
    }

    /// Returns a stable snapshot of all channels owned by the requested role.
    /// Keeping the filtering here avoids UI code making assumptions about how
    /// channels are persisted and makes multi-channel editors deterministic.
    public func list(role: MiraFakeChannel.Role) -> [MiraFakeChannel] {
        return self.queue.sync {
            self.loadIfNeeded()
            return self.channelsCache.filter { $0.role == role }
        }
    }

    /// Mutates one channel in place while preserving its stable id. This is
    /// useful for list editors that update counters or role labels without
    /// constructing a second copy of the channel.
    public func update(id: String, _ transform: (inout MiraFakeChannel) -> Void) {
        self.queue.sync {
            self.loadIfNeeded()
            guard !self.readOnly else { return }
            guard let index = self.channelsCache.firstIndex(where: { $0.id == id }) else { return }
            var channel = self.channelsCache[index]
            transform(&channel)
            channel.updatedAt = MiraFakeChannel.currentTimestamp()
            self.channelsCache[index] = channel
            self.persistLocked()
            self.publishLocked()
        }
    }

    public func add(_ channel: MiraFakeChannel) {
        self.upsert(channel)
    }

    public func update(_ channel: MiraFakeChannel) {
        self.upsert(channel)
    }

    public func upsert(_ channel: MiraFakeChannel) {
        self.queue.sync {
            self.loadIfNeeded()
            guard !self.readOnly else { return }
            var channel = channel
            channel.updatedAt = MiraFakeChannel.currentTimestamp()
            if let index = self.channelsCache.firstIndex(where: { $0.id == channel.id }) {
                self.channelsCache[index] = channel
            } else {
                self.channelsCache.append(channel)
            }
            self.persistLocked()
            self.publishLocked()
        }
    }

    @discardableResult
    public func remove(id: String) -> Bool {
        return self.queue.sync {
            self.loadIfNeeded()
            guard !self.readOnly else { return false }
            guard let index = self.channelsCache.firstIndex(where: { $0.id == id }) else { return false }
            self.channelsCache.remove(at: index)
            self.persistLocked()
            self.publishLocked()
            return true
        }
    }

    public func addPost(channelId: String, post: MiraFakeChannel.Post) {
        self.queue.sync {
            self.loadIfNeeded()
            guard !self.readOnly else { return }
            guard let index = self.channelsCache.firstIndex(where: { $0.id == channelId }) else { return }
            var channel = self.channelsCache[index]
            channel.posts.removeAll(where: { $0.id == post.id })
            channel.posts.append(post)
            channel.updatedAt = MiraFakeChannel.currentTimestamp()
            self.channelsCache[index] = channel
            self.persistLocked()
            self.publishLocked()
        }
    }

    public func removePost(channelId: String, postId: String) {
        self.queue.sync {
            self.loadIfNeeded()
            guard !self.readOnly else { return }
            guard let index = self.channelsCache.firstIndex(where: { $0.id == channelId }) else { return }
            var channel = self.channelsCache[index]
            channel.posts.removeAll(where: { $0.id == postId })
            channel.updatedAt = MiraFakeChannel.currentTimestamp()
            self.channelsCache[index] = channel
            self.persistLocked()
            self.publishLocked()
        }
    }

    public func clear() {
        self.queue.sync {
            self.loadIfNeeded()
            guard !self.readOnly else { return }
            self.channelsCache.removeAll()
            self.persistLocked()
            self.publishLocked()
        }
    }
}

public struct MiraLocalProfileOverride: Codable, Equatable, Identifiable {
    public let id: String
    public var username: String?
    /// A local display tag (shown with an @ when rendered). This is kept
    /// separate from username so a preview can show an arbitrary tag while
    /// preserving the account's local username override.
    public var tag: String?
    public var phoneNumber: String?
    public var firstName: String?
    public var lastName: String?
    public var updatedAt: Int32

    public init(id: String,
                username: String? = nil,
                tag: String? = nil,
                phoneNumber: String? = nil,
                firstName: String? = nil,
                lastName: String? = nil,
                updatedAt: Int32 = Int32(Date().timeIntervalSince1970)) {
        self.id = id
        self.username = MiraLocalProfileOverride.normalizedHandle(username)
        self.tag = MiraLocalProfileOverride.normalizedHandle(tag)
        self.phoneNumber = phoneNumber
        self.firstName = firstName
        self.lastName = lastName
        self.updatedAt = updatedAt
    }

    private static func normalizedHandle(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutAt = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
        return withoutAt.isEmpty ? nil : withoutAt
    }
}

public struct MiraLocalProfileOverridesSnapshot: Codable, Equatable {
    public static let currentSchemaVersion = 2
    public let schemaVersion: Int
    public let overrides: [MiraLocalProfileOverride]

    public init(schemaVersion: Int = MiraLocalProfileOverridesSnapshot.currentSchemaVersion,
                overrides: [MiraLocalProfileOverride] = []) {
        self.schemaVersion = schemaVersion
        self.overrides = overrides
    }
}

/// UI-only profile projection. Keys are stable local identifiers (account
/// peer id, a contact peer id or a fake channel id), never server mutations.
public final class MiraLocalProfileOverridesStore {
    private let queue = DispatchQueue(label: "org.telegram.mira.profileOverrides", qos: .utility)
    private let publicationQueue = DispatchQueue(label: "org.telegram.mira.profileOverrides.publication", qos: .utility)
    private let filePath: String
    private var overridesCache: [MiraLocalProfileOverride] = []
    private var didLoad = false
    private var needsMigrationWrite = false
    private var readOnly = false
    private let changesPromise = ValuePromise<[MiraLocalProfileOverride]>([], ignoreRepeated: true)

    public init(basePath: String) { self.filePath = basePath + "/mira-local-profile-overrides.json" }

    private func loadIfNeeded() {
        guard !self.didLoad else { return }
        self.didLoad = true
        guard let data = FileManager.default.contents(atPath: self.filePath) else {
            self.publishLocked()
            return
        }
        if let snapshot = try? JSONDecoder().decode(MiraLocalProfileOverridesSnapshot.self, from: data) {
            self.overridesCache = snapshot.overrides
            if snapshot.schemaVersion > MiraLocalProfileOverridesSnapshot.currentSchemaVersion {
                self.readOnly = true
            } else {
                self.needsMigrationWrite = snapshot.schemaVersion < MiraLocalProfileOverridesSnapshot.currentSchemaVersion
            }
        } else if let legacy = try? JSONDecoder().decode([MiraLocalProfileOverride].self, from: data) {
            self.overridesCache = legacy
            self.needsMigrationWrite = true
        } else {
            self.readOnly = true
        }
        if self.needsMigrationWrite {
            self.persistLocked()
            self.needsMigrationWrite = false
        }
        self.publishLocked()
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(MiraLocalProfileOverridesSnapshot(overrides: self.overridesCache)) else { return }
        let url = URL(fileURLWithPath: self.filePath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic])
    }

    private func publishLocked() {
        let value = self.overridesCache
        self.publicationQueue.async { [weak self] in self?.changesPromise.set(value) }
    }

    public var changes: Signal<[MiraLocalProfileOverride], NoError> {
        return Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            let disposable = self.changesPromise.get().start(next: { value in
                subscriber.putNext(value)
            })
            self.queue.async { self.loadIfNeeded() }
            return disposable
        }
    }

    public func list() -> [MiraLocalProfileOverride] {
        return self.queue.sync { self.loadIfNeeded(); return self.overridesCache }
    }

    public var isReadOnly: Bool {
        return self.queue.sync { self.loadIfNeeded(); return self.readOnly }
    }

    public func `override`(forKey key: String) -> MiraLocalProfileOverride? {
        return self.queue.sync { self.loadIfNeeded(); return self.overridesCache.first(where: { $0.id == key }) }
    }

    public func set(_ value: MiraLocalProfileOverride) {
        self.queue.sync {
            self.loadIfNeeded()
            guard !self.readOnly else { return }
            if let index = self.overridesCache.firstIndex(where: { $0.id == value.id }) {
                self.overridesCache[index] = value
            } else {
                self.overridesCache.append(value)
            }
            self.persistLocked()
            self.publishLocked()
        }
    }

    @discardableResult
    public func remove(forKey key: String) -> Bool {
        return self.queue.sync {
            self.loadIfNeeded()
            guard !self.readOnly else { return false }
            guard let index = self.overridesCache.firstIndex(where: { $0.id == key }) else { return false }
            self.overridesCache.remove(at: index)
            self.persistLocked()
            self.publishLocked()
            return true
        }
    }

    /// Returns the override when present and otherwise preserves the server
    /// value. This keeps call sites explicit about projection boundaries.
    public func effectiveUsername(forKey key: String, fallback: String?) -> String? {
        let value = self.`override`(forKey: key)
        return value?.username ?? fallback
    }

    public func effectiveTag(forKey key: String, fallback: String?) -> String? {
        let value = self.`override`(forKey: key)
        return value?.tag ?? fallback
    }

    public func effectivePhoneNumber(forKey key: String, fallback: String?) -> String? {
        return self.`override`(forKey: key)?.phoneNumber ?? fallback
    }

    public func effectiveDisplayName(forKey key: String, fallback: String?) -> String? {
        guard let value = self.`override`(forKey: key) else { return fallback }
        let name = [value.firstName, value.lastName].compactMap { $0 }.joined(separator: " ")
        return name.isEmpty ? fallback : name
    }

    public func clear() {
        self.queue.sync {
            self.loadIfNeeded()
            guard !self.readOnly else { return }
            self.overridesCache.removeAll()
            self.persistLocked()
            self.publishLocked()
        }
    }
}
