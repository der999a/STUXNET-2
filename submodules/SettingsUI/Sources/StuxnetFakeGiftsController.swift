import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext
import LocalizedPeerData
import OverlayStatusController

private func stuxnetFakeGiftTitle(_ gift: MiraFakeGift) -> String {
    if let snapshot = gift.giftSnapshot {
        switch snapshot {
        case let .generic(genericGift):
            return genericGift.title ?? "Gift #\(genericGift.id)"
        case let .unique(uniqueGift):
            return "\(uniqueGift.title) #\(uniqueGift.number)"
        }
    }
    switch gift.kind {
    case .regular:
        if let giftId = gift.giftId {
            return "Gift #\(giftId)"
        }
        return "Gift"
    case .uniqueBySlug, .uniqueById:
        if let uniqueNumber = gift.uniqueNumber {
            return "Unique #\(uniqueNumber)"
        }
        return gift.slug ?? "Unique Gift"
    }
}

private func stuxnetFakeGiftDateString(_ timestamp: Int32) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
}

private func stuxnetFakeGiftSubtitle(_ gift: MiraFakeGift) -> String {
    let fromPart: String
    if let fromName = gift.fromName, !fromName.isEmpty {
        fromPart = fromName
    } else if let fromPeerId = gift.fromPeerId {
        fromPart = "ID \(fromPeerId)"
    } else {
        fromPart = "Anonymous"
    }
    return "from \(fromPart) · \(stuxnetFakeGiftDateString(gift.date))"
}

private func stuxnetNormalizedGiftSlug(_ text: String) -> String {
    var slug = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let range = slug.range(of: "t.me/nft/", options: .caseInsensitive) {
        slug = String(slug[range.upperBound...])
    }
    if let queryIndex = slug.firstIndex(of: "?") {
        slug = String(slug[..<queryIndex])
    }
    if slug.hasPrefix("@") {
        slug = String(slug.dropFirst())
    }
    return slug
}

// MARK: - List controller

private final class StuxnetFakeGiftsControllerArguments {
    let addGift: () -> Void
    let editGift: (MiraFakeGift) -> Void

    init(addGift: @escaping () -> Void, editGift: @escaping (MiraFakeGift) -> Void) {
        self.addGift = addGift
        self.editGift = editGift
    }
}

private enum StuxnetFakeGiftsControllerSection: Int32 {
    case add
    case gifts
}

private enum StuxnetFakeGiftsControllerEntry: ItemListNodeEntry {
    case addGift(String)
    case giftsHeader(String)
    case gift(Int, MiraFakeGift, String, String)
    case emptyText(String)

    var section: ItemListSectionId {
        switch self {
        case .addGift:
            return StuxnetFakeGiftsControllerSection.add.rawValue
        case .giftsHeader, .gift, .emptyText:
            return StuxnetFakeGiftsControllerSection.gifts.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case .addGift:
            return 0
        case .giftsHeader:
            return 1
        case let .gift(index, _, _, _):
            return 2 + index
        case .emptyText:
            return 10000
        }
    }

