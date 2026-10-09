import Foundation
import Postbox
import SwiftSignalKit

public struct MiraFakeGift: Codable, Equatable {
    public enum Kind: String, Codable {
        case regular
        case uniqueBySlug
        case uniqueById
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case giftId
        case slug
        case uniqueNumber
        case fromPeerId
        case fromName
        case caption
        case date
        case isHidden
        case isSaved
        case showInChat
        case chatMessagePeerId
        case chatMessageId
        case giftSnapshot
    }

    public var id: String
    public var kind: Kind
    public var giftId: Int64?
    public var slug: String?
    public var uniqueNumber: Int32?
    public var fromPeerId: Int64?
    public var fromName: String?
    public var caption: String?
    public var date: Int32
    public var isHidden: Bool
    public var isSaved: Bool
    public var showInChat: Bool

    // Local "gift received" message location, set after insertion so it can be deleted again.
    public var chatMessagePeerId: Int64?
    public var chatMessageId: Int32?

    // Resolved gift data cached at add-time (or after first successful resolution),
    // so the profile shelf renders without any extra network requests.
    public var giftSnapshot: StarGift?

    public init(
        id: String = UUID().uuidString,
        kind: Kind,
        giftId: Int64? = nil,
        slug: String? = nil,
        uniqueNumber: Int32? = nil,
        fromPeerId: Int64? = nil,
        fromName: String? = nil,
        caption: String? = nil,
        date: Int32,
        isHidden: Bool = false,
        isSaved: Bool = false,
        showInChat: Bool = false,
        chatMessagePeerId: Int64? = nil,
        chatMessageId: Int32? = nil,
        giftSnapshot: StarGift? = nil
    ) {
        self.id = id
        self.kind = kind
        self.giftId = giftId
        self.slug = slug
        self.uniqueNumber = uniqueNumber
        self.fromPeerId = fromPeerId
        self.fromName = fromName
        self.caption = caption
        self.date = date
        self.isHidden = isHidden
        self.isSaved = isSaved
        self.showInChat = showInChat
        self.chatMessagePeerId = chatMessagePeerId
        self.chatMessageId = chatMessageId
        self.giftSnapshot = giftSnapshot
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.kind = try container.decode(Kind.self, forKey: .kind)
        self.giftId = try container.decodeIfPresent(Int64.self, forKey: .giftId)
        self.slug = try container.decodeIfPresent(String.self, forKey: .slug)
        self.uniqueNumber = try container.decodeIfPresent(Int32.self, forKey: .uniqueNumber)
        self.fromPeerId = try container.decodeIfPresent(Int64.self, forKey: .fromPeerId)
        self.fromName = try container.decodeIfPresent(String.self, forKey: .fromName)
        self.caption = try container.decodeIfPresent(String.self, forKey: .caption)
        self.date = try container.decodeIfPresent(Int32.self, forKey: .date) ?? 0
        self.isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        self.isSaved = try container.decodeIfPresent(Bool.self, forKey: .isSaved) ?? false
        self.showInChat = try container.decodeIfPresent(Bool.self, forKey: .showInChat) ?? false
        self.chatMessagePeerId = try container.decodeIfPresent(Int64.self, forKey: .chatMessagePeerId)
        self.chatMessageId = try container.decodeIfPresent(Int32.self, forKey: .chatMessageId)
        self.giftSnapshot = try container.decodeIfPresent(StarGift.self, forKey: .giftSnapshot)
    }

    // Deterministic, collision-safe savedId for StarGiftReference.peer (Swift's hashValue is randomized per launch).
    public var stableSavedId: Int64 {
        var hash: UInt64 = 14695981039346656037
        for byte in self.id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return Int64(bitPattern: (hash & 0x0000ffffffffffff) | 0x1111000000000000)
    }

    public static func isLocalSavedId(_ id: Int64) -> Bool {
        return UInt64(bitPattern: id) & 0xffff000000000000 == 0x1111000000000000
    }

