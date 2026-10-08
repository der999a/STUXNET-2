import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import ItemListDatePickerItem
import PresentationDataUtils

private final class MiraFakeMessageState {
    var text: String = ""
    var oneMessagePerLine: Bool = false
    var outgoing: Bool = false
    var sender: String = ""
    var datePreset: Int = 0
    var customDaysBack: String = ""
    var exactDate: Int32 = Int32(Date().timeIntervalSince1970)
    var exactDateSelection: Bool = false
    var exactSeconds: String = String(format: "%02d", Calendar.current.component(.second, from: Date()))
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
    case batchMode(Bool)
    case directionHeader
    case fromThem(Bool)
    case fromMe(Bool)
    case senderHeader
    case senderInput(String)
    case dateHeader
    case preset(Int, String, Bool)
    case exactDatePicker(Int32, Bool)
    case exactSeconds(String)
    case customDays(String)
    case hint(String)

    var section: ItemListSectionId {
        switch self {
        case .input, .batchMode:
            return 0
        case .directionHeader, .fromThem, .fromMe, .senderHeader, .senderInput:
            return 1
        case .dateHeader, .preset, .exactDatePicker, .exactSeconds, .customDays:
            return 2
        case .hint:
            return 3
        }
    }

    var stableId: Int {
        switch self {
        case .input:
            return 0
        case .batchMode:
            return 1
        case .directionHeader:
            return 2
        case .fromThem:
            return 3
        case .fromMe:
            return 4
        case .senderHeader:
            return 5
        case .senderInput:
            return 6
        case .dateHeader:
            return 7
        case let .preset(index, _, _):
            return 8 + index
        case .exactDatePicker:
            return 8 + miraFakeMessageDatePresets.count
        case .exactSeconds:
            return 9 + miraFakeMessageDatePresets.count
        case .customDays:
            return 10 + miraFakeMessageDatePresets.count
        case .hint:
            return 11 + miraFakeMessageDatePresets.count
        }
    }

