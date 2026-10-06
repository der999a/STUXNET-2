import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import PresentationDataUtils

private enum MiraEditHistoryEntry: ItemListNodeEntry {
    case revision(Int, String, String)

    var section: ItemListSectionId {
        switch self {
        case let .revision(index, _, _):
            return Int32(index)
        }
    }

    var stableId: Int {
        switch self {
        case let .revision(index, _, _):
            return index
        }
    }

    static func <(lhs: MiraEditHistoryEntry, rhs: MiraEditHistoryEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .revision(_, dateString, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain("\(dateString)\n\(text)"), sectionId: self.section)
        }
    }
}

private func miraEditHistoryEntries(edits: [MiraMessageEditRecord]) -> [MiraEditHistoryEntry] {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short

    var entries: [MiraEditHistoryEntry] = []
    for (index, edit) in edits.enumerated() {
        let dateString: String
        if let editDate = edit.editDate, editDate != 0 {
            dateString = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(editDate)))
        } else {
            dateString = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(edit.date)))
        }
        entries.append(.revision(index, dateString, edit.text))
    }
    return entries
}

public func miraEditHistoryController(context: AccountContext, edits: [MiraMessageEditRecord]) -> ViewController {
    let signal = context.sharedContext.presentationData
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Edit history"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: miraEditHistoryEntries(edits: edits), style: .blocks)

        return (controllerState, (listState, ()))
    }

    return ItemListController(context: context, state: signal)
}