    static func <(lhs: StuxnetFakeGiftsControllerEntry, rhs: StuxnetFakeGiftsControllerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! StuxnetFakeGiftsControllerArguments
        switch self {
        case let .addGift(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, titleColor: .accent, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.addGift()
            })
        case let .giftsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .gift(_, gift, title, subtitle):
            var badges: [String] = []
            if gift.isSaved {
                badges.append("Pinned")
            }
            if gift.isHidden {
                badges.append("Hidden")
            }
            let detail = badges.isEmpty ? subtitle : "\(subtitle) · \(badges.joined(separator: ", "))"
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: "", labelStyle: .detailText, additionalDetailLabel: detail, sectionId: self.section, style: .blocks, action: {
                arguments.editGift(gift)
            })
        case let .emptyText(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func stuxnetFakeGiftsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = StuxnetFakeGiftsControllerArguments(addGift: {
        pushControllerImpl?(stuxnetAddFakeGiftController(context: context))
    }, editGift: { gift in
        pushControllerImpl?(stuxnetAddFakeGiftController(context: context, editing: gift))
    })

    let signal = combineLatest(context.sharedContext.presentationData, context.account.miraFakeGiftsStore.changes)
    |> map { presentationData, gifts -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [StuxnetFakeGiftsControllerEntry] = []
        entries.append(.addGift("Add Gift"))
        entries.append(.giftsHeader("Fake Gifts".uppercased()))
        var index = 0
        for gift in gifts {
            entries.append(.gift(index, gift, stuxnetFakeGiftTitle(gift), stuxnetFakeGiftSubtitle(gift)))
            index += 1
        }
        if gifts.isEmpty {
            entries.append(.emptyText("No fake gifts yet. Added gifts appear on your own profile while Fake Gifts are enabled."))
        }

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Fake Gifts"), leftNavigationButton: nil, rightNavigationButton: ItemListNavigationButton(content: .icon(.add), style: .regular, enabled: true, action: {
            arguments.addGift()
        }), backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}

// MARK: - Add / edit gift controller

private enum StuxnetFakeGiftDatePreset: Equatable {
    case now
    case hourAgo
    case todayMorning
    case days(Int32)

    func timestamp() -> Int32 {
        let now = Date()
        switch self {
        case .now:
            return Int32(now.timeIntervalSince1970)
        case .hourAgo:
            return Int32(now.timeIntervalSince1970) - 3600
        case .todayMorning:
            let startOfDay = Calendar.current.startOfDay(for: now)
            return Int32(startOfDay.addingTimeInterval(9 * 3600).timeIntervalSince1970)
        case let .days(days):
            return Int32(now.timeIntervalSince1970) - days * 86400
        }
    }

    var title: String {
        switch self {
        case .now:
            return "Now"
        case .hourAgo:
            return "1 hour ago"
        case .todayMorning:
            return "Today morning"
        case let .days(days):
            switch days {
            case 1:
                return "Yesterday"
            case 7:
                return "7 days ago"
            case 30:
                return "30 days ago"
            case 90:
                return "90 days ago"
            default:
                return "\(days) days ago"
            }
        }
    }

    static func from(timestamp: Int32) -> StuxnetFakeGiftDatePreset {
        let now = Date()
        let diff = Int32(now.timeIntervalSince1970) - timestamp
        if diff < 40 * 60 {
            return .now
        } else if diff < 90 * 60 {
            return .hourAgo
        } else if diff < 86400, Calendar.current.isDateInToday(Date(timeIntervalSince1970: TimeInterval(timestamp))) {
            return .todayMorning
        } else {
            return .days(max(1, diff / 86400))
        }
    }
}

private struct StuxnetAddFakeGiftState: Equatable {
    var kind: MiraFakeGift.Kind = .regular
    var selectedGift: StarGift.Gift?
    var slugText: String = ""
    var fromText: String = ""
    var captionText: String = ""
    var datePreset: StuxnetFakeGiftDatePreset = .now
    var isHidden: Bool = false
    var isSaved: Bool = false
    var showInChat: Bool = false
    var isSaving: Bool = false
}

private final class StuxnetAddFakeGiftControllerArguments {
    let updateState: ((inout StuxnetAddFakeGiftState) -> Void) -> Void
    let openGiftPicker: () -> Void
    let openDatePicker: () -> Void
    let deleteGift: () -> Void

    init(updateState: @escaping ((inout StuxnetAddFakeGiftState) -> Void) -> Void, openGiftPicker: @escaping () -> Void, openDatePicker: @escaping () -> Void, deleteGift: @escaping () -> Void) {
        self.updateState = updateState
        self.openGiftPicker = openGiftPicker
        self.openDatePicker = openDatePicker
        self.deleteGift = deleteGift
    }
}

