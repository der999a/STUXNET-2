import Foundation
import SwiftSignalKit
import Postbox

/// The local Stars ledger is deliberately separate from Telegram's Stars
/// balance.  Entries are account-local, durable and never become API
/// requests.  It is used by fake gifts and fake Stars messages so previews
/// can have coherent balance/history semantics without touching the server.
public enum MiraFakeStarsLedgerEntryKind: String, Codable {
    case initial
    case credit
    case debit
    case fakeGiftTransfer
    case fakeGiftConversion
    case fakeStarsMessage
}

public struct MiraFakeStarsLedgerEntry: Codable, Equatable {
    public let id: String
    public let date: Int32
    public let delta: Int64
    public let balance: Int64
    public let kind: MiraFakeStarsLedgerEntryKind
    public let relatedId: String?
    public let peerId: Int64?
    public let note: String?

    public init(id: String = UUID().uuidString,
                date: Int32,
                delta: Int64,
                balance: Int64,
                kind: MiraFakeStarsLedgerEntryKind,
                relatedId: String? = nil,
                peerId: Int64? = nil,
                note: String? = nil) {
        self.id = id
        self.date = date
        self.delta = delta
        self.balance = balance
        self.kind = kind
        self.relatedId = relatedId
        self.peerId = peerId
        self.note = note
    }
}

public struct MiraFakeStarsLedgerSnapshot: Codable, Equatable {
    public let balance: Int64
    public let entries: [MiraFakeStarsLedgerEntry]

    public init(balance: Int64 = 0, entries: [MiraFakeStarsLedgerEntry] = []) {
        self.balance = max(0, balance)
        self.entries = entries
    }
}

public final class MiraFakeStarsLedger {
    private static let registryQueue = DispatchQueue(label: "org.telegram.mira.fakeStarsLedger.registry")
    private static var registeredStores: [Int64: MiraFakeStarsLedger] = [:]

    public static func register(accountPeerId: PeerId, ledger: MiraFakeStarsLedger) {
        self.registryQueue.sync {
            self.registeredStores[accountPeerId.toInt64()] = ledger
        }
    }

    public static func store(for accountPeerId: PeerId) -> MiraFakeStarsLedger? {
        return self.registryQueue.sync {
            return self.registeredStores[accountPeerId.toInt64()]
        }
    }

    private let queue = DispatchQueue(label: "org.telegram.mira.fakeStarsLedger", qos: .utility)
    private let publicationQueue = DispatchQueue(label: "org.telegram.mira.fakeStarsLedger.publication", qos: .utility)
    private let filePath: String
    private var balanceCache: Int64 = 0
    private var entriesCache: [MiraFakeStarsLedgerEntry] = []
    private var didLoad = false
    private let changesPromise = ValuePromise<MiraFakeStarsLedgerSnapshot>(MiraFakeStarsLedgerSnapshot(), ignoreRepeated: true)

    public init(basePath: String) {
        self.filePath = basePath + "/mira-fake-stars-ledger.json"
    }

    private func loadIfNeeded() {
        guard !self.didLoad else {
            return
        }
        self.didLoad = true
        guard let data = FileManager.default.contents(atPath: self.filePath) else {
            self.publishLocked()
            return
        }
        if let snapshot = try? JSONDecoder().decode(MiraFakeStarsLedgerSnapshot.self, from: data) {
            self.balanceCache = max(0, snapshot.balance)
            self.entriesCache = snapshot.entries
        } else if let legacyEntries = try? JSONDecoder().decode([MiraFakeStarsLedgerEntry].self, from: data) {
            // Be liberal when recovering an early experimental build that
            // wrote only the journal array.
            self.entriesCache = legacyEntries
            self.balanceCache = max(0, legacyEntries.last?.balance ?? 0)
        }
        self.publishLocked()
    }

    private func persistLocked() {
        let snapshot = MiraFakeStarsLedgerSnapshot(balance: self.balanceCache, entries: self.entriesCache)
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        try? data.write(to: URL(fileURLWithPath: self.filePath), options: [.atomic])
    }

