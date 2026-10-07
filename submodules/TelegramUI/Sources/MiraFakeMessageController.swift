import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import PresentationDataUtils

private final class MiraFakeMessageState {
    var text: String = ""
    var outgoing: Bool = false
    var sender: String = ""
    var datePreset: Int = 0
    var customDaysBack: String = ""
    var version: Int = 0
}

private final class MiraFakeMessageControllerArguments {
    let state: MiraFakeMessageState
    let updated: () -> Void

    init(state: MiraFakeMessageState, updated: @escaping () -> Void) {
        self.state = state
        self.updated = updated
    }
}

private enum MiraFakeMessageEntry: ItemListNodeEntry {
    case input(String)
    case directionHeader
    case fromThem(Bool)
    case fromMe(Bool)
    case senderHeader
    case senderInput(String)
    case dateHeader
    case preset(Int, String, Bool)
    case customDays(String)
    case hint(String)

    var section: ItemListSectionId {
        switch self {
        case .input:
            return 0
        case .directionHeader, .fromThem, .fromMe, .senderHeader, .senderInput:
            return 1
        case .dateHeader, .preset, .customDays:
            return 2
        case .hint:
            return 3
        }
    }

    var stableId: Int {
        switch self {
        case .input:
            return 0
        case .directionHeader:
            return 1
        case .fromThem:
            return 2
        case .fromMe:
            return 3
        case .senderHeader:
            return 4
        case .senderInput:
            return 5
        case .dateHeader:
            return 6
        case let .preset(index, _, _):
            return 7 + index
        case .customDays:
            return 12
        case .hint:
            return 13
        }
    }