private enum StuxnetAddFakeGiftSection: Int32 {
    case type
    case gift
    case from
    case details
    case delete
}

private enum StuxnetAddFakeGiftEntry: ItemListNodeEntry {
    case typeHeader(String)
    case typeRegular(Bool)
    case typeUnique(Bool)
    case giftHeader(String)
    case giftPicker(String)
    case slugInput(String)
    case fromHeader(String)
    case fromInput(String)
    case detailsHeader(String)
    case captionInput(String)
    case dateRow(String)
    case hidden(Bool)
    case saved(Bool)
    case showInChat(Bool)
    case footerInfo(String)
    case deleteGift(String)

    var section: ItemListSectionId {
        switch self {
        case .typeHeader, .typeRegular, .typeUnique:
            return StuxnetAddFakeGiftSection.type.rawValue
        case .giftHeader, .giftPicker, .slugInput:
            return StuxnetAddFakeGiftSection.gift.rawValue
        case .fromHeader, .fromInput:
            return StuxnetAddFakeGiftSection.from.rawValue
        case .detailsHeader, .captionInput, .dateRow, .hidden, .saved, .showInChat, .footerInfo:
            return StuxnetAddFakeGiftSection.details.rawValue
        case .deleteGift:
            return StuxnetAddFakeGiftSection.delete.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case .typeHeader:
            return 0
        case .typeRegular:
            return 1
        case .typeUnique:
            return 2
        case .giftHeader:
            return 3
        case .giftPicker:
            return 4
        case .slugInput:
            return 5
        case .fromHeader:
            return 6
        case .fromInput:
            return 7
        case .detailsHeader:
            return 8
        case .captionInput:
            return 9
        case .dateRow:
            return 10
        case .hidden:
            return 11
        case .saved:
            return 12
        case .showInChat:
            return 13
        case .footerInfo:
            return 14
        case .deleteGift:
            return 15
        }
    }

    static func <(lhs: StuxnetAddFakeGiftEntry, rhs: StuxnetAddFakeGiftEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! StuxnetAddFakeGiftControllerArguments
        switch self {
        case let .typeHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .typeRegular(isSelected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: "Regular Gift", style: .right, checked: isSelected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.updateState { state in
                    state.kind = .regular
                }
            })
        case let .typeUnique(isSelected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: "Unique (NFT) Gift", style: .right, checked: isSelected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.updateState { state in
                    state.kind = .uniqueBySlug
                }
            })
        case let .giftHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .giftPicker(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Gift", label: label, labelStyle: .detailText, sectionId: self.section, style: .blocks, action: {
                arguments.openGiftPicker()
            })
        case let .slugInput(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: "Slug"), text: text, placeholder: "PlushPepe-12345", type: .regular(capitalization: false, autocorrection: false), sectionId: self.section, textUpdated: { value in
                arguments.updateState { state in
                    state.slugText = value
                }
            }, action: {})
        case let .fromHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .fromInput(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: "From"), text: text, placeholder: "@username or user ID", type: .regular(capitalization: false, autocorrection: false), sectionId: self.section, textUpdated: { value in
                arguments.updateState { state in
                    state.fromText = value
                }
            }, action: {})
        case let .detailsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .captionInput(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: "Caption"), text: text, placeholder: "Optional caption", type: .regular(capitalization: true, autocorrection: true), sectionId: self.section, textUpdated: { value in
                arguments.updateState { state in
                    state.captionText = value
                }
            }, action: {})
        case let .dateRow(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Date", label: label, labelStyle: .detailText, sectionId: self.section, style: .blocks, action: {
                arguments.openDatePicker()
            })
        case let .hidden(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hidden", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateState { state in
                    state.isHidden = value
                }
            })
        case let .saved(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Saved (Pinned on Profile)", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateState { state in
                    state.isSaved = value
                }
            })
        case let .showInChat(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Show in Chat", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateState { state in
                    state.showInChat = value
                }
            })
        case let .footerInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .deleteGift(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.deleteGift()
            })
        }
    }
}