    private func publishLocked() {
        let snapshot = MiraFakeStarsLedgerSnapshot(balance: self.balanceCache, entries: self.entriesCache)
        self.publicationQueue.async { [weak self] in
            self?.changesPromise.set(snapshot)
        }
    }

    public func snapshot() -> MiraFakeStarsLedgerSnapshot {
        return self.queue.sync {
            self.loadIfNeeded()
            return MiraFakeStarsLedgerSnapshot(balance: self.balanceCache, entries: self.entriesCache)
        }
    }

    public var balance: Int64 {
        return self.snapshot().balance
    }

    public var entries: [MiraFakeStarsLedgerEntry] {
        return self.snapshot().entries
    }

    public func canDebit(_ amount: Int64) -> Bool {
        guard amount >= 0 else {
            return false
        }
        return self.queue.sync {
            self.loadIfNeeded()
            return amount <= self.balanceCache
        }
    }

    public var changes: Signal<MiraFakeStarsLedgerSnapshot, NoError> {
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

    /// Replaces the local balance and writes an explicit adjustment entry.
    /// This is called when the Stuxnet settings value is edited manually.
    @discardableResult
    public func setBalance(_ value: Int64, date: Int32 = MiraFakeStarsLedger.currentTimestamp(), note: String? = nil) -> Bool {
        let normalized = max(0, value)
        return self.queue.sync {
            self.loadIfNeeded()
            guard normalized != self.balanceCache else {
                return true
            }
            let delta: Int64
            if normalized >= self.balanceCache {
                delta = normalized - self.balanceCache
            } else {
                delta = -(self.balanceCache - normalized)
            }
            self.balanceCache = normalized
            self.entriesCache.append(MiraFakeStarsLedgerEntry(date: date, delta: delta, balance: normalized, kind: .initial, note: note))
            self.persistLocked()
            self.publishLocked()
            return true
        }
    }

    @discardableResult
    public func credit(_ amount: Int64, kind: MiraFakeStarsLedgerEntryKind = .credit, relatedId: String? = nil, peerId: Int64? = nil, date: Int32 = MiraFakeStarsLedger.currentTimestamp(), note: String? = nil) -> Bool {
        guard amount > 0 else {
            return amount == 0
        }
        return self.apply(amount: amount, kind: kind, relatedId: relatedId, peerId: peerId, date: date, note: note)
    }

    @discardableResult
    public func debit(_ amount: Int64, kind: MiraFakeStarsLedgerEntryKind = .debit, relatedId: String? = nil, peerId: Int64? = nil, date: Int32 = MiraFakeStarsLedger.currentTimestamp(), note: String? = nil) -> Bool {
        guard amount >= 0 else {
            return false
        }
        return self.queue.sync {
            self.loadIfNeeded()
            guard amount <= self.balanceCache else {
                return false
            }
            guard !self.hasEntryLocked(kind: kind, relatedId: relatedId) else {
                return true
            }
            let next = self.balanceCache - amount
            self.balanceCache = next
            self.entriesCache.append(MiraFakeStarsLedgerEntry(date: date, delta: -amount, balance: next, kind: kind, relatedId: relatedId, peerId: peerId, note: note))
            self.persistLocked()
            self.publishLocked()
            return true
        }
    }

    /// Records a fake Stars message exactly once. Outgoing messages debit the
    /// local balance; incoming ones credit it. A zero amount is still recorded
    /// so editing/reloading the message remains idempotent.
    @discardableResult
    public func recordFakeStarsMessage(id: String, peerId: Int64, amount: Int64, outgoing: Bool, date: Int32 = MiraFakeStarsLedger.currentTimestamp()) -> Bool {
        let normalized = max(0, amount)
        if outgoing {
            return self.debit(normalized, kind: .fakeStarsMessage, relatedId: id, peerId: peerId, date: date, note: "Fake Stars message")
        } else {
            return self.credit(normalized, kind: .fakeStarsMessage, relatedId: id, peerId: peerId, date: date, note: "Fake Stars message")
        }
    }

    /// Applies only the delta introduced by editing a fake Stars message. The
    /// immutable original entry remains in history and the adjustment is a
    /// separate idempotent event.
    @discardableResult
    public func adjustFakeStarsMessage(id: String, peerId: Int64, oldAmount: Int64, newAmount: Int64, outgoing: Bool, date: Int32 = MiraFakeStarsLedger.currentTimestamp()) -> Bool {
        let oldValue = max(0, oldAmount)
        let newValue = max(0, newAmount)
        guard oldValue != newValue else {
            return true
        }
        let delta = newValue - oldValue
        let relatedId = "\(id):edit:\(date):\(newValue)"
        if outgoing {
            if delta > 0 {
                return self.debit(delta, kind: .fakeStarsMessage, relatedId: relatedId, peerId: peerId, date: date, note: "Fake Stars message edit")
            } else {
                return self.credit(-delta, kind: .fakeStarsMessage, relatedId: relatedId, peerId: peerId, date: date, note: "Fake Stars message edit refund")
            }
        } else if delta > 0 {
            return self.credit(delta, kind: .fakeStarsMessage, relatedId: relatedId, peerId: peerId, date: date, note: "Fake Stars message edit")
        } else {
            return self.debit(-delta, kind: .fakeStarsMessage, relatedId: relatedId, peerId: peerId, date: date, note: "Fake Stars message edit reversal")
        }
    }

    @discardableResult
    public func recordGiftTransfer(id: String, peerId: Int64, fee: Int64, date: Int32 = MiraFakeStarsLedger.currentTimestamp()) -> Bool {
        return self.debit(max(0, fee), kind: .fakeGiftTransfer, relatedId: id, peerId: peerId, date: date, note: "Fake gift transfer")
    }

    @discardableResult
    public func recordGiftConversion(id: String, peerId: Int64, stars: Int64, date: Int32 = MiraFakeStarsLedger.currentTimestamp()) -> Bool {
        return self.credit(max(0, stars), kind: .fakeGiftConversion, relatedId: id, peerId: peerId, date: date, note: "Fake gift conversion")
    }

    public func hasEntry(kind: MiraFakeStarsLedgerEntryKind, relatedId: String?) -> Bool {
        return self.queue.sync {
            self.loadIfNeeded()
            return self.hasEntryLocked(kind: kind, relatedId: relatedId)
        }
    }

    private func hasEntryLocked(kind: MiraFakeStarsLedgerEntryKind, relatedId: String?) -> Bool {
        return self.entriesCache.contains { $0.kind == kind && $0.relatedId == relatedId }
    }

    private func apply(amount: Int64, kind: MiraFakeStarsLedgerEntryKind, relatedId: String?, peerId: Int64?, date: Int32, note: String?) -> Bool {
        return self.queue.sync {
            self.loadIfNeeded()
            guard !self.hasEntryLocked(kind: kind, relatedId: relatedId), amount >= 0,
                  self.balanceCache <= Int64.max - amount else {
                return self.hasEntryLocked(kind: kind, relatedId: relatedId)
            }
            let next = self.balanceCache + amount
            self.balanceCache = next
            self.entriesCache.append(MiraFakeStarsLedgerEntry(date: date, delta: amount, balance: next, kind: kind, relatedId: relatedId, peerId: peerId, note: note))
            self.persistLocked()
            self.publishLocked()
            return true
        }
    }

    public func clear() {
        self.queue.async {
            self.didLoad = true
            self.balanceCache = 0
            self.entriesCache.removeAll()
            try? FileManager.default.removeItem(atPath: self.filePath)
            self.publishLocked()
        }
    }

    public static func currentTimestamp() -> Int32 {
        return Int32(clamping: Int64(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970))
    }
}
