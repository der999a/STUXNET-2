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
    case dateHeader
    case preset(Int, String, Bool)
    case customDays(String)
    case hint(String)

    var section: ItemListSectionId {
        switch self {
        case .input:
            return 0
        case .directionHeader, .fromThem, .fromMe:
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
        case .dateHeader:
            return 4
        case let .preset(index, _, _):
            return 5 + index
        case .customDays:
            return 10
        case .hint:
            return 11
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

    let signal = combineLatest(context.sharedContext.presentationData, versionPromise.get())
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, MiraFakeMessageControllerArguments)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Add Fake Message"), leftNavigationButton: nil, rightNavigationButton: ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .regular, enabled: true, action: {
            let text = state.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
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
                let _ = context.engine.messages.miraAddFakeMessage(peerId: peerId, text: text, outgoing: state.outgoing, date: date).start()
            }
            dismissImpl?()
        }), backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))

        var entries: [MiraFakeMessageEntry] = []
        entries.append(.input(state.text))
        entries.append(.directionHeader)
        entries.append(.fromThem(!state.outgoing))
        entries.append(.fromMe(state.outgoing))
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
                arguments.remove(record.id)
            })
        case let .removeAll(title):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.removeAll()
            })
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private final class MiraFakeMessagesListArguments {
    let add: () -> Void
    let removeAll: () -> Void
    let remove: (String) -> Void

    init(add: @escaping () -> Void, removeAll: @escaping () -> Void, remove: @escaping (String) -> Void) {
        self.add = add
        self.removeAll = removeAll
        self.remove = remove
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
    let arguments = MiraFakeMessagesListArguments(add: {
        pushControllerImpl?(miraFakeMessageController(context: context, peerId: peerId))
    }, removeAll: {
        let _ = context.engine.messages.miraRemoveAllFakeMessages(peerId: peerId).start()
    }, remove: { id in
        let _ = context.engine.messages.miraRemoveFakeMessage(id: id).start()
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
                let direction = record.outgoing ? "From you" : "From chat"
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
    return controller
}