public func stuxnetAddFakeGiftController(context: AccountContext, editing existingGift: MiraFakeGift? = nil) -> ViewController {
    let initialState: StuxnetAddFakeGiftState
    if let existingGift {
        var state = StuxnetAddFakeGiftState()
        state.kind = existingGift.kind == .regular ? .regular : .uniqueBySlug
        if let snapshot = existingGift.giftSnapshot, case let .generic(genericGift) = snapshot {
            state.selectedGift = genericGift
        }
        state.slugText = existingGift.slug ?? ""
        state.fromText = existingGift.fromPeerId.flatMap { "\($0)" } ?? existingGift.fromName ?? ""
        state.captionText = existingGift.caption ?? ""
        state.datePreset = StuxnetFakeGiftDatePreset.from(timestamp: existingGift.date)
        state.isHidden = existingGift.isHidden
        state.isSaved = existingGift.isSaved
        state.showInChat = existingGift.showInChat
        initialState = state
    } else {
        initialState = StuxnetAddFakeGiftState()
    }

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    var currentState = initialState
    let updateState: ((inout StuxnetAddFakeGiftState) -> Void) -> Void = { f in
        f(&currentState)
        statePromise.set(currentState)
    }

    var pushControllerImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?
    var dismissImpl: (() -> Void)?
    var currentPresentationData: PresentationData = context.sharedContext.currentPresentationData.with { $0 }
    var currentOverlay: ViewController?

    let store = context.account.miraFakeGiftsStore

    let persistAndSync: (MiraFakeGift) -> Void = { gift in
        var gift = gift
        gift.chatMessagePeerId = nil
        gift.chatMessageId = nil
        let removeOld: Signal<Void, NoError> = existingGift.map { store.deleteChatMessageSignal(account: context.account, entry: $0) } ?? .single(())
        let sync = removeOld |> mapToSignal { _ -> Signal<MiraFakeGift, NoError> in
            if gift.showInChat {
                return store.insertChatMessage(account: context.account, entry: gift)
            } else {
                return .single(gift)
            }
        }
        let _ = (sync |> deliverOnMainQueue).start(next: { updatedGift in
            // Upsert keeps a fast edit/insert sequence idempotent even when the
            // previous chat-message deletion finishes after the settings write.
            store.upsert(updatedGift)
            dismissImpl?()
        })
    }

    let resolveFromAndSave: (MiraFakeGift) -> Void = { gift in
        var gift = gift
        let fromText = currentState.fromText.trimmingCharacters(in: .whitespacesAndNewlines)
        if fromText.isEmpty {
            persistAndSync(gift)
            return
        }
        if let peerIdValue = Int64(fromText) {
            gift.fromPeerId = peerIdValue
            if let existingGift, existingGift.fromPeerId == peerIdValue, let existingName = existingGift.fromName {
                gift.fromName = existingName
            } else {
                gift.fromName = "ID \(peerIdValue)"
            }
            persistAndSync(gift)
            return
        }
        var name = fromText
        if name.hasPrefix("@") {
            name = String(name.dropFirst())
        }
        if let range = name.range(of: "t.me/", options: .caseInsensitive) {
            name = String(name[range.upperBound...])
        }
        if let queryIndex = name.firstIndex(of: "?") {
            name = String(name[..<queryIndex])
        }
        let overlay = OverlayStatusController(theme: currentPresentationData.theme, type: .loading(cancelled: nil))
        presentControllerImpl?(overlay)
        currentOverlay = overlay
        let _ = (context.engine.peers.resolvePeerByName(name: name, referrer: nil)
        |> deliverOnMainQueue).start(next: { result in
            if case let .result(peer) = result {
                currentOverlay?.dismiss()
                currentOverlay = nil
                if let peer {
                    gift.fromPeerId = peer.id.toInt64()
                    gift.fromName = peer.compactDisplayTitle
                } else {
                    gift.fromPeerId = nil
                    gift.fromName = name
                }
                persistAndSync(gift)
            }
        })
    }

    let saveImpl: () -> Void = {
        let state = currentState
        guard !state.isSaving else {
            return
        }
        let caption = state.captionText.trimmingCharacters(in: .whitespacesAndNewlines)
        var gift = MiraFakeGift(
            id: existingGift?.id ?? UUID().uuidString,
            kind: state.kind,
            caption: caption.isEmpty ? nil : caption,
            date: state.datePreset.timestamp(),
            isHidden: state.isHidden,
            isSaved: state.isSaved,
            showInChat: state.showInChat
        )
        switch state.kind {
        case .regular:
            guard let selectedGift = state.selectedGift else {
                return
            }
            gift.giftId = selectedGift.id
            gift.giftSnapshot = .generic(selectedGift)
            resolveFromAndSave(gift)
        case .uniqueBySlug, .uniqueById:
            let slug = stuxnetNormalizedGiftSlug(state.slugText)
            guard !slug.isEmpty else {
                return
            }
            if let existingGift, existingGift.slug == slug, let snapshot = existingGift.giftSnapshot, case let .unique(uniqueGift) = snapshot {
                gift.slug = uniqueGift.slug
                gift.uniqueNumber = uniqueGift.number
                gift.giftSnapshot = snapshot
                resolveFromAndSave(gift)
                return
            }
            updateState { $0.isSaving = true }
            let overlay = OverlayStatusController(theme: currentPresentationData.theme, type: .loading(cancelled: nil))
            presentControllerImpl?(overlay)
            currentOverlay = overlay
            let _ = (context.engine.payments.getUniqueStarGift(slug: slug)
            |> deliverOnMainQueue).start(next: { uniqueGift in
                currentOverlay?.dismiss()
                currentOverlay = nil
                updateState { $0.isSaving = false }
                gift.kind = .uniqueBySlug
                gift.slug = uniqueGift.slug
                gift.uniqueNumber = uniqueGift.number
                gift.giftSnapshot = .unique(uniqueGift)
                resolveFromAndSave(gift)
            }, error: { _ in
                currentOverlay?.dismiss()
                currentOverlay = nil
                updateState { $0.isSaving = false }
                presentControllerImpl?(textAlertController(context: context, title: "Gift Not Found", text: "Could not find a unique gift with this slug. Check the slug or paste a t.me/nft/ link.", actions: [TextAlertAction(type: .defaultAction, title: "OK", action: {})]))
            })
        }
    }

    let arguments = StuxnetAddFakeGiftControllerArguments(updateState: updateState, openGiftPicker: {
        pushControllerImpl?(stuxnetFakeGiftPickerController(context: context, currentGiftId: currentState.selectedGift?.id, select: { gift in
            updateState { state in
                state.selectedGift = gift
            }
        }))
    }, openDatePicker: {
        pushControllerImpl?(stuxnetFakeGiftDatePickerController(context: context, currentPreset: currentState.datePreset, select: { preset in
            updateState { state in
                state.datePreset = preset
            }
        }))
    }, deleteGift: {
        guard let existingGift else {
            return
        }
        store.deleteChatMessage(account: context.account, entry: existingGift)
        store.remove(id: existingGift.id)
        dismissImpl?()
    })

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        currentPresentationData = presentationData

        var entries: [StuxnetAddFakeGiftEntry] = []
        entries.append(.typeHeader("Gift Type".uppercased()))
        entries.append(.typeRegular(state.kind == .regular))
        entries.append(.typeUnique(state.kind != .regular))

        entries.append(.giftHeader("Gift".uppercased()))
        if state.kind == .regular {
            let label: String
            if let selectedGift = state.selectedGift {
                label = selectedGift.title ?? "Gift #\(selectedGift.id)"
            } else {
                label = "Not Selected"
            }
            entries.append(.giftPicker(label))
        } else {
            entries.append(.slugInput(state.slugText))
        }

        entries.append(.fromHeader("Sender".uppercased()))
        entries.append(.fromInput(state.fromText))

        entries.append(.detailsHeader("Details".uppercased()))
        entries.append(.captionInput(state.captionText))
        entries.append(.dateRow(state.datePreset.title))
        entries.append(.hidden(state.isHidden))
        entries.append(.saved(state.isSaved))
        entries.append(.showInChat(state.showInChat))
        entries.append(.footerInfo("The gift is only visible to you, on your own profile, while Fake Gifts are enabled."))

        if existingGift != nil {
            entries.append(.deleteGift("Delete Gift"))
        }

        let canSave: Bool
        switch state.kind {
        case .regular:
            canSave = state.selectedGift != nil && !state.isSaving
        case .uniqueBySlug, .uniqueById:
            canSave = !stuxnetNormalizedGiftSlug(state.slugText).isEmpty && !state.isSaving
        }

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(existingGift != nil ? "Edit Fake Gift" : "Add Fake Gift"), leftNavigationButton: nil, rightNavigationButton: ItemListNavigationButton(content: .text("Save"), style: .bold, enabled: canSave, action: {
            saveImpl()
        }), backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    dismissImpl = { [weak controller] in
        controller?.dismiss()
    }
    return controller
}