    /// Settings historically persisted a raw Telegram user id while newer
    /// entries may contain the packed PeerId value. Normalize both forms
    /// before looking up a sender so malformed values never reach PeerId's
    /// packed initializer in the message/profile projection.
    public static func peerId(fromStoredValue value: Int64) -> PeerId? {
        guard value > 0 else {
            return nil
        }
        if value <= Int64(Int32.max) {
            return PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(value))
        }
        let bits = UInt64(bitPattern: value)
        let namespaceBits = UInt32((bits >> 32) & 0x7)
        let namespace = PeerId.Namespace._internalFromInt32Value(Int32(bitPattern: namespaceBits))
        guard namespace == Namespaces.Peer.CloudUser || namespace == Namespaces.Peer.CloudGroup || namespace == Namespaces.Peer.CloudChannel || namespace == Namespaces.Peer.SecretChat else {
            return nil
        }
        let idValue: Int64
        if namespace == Namespaces.Peer.SecretChat && ((bits >> 35) & 0xffffffff) == 0 {
            // Match Postbox's legacy namespace-3 codec: its low word is a
            // signed Int32, including negative ids.
            idValue = Int64(Int32(bitPattern: UInt32(bits & 0xffffffff)))
        } else {
            let idBits = ((bits >> 35) << 32) | (bits & 0xffffffff)
            idValue = Int64(bitPattern: idBits)
        }
        guard idValue >= -0x007fffffffffffff && idValue <= 0x00ffffffffffffff else {
            return nil
        }
        return PeerId(namespace: namespace, id: PeerId.Id._internalFromInt64Value(idValue))
    }
}

public final class MiraFakeGiftsStore {
    private static let registryQueue = DispatchQueue(label: "org.telegram.mira.fakeGiftsStore.registry")
    private static var registeredStores: [Int64: MiraFakeGiftsStore] = [:]

    public static func register(accountPeerId: PeerId, store: MiraFakeGiftsStore) {
        self.registryQueue.sync {
            self.registeredStores[accountPeerId.toInt64()] = store
        }
    }

    public static func store(for accountPeerId: PeerId) -> MiraFakeGiftsStore? {
        return self.registryQueue.sync {
            return self.registeredStores[accountPeerId.toInt64()]
        }
    }

    private let queue = DispatchQueue(label: "org.telegram.mira.fakeGiftsStore", qos: .utility)
    // ValuePromise delivers synchronously on the thread that calls `set`. Never
    // publish while holding `queue`: subscribers commonly call `list()` from
    // their callback, and that would synchronously wait on this queue again.
    private let publicationQueue = DispatchQueue(label: "org.telegram.mira.fakeGiftsStore.publication", qos: .utility)
    private let filePath: String
    private var cache: [MiraFakeGift] = []
    private var didLoad = false

    private let changesPromise = ValuePromise<[MiraFakeGift]>([], ignoreRepeated: true)

    private func publishLocked() {
        let snapshot = self.cache
        self.publicationQueue.async { [weak self] in
            self?.changesPromise.set(snapshot)
        }
    }

    public init(basePath: String) {
        self.filePath = basePath + "/mira-fake-gifts.json"
    }

    private func loadIfNeeded() {
        if self.didLoad {
            return
        }
        self.didLoad = true
        if let data = FileManager.default.contents(atPath: self.filePath), let gifts = try? JSONDecoder().decode([MiraFakeGift].self, from: data) {
            // Older builds could append the same entry more than once when an edit
            // raced an asynchronous insert. Keep the newest copy by id so the
            // profile and chat projections remain one-to-one.
            var uniqueGifts: [MiraFakeGift] = []
            var indexes: [String: Int] = [:]
            for gift in gifts {
                if let index = indexes[gift.id] {
                    uniqueGifts[index] = gift
                } else {
                    indexes[gift.id] = uniqueGifts.count
                    uniqueGifts.append(gift)
                }
            }
            self.cache = uniqueGifts
            if self.cache.count != gifts.count {
                self.saveLocked()
            }
        }
        self.publishLocked()
    }

    private func saveLocked() {
        guard let data = try? JSONEncoder().encode(self.cache) else {
            return
        }
        try? data.write(to: URL(fileURLWithPath: self.filePath), options: [.atomic])
    }

    public func list() -> [MiraFakeGift] {
        return self.queue.sync {
            self.loadIfNeeded()
            return self.cache
        }
    }

    public var changes: Signal<[MiraFakeGift], NoError> {
        return Signal { [weak self] subscriber in
            guard let self else {
                return EmptyDisposable
            }
            let disposable = self.changesPromise.get().start(next: { value in
                subscriber.putNext(value)
            })
            self.queue.async {
                self.loadIfNeeded()
            }
            return disposable
        }
    }

