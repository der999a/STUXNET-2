import Foundation
import TelegramApi
import Postbox
import SwiftSignalKit
import MtProtoKit

private typealias SignalKitTimer = SwiftSignalKit.Timer


private final class AccountPresenceManagerImpl {
    private let queue: Queue
    private let network: Network
    private let postbox: Postbox
    private let accountPeerId: PeerId
    let isPerformingUpdate = ValuePromise<Bool>(false, ignoreRepeated: true)
    
    private var shouldKeepOnlinePresenceDisposable: Disposable?
    private let currentRequestDisposable = MetaDisposable()
    private var onlineTimer: SignalKitTimer?
    
    private var wasOnline: Bool?
    
    init(queue: Queue, shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network, postbox: Postbox, accountPeerId: PeerId) {
        self.queue = queue
        self.network = network
        self.postbox = postbox
        self.accountPeerId = accountPeerId
        
        self.shouldKeepOnlinePresenceDisposable = (shouldKeepOnlinePresence
        |> distinctUntilChanged
        |> deliverOn(self.queue)).start(next: { [weak self] value in
            guard let `self` = self else {
                return
            }
            if self.wasOnline != value {
                self.wasOnline = value
                self.updatePresence(value)
            }
        })
    }
    
    deinit {
        assert(self.queue.isCurrent())
        self.shouldKeepOnlinePresenceDisposable?.dispose()
        self.currentRequestDisposable.dispose()
        self.onlineTimer?.invalidate()
    }
    
    private func updatePresence(_ isOnline: Bool) {
        // Keep the local cached presence in sync with the packets we send.
        // Account initialization used to mark the account online until Int32.max,
        // which made profiles show a permanent "online" state even after going
        // to the background. Telegram refreshes this lease periodically, so use a
        // short local lease as well and clear it when presence is disabled.
        let now = Int32(clamping: Int64(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970))
        let shouldExposeOnline = isOnline && MiraCoreGate.shared.snapshot(forAccountPeerId: self.accountPeerId).sendOnlinePackets
        let localStatus: UserPresenceStatus = shouldExposeOnline ? .present(until: Int32(clamping: Int64(now) + 60)) : .none
        let _ = self.postbox.transaction { transaction -> Void in
            transaction.updatePeerPresencesInternal(
                presences: [self.accountPeerId: TelegramUserPresence(status: localStatus, lastActivity: now)],
                merge: { _, updated in return updated }
            )
        }.start()

        let request: Signal<Api.Bool, MTRpcError>
        if isOnline {
            let timer = SignalKitTimer(timeout: 30.0, repeat: false, completion: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.updatePresence(true)
            }, queue: self.queue)
            self.onlineTimer = timer
            timer.start()
            if MiraCoreGate.shared.snapshot(forAccountPeerId: self.accountPeerId).sendOnlinePackets {
                request = self.network.request(Api.functions.account.updateStatus(offline: .boolFalse))
            } else {
                request = self.network.request(Api.functions.account.updateStatus(offline: .boolTrue))
            }
        } else {
            self.onlineTimer?.invalidate()
            self.onlineTimer = nil
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolTrue))
        }
        self.isPerformingUpdate.set(true)
        self.currentRequestDisposable.set((request
        |> `catch` { _ -> Signal<Api.Bool, NoError> in
            return .single(.boolFalse)
        }
        |> deliverOn(self.queue)).start(completed: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.isPerformingUpdate.set(false)
        }))
    }
}

final class AccountPresenceManager {
    private let queue = Queue()
    private let impl: QueueLocalObject<AccountPresenceManagerImpl>
    
    init(shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network, postbox: Postbox, accountPeerId: PeerId) {
        let queue = self.queue
        self.impl = QueueLocalObject(queue: self.queue, generate: {
            return AccountPresenceManagerImpl(queue: queue, shouldKeepOnlinePresence: shouldKeepOnlinePresence, network: network, postbox: postbox, accountPeerId: accountPeerId)
        })
    }
    
    func isPerformingUpdate() -> Signal<Bool, NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            self.impl.with { impl in
                disposable.set(impl.isPerformingUpdate.get().start(next: { value in
                    subscriber.putNext(value)
                }))
            }
            return disposable
        }
    }
}