// MARK: - Regular gift picker (catalog)

private final class StuxnetFakeGiftPickerArguments {
    let select: (StarGift.Gift) -> Void

    init(select: @escaping (StarGift.Gift) -> Void) {
        self.select = select
    }

    private let disposable = MetaDisposable()
    private let updateDisposable = MetaDisposable()
    let catalogPromise = ValuePromise<[StarGift.Gift]?>(nil, ignoreRepeated: true)

    func load(context: AccountContext) {
        // Reuse snapshots from previously configured gifts when Telegram's
        // catalog is unavailable. Snapshots contain the real media resource,
        // so offline entries still render like normal Telegram gifts.
        let fallbackGifts: [StarGift.Gift] = context.account.miraFakeGiftsStore.list().compactMap { entry in
            guard let snapshot = entry.giftSnapshot else {
                return nil
            }
            if case let .generic(gift) = snapshot {
                return gift
            }
            return nil
        }
        self.disposable.set((context.engine.payments.cachedStarGifts()
        |> timeout(3.0, queue: .mainQueue(), alternate: .single(nil))
        |> map { items -> [StarGift.Gift]? in
            let catalogGifts = items?.compactMap { gift -> StarGift.Gift? in
                if case let .generic(genericGift) = gift {
                    return genericGift
                }
                return nil
            }
            if let catalogGifts, !catalogGifts.isEmpty {
                return catalogGifts
            }
            return fallbackGifts.isEmpty ? [] : fallbackGifts
        }
        |> deliverOnMainQueue).start(next: { [weak self] gifts in
            self?.catalogPromise.set(gifts)
        }))
        self.updateDisposable.set(context.engine.payments.keepStarGiftsUpdated().start())
    }

