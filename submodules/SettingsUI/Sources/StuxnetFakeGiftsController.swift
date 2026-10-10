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
import ItemListDatePickerItem

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
    // Telegram shows the exact time for gift entries when the detail is open.
    // Keep seconds here as well so two gifts created in the same minute remain
    // distinguishable while still following the device's locale and 12/24-hour
    // preference.
    formatter.timeStyle = .medium
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
    var details = "from \(fromPart) · \(stuxnetFakeGiftDateString(gift.date))"
    if case let .generic(genericGift) = gift.giftSnapshot, genericGift.convertStars > 0 {
        details += " · converts to \(genericGift.convertStars) Stars"
    }
    return details
}

private func stuxnetFakeGiftKindLabel(_ gift: MiraFakeGift) -> String {
    switch gift.kind {
    case .regular:
        return "Regular"
    case .uniqueBySlug, .uniqueById:
        return "NFT"
    }
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
            var badges: [String] = [stuxnetFakeGiftKindLabel(gift)]
            if gift.isSaved {
                badges.append("Pinned")
            }
            if gift.isHidden {
                badges.append("Hidden")
            }
            if gift.showInChat {
                badges.append("In chat")
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
        }), backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)
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
    case exact(Int32)

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
            return Int32(clamping: Int64(now.timeIntervalSince1970) - Int64(days) * 86400)
        case let .exact(timestamp):
            return timestamp
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
        case let .exact(timestamp):
            return stuxnetFakeGiftDateString(timestamp)
        }
    }

    static func from(timestamp: Int32) -> StuxnetFakeGiftDatePreset {
        let now = Date()
        let diff = Int64(now.timeIntervalSince1970) - Int64(timestamp)
        if diff < 40 * 60 {
            return .now
        } else if diff < 90 * 60 {
            return .hourAgo
        } else if diff < 86400, Calendar.current.isDateInToday(Date(timeIntervalSince1970: TimeInterval(timestamp))) {
            return .todayMorning
        } else {
            return .days(Int32(clamping: max(1, diff / 86400)))
        }
    }
}

private struct StuxnetAddFakeGiftState: Equatable {
    var kind: MiraFakeGift.Kind = .regular
    var selectedGift: StarGift.Gift?
    var slugText: String = ""
    var fromText: String = ""
    var selectedSenderId: EnginePeer.Id?
    var selectedSenderName: String?
    var captionText: String = ""
    var datePreset: StuxnetFakeGiftDatePreset = .now
    // Preserve an edited gift's exact timestamp until the user explicitly
    // chooses another date preset.
    var exactTimestamp: Int32?
    var isHidden: Bool = false
    var isSaved: Bool = false
    var showInChat: Bool = false
    // Telegram's collectible transfer price is 25 Stars. Keep the value
    // visible in the editor so a newly-created NFT cannot accidentally be
    // persisted as a free transfer.
    var transferStarsText: String = "25"
    var isSaving: Bool = false
}

private final class StuxnetAddFakeGiftControllerArguments {
    let updateState: ((inout StuxnetAddFakeGiftState) -> Void) -> Void
    let openGiftPicker: () -> Void
    let openDatePicker: () -> Void
    let openSenderPicker: () -> Void
    let deleteGift: () -> Void