    public func add(_ gift: MiraFakeGift) {
        self.upsert(gift)
    }

    public func update(_ gift: MiraFakeGift) {
        self.upsert(gift)
    }

    /// Inserts a new entry or replaces the existing entry with the same stable id.
    /// Fake gift settings are edited from an asynchronous UI flow, so treating
    /// update as a strict "must already exist" operation can silently lose edits.
    public func upsert(_ gift: MiraFakeGift) {
        self.queue.async {
            self.loadIfNeeded()
            if let index = self.cache.firstIndex(where: { $0.id == gift.id }) {
                self.cache[index] = gift
            } else {
                self.cache.append(gift)
            }
            self.saveLocked()
            self.publishLocked()
        }
    }

    public func remove(id: String) {
        self.queue.async {
            self.loadIfNeeded()
            self.cache.removeAll(where: { $0.id == id })
            self.saveLocked()
            self.publishLocked()
        }
    }

    public func updateSnapshot(id: String, snapshot: StarGift) {
        self.queue.async {
            self.loadIfNeeded()
            if let index = self.cache.firstIndex(where: { $0.id == id }), self.cache[index].giftSnapshot == nil {
                self.cache[index].giftSnapshot = snapshot
                self.saveLocked()
                self.publishLocked()
            }
        }
    }

    /// Returns true when a saved-gift reference belongs to this local store.
    /// Synthetic gifts must never be sent to the Telegram payments API: their
    /// saved ids only exist in the local profile projection.
    public func isLocalReference(_ reference: StarGiftReference, accountPeerId: PeerId) -> Bool {
        guard case let .peer(peerId, savedId) = reference, peerId == accountPeerId else {
            return false
        }
        // Keep stale references local after deletion as well: an already-open
        // gift sheet must not send its synthetic id to the payments API.
        return MiraFakeGift.isLocalSavedId(savedId)
    }

    /// Applies a local profile change without touching the network.
    public func updateLocalReference(_ reference: StarGiftReference, accountPeerId: PeerId, added: Bool? = nil, pinned: Bool? = nil) {
        guard case let .peer(peerId, savedId) = reference, peerId == accountPeerId else {
            return
        }
        self.queue.async {
            self.loadIfNeeded()
            guard let index = self.cache.firstIndex(where: { $0.stableSavedId == savedId }) else {
                return
            }
            var gift = self.cache[index]
            if let added {
                gift.isHidden = !added
                if !added {
                    gift.isSaved = false
                }
            }
            if let pinned {
                gift.isSaved = pinned
                if pinned {
                    gift.isHidden = false
                }
            }
            guard gift != self.cache[index] else {
                return
            }
            self.cache[index] = gift
            self.saveLocked()
            self.publishLocked()
        }
    }

    public func clear() {
        self.queue.async {
            self.didLoad = true
            self.cache.removeAll()
            try? FileManager.default.removeItem(atPath: self.filePath)
            self.publishLocked()
        }
    }

    /// Clears fake gifts and their local-only chat projections together. The
    /// plain `clear()` method remains for callers that only need to reset data.
    public func clear(account: Account) {
        let entries = self.list()
        let messageIds = entries.compactMap { entry -> MessageId? in
            guard let peerId = entry.chatMessagePeerId, let id = entry.chatMessageId else {
                return nil
            }
            return MessageId(peerId: EnginePeer.Id(peerId), namespace: Namespaces.Message.Local, id: id)
        }
        let _ = account.postbox.transaction { transaction in
            if !messageIds.isEmpty {
                transaction.deleteMessages(messageIds, forEachMedia: nil)
            }
        }.start(completed: { [weak self] in
            self?.clear()
        })
    }
}

extension MiraFakeGiftsStore {
    public func resolvedProfileGifts(account: Account) -> Signal<[ProfileGiftsContext.State.StarGift], NoError> {
        return self.resolvedProfileGifts(account: account, entries: self.list())
    }

    public func resolvedProfileGifts(account: Account, entries: [MiraFakeGift]) -> Signal<[ProfileGiftsContext.State.StarGift], NoError> {
        if entries.isEmpty {
            return .single([])
        }
        return combineLatest(entries.map { self.resolveEntry($0, account: account) })
        |> map { values in
            return values.compactMap { $0 }
        }
    }