    deinit {
        self.disposable.dispose()
        self.updateDisposable.dispose()
    }
}

private enum StuxnetFakeGiftPickerEntry: ItemListNodeEntry {
    case gift(Int, StarGift.Gift, Bool)
    case loading(String)
    case empty(String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int {
        switch self {
        case let .gift(index, _, _):
            return index
        case .loading:
            return 100000
        case .empty:
            return 100001
        }
    }

    static func <(lhs: StuxnetFakeGiftPickerEntry, rhs: StuxnetFakeGiftPickerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! StuxnetFakeGiftPickerArguments
        switch self {
        case let .gift(_, gift, isSelected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: gift.title ?? "Gift #\(gift.id)", subtitle: "★ \(gift.price)", style: .right, checked: isSelected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.select(gift)
            })
        case let .loading(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func stuxnetFakeGiftPickerController(context: AccountContext, currentGiftId: Int64?, select: @escaping (StarGift.Gift) -> Void) -> ViewController {
    var dismissImpl: (() -> Void)?

    let arguments = StuxnetFakeGiftPickerArguments(select: { gift in
        select(gift)
        dismissImpl?()
    })
    arguments.load(context: context)

    let signal = combineLatest(context.sharedContext.presentationData, arguments.catalogPromise.get())
    |> map { presentationData, gifts -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [StuxnetFakeGiftPickerEntry] = []
        if let gifts, !gifts.isEmpty {
            var index = 0
            for gift in gifts {
                entries.append(.gift(index, gift, gift.id == currentGiftId))
                index += 1
            }
        } else if gifts == nil {
            entries.append(.loading("Loading gifts..."))
        } else {
            entries.append(.empty("No cached gifts available. Add a gift while online, then it will remain available here offline."))
        }

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Select Gift"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        controller?.dismiss()
    }
    return controller
}

// MARK: - Date picker

private final class StuxnetFakeGiftDatePickerArguments {
    let select: (StuxnetFakeGiftDatePreset) -> Void
    let updateCustomDays: (String) -> Void

    init(select: @escaping (StuxnetFakeGiftDatePreset) -> Void, updateCustomDays: @escaping (String) -> Void) {
        self.select = select
        self.updateCustomDays = updateCustomDays
    }
}

private enum StuxnetFakeGiftDatePickerEntry: ItemListNodeEntry {
    case option(Int, StuxnetFakeGiftDatePreset, String, Bool)
    case customDays(String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int {
        switch self {
        case let .option(index, _, _, _):
            return index
        case .customDays:
            return 100000
        }
    }

    static func <(lhs: StuxnetFakeGiftDatePickerEntry, rhs: StuxnetFakeGiftDatePickerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! StuxnetFakeGiftDatePickerArguments
        switch self {
        case let .option(_, preset, title, isSelected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .right, checked: isSelected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.select(preset)
            })
        case let .customDays(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: "Custom"), text: text, placeholder: "Days back", type: .number, returnKeyType: .done, sectionId: self.section, textUpdated: { value in
                arguments.updateCustomDays(value)
            }, action: {})
        }
    }
}

private func stuxnetFakeGiftDatePickerController(context: AccountContext, currentPreset: StuxnetFakeGiftDatePreset, select: @escaping (StuxnetFakeGiftDatePreset) -> Void) -> ViewController {
    var dismissImpl: (() -> Void)?

    var customDaysText: String = ""
    if case let .days(days) = currentPreset, ![1, 7, 30, 90].contains(days) {
        customDaysText = "\(days)"
    }

    let applyCustom: () -> Void = {
        if let days = Int32(customDaysText), days >= 0 {
            select(.days(days))
            dismissImpl?()
        }
    }

    let arguments = StuxnetFakeGiftDatePickerArguments(select: { preset in
        select(preset)
        dismissImpl?()
    }, updateCustomDays: { value in
        customDaysText = value
    })

    let presets: [StuxnetFakeGiftDatePreset] = [.now, .hourAgo, .todayMorning, .days(1), .days(7), .days(30), .days(90)]

    let signal = context.sharedContext.presentationData
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [StuxnetFakeGiftDatePickerEntry] = []
        var index = 0
        for preset in presets {
            entries.append(.option(index, preset, preset.title, preset == currentPreset))
            index += 1
        }
        entries.append(.customDays(customDaysText))

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Gift Date"), leftNavigationButton: nil, rightNavigationButton: ItemListNavigationButton(content: .text("Done"), style: .bold, enabled: true, action: {
            applyCustom()
            dismissImpl?()
        }), backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        controller?.dismiss()
    }
    return controller
}