    init(updateState: @escaping ((inout StuxnetAddFakeGiftState) -> Void) -> Void, openGiftPicker: @escaping () -> Void, openDatePicker: @escaping () -> Void, openSenderPicker: @escaping () -> Void, deleteGift: @escaping () -> Void) {
        self.updateState = updateState
        self.openGiftPicker = openGiftPicker
        self.openDatePicker = openDatePicker
        self.openSenderPicker = openSenderPicker
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
    case fromPicker(String)
    case detailsHeader(String)
    case captionInput(String)
    case dateRow(String)
    case hidden(Bool)
    case saved(Bool)
    case showInChat(Bool)
    case transferStarsInput(String)
    case footerInfo(String)
    case deleteGift(String)

    var section: ItemListSectionId {
        switch self {
        case .typeHeader, .typeRegular, .typeUnique:
            return StuxnetAddFakeGiftSection.type.rawValue
        case .giftHeader, .giftPicker, .slugInput:
            return StuxnetAddFakeGiftSection.gift.rawValue
        case .fromHeader, .fromInput, .fromPicker:
            return StuxnetAddFakeGiftSection.from.rawValue
        case .detailsHeader, .captionInput, .dateRow, .hidden, .saved, .showInChat, .transferStarsInput, .footerInfo:
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
        case .fromPicker:
            return 8
        case .detailsHeader:
            return 9
        case .captionInput:
            return 10
        case .dateRow:
            return 11
        case .hidden:
            return 12
        case .saved:
            return 13
        case .showInChat:
            return 14
        case .transferStarsInput:
            return 15
        case .footerInfo:
            return 16
        case .deleteGift:
            return 17
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
                    state.selectedSenderId = nil
                    state.selectedSenderName = nil
                }
            }, action: {})
        case let .fromPicker(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: presentationData.strings.baseLanguageCode.hasPrefix("ru") ? "Выбрать отправителя" : "Choose sender", label: label, sectionId: self.section, style: .blocks, action: arguments.openSenderPicker)
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
        case let .transferStarsInput(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: "NFT transfer fee (Stars)"), text: text, placeholder: "0", type: .number, sectionId: self.section, textUpdated: { value in
                arguments.updateState { state in
                    state.transferStarsText = value
                }
            }, action: {})
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
        state.datePreset = .exact(existingGift.date)
        state.exactTimestamp = existingGift.date
        state.isHidden = existingGift.isHidden
        state.isSaved = existingGift.isSaved
        state.showInChat = existingGift.showInChat
        state.transferStarsText = existingGift.isUnique
            ? String(max(MiraFakeGift.defaultNFTTransferStars, existingGift.transferStars ?? MiraFakeGift.defaultNFTTransferStars))
            : String(MiraFakeGift.defaultNFTTransferStars)
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
    var didDelete = false
    var currentPresentationData: PresentationData = context.sharedContext.currentPresentationData.with { $0 }
    var currentOverlay: ViewController?
    let operationDisposable = MetaDisposable()

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
            guard !didDelete else {
                return
            }
            // Upsert keeps a fast edit/insert sequence idempotent even when the
            // previous chat-message deletion finishes after the settings write.
            store.upsert(updatedGift)
            updateState { $0.isSaving = false }
            dismissImpl?()
        })
    }

    let resolveFromAndSave: (MiraFakeGift, String) -> Void = { gift, senderText in
        var gift = gift
        // Use the snapshot captured by Save. Reading currentState here lets a
        // later keystroke change the sender while an NFT lookup is in flight.
        let fromText = senderText.trimmingCharacters(in: .whitespacesAndNewlines)
        if gift.fromPeerId != nil {
            persistAndSync(gift)
            return
        }
        if fromText.isEmpty {
            persistAndSync(gift)
            return
        }
        if let peerIdValue = Int64(fromText) {
            guard MiraFakeGift.peerId(fromStoredValue: peerIdValue, isPacked: false) != nil else {
                updateState { $0.isSaving = false }
                presentControllerImpl?(textAlertController(context: context, title: "Invalid user ID", text: "Enter a Telegram user ID or @username.", actions: [TextAlertAction(type: .defaultAction, title: currentPresentationData.strings.Common_OK, action: {})]))
                return
            }
            gift.fromPeerId = peerIdValue
            gift.fromPeerIdIsPacked = false
            if let existingGift, existingGift.fromPeerId == peerIdValue, let existingName = existingGift.fromName {
                gift.fromName = existingName
                gift.fromPeerIdIsPacked = existingGift.fromPeerIdIsPacked
            } else {
                gift.fromName = "ID \(peerIdValue)"
            }
            guard let storedId = MiraFakeGift.peerId(fromStoredValue: peerIdValue, isPacked: gift.fromPeerIdIsPacked) else {
                updateState { $0.isSaving = false }
                return
            }
            operationDisposable.set((context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: storedId))
            |> deliverOnMainQueue).start(next: { peer in
                if let peer, case .user = peer {
                    gift.fromName = peer.compactDisplayTitle
                }
                persistAndSync(gift)
            }))
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
        operationDisposable.set((context.engine.peers.resolvePeerByName(name: name, referrer: nil)
        |> deliverOnMainQueue).start(next: { result in
            guard !didDelete else {
                return
            }
            if case let .result(peer) = result {
                currentOverlay?.dismiss()
                currentOverlay = nil
                if let peer {
                    gift.fromPeerId = peer.id.toInt64()
                    gift.fromPeerIdIsPacked = true
                    gift.fromName = peer.compactDisplayTitle
                } else {
                    gift.fromPeerId = nil
                    gift.fromName = name
                }
                persistAndSync(gift)
            }
        }))
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
            date: state.exactTimestamp ?? state.datePreset.timestamp(),
            isHidden: state.isHidden,
            isSaved: state.isSaved,
            showInChat: state.showInChat,
            transferStars: state.kind == .regular
                ? nil
                : max(MiraFakeGift.defaultNFTTransferStars, Int64(state.transferStarsText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? MiraFakeGift.defaultNFTTransferStars)
        )
        if let senderId = state.selectedSenderId {
            gift.fromPeerId = senderId.toInt64()
            gift.fromPeerIdIsPacked = true
            gift.fromName = state.selectedSenderName
        } else if let existingGift, let existingSenderId = existingGift.fromPeerId,
                  state.fromText == String(existingSenderId) {
            // Preserve unchanged stored sender ids in their original format.
            // Legacy entries can be raw or packed; resolving the displayed
            // number again as a raw user id can corrupt a packed sender.
            gift.fromPeerId = existingSenderId
            gift.fromPeerIdIsPacked = existingGift.fromPeerIdIsPacked
            gift.fromName = existingGift.fromName
        }
        switch state.kind {
        case .regular:
            guard let selectedGift = state.selectedGift else {
                return
            }
            updateState { $0.isSaving = true }
            gift.giftId = selectedGift.id
            gift.giftSnapshot = .generic(selectedGift)
            resolveFromAndSave(gift, state.fromText)
        case .uniqueBySlug, .uniqueById:
            let slug = stuxnetNormalizedGiftSlug(state.slugText)
            guard !slug.isEmpty else {
                return
            }
            updateState { $0.isSaving = true }
            if let existingGift, existingGift.slug == slug, let snapshot = existingGift.giftSnapshot, case let .unique(uniqueGift) = snapshot {
                gift.slug = uniqueGift.slug
                gift.uniqueNumber = uniqueGift.number
                gift.giftSnapshot = snapshot
                resolveFromAndSave(gift, state.fromText)
                return
            }
            let overlay = OverlayStatusController(theme: currentPresentationData.theme, type: .loading(cancelled: nil))
            presentControllerImpl?(overlay)
            currentOverlay = overlay
            operationDisposable.set((context.engine.payments.getUniqueStarGift(slug: slug)
            |> deliverOnMainQueue).start(next: { uniqueGift in
                guard !didDelete else {
                    return
                }
                currentOverlay?.dismiss()
                currentOverlay = nil
                gift.kind = .uniqueBySlug
                gift.slug = uniqueGift.slug
                gift.uniqueNumber = uniqueGift.number
                gift.giftSnapshot = .unique(uniqueGift)
                resolveFromAndSave(gift, state.fromText)
            }, error: { _ in
                guard !didDelete else {
                    return
                }
                currentOverlay?.dismiss()
                currentOverlay = nil
                updateState { $0.isSaving = false }
                presentControllerImpl?(textAlertController(context: context, title: "Gift Not Found", text: "Could not find a unique gift with this slug. Check the slug or paste a t.me/nft/ link.", actions: [TextAlertAction(type: .defaultAction, title: "OK", action: {})]))
            }))
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
                // Selecting a preset is an explicit date change; don't keep
                // the exact timestamp captured when an existing gift loaded.
                state.exactTimestamp = nil
            }
        }))
    }, openSenderPicker: {
        let picker = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.onlyPrivateChats, .excludeSavedMessages, .removeSearchHeader, .excludeRecent, .doNotSearchMessages], title: currentPresentationData.strings.baseLanguageCode.hasPrefix("ru") ? "Отправитель подарка" : "Gift sender"))
        picker.peerSelected = { [weak picker] peer, _ in
            guard case .user = peer else {
                return
            }
            updateState { state in
                state.selectedSenderId = peer.id
                state.selectedSenderName = peer.compactDisplayTitle
                state.fromText = String(peer.id.toInt64())
            }
            if let picker, let navigationController = picker.navigationController as? NavigationController, navigationController.topViewController === picker {
                _ = navigationController.popViewController(animated: true)
            } else {
                picker?.dismiss()
            }
        }
        pushControllerImpl?(picker)
    }, deleteGift: {
        guard let existingGift else {
            return
        }
        let alert = textAlertController(
            context: context,
            title: "Delete Gift?",
            text: "This gift will be removed from your local profile preview and chat.",
            actions: [
                TextAlertAction(type: .genericAction, title: currentPresentationData.strings.Common_Cancel, action: {}),
                TextAlertAction(type: .defaultDestructiveAction, title: currentPresentationData.strings.Common_Delete, action: {
                    didDelete = true
                    updateState { $0.isSaving = true }
                    operationDisposable.set((store.deleteChatMessageSignal(account: context.account, entry: existingGift)
                    |> deliverOnMainQueue).start(completed: {
                        store.remove(id: existingGift.id)
                    }))
                    dismissImpl?()
                })
            ]
        )
        presentControllerImpl?(alert)
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
        entries.append(.fromPicker(state.selectedSenderName ?? ""))

        entries.append(.detailsHeader("Details".uppercased()))
        entries.append(.captionInput(state.captionText))
        entries.append(.dateRow(state.datePreset.title))
        entries.append(.hidden(state.isHidden))
        entries.append(.saved(state.isSaved))
        entries.append(.showInChat(state.showInChat))
        if state.kind != .regular {
            entries.append(.transferStarsInput(state.transferStarsText))
        }
        entries.append(.footerInfo("Fake gifts stay local. NFT transfers use Telegram's 25 Stars fee and are recorded in the local Stars history."))

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
        }), backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)
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
        // Deletion is intentionally allowed to finish after the editor is
        // dismissed; cancelling it here would leave the old local entry alive.
        if !didDelete {
            operationDisposable.dispose()
        }
        currentOverlay?.dismiss()
        currentOverlay = nil
        guard let controller else {
            return
        }
        if let navigationController = controller.navigationController as? NavigationController, navigationController.topViewController === controller {
            _ = navigationController.popViewController(animated: true)
        } else {
            controller.dismiss()
        }
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

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Select Gift"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        guard let controller else {
            return
        }
        if let navigationController = controller.navigationController as? NavigationController, navigationController.topViewController === controller {
            _ = navigationController.popViewController(animated: true)
        } else {
            controller.dismiss()
        }
    }
    return controller
}

