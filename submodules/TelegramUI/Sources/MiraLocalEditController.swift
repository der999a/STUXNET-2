import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import PresentationDataUtils

private final class MiraLocalEditState {
    var text: String

    init(text: String) {
        self.text = text
    }
}

private final class MiraLocalEditControllerArguments {
    let state: MiraLocalEditState

    init(state: MiraLocalEditState) {
        self.state = state
    }
}

private enum MiraLocalEditEntry: ItemListNodeEntry {
    case input(String)
    case hint(String)

    var section: ItemListSectionId {
        switch self {
        case .input:
            return 0
        case .hint:
            return 1
        }
    }

    var stableId: Int {
        switch self {
        case .input:
            return 0
        case .hint:
            return 1
        }
    }

    static func <(lhs: MiraLocalEditEntry, rhs: MiraLocalEditEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MiraLocalEditControllerArguments
        switch self {
        case let .input(text):
            return ItemListMultilineInputItem(presentationData: presentationData, text: text, placeholder: "Message text", maxLength: nil, sectionId: self.section, style: .blocks, textUpdated: { value in
                arguments.state.text = value
            })
        case let .hint(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func miraLocalEditController(context: AccountContext, messageId: MessageId, initialText: String) -> ViewController {
    let state = MiraLocalEditState(text: initialText)
    let arguments = MiraLocalEditControllerArguments(state: state)
    var dismissImpl: (() -> Void)?

    let signal = context.sharedContext.presentationData
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Edit locally"), leftNavigationButton: nil, rightNavigationButton: ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .regular, enabled: true, action: {
            if state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let _ = context.engine.messages.miraRemoveLocalMessageOverride(messageId: messageId).start()
            } else {
                let _ = context.engine.messages.miraSetLocalMessageOverride(messageId: messageId, text: state.text).start()
            }
            dismissImpl?()
        }), backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let entries: [MiraLocalEditEntry] = [
            .input(state.text),
            .hint("Only you can see this version of the message. Save an empty text to revert.")
        ]
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        (controller?.navigationController as? NavigationController)?.popViewController(animated: true)
    }
    return controller
}