    static func <(lhs: MiraFakeMessageEntry, rhs: MiraFakeMessageEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        guard let arguments = arguments as? MiraFakeMessageControllerArguments else {
            return ItemListTextItem(presentationData: presentationData, text: .plain(""), sectionId: self.section)
        }
        switch self {
        case let .input(text):
            return ItemListMultilineInputItem(presentationData: presentationData, text: text, placeholder: "Message text", maxLength: nil, sectionId: self.section, style: .blocks, textUpdated: { value in
                arguments.state.text = value
                arguments.updated()
            })
        case let .batchMode(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "One message per line", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.state.oneMessagePerLine = value
                arguments.updated()
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
                arguments.updated()
            }, action: {})
        case .dateHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "Date", sectionId: self.section)
        case let .preset(index, title, checked):
            return ItemListCheckboxItem(presentationData: presentationData, title: title, style: .left, checked: checked, zeroSeparatorInsets: true, sectionId: self.section, action: {
                arguments.state.datePreset = index
                arguments.updated()
            })
        case let .exactDatePicker(timestamp, selectingDate):
            return ItemListDatePickerItem(presentationData: presentationData, systemStyle: .glass, dateTimeFormat: presentationData.dateTimeFormat, date: timestamp, minDate: 0, title: "Exact date & time", displayingDateSelection: selectingDate, displayingTimeSelection: !selectingDate, sectionId: self.section, style: .blocks, toggleDateSelection: {
                arguments.state.exactDateSelection = true
                arguments.updated()
            }, toggleTimeSelection: {
                arguments.state.exactDateSelection = false
                arguments.updated()
            }, updated: { date in
                let calendar = Calendar.current
                let previousSeconds = calendar.component(.second, from: Date(timeIntervalSince1970: TimeInterval(arguments.state.exactDate)))
                var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(date)))
                components.second = previousSeconds
                if let updatedDate = calendar.date(from: components) {
                    arguments.state.exactDate = miraClampedMessageTimestamp(Int64(updatedDate.timeIntervalSince1970))
                    arguments.state.exactSeconds = String(format: "%02d", previousSeconds)
                    arguments.updated()
                }
            })
        case let .exactSeconds(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(), text: text, placeholder: "Seconds (0-59)", type: .number, sectionId: self.section, textUpdated: { value in
                let filtered = String(value.filter { $0.isNumber }.prefix(2))
                let seconds = min(59, Int(filtered) ?? 0)
                arguments.state.exactSeconds = String(format: "%02d", seconds)
                let calendar = Calendar.current
                var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(arguments.state.exactDate)))
                components.second = seconds
                if let updatedDate = calendar.date(from: components) {
                    arguments.state.exactDate = miraClampedMessageTimestamp(Int64(updatedDate.timeIntervalSince1970))
                }
                arguments.updated()
            }, action: {})
        case let .customDays(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(), text: text, placeholder: "Days back", type: .number, sectionId: self.section, textUpdated: { value in
                arguments.state.customDaysBack = value
                arguments.updated()
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
    ("Exact date & time", -2),
    ("Custom (days back)", -1)
]

private let miraFakeMessageMaximumBatchSize = 1000

private func miraClampedMessageTimestamp(_ value: Int64) -> Int32 {
    return Int32(max(Int64(Int32.min), min(Int64(Int32.max), value)))
}

public func miraFakeMessageController(context: AccountContext, peerId: PeerId) -> ViewController {
    let state = MiraFakeMessageState()
    let versionPromise = ValuePromise<Int>(0, ignoreRepeated: true)
    var dismissImpl: (() -> Void)?

    let arguments = MiraFakeMessageControllerArguments(state: state, updated: {
        state.version += 1
        versionPromise.set(state.version)
    })

    let addMessages: (PeerId?, String?) -> Void = { authorPeerId, authorName in
        let texts: [String]
        if state.oneMessagePerLine {
            texts = state.text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(miraFakeMessageMaximumBatchSize)
                .map { $0 }
        } else {
            let text = state.text.trimmingCharacters(in: .whitespacesAndNewlines)
            texts = text.isEmpty ? [] : [text]
        }
        guard !texts.isEmpty else {
            return
        }
        let now = miraClampedMessageTimestamp(Int64(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970))
        let baseDate: Int32
        if state.datePreset == miraFakeMessageDatePresets.count - 2 {
            baseDate = miraClampedMessageTimestamp(Int64(state.exactDate))
        } else if state.datePreset < miraFakeMessageDatePresets.count, let offset = miraFakeMessageDatePresets[state.datePreset].1 {
            if offset < 0 {
                let requestedDays = Int64(state.customDaysBack) ?? 0
                let days = max(0, min(requestedDays, Int64(Int32.max) / 86400))
                baseDate = miraClampedMessageTimestamp(Int64(now) - days * 86400)
            } else {
                baseDate = miraClampedMessageTimestamp(Int64(now) - Int64(offset))
            }
        } else {
            baseDate = now
        }
        for (index, text) in texts.enumerated() {
            // Keep scripted lines in their entered order when the chat sorts by date.
            let date = miraClampedMessageTimestamp(Int64(baseDate) - Int64(texts.count - 1 - index))
            let _ = context.engine.messages.miraAddFakeMessage(peerId: peerId, text: text, outgoing: state.outgoing, date: date, authorPeerId: authorPeerId, authorName: authorName).start()
        }
        dismissImpl?()
    }

    let resolveSenderAndAdd: () -> Void = {
        guard !state.outgoing else {
            addMessages(nil, nil)
            return
        }
        let sender = state.sender.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sender.isEmpty else {
            addMessages(nil, nil)
            return
        }
        if let value = Int64(sender) {
            guard value > 0, value <= 0x00ffffffffffffff else {
                addMessages(nil, sender)
                return
            }
            let _ = (context.account.postbox.transaction { transaction -> EnginePeer? in
                let userPeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(value))
                return transaction.getPeer(userPeerId).flatMap(EnginePeer.init)
            } |> deliverOnMainQueue).start(next: { peer in
                addMessages(peer?.id, peer?.compactDisplayTitle ?? sender)
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
                addMessages(peer?.id, peer?.compactDisplayTitle ?? sender)
            })
        }
    }

    let signal = combineLatest(context.sharedContext.presentationData, versionPromise.get())
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, MiraFakeMessageControllerArguments)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Add Fake Message"), leftNavigationButton: nil, rightNavigationButton: ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .regular, enabled: true, action: {
            resolveSenderAndAdd()
        }), backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)

        var entries: [MiraFakeMessageEntry] = []
        entries.append(.input(state.text))
        entries.append(.batchMode(state.oneMessagePerLine))
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
        if state.datePreset == miraFakeMessageDatePresets.count - 2 {
            entries.append(.exactDatePicker(state.exactDate, state.exactDateSelection))
            entries.append(.exactSeconds(state.exactSeconds))
        }
        if state.datePreset == miraFakeMessageDatePresets.count - 1 {
            entries.append(.customDays(state.customDaysBack))
        }
        let pendingCount: Int
        if state.oneMessagePerLine {
            pendingCount = state.text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.count
        } else {
            pendingCount = state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1
        }
        let countHint = pendingCount > 0 ? " Ready to add \(pendingCount) local message\(pendingCount == 1 ? "" : "s")." : ""
        entries.append(.hint("Messages stay on this device and are never sent to the server. \(state.oneMessagePerLine ? "Each non-empty line becomes a separate message." : "")\(countHint)"))

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
        guard let arguments = arguments as? MiraFakeMessagesListArguments else {
            return ItemListTextItem(presentationData: presentationData, text: .plain(""), sectionId: self.section)
        }
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
    formatter.timeStyle = .medium
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
}

public func miraFakeMessagesController(context: AccountContext, peerId: PeerId) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?
    let arguments = MiraFakeMessagesListArguments(add: {
        pushControllerImpl?(miraFakeMessageController(context: context, peerId: peerId))
    }, confirmRemoveAll: {
        let strings = context.sharedContext.currentPresentationData.with { $0.strings }
        let controller = textAlertController(context: context, title: "Remove Fake Messages?", text: "All local fake messages in this chat will be removed.", actions: [
            TextAlertAction(type: .genericAction, title: strings.Common_Cancel, action: {}),
            TextAlertAction(type: .destructiveAction, title: strings.Common_Delete, action: {
                let _ = context.engine.messages.miraRemoveAllFakeMessages(peerId: peerId).start()
            })
        ])
        presentControllerImpl?(controller)
    }, confirmRemove: { record in
        let strings = context.sharedContext.currentPresentationData.with { $0.strings }
        let controller = textAlertController(context: context, title: "Remove Fake Message?", text: "This local message will be removed from the chat.", actions: [
            TextAlertAction(type: .genericAction, title: strings.Common_Cancel, action: {}),
            TextAlertAction(type: .destructiveAction, title: strings.Common_Delete, action: {
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
                    if record.authorPeerId != nil {
                        direction = "From \(authorName)"
                    } else {
                        direction = "Local label: \(authorName)"
                    }
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
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: true
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