    static func <(lhs: MiraFakeMessageEntry, rhs: MiraFakeMessageEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MiraFakeMessageControllerArguments
        switch self {
        case let .input(text):
            return ItemListMultilineInputItem(presentationData: presentationData, text: text, placeholder: "Message text", maxLength: nil, sectionId: self.section, style: .blocks, textUpdated: { value in
                arguments.state.text = value
            })
        case .directionHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "Direction", sectionId: self.section)
        case let .fromThem(checked):
            return ItemListCheckboxItem(presentationData: presentationData, title: "From them", style: .left, checked: checked, zeroSeparatorInsets: true, sectionId: self.section, action: {
                arguments.state.outgoing = false
                arguments.updated()
            })
        case let .fromMe(checked):
            return ItemListCheckboxItem(presentationData: presentationData, title: "From me", style: .left, checked: checked, zeroSeparatorInsets: true, sectionId: self.section, action: {
                arguments.state.outgoing = true
                arguments.updated()
            })
        case .senderHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "Sender", sectionId: self.section)
        case let .senderInput(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(), text: text, placeholder: "@username or user ID", type: .regular(capitalization: false, autocorrection: false), sectionId: self.section, textUpdated: { value in
                arguments.state.sender = value
            }, action: {})
        case .dateHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "Date", sectionId: self.section)
        case let .preset(index, title, checked):
            return ItemListCheckboxItem(presentationData: presentationData, title: title, style: .left, checked: checked, zeroSeparatorInsets: true, sectionId: self.section, action: {
                arguments.state.datePreset = index
                arguments.updated()
            })
        case let .customDays(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(), text: text, placeholder: "Days back", type: .number, sectionId: self.section, textUpdated: { value in
                arguments.state.customDaysBack = value
            }, action: {
            })
        case let .hint(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private let miraFakeMessageDatePresets: [(String, Int32?)] = [
    ("Now", nil),
    ("1 hour ago", 3600),
    ("Yesterday", 86400),
    ("7 days ago", 7 * 86400),
    ("Custom (days back)", -1)
]

public func miraFakeMessageController(context: AccountContext, peerId: PeerId) -> ViewController {
    let state = MiraFakeMessageState()
    let versionPromise = ValuePromise<Int>(0, ignoreRepeated: true)
    var dismissImpl: (() -> Void)?

    let arguments = MiraFakeMessageControllerArguments(state: state, updated: {
        state.version += 1
        versionPromise.set(state.version)
    })

    let addMessage: (PeerId?, String?) -> Void = { authorPeerId, authorName in
        let text = state.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }
        let now = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
        let date: Int32
        if state.datePreset < miraFakeMessageDatePresets.count, let offset = miraFakeMessageDatePresets[state.datePreset].1 {
            if offset < 0 {
                let days = max(0, Int32(state.customDaysBack) ?? 0)
                date = now - days * 86400
            } else {
                date = now - offset
            }
        } else {
            date = now
        }
        let _ = context.engine.messages.miraAddFakeMessage(peerId: peerId, text: text, outgoing: state.outgoing, date: date, authorPeerId: authorPeerId, authorName: authorName).start()
        dismissImpl?()
    }

    let resolveSenderAndAdd: () -> Void = {
        guard !state.outgoing else {
            addMessage(nil, nil)
            return
        }
        let sender = state.sender.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sender.isEmpty else {
            addMessage(nil, nil)
            return
        }
        if let value = Int64(sender) {
            let _ = (context.account.postbox.transaction { transaction -> EnginePeer? in
                let encodedPeerId = PeerId(value)
                if let peer = transaction.getPeer(encodedPeerId).flatMap(EnginePeer.init) {
                    return peer
                }
                let userPeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(value))
                return transaction.getPeer(userPeerId).flatMap(EnginePeer.init)
            } |> deliverOnMainQueue).start(next: { peer in
                addMessage(peer?.id, peer?.compactDisplayTitle ?? sender)
            })
        } else {
            var name = sender
            if name.hasPrefix("@") {
                name = String(name.dropFirst())
            }
            if let range = name.range(of: "t.me/", options: .caseInsensitive) {
                name = String(name[range.upperBound...])
            }
            let _ = (context.engine.peers.resolvePeerByName(name: name, referrer: nil)
            |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
                switch result {
                case .progress:
                    return .complete()
                case let .result(peer):
                    return .single(peer)
                }
            }
            |> deliverOnMainQueue).start(next: { peer in
                addMessage(peer?.id, peer?.compactDisplayTitle ?? sender)
            })
        }
    }

    let signal = combineLatest(context.sharedContext.presentationData, versionPromise.get())
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, MiraFakeMessageControllerArguments)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Add Fake Message"), leftNavigationButton: nil, rightNavigationButton: ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .regular, enabled: true, action: {
            resolveSenderAndAdd()
        }), backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))

        var entries: [MiraFakeMessageEntry] = []
        entries.append(.input(state.text))
        entries.append(.directionHeader)
        entries.append(.fromThem(!state.outgoing))
        entries.append(.fromMe(state.outgoing))
        if !state.outgoing {
            entries.append(.senderHeader)
            entries.append(.senderInput(state.sender))
        }
        entries.append(.dateHeader)
        for (index, preset) in miraFakeMessageDatePresets.enumerated() {
            entries.append(.preset(index, preset.0, state.datePreset == index))
        }
        if state.datePreset == miraFakeMessageDatePresets.count - 1 {
            entries.append(.customDays(state.customDaysBack))
        }
        entries.append(.hint("The message is stored locally and never sent to the server. It appears at the end of the chat."))

        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        let _ = (controller?.navigationController as? NavigationController)?.popViewController(animated: true)
    }
    return controller
}

private enum MiraFakeMessagesListEntry: ItemListNodeEntry {
    case add(String)
    case count(String)
    case message(Int, FakeMessageRecord, String, String)
    case removeAll(String)
    case empty(String)

    var section: ItemListSectionId {
        switch self {
        case .add, .count:
            return 0
        case .message, .removeAll, .empty:
            return 1
        }
    }

    var stableId: Int {
        switch self {
        case .add:
            return 0
        case .count:
            return 1
        case let .message(index, _, _, _):
            return 10 + index * 2
        case .removeAll:
            return 100000
        case .empty:
            return 100001
        }
    }

