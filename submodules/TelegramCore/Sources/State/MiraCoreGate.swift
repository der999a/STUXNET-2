import Foundation
import SwiftSignalKit
import Postbox

public struct MiraCoreGateSnapshot: Equatable {
    public var sendReadMessages: Bool = true
    public var sendReadStories: Bool = true
    public var sendOnlinePackets: Bool = true
    public var sendUploadProgress: Bool = true
    public var sendOfflinePacketAfterOnline: Bool = false
    public var markReadAfterAction: Bool = false
    public var useScheduledMessages: Bool = false
    public var scheduledDelaySeconds: Int32 = 12
    public var sendWithoutSound: Int32 = 0
    public var saveDeletedMessages: Bool = true
    public var saveMessagesHistory: Bool = true
    public var saveForBots: Bool = false
    public var localMessageEditEnabled: Bool = true
    public var disableAds: Bool = true
    public var disableStories: Bool = false
    public var localPremium: Bool = false
    public var filterZalgo: Bool = false
    public var isGhostActive: Bool = false
    public var fakeGiftsEnabled: Bool = false
    public var voiceChangerEnabled: Bool = false
    public var voiceChangerPreset: Int32 = 0
    
    public init() {
    }
}

public final class MiraCoreGate {
    public static let shared = MiraCoreGate()
    
    private let value = Atomic<MiraCoreGateSnapshot>(value: MiraCoreGateSnapshot())
    private let accountValues = Atomic<[PeerId: MiraCoreGateSnapshot]>(value: [:])
    
    public var snapshot: MiraCoreGateSnapshot {
        return self.value.with { $0 }
    }
    
    public func apply(_ snapshot: MiraCoreGateSnapshot) {
        let _ = self.value.swap(snapshot)
    }

    /// Applies a snapshot for one Telegram account. The legacy global snapshot
    /// remains the fallback for accounts without an override.
    public func apply(_ snapshot: MiraCoreGateSnapshot, forAccountPeerId accountPeerId: PeerId) {
        let _ = self.accountValues.modify { values in
            var values = values
            values[accountPeerId] = snapshot
            return values
        }
    }

    /// Replaces the active account set so logged-out accounts cannot leave a
    /// stale override behind for a later login.
    public func replaceAccountSnapshots(_ snapshots: [PeerId: MiraCoreGateSnapshot]) {
        let _ = self.accountValues.swap(snapshots)
    }

    /// Resolves the effective snapshot for an account without changing the
    /// process-wide legacy snapshot used by older call sites.
    public func snapshot(forAccountPeerId accountPeerId: PeerId?) -> MiraCoreGateSnapshot {
        guard let accountPeerId = accountPeerId else {
            return self.snapshot
        }
        return self.accountValues.with { values in
            return values[accountPeerId] ?? self.snapshot
        }
    }
    
    public var sendReadMessages: Bool {
        return self.snapshot.sendReadMessages
    }
    
    public var sendReadStories: Bool {
        return self.snapshot.sendReadStories
    }
    
    public var sendOnlinePackets: Bool {
        return self.snapshot.sendOnlinePackets
    }
    
    public var sendUploadProgress: Bool {
        return self.snapshot.sendUploadProgress
    }
    
    public var sendOfflinePacketAfterOnline: Bool {
        return self.snapshot.sendOfflinePacketAfterOnline
    }
    
    public var markReadAfterAction: Bool {
        return self.snapshot.markReadAfterAction
    }
    
    public var useScheduledMessages: Bool {
        return self.snapshot.useScheduledMessages
    }
    
    public var scheduledDelaySeconds: Int32 {
        return self.snapshot.scheduledDelaySeconds
    }
    
    public var sendWithoutSound: Int32 {
        return self.snapshot.sendWithoutSound
    }
    
    public var saveDeletedMessages: Bool {
        return self.snapshot.saveDeletedMessages
    }
    
    public var saveMessagesHistory: Bool {
        return self.snapshot.saveMessagesHistory
    }
    
    public var saveForBots: Bool {
        return self.snapshot.saveForBots
    }

    public var localMessageEditEnabled: Bool {
        return self.snapshot.localMessageEditEnabled
    }
    
    public var disableAds: Bool {
        return self.snapshot.disableAds
    }
    
    public var disableStories: Bool {
        return self.snapshot.disableStories
    }
    
    public var localPremium: Bool {
        return self.snapshot.localPremium
    }
    
    public var filterZalgo: Bool {
        return self.snapshot.filterZalgo
    }
    
    public var isGhostActive: Bool {
        return self.snapshot.isGhostActive
    }
    
    public var fakeGiftsEnabled: Bool {
        return self.snapshot.fakeGiftsEnabled
    }
    
    public var voiceChangerEnabled: Bool {
        return self.snapshot.voiceChangerEnabled
    }
    
    public var voiceChangerPreset: Int32 {
        return self.snapshot.voiceChangerPreset
    }
    
    private init() {
    }
}
