import Foundation
import UIKit
import Display
import SwiftSignalKit
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
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
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
        (controller?.navigationController as? NavigationController)?.popViewController(animated: true)
    }
    return controller
}