    static func < (lhs: MiraFakeMessagesListEntry, rhs: MiraFakeMessagesListEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MiraFakeMessagesListArguments
        switch self {
        case let .add(title):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.add()
            })
        case let .count(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .message(_, record, title, detail):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: detail, labelStyle: .detailText, sectionId: self.section, style: .blocks, action: {
                arguments.confirmRemove(record)
            })
        case let .removeAll(title):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.confirmRemoveAll()
            })
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private final class MiraFakeMessagesListArguments {
    let add: () -> Void
    let confirmRemoveAll: () -> Void
    let confirmRemove: (FakeMessageRecord) -> Void

    init(add: @escaping () -> Void, confirmRemoveAll: @escaping () -> Void, confirmRemove: @escaping (FakeMessageRecord) -> Void) {
        self.add = add
        self.confirmRemoveAll = confirmRemoveAll
        self.confirmRemove = confirmRemove
    }
}

private func miraFakeMessageListDate(_ timestamp: Int32) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
}

public func miraFakeMessagesController(context: AccountContext, peerId: PeerId) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?
    let arguments = MiraFakeMessagesListArguments(add: {
        pushControllerImpl?(miraFakeMessageController(context: context, peerId: peerId))
    }, confirmRemoveAll: {
        let controller = textAlertController(context: context, title: "Remove Fake Messages?", text: "All local fake messages in this chat will be removed.", actions: [
            TextAlertAction(type: .genericAction, title: "Cancel", action: {}),
            TextAlertAction(type: .destructiveAction, title: "Remove All", action: {
                let _ = context.engine.messages.miraRemoveAllFakeMessages(peerId: peerId).start()
            })
        ])
        presentControllerImpl?(controller)
    }, confirmRemove: { record in
        let controller = textAlertController(context: context, title: "Remove Fake Message?", text: "This local message will be removed from the chat.", actions: [
            TextAlertAction(type: .genericAction, title: "Cancel", action: {}),
            TextAlertAction(type: .destructiveAction, title: "Remove", action: {
                let _ = context.engine.messages.miraRemoveFakeMessage(id: record.id).start()
            })
        ])
        presentControllerImpl?(controller)
    })

    let signal = combineLatest(context.sharedContext.presentationData, context.account.miraMessageHistoryStore.fakeMessagesChanges)
    |> map { presentationData, records -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let peerRecords = records.filter { $0.messagePeerId == peerId.toInt64() }.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.id < rhs.id
            }
            return lhs.date < rhs.date
        }
        var entries: [MiraFakeMessagesListEntry] = []
        entries.append(.add("Add Fake Message"))
        entries.append(.count(peerRecords.isEmpty ? "No local messages" : "\(peerRecords.count) local message\(peerRecords.count == 1 ? "" : "s")"))
        if peerRecords.isEmpty {
            entries.append(.empty("Fake messages stay on this device and are never sent to Telegram."))
        } else {
            for (index, record) in peerRecords.enumerated() {
                let preview = record.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                let title = preview.isEmpty ? "(empty message)" : String(preview.prefix(80))
                let direction: String
                if record.outgoing {
                    direction = "From you"
                } else if let authorName = record.authorName, !authorName.isEmpty {
                    direction = "From \(authorName)"
                } else {
                    direction = "From chat"
                }
                entries.append(.message(index, record, title, "\(direction) · \(miraFakeMessageListDate(record.date))"))
            }
            entries.append(.removeAll("Remove all fake messages"))
        }

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Fake Messages"),
            leftNavigationButton: nil,
            rightNavigationButton: ItemListNavigationButton(content: .icon(.add), style: .regular, enabled: true, action: {
                arguments.add()
            }),
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] nextController in
        (controller?.navigationController as? NavigationController)?.pushViewController(nextController)
    }
    presentControllerImpl = { [weak controller] alertController in
        controller?.present(alertController, in: .window(.root))
    }
    return controller
}