    private func resolveEntry(_ entry: MiraFakeGift, account: Account) -> Signal<ProfileGiftsContext.State.StarGift?, NoError> {
        let giftSignal: Signal<StarGift?, NoError>
        if let snapshot = entry.giftSnapshot {
            giftSignal = .single(snapshot)
        } else {
            switch entry.kind {
            case .regular:
                if let giftId = entry.giftId {
                    giftSignal = _internal_cachedStarGifts(postbox: account.postbox)
                    |> take(1)
                    |> map { list -> StarGift? in
                        return list?.items.first(where: { $0.giftId == giftId })
                    }
                } else {
                    giftSignal = .single(nil)
                }
            case .uniqueBySlug:
                if let slug = entry.slug, !slug.isEmpty {
                    giftSignal = _internal_getUniqueStarGift(account: account, slug: slug)
                    |> map { gift -> StarGift? in
                        return .unique(gift)
                    }
                    |> `catch` { _ -> Signal<StarGift?, NoError> in
                        return .single(nil)
                    }
                } else {
                    giftSignal = .single(nil)
                }
            case .uniqueById:
                giftSignal = .single(nil)
            }
        }

        return giftSignal
        |> mapToSignal { gift -> Signal<ProfileGiftsContext.State.StarGift?, NoError> in
            guard let gift else {
                return .single(nil)
            }
            if entry.giftSnapshot == nil {
                self.updateSnapshot(id: entry.id, snapshot: gift)
            }
            return account.postbox.transaction { transaction -> ProfileGiftsContext.State.StarGift in
                var fromPeer: EnginePeer?
                if let fromPeerId = entry.fromPeerId, let normalizedPeerId = MiraFakeGift.peerId(fromStoredValue: fromPeerId) {
                    fromPeer = transaction.getPeer(normalizedPeerId).flatMap { EnginePeer($0) }
                }

                // A gift sender is rendered as a user in Telegram's gift
                // bubble. Treat groups/channels/secret chats as unresolved so
                // a malformed sender id cannot produce an invalid local
                // message author or peer projection.
                if let resolvedFromPeer = fromPeer {
                    switch resolvedFromPeer {
                    case .user:
                        break
                    case .legacyGroup, .channel, .community, .secretChat:
                        fromPeer = nil
                    }
                }
                let reference: StarGiftReference
                switch gift {
                case .unique:
                    // Both regular and unique fake gifts are local objects.
                    // A slug reference would be interpreted as a real server
                    // gift by GiftViewScreen and could trigger network actions.
                    reference = .peer(peerId: account.peerId, id: entry.stableSavedId)
                case .generic:
                    reference = .peer(peerId: account.peerId, id: entry.stableSavedId)
                }
                return ProfileGiftsContext.State.StarGift(
                    gift: gift,
                    reference: reference,
                    fromPeer: fromPeer,
                    date: entry.date,
                    text: entry.caption,
                    entities: nil,
                    nameHidden: false,
                    savedToProfile: !entry.isHidden || entry.isSaved,
                    pinnedToTop: entry.isSaved,
                    convertStars: nil,
                    canUpgrade: false,
                    canExportDate: nil,
                    upgradeStars: nil,
                    transferStars: nil,
                    canTransferDate: nil,
                    canResaleDate: nil,
                    collectionIds: nil,
                    prepaidUpgradeHash: nil,
                    upgradeSeparate: false,
                    dropOriginalDetailsStars: nil,
                    number: nil,
                    isRefunded: false,
                    canCraftAt: nil
                )
            }
        }
    }
}