// MARK: - Date picker

private final class StuxnetFakeGiftDatePickerArguments {
    let select: (StuxnetFakeGiftDatePreset) -> Void
    let updateCustomDays: (String) -> Void
    let updateExactDate: (Int32) -> Void
    let updateSeconds: (String) -> Void
    let toggleDateSelection: (Bool) -> Void

    init(select: @escaping (StuxnetFakeGiftDatePreset) -> Void, updateCustomDays: @escaping (String) -> Void, updateExactDate: @escaping (Int32) -> Void, updateSeconds: @escaping (String) -> Void, toggleDateSelection: @escaping (Bool) -> Void) {
        self.select = select
        self.updateCustomDays = updateCustomDays
        self.updateExactDate = updateExactDate
        self.updateSeconds = updateSeconds
        self.toggleDateSelection = toggleDateSelection
    }
}

private enum StuxnetFakeGiftDatePickerEntry: ItemListNodeEntry {
    case option(Int, StuxnetFakeGiftDatePreset, String, Bool)
    case customDays(String)
    case exactDate(Int32, Bool)
    case seconds(String)
    case info(String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int {
        switch self {
        case let .option(index, _, _, _):
            return index
        case .customDays:
            return 100000
        case .exactDate:
            return 100001
        case .seconds:
            return 100002
        case .info:
            return 100003
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
            let title = presentationData.strings.baseLanguageCode.hasPrefix("ru") ? "Дней назад" : "Days back"
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: title), text: text, placeholder: "0", type: .number, returnKeyType: .done, sectionId: self.section, textUpdated: { value in
                arguments.updateCustomDays(value)
            }, action: {})
        case let .exactDate(timestamp, selectingDate):
            let russian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
            return ItemListDatePickerItem(presentationData: presentationData, systemStyle: .glass, dateTimeFormat: presentationData.dateTimeFormat, date: timestamp, minDate: 0, title: russian ? "Дата и время" : "Date & time", displayingDateSelection: selectingDate, displayingTimeSelection: !selectingDate, sectionId: self.section, style: .blocks, toggleDateSelection: {
                arguments.toggleDateSelection(true)
            }, toggleTimeSelection: {
                arguments.toggleDateSelection(false)
            }, updated: { date in
                arguments.updateExactDate(date)
            })
        case let .seconds(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: presentationData.strings.baseLanguageCode.hasPrefix("ru") ? "Секунды" : "Seconds"), text: text, placeholder: "0–59", type: .number, returnKeyType: .done, sectionId: self.section, textUpdated: arguments.updateSeconds, action: {})
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func stuxnetFakeGiftDatePickerController(context: AccountContext, currentPreset: StuxnetFakeGiftDatePreset, select: @escaping (StuxnetFakeGiftDatePreset) -> Void) -> ViewController {
    var dismissImpl: (() -> Void)?
    let revision = ValuePromise<Int>(0)
    var version = 0
    let refresh: () -> Void = {
        version += 1
        revision.set(version)
    }
    var exactDate = currentPreset.timestamp()
    var selectingDate = true
    var secondsText = String(format: "%02d", Calendar.current.component(.second, from: Date(timeIntervalSince1970: TimeInterval(exactDate))))
    var customDateChanged = false

    var customDaysText: String = ""
    if case let .days(days) = currentPreset, ![1, 7, 30, 90].contains(days) {
        customDaysText = "\(days)"
    }

    let applyCustom: () -> Void = {
        if !customDateChanged, let days = Int32(customDaysText), days >= 0 {
            select(.days(days))
        } else {
            select(.exact(exactDate))
        }
        dismissImpl?()
    }

    let arguments = StuxnetFakeGiftDatePickerArguments(select: { preset in
        select(preset)
        dismissImpl?()
    }, updateCustomDays: { value in
        customDaysText = value
        customDateChanged = false
    }, updateExactDate: { timestamp in
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
        components.second = calendar.component(.second, from: Date(timeIntervalSince1970: TimeInterval(exactDate)))
        if let date = calendar.date(from: components) {
            exactDate = Int32(clamping: Int64(date.timeIntervalSince1970))
            customDateChanged = true
            refresh()
        }
    }, updateSeconds: { value in
        secondsText = value
        if let seconds = Int(value), (0 ... 59).contains(seconds) {
            let calendar = Calendar.current
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(exactDate)))
            components.second = seconds
            if let date = calendar.date(from: components) {
                exactDate = Int32(clamping: Int64(date.timeIntervalSince1970))
                customDateChanged = true
            }
        }
        refresh()
    }, toggleDateSelection: { value in
        selectingDate = value
        refresh()
    })

    let presets: [StuxnetFakeGiftDatePreset] = [.now, .hourAgo, .todayMorning, .days(1), .days(7), .days(30), .days(90)]

    let signal = combineLatest(context.sharedContext.presentationData, revision.get())
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [StuxnetFakeGiftDatePickerEntry] = []
        var index = 0
        for preset in presets {
            entries.append(.option(index, preset, preset.title, preset == currentPreset))
            index += 1
        }
        entries.append(.customDays(customDaysText))
        entries.append(.exactDate(exactDate, selectingDate))
        entries.append(.seconds(secondsText))
        let dateInfo = presentationData.strings.baseLanguageCode.hasPrefix("ru")
            ? "Выберите готовую дату или укажите точную дату, время и секунды. Подарок останется только на этом устройстве."
            : "Choose a preset or enter an exact date, time, and seconds. The gift stays on this device only."
        entries.append(.info(dateInfo))

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(presentationData.strings.baseLanguageCode.hasPrefix("ru") ? "Дата подарка" : "Gift Date"), leftNavigationButton: nil, rightNavigationButton: ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .bold, enabled: Int(secondsText).map { (0 ... 59).contains($0) } ?? false, action: {
            applyCustom()
        }), backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        guard let controller else {
            return
        }
        if let navigationController = controller.navigationController as? NavigationController, navigationController.topViewController === controller {
            _ = navigationController.popViewController(animated: true)
        } else {
            controller.dismiss()
        }
    }
    return controller
}
