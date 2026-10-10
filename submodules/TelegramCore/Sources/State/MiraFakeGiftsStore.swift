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
        case fromPeerIdIsPacked
        case fromName
        case caption
        case date
        case isHidden
        case isSaved
        case showInChat
        case transferStars
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
    // nil denotes legacy entries that mixed raw user ids and packed PeerIds.
    public var fromPeerIdIsPacked: Bool?
    public var fromName: String?
    public var caption: String?
    public var date: Int32
    public var isHidden: Bool
    public var isSaved: Bool
    public var showInChat: Bool
    /// Optional local-only transfer fee. Nil preserves the old free-transfer
    /// behaviour; when set, the fake Stars ledger debits it atomically.
    public var transferStars: Int64?

    // Local "gift received" message location, set after insertion so it can be deleted again.
    public var chatMessagePeerId: Int64?
    public var chatMessageId: Int32?

    // Resolved gift data cached at add-time (or after first successful resolution),
    // so the profile shelf renders without any extra network requests.
    public var giftSnapshot: StarGift?

    /// The persisted kind is authoritative for fake gifts.  The snapshot can
    /// be missing while a catalog item is being resolved, so callers should
    /// use this instead of inferring NFT state from optional fields.
    public var isUnique: Bool {
        switch self.kind {
        case .regular:
            return false
        case .uniqueBySlug, .uniqueById:
            return true
        }
    }

    public init(
        id: String = UUID().uuidString,
        kind: Kind,
        giftId: Int64? = nil,
        slug: String? = nil,
        uniqueNumber: Int32? = nil,
        fromPeerId: Int64? = nil,
        fromPeerIdIsPacked: Bool? = nil,
        fromName: String? = nil,
        caption: String? = nil,
        date: Int32,
        isHidden: Bool = false,
        isSaved: Bool = false,
        showInChat: Bool = false,
        transferStars: Int64? = nil,
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
        self.fromPeerIdIsPacked = fromPeerIdIsPacked
        self.fromName = fromName
        self.caption = caption
        self.date = date
        self.isHidden = isHidden
        self.isSaved = isSaved
        self.showInChat = showInChat
        self.transferStars = transferStars.map { max(0, $0) }
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
        self.fromPeerIdIsPacked = try container.decodeIfPresent(Bool.self, forKey: .fromPeerIdIsPacked)
        self.fromName = try container.decodeIfPresent(String.self, forKey: .fromName)
        self.caption = try container.decodeIfPresent(String.self, forKey: .caption)
        self.date = try container.decodeIfPresent(Int32.self, forKey: .date) ?? 0
        self.isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        self.isSaved = try container.decodeIfPresent(Bool.self, forKey: .isSaved) ?? false
        self.showInChat = try container.decodeIfPresent(Bool.self, forKey: .showInChat) ?? false
        self.transferStars = try container.decodeIfPresent(Int64.self, forKey: .transferStars).map { max(0, $0) }
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
    public static func peerId(fromStoredValue value: Int64, isPacked: Bool? = nil) -> PeerId? {
        guard value > 0 else {
            return nil
        }
        if isPacked == false || (isPacked == nil && value <= Int64(Int32.max)) {
            guard value <= 0x00ffffffffffffff else {
                return nil
            }
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
            guard let value = entry.chatMessagePeerId, let peerId = MiraMessageHistoryStore.peerId(fromPackedValue: value), let id = entry.chatMessageId else {
                return nil
            }
            return MessageId(peerId: peerId, namespace: Namespaces.Message.Local, id: id)
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
                if let fromPeerId = entry.fromPeerId, let normalizedPeerId = MiraFakeGift.peerId(fromStoredValue: fromPeerId, isPacked: entry.fromPeerIdIsPacked) {
                    fromPeer = transaction.getPeer(normalizedPeerId).flatMap { EnginePeer($0) }
                }
                if entry.fromPeerIdIsPacked == nil, let rawId = entry.fromPeerId, let userId = MiraFakeGift.peerId(fromStoredValue: rawId, isPacked: false), let user = transaction.getPeer(userId).flatMap(EnginePeer.init), case .user = user {
                    fromPeer = user
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
                var projectedGift = gift
                if case let .unique(uniqueGift) = gift {
                    var attributes = uniqueGift.attributes.filter { $0.attributeType != .originalInfo }
                    attributes.append(.originalInfo(senderPeerId: fromPeer?.id, recipientPeerId: account.peerId, date: entry.date, text: entry.caption, entities: nil))
                    // Keep Telegram's model/pattern/backdrop assets, while the
                    // local sender and recipient drive avatars and profile links.
                    projectedGift = .unique(StarGift.UniqueGift(
                        id: uniqueGift.id, giftId: uniqueGift.giftId, title: uniqueGift.title, number: uniqueGift.number, slug: uniqueGift.slug,
                        owner: .peerId(account.peerId), attributes: attributes, availability: uniqueGift.availability,
                        giftAddress: nil, resellAmounts: nil, resellForTonOnly: false, releasedBy: uniqueGift.releasedBy,
                        valueAmount: uniqueGift.valueAmount, valueCurrency: uniqueGift.valueCurrency, valueUsdAmount: uniqueGift.valueUsdAmount,
                        flags: uniqueGift.flags, themePeerId: uniqueGift.themePeerId, peerColor: uniqueGift.peerColor, hostPeerId: nil,
                        minOfferStars: nil, craftChancePermille: uniqueGift.craftChancePermille
                    ))
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
                // Keep the server-provided values for ordinary gifts.  These
                // values drive Telegram's "keep or convert" copy and the
                // conversion action; leaving them nil made local regular
                // gifts look like NFTs and silently removed that UI.
                let genericGift: StarGift.Gift? = {
                    if case let .generic(genericGift) = projectedGift {
                        return genericGift
                    }
                    return nil
                }()
                return ProfileGiftsContext.State.StarGift(
                    gift: projectedGift,
                    reference: reference,
                    fromPeer: fromPeer,
                    date: entry.date,
                    text: entry.caption,
                    entities: nil,
                    nameHidden: false,
                    savedToProfile: !entry.isHidden || entry.isSaved,
                    pinnedToTop: entry.isSaved,
                    convertStars: genericGift.flatMap { $0.convertStars > 0 ? $0.convertStars : nil },
                    canUpgrade: genericGift?.upgradeStars != nil,
                    canExportDate: nil,
                    upgradeStars: genericGift?.upgradeStars,
                    // Local NFTs can be transferred through the same UI as a
                    // Telegram NFT. A zero fee keeps this operation local and
                    // prevents the synthetic reference from reaching the API.
                    transferStars: entry.isUnique ? 0 : nil,
                    canTransferDate: nil,
                    canResaleDate: nil,
                    collectionIds: nil,
                    prepaidUpgradeHash: nil,
                    upgradeSeparate: false,
                    dropOriginalDetailsStars: nil,
                    number: {
                        if case let .unique(uniqueGift) = projectedGift {
                            return uniqueGift.number
                        }
                        return nil
                    }(),
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
    public func insertChatMessage(account: Account, entry: MiraFakeGift, forcedChatPeerId: PeerId? = nil) -> Signal<MiraFakeGift, NoError> {
        // A persisted entry can outlive its Postbox message (for example after
        // history cleanup, an interrupted migration, or a previous build that
        // used a different local id). Do not trust the cached id blindly: a
        // missing message leaves the chat list with a stale projection and the
        // next fake-gift edit can never repair it.
        if let chatMessageId = entry.chatMessageId,
           let storedPeerId = entry.chatMessagePeerId,
           let chatMessagePeerId = MiraMessageHistoryStore.peerId(fromPackedValue: storedPeerId) {
            let messageId = MessageId(peerId: chatMessagePeerId, namespace: Namespaces.Message.Local, id: chatMessageId)
            return account.postbox.transaction { transaction -> Bool in
                return transaction.getMessage(messageId)?.globallyUniqueId == entry.stableSavedId
            }
            |> mapToSignal { exists -> Signal<MiraFakeGift, NoError> in
                if exists {
                    return .single(entry)
                }
                var repairedEntry = entry
                repairedEntry.chatMessagePeerId = nil
                repairedEntry.chatMessageId = nil
                return self.insertChatMessage(account: account, entry: repairedEntry)
            }
        } else if entry.chatMessageId != nil || entry.chatMessagePeerId != nil {
            // Clear malformed legacy references before attempting a fresh
            // insertion. This also prevents invalid packed PeerIds from
            // reaching Postbox's debug assertions.
            var repairedEntry = entry
            repairedEntry.chatMessagePeerId = nil
            repairedEntry.chatMessageId = nil
            return self.insertChatMessage(account: account, entry: repairedEntry)
        }
        return self.resolveEntry(entry, account: account)
        |> mapToSignal { resolved -> Signal<MiraFakeGift, NoError> in
            guard let resolved else {
                return .single(entry)
            }
            var entry = entry
            return account.postbox.transaction { transaction -> MiraFakeGift in
                var fromPeer: EnginePeer?
                if let fromPeerId = entry.fromPeerId, let normalizedPeerId = MiraFakeGift.peerId(fromStoredValue: fromPeerId, isPacked: entry.fromPeerIdIsPacked) {
                    fromPeer = transaction.getPeer(normalizedPeerId).flatMap { EnginePeer($0) }
                }
                if entry.fromPeerIdIsPacked == nil, let rawId = entry.fromPeerId, let userId = MiraFakeGift.peerId(fromStoredValue: rawId, isPacked: false), let user = transaction.getPeer(userId).flatMap(EnginePeer.init), case .user = user {
                    fromPeer = user
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
                if let forcedChatPeerId {
                    // Transfers are authored by the local account but belong
                    // in the selected recipient chat, not Saved Messages.
                    chatPeerId = forcedChatPeerId
                    authorId = account.peerId
                } else if let fromPeer, fromPeer.id != account.peerId {
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
                    let genericGift: StarGift.Gift? = {
                        if case let .generic(value) = resolved.gift {
                            return value
                        }
                        return nil
                    }()
                    action = .starGift(
                        gift: resolved.gift,
                        // Preserve the catalog's conversion value in the
                        // action message as well as in the profile projection.
                        // GiftViewScreen reads this field when opened from a
                        // chat, so fake regular gifts behave like Telegram
                        // gifts in both entry points.
                        convertStars: genericGift.flatMap { $0.convertStars > 0 ? $0.convertStars : nil },
                        text: entry.caption,
                        entities: nil,
                        nameHidden: false,
                        savedToProfile: !entry.isHidden || entry.isSaved,
                        converted: false,
                        upgraded: false,
                        canUpgrade: genericGift?.upgradeStars != nil,
                        upgradeStars: genericGift?.upgradeStars,
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
                        transferStars: entry.isUnique ? 0 : nil,
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
                // If an earlier process was interrupted after adding the
                // Postbox row but before persisting its ids, the cached
                // reference is empty and a retry would otherwise leave two
                // identical gift actions in the chat. Remove only our local
                // stable-id projection before inserting the replacement.
                var staleMessageIds: [MessageId] = []
                transaction.withAllMessages(peerId: chatPeerId, namespace: Namespaces.Message.Local) { existingMessage in
                    if existingMessage.globallyUniqueId == entry.stableSavedId {
                        staleMessageIds.append(existingMessage.id)
                    }
                    return true
                }
                if !staleMessageIds.isEmpty {
                    transaction.deleteMessages(staleMessageIds, forEachMedia: nil)
                }
                let mapping = transaction.addMessages([message], location: .Random)
                if let messageId = mapping[entry.stableSavedId] {
                    entry.chatMessagePeerId = messageId.peerId.toInt64()
                    entry.chatMessageId = messageId.id
                }
                if [Namespaces.Peer.CloudUser, Namespaces.Peer.CloudGroup, Namespaces.Peer.CloudChannel].contains(chatPeerId.namespace),
                   case .notIncluded = transaction.getPeerChatListInclusion(chatPeerId) {
                    transaction.updatePeerChatListInclusion(chatPeerId, inclusion: .ifHasMessagesOrOneOf(groupId: .root, pinningIndex: nil, minTimestamp: nil))
                }
                return entry
            }
        }
    }

    public func deleteChatMessageSignal(account: Account, entry: MiraFakeGift) -> Signal<Void, NoError> {
        guard let chatMessageId = entry.chatMessageId, let storedPeerId = entry.chatMessagePeerId, let chatMessagePeerId = MiraMessageHistoryStore.peerId(fromPackedValue: storedPeerId) else {
            return .single(())
        }
        return account.postbox.transaction { transaction in
            transaction.deleteMessages([MessageId(peerId: chatMessagePeerId, namespace: Namespaces.Message.Local, id: chatMessageId)], forEachMedia: nil)
        }
    }

    public func deleteChatMessage(account: Account, entry: MiraFakeGift) {
        let _ = self.deleteChatMessageSignal(account: account, entry: entry).start()
    }

    /// Converts a local regular gift without ever sending its synthetic
    /// reference to Telegram. The chat projection and profile entry are
    /// removed together so a conversion cannot leave a stale gift bubble.
    public func convertLocalReference(account: Account, reference: StarGiftReference) {
        guard case let .peer(peerId, savedId) = reference,
              peerId == account.peerId,
              MiraFakeGift.isLocalSavedId(savedId) else {
            return
        }
        let entry = self.list().first(where: { $0.stableSavedId == savedId })
        if let entry {
            if !entry.isUnique, case let .generic(gift)? = entry.giftSnapshot {
                // Conversion is a local credit. The related gift id makes the
                // operation idempotent if the UI sends the action twice.
                _ = account.miraFakeStarsLedger.recordGiftConversion(
                    id: entry.id,
                    peerId: account.peerId.toInt64(),
                    stars: max(0, gift.convertStars),
                    date: entry.date
                )
            }
            let _ = self.deleteChatMessageSignal(account: account, entry: entry).start(completed: { [weak self] in
                self?.remove(id: entry.id)
            })
        } else {
            self.queue.async { [weak self] in
                self?.loadIfNeeded()
                self?.cache.removeAll(where: { $0.stableSavedId == savedId })
                self?.saveLocked()
                self?.publishLocked()
            }
        }
    }

    /// Moves a local fake NFT into the recipient's local chat. The operation is
    /// deliberately account-local: no synthetic reference is sent to Telegram
    /// and the original profile entry is removed only after its chat projection
    /// has been deleted.
    public func transferLocalReference(account: Account, reference: StarGiftReference, recipientPeerId: PeerId) -> Signal<Never, TransferStarGiftError> {
        guard case let .peer(peerId, savedId) = reference,
              peerId == account.peerId,
              MiraFakeGift.isLocalSavedId(savedId),
              let source = self.list().first(where: { $0.stableSavedId == savedId }),
              source.isUnique else {
            return .fail(.generic)
        }
        let transferFee = source.transferStars ?? 0
        guard account.miraFakeStarsLedger.recordGiftTransfer(
            id: source.id,
            peerId: recipientPeerId.toInt64(),
            fee: transferFee,
            date: Int32(clamping: Int64(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970))
        ) else {
            // Insufficient local fake Stars leaves the source gift intact.
            return .fail(.generic)
        }
        let remove = self.deleteChatMessageSignal(account: account, entry: source)
        return remove
        |> mapToSignal { [weak self] _ -> Signal<Never, TransferStarGiftError> in
            guard let self else {
                return .complete()
            }
            self.remove(id: source.id)
            var transferred = source
            transferred.id = UUID().uuidString
            transferred.fromPeerId = account.peerId.toInt64()
            transferred.fromPeerIdIsPacked = true
            transferred.fromName = nil
            transferred.date = Int32(clamping: Int64(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970))
            transferred.chatMessagePeerId = nil
            transferred.chatMessageId = nil
            transferred.showInChat = true
            return self.insertChatMessage(account: account, entry: transferred, forcedChatPeerId: recipientPeerId)
            |> ignoreValues
            |> castError(TransferStarGiftError.self)
        }
    }
}