extension MiraFakeGiftsStore {
    // Inserts a local-only "gift received" action message (same TelegramMediaAction payload as a real one)
    // into the sender's chat, or into Saved Messages when there is no resolvable sender.
    // Returns the entry updated with chatMessagePeerId/chatMessageId for later deletion.
    public func insertChatMessage(account: Account, entry: MiraFakeGift) -> Signal<MiraFakeGift, NoError> {
        if entry.chatMessageId != nil {
            return .single(entry)
        }
        return self.resolveEntry(entry, account: account)
        |> mapToSignal { resolved -> Signal<MiraFakeGift, NoError> in
            guard let resolved else {
                return .single(entry)
            }
            var entry = entry
            return account.postbox.transaction { transaction -> MiraFakeGift in
                var fromPeer: EnginePeer?
                if let fromPeerId = entry.fromPeerId, let normalizedPeerId = MiraFakeGift.peerId(fromStoredValue: fromPeerId) {
                    fromPeer = transaction.getPeer(normalizedPeerId).flatMap { EnginePeer($0) }
                }

                if let resolvedFromPeer = fromPeer {
                    switch resolvedFromPeer {
                    case .user:
                        break
                    case .legacyGroup, .channel, .community, .secretChat:
                        fromPeer = nil
                    }
                }

                let chatPeerId: PeerId
                let authorId: PeerId
                if let fromPeer, fromPeer.id != account.peerId {
                    chatPeerId = fromPeer.id
                    authorId = fromPeer.id
                } else {
                    chatPeerId = account.peerId
                    authorId = fromPeer?.id ?? account.peerId
                }

                let senderId: EnginePeer.Id? = authorId == account.peerId ? nil : authorId
                let action: TelegramMediaActionType
                switch resolved.gift {
                case .generic:
                    action = .starGift(
                        gift: resolved.gift,
                        convertStars: nil,
                        text: entry.caption,
                        entities: nil,
                        nameHidden: false,
                        savedToProfile: !entry.isHidden || entry.isSaved,
                        converted: false,
                        upgraded: false,
                        canUpgrade: false,
                        upgradeStars: nil,
                        isRefunded: false,
                        isPrepaidUpgrade: false,
                        upgradeMessageId: nil,
                        peerId: account.peerId,
                        senderId: senderId,
                        savedId: entry.stableSavedId,
                        prepaidUpgradeHash: nil,
                        giftMessageId: nil,
                        upgradeSeparate: false,
                        isAuctionAcquired: false,
                        toPeerId: nil,
                        number: nil
                    )
                case .unique:
                    action = .starGiftUnique(
                        gift: resolved.gift,
                        isUpgrade: false,
                        isTransferred: false,
                        savedToProfile: !entry.isHidden || entry.isSaved,
                        canExportDate: nil,
                        transferStars: nil,
                        isRefunded: false,
                        isPrepaidUpgrade: false,
                        peerId: account.peerId,
                        senderId: senderId,
                        savedId: entry.stableSavedId,
                        resaleAmount: nil,
                        canTransferDate: nil,
                        canResaleDate: nil,
                        dropOriginalDetailsStars: nil,
                        assigned: true,
                        fromOffer: false,
                        canCraftAt: nil,
                        isCrafted: false
                    )
                }

                var flags = StoreMessageFlags()
                if chatPeerId != account.peerId {
                    flags.insert(.Incoming)
                }
                let message = StoreMessage(
                    peerId: chatPeerId,
                    namespace: Namespaces.Message.Local,
                    customStableId: nil,
                    globallyUniqueId: entry.stableSavedId,
                    groupingKey: nil,
                    threadId: nil,
                    timestamp: entry.date,
                    flags: flags,
                    tags: [],
                    globalTags: [],
                    localTags: [],
                    forwardInfo: nil,
                    authorId: authorId,
                    text: "",
                    attributes: [],
                    media: [TelegramMediaAction(action: action)]
                )
                let mapping = transaction.addMessages([message], location: .Random)
                if let messageId = mapping[entry.stableSavedId] {
                    entry.chatMessagePeerId = messageId.peerId.toInt64()
                    entry.chatMessageId = messageId.id
                }
                return entry
            }
        }
    }

    public func deleteChatMessageSignal(account: Account, entry: MiraFakeGift) -> Signal<Void, NoError> {
        guard let chatMessageId = entry.chatMessageId, let chatMessagePeerId = entry.chatMessagePeerId else {
            return .single(())
        }
        return account.postbox.transaction { transaction in
            transaction.deleteMessages([MessageId(peerId: EnginePeer.Id(chatMessagePeerId), namespace: Namespaces.Message.Local, id: chatMessageId)], forEachMedia: nil)
        }
    }

    public func deleteChatMessage(account: Account, entry: MiraFakeGift) {
        let _ = self.deleteChatMessageSignal(account: account, entry: entry).start()
    }
}
