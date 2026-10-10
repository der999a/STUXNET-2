import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext

private func stuxnetFormattedNumber(_ value: Int64) -> String {
    let digits = String(value)
    var result = ""
    var count = 0
    for character in digits.reversed() {
        if count == 3 {
            result = "," + result
            count = 0
        }
        result = String(character) + result
        count += 1
    }
    return result
}

private func stuxnetFormattedGiftInventory(_ value: Int32) -> String {
    let count = Int64(max(0, value))
    return "\(stuxnetFormattedNumber(count)) \(count == 1 ? \"gift\" : \"gifts\")"
}

private func stuxnetSendWithoutSoundString(_ value: Int32) -> String {
    switch value {
    case 1:
        return "In Ghost Mode"
    case 2:
        return "Always"
    default:
        return "Never"
    }
}

private func stuxnetVoiceChangerPresetName(_ id: Int32) -> String {
    switch id {
    case 1:
        return "Chipmunk"
    case 2:
        return "Deep"
    case 3:
        return "Robot"
    case 4:
        return "Helium"
    case 5:
        return "Echo"
    case 6:
        return "Child"
    case 7:
        return "Radio"
    case 8:
        return "Whisper"
    case 9:
        return "Anonymous"
    case 10:
        return "Anonymous Pro"
    case 11:
        return "Demon"
    case 12:
        return "Cyber"
    case 13:
        return "Masked"
    default:
        return "Off"
    }
}

private final class StuxnetControllerArguments {
    let context: AccountContext
    let updateSettings: (@escaping (inout MiraSettings) -> Void) -> Void
    let updateGhostSettings: (@escaping (inout MiraGhostSettings) -> Void) -> Void
    let pushController: (ViewController) -> Void
    var presentController: ((ViewController) -> Void)?

    init(context: AccountContext, updateSettings: @escaping (@escaping (inout MiraSettings) -> Void) -> Void, updateGhostSettings: @escaping (@escaping (inout MiraGhostSettings) -> Void) -> Void, pushController: @escaping (ViewController) -> Void) {
        self.context = context
        self.updateSettings = updateSettings
        self.updateGhostSettings = updateGhostSettings
        self.pushController = pushController
    }
}

private func stuxnetControllerArguments(context: AccountContext, pushController: @escaping (ViewController) -> Void) -> StuxnetControllerArguments {
    let accountManager = context.sharedContext.accountManager
    return StuxnetControllerArguments(context: context, updateSettings: { f in
        let _ = updateMiraSettingsInteractively(accountManager: accountManager, f).start()
    }, updateGhostSettings: { f in
        let _ = updateMiraSettingsInteractively(accountManager: accountManager, { settings in
            var ghostSettings = settings.ghostSettings(forAccountPeerId: context.account.peerId)
            f(&ghostSettings)
            settings.setGhostSettings(ghostSettings, forAccountPeerId: context.account.peerId)
        }).start()
    }, pushController: pushController)
}

private func stuxnetItemListController<Entry: ItemListNodeEntry>(context: AccountContext, title: String, arguments: StuxnetControllerArguments, entries: @escaping (MiraSettings) -> [Entry]) -> ViewController {
    let signal = combineLatest(context.sharedContext.presentationData, miraSettingsSignal(accountManager: context.sharedContext.accountManager))
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries(settings), style: .blocks)

        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}

private final class StuxnetOptionsPickerArguments<T: Equatable> {
    let select: (T) -> Void

    init(select: @escaping (T) -> Void) {
        self.select = select
    }
}

private enum StuxnetOptionsPickerEntry<T: Equatable>: ItemListNodeEntry {
    case option(Int, T, String, Bool)
    case footer(String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int {
        switch self {
        case let .option(index, _, _, _):
            return index
        case .footer:
            return Int.max
        }
    }

    static func <(lhs: StuxnetOptionsPickerEntry<T>, rhs: StuxnetOptionsPickerEntry<T>) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! StuxnetOptionsPickerArguments<T>
        switch self {
        case let .option(_, value, title, isSelected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .right, checked: isSelected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.select(value)
            })
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func stuxnetOptionsPickerController<T: Equatable>(context: AccountContext, title: String, options: [(T, String)], currentValue: @escaping (MiraSettings) -> T, updateValue: @escaping (inout MiraSettings, T) -> Void, footer: String? = nil) -> ViewController {
    let accountManager = context.sharedContext.accountManager

    let arguments = StuxnetOptionsPickerArguments<T>(select: { value in
        let _ = updateMiraSettingsInteractively(accountManager: accountManager, { settings in
            updateValue(&settings, value)
        }).start()
    })

    let signal = combineLatest(context.sharedContext.presentationData, miraSettingsSignal(accountManager: accountManager))
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let current = currentValue(settings)

        var entries: [StuxnetOptionsPickerEntry<T>] = []
        var index = 0
        for (value, optionTitle) in options {
            entries.append(.option(index, value, optionTitle, value == current))
            index += 1
        }
        if let footer {
            entries.append(.footer(footer))
        }

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)

        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}

private final class StuxnetManualIntegerArguments {
    var text: String
    var hasInitialized = false
    let update: (Int64) -> Void

    init(text: String, update: @escaping (Int64) -> Void) {
        self.text = text
        self.update = update
    }
}

private enum StuxnetManualIntegerEntry: ItemListNodeEntry {
    case input(String)
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .input:
            return 0
        case .footer:
            return 1
        }
    }

    var stableId: Int {
        switch self {
        case .input:
            return 0
        case .footer:
            return 1
        }
    }

    static func < (lhs: StuxnetManualIntegerEntry, rhs: StuxnetManualIntegerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! StuxnetManualIntegerArguments
        switch self {
        case let .input(text):
            return ItemListSingleLineInputItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: NSAttributedString(string: "Value"),
                text: text,
                placeholder: "Enter a number",
                type: .number,
                sectionId: self.section,
                textUpdated: { value in
                    arguments.text = value
                    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let parsed = Int64(normalized) {
                        arguments.update(parsed)
                    }
                },
                action: {}
            )
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func stuxnetManualIntegerController(
    context: AccountContext,
    title: String,
    currentValue: @escaping (MiraSettings) -> Int64,
    range: ClosedRange<Int64>,
    updateValue: @escaping (inout MiraSettings, Int64) -> Void,
    footer: String
) -> ViewController {
    let accountManager = context.sharedContext.accountManager
    let arguments = StuxnetManualIntegerArguments(text: "", update: { value in
        let clamped = max(range.lowerBound, min(range.upperBound, value))
        let _ = updateMiraSettingsInteractively(accountManager: accountManager, { settings in
            updateValue(&settings, clamped)
        }).start()
    })
    var dismissImpl: (() -> Void)?

    let signal = combineLatest(context.sharedContext.presentationData, miraSettingsSignal(accountManager: accountManager))
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, StuxnetManualIntegerArguments)) in
        if !arguments.hasInitialized {
            let initial = max(range.lowerBound, min(range.upperBound, currentValue(settings)))
            arguments.text = String(initial)
            arguments.hasInitialized = true
        }
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(title),
            leftNavigationButton: nil,
            rightNavigationButton: ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .regular, enabled: true, action: {
                dismissImpl?()
            }),
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: [.input(arguments.text), .footer(footer)],
            style: .blocks
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        (controller?.navigationController as? NavigationController)?.popViewController(animated: true)
    }
    return controller
}

// MARK: - Hub

private enum StuxnetHubSection: Int32 {
    case main
    case actions
}

private enum StuxnetHubEntry: ItemListNodeEntry {
    case ghost(Bool)
    case privacy
    case spy
    case fake
    case voiceChanger(Bool)
    case appearance
    case resetAll
    case versionInfo(String)

    var section: ItemListSectionId {
        switch self {
        case .ghost, .privacy, .spy, .fake, .voiceChanger, .appearance:
            return StuxnetHubSection.main.rawValue
        case .resetAll, .versionInfo:
            return StuxnetHubSection.actions.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case .ghost:
            return 0
        case .privacy:
            return 1
        case .spy:
            return 2
        case .fake:
            return 3
        case .voiceChanger:
            return 4
        case .appearance:
            return 5
        case .resetAll:
            return 6
        case .versionInfo:
            return 7
        }
    }

    static func <(lhs: StuxnetHubEntry, rhs: StuxnetHubEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! StuxnetControllerArguments
        switch self {
        case let .ghost(isActive):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.antiSpam, title: "Ghost Mode", label: isActive ? "On" : "Off", sectionId: self.section, style: .blocks, action: {
                arguments.pushController(stuxnetGhostSettingsController(context: arguments.context))
            })
        case .privacy:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.security, title: "Privacy & Presence", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.pushController(stuxnetPrivacySettingsController(context: arguments.context))
            })
        case .spy:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.recentActions, title: "Spy & Message History", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.pushController(stuxnetSpySettingsController(context: arguments.context))
            })
        case .fake:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.premium, title: "Fake Features", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.pushController(stuxnetFakeSettingsController(context: arguments.context))
            })
        case let .voiceChanger(isEnabled):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.voices, title: "Voice Changer", label: isEnabled ? "On" : "Off", sectionId: self.section, style: .blocks, action: {
                arguments.pushController(stuxnetVoiceChangerSettingsController(context: arguments.context))
            })
        case .appearance:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.appearance, title: "Appearance & Misc", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.pushController(stuxnetAppearanceSettingsController(context: arguments.context))
            })
        case .resetAll:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Reset All Stuxnet Settings", kind: .destructive, alignment: .center, sectionId: self.section, style: .blocks, action: {
                let controller = textAlertController(context: arguments.context, title: "Reset All Stuxnet Settings?", text: "All Stuxnet settings will be reset to their defaults. This cannot be undone.", actions: [
                    TextAlertAction(type: .destructiveAction, title: "Reset", action: {
                        arguments.updateSettings { settings in
                            settings = .defaultSettings
                        }
                        arguments.context.account.miraFakeGiftsStore.clear(account: arguments.context.account)
                        arguments.context.account.miraFakeStarsLedger.clear()
                    }),
                    TextAlertAction(type: .genericAction, title: "Cancel", action: {
                    })
                ])
                arguments.presentController?(controller)
            })
        case let .versionInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func stuxnetHubEntries(settings: MiraSettings, accountPeerId: PeerId) -> [StuxnetHubEntry] {
    var entries: [StuxnetHubEntry] = []
    entries.append(.ghost(settings.ghostSettings(forAccountPeerId: accountPeerId).isGhostActive))
    entries.append(.privacy)
    entries.append(.spy)
    entries.append(.fake)
    entries.append(.voiceChanger(settings.voiceChangerEnabled))
    entries.append(.appearance)
    entries.append(.resetAll)
    entries.append(.versionInfo("Stuxnet 12.9.2 · client-side only · nothing is sent to servers"))
    return entries
}

public func stuxnetSettingsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?

    let arguments = stuxnetControllerArguments(context: context, pushController: { controller in
        pushControllerImpl?(controller)
    })
    arguments.presentController = { controller in
        presentControllerImpl?(controller)
    }

    let controller = stuxnetItemListController(context: context, title: "Stuxnet", arguments: arguments, entries: { settings in
        return stuxnetHubEntries(settings: settings, accountPeerId: context.account.peerId)
    })
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}

// MARK: - Ghost Mode

private enum StuxnetGhostSection: Int32 {
    case master
    case packets
    case locks
    case actions
    case info
}

private enum StuxnetGhostEntry: ItemListNodeEntry {
    case master(Bool)

    case packetsHeader(String)
    case sendReadMessages(Bool)
    case sendReadStories(Bool)
    case sendOnlinePackets(Bool)
    case sendUploadProgress(Bool)
    case sendOfflinePacketAfterOnline(Bool)

    case locksHeader(String)
    case sendReadMessagesLocked(Bool)
    case sendReadStoriesLocked(Bool)
    case sendOnlinePacketsLocked(Bool)
    case sendUploadProgressLocked(Bool)
    case sendOfflinePacketAfterOnlineLocked(Bool)
    case locksInfo(String)

    case actionsHeader(String)
    case markReadAfterAction(Bool)
    case useScheduledMessages(Bool)
    case scheduledDelay(String)
    case sendWithoutSound(String)
    case suggestGhostBeforeStory(Bool)

    case ghostInfo(String)

    var section: ItemListSectionId {
        switch self {
        case .master:
            return StuxnetGhostSection.master.rawValue
        case .packetsHeader, .sendReadMessages, .sendReadStories, .sendOnlinePackets, .sendUploadProgress, .sendOfflinePacketAfterOnline:
            return StuxnetGhostSection.packets.rawValue
        case .locksHeader, .sendReadMessagesLocked, .sendReadStoriesLocked, .sendOnlinePacketsLocked, .sendUploadProgressLocked, .sendOfflinePacketAfterOnlineLocked, .locksInfo:
            return StuxnetGhostSection.locks.rawValue
        case .actionsHeader, .markReadAfterAction, .useScheduledMessages, .scheduledDelay, .sendWithoutSound, .suggestGhostBeforeStory:
            return StuxnetGhostSection.actions.rawValue
        case .ghostInfo:
            return StuxnetGhostSection.info.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case .master:
            return 0
        case .packetsHeader:
            return 1
        case .sendReadMessages:
            return 2
        case .sendReadStories:
            return 3
        case .sendOnlinePackets:
            return 4
        case .sendUploadProgress:
            return 5
        case .sendOfflinePacketAfterOnline:
            return 6
        case .locksHeader:
            return 7
        case .sendReadMessagesLocked:
            return 8
        case .sendReadStoriesLocked:
            return 9
        case .sendOnlinePacketsLocked:
            return 10
        case .sendUploadProgressLocked:
            return 11
        case .sendOfflinePacketAfterOnlineLocked:
            return 12
        case .locksInfo:
            return 13
        case .actionsHeader:
            return 14
        case .markReadAfterAction:
            return 15
        case .useScheduledMessages:
            return 16
        case .scheduledDelay:
            return 17
        case .sendWithoutSound:
            return 18
        case .suggestGhostBeforeStory:
            return 19
        case .ghostInfo:
            return 20
        }
    }

    static func <(lhs: StuxnetGhostEntry, rhs: StuxnetGhostEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! StuxnetControllerArguments
        switch self {
        case let .master(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Ghost Mode", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostSettings { ghostSettings in
                    ghostSettings.setGhostModeEnabled(value)
                }
            })
        case let .packetsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .sendReadMessages(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Send Read Confirmations", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostSettings { ghostSettings in
                    ghostSettings.sendReadMessages = value
                }
            })
        case let .sendReadStories(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Send Story Views", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostSettings { ghostSettings in
                    ghostSettings.sendReadStories = value
                }
            })
        case let .sendOnlinePackets(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Send Online Status", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostSettings { ghostSettings in
                    ghostSettings.sendOnlinePackets = value
                }
            })
        case let .sendUploadProgress(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Send Typing & Upload Progress", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostSettings { ghostSettings in
                    ghostSettings.sendUploadProgress = value
                }
            })
        case let .sendOfflinePacketAfterOnline(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Send Offline Packet After Online", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostSettings { ghostSettings in
                    ghostSettings.sendOfflinePacketAfterOnline = value
                }
            })
        case let .locksHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .sendReadMessagesLocked(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Lock Read Confirmations", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostSettings { ghostSettings in
                    ghostSettings.sendReadMessagesLocked = value
                }
            })
        case let .sendReadStoriesLocked(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Lock Story Views", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostSettings { ghostSettings in
                    ghostSettings.sendReadStoriesLocked = value
                }
            })
        case let .sendOnlinePacketsLocked(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Lock Online Status", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostSettings { ghostSettings in
                    ghostSettings.sendOnlinePacketsLocked = value
                }
            })
        case let .sendUploadProgressLocked(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Lock Typing & Upload Progress", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostSettings { ghostSettings in
                    ghostSettings.sendUploadProgressLocked = value
                }
            })
        case let .sendOfflinePacketAfterOnlineLocked(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Lock Offline Packet", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostSettings { ghostSettings in
                    ghostSettings.sendOfflinePacketAfterOnlineLocked = value
                }
            })
        case let .locksInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .actionsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .markReadAfterAction(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Mark as Read After Action", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostSettings { ghostSettings in
                    ghostSettings.markReadAfterAction = value
                }
            })
        case let .useScheduledMessages(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Delayed Sending in Ghost Mode", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostSettings { ghostSettings in
                    ghostSettings.useScheduledMessages = value
                }
            })
        case let .scheduledDelay(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Delay", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.pushController(stuxnetOptionsPickerController(context: arguments.context, title: "Delay", options: [
                    (5, "5 sec"),
                    (10, "10 sec"),
                    (12, "12 sec"),
                    (30, "30 sec"),
                    (60, "60 sec"),
                    (120, "120 sec")
                ], currentValue: { settings in
                    return Int64(settings.ghostSettings(forAccountPeerId: arguments.context.account.peerId).scheduledDelaySeconds)
                }, updateValue: { settings, value in
                    var ghostSettings = settings.ghostSettings(forAccountPeerId: arguments.context.account.peerId)
                    ghostSettings.scheduledDelaySeconds = Int32(value)
                    settings.setGhostSettings(ghostSettings, forAccountPeerId: arguments.context.account.peerId)
                }))
            })
        case let .sendWithoutSound(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Send Without Sound", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.pushController(stuxnetOptionsPickerController(context: arguments.context, title: "Send Without Sound", options: [
                    (0, "Never"),
                    (1, "In Ghost Mode"),
                    (2, "Always")
                ], currentValue: { settings in
                    return Int64(settings.ghostSettings(forAccountPeerId: arguments.context.account.peerId).sendWithoutSound)
                }, updateValue: { settings, value in
                    var ghostSettings = settings.ghostSettings(forAccountPeerId: arguments.context.account.peerId)
                    ghostSettings.sendWithoutSound = Int32(value)
                    settings.setGhostSettings(ghostSettings, forAccountPeerId: arguments.context.account.peerId)
                }))
            })
        case let .suggestGhostBeforeStory(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Suggest Ghost Mode Before Viewing Stories", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostSettings { ghostSettings in
                    ghostSettings.suggestGhostBeforeStory = value
                }
            })
        case let .ghostInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func stuxnetGhostEntries(settings: MiraSettings, accountPeerId: PeerId) -> [StuxnetGhostEntry] {
    var entries: [StuxnetGhostEntry] = []

    let ghostSettings = settings.ghostSettings(forAccountPeerId: accountPeerId)

    entries.append(.master(ghostSettings.isGhostActive))

    entries.append(.packetsHeader("Packets".uppercased()))
    entries.append(.sendReadMessages(ghostSettings.sendReadMessages))
    entries.append(.sendReadStories(ghostSettings.sendReadStories))
    entries.append(.sendOnlinePackets(ghostSettings.sendOnlinePackets))
    entries.append(.sendUploadProgress(ghostSettings.sendUploadProgress))
    entries.append(.sendOfflinePacketAfterOnline(ghostSettings.sendOfflinePacketAfterOnline))

    entries.append(.locksHeader("Locks".uppercased()))
    entries.append(.sendReadMessagesLocked(ghostSettings.sendReadMessagesLocked))
    entries.append(.sendReadStoriesLocked(ghostSettings.sendReadStoriesLocked))
    entries.append(.sendOnlinePacketsLocked(ghostSettings.sendOnlinePacketsLocked))
    entries.append(.sendUploadProgressLocked(ghostSettings.sendUploadProgressLocked))
    entries.append(.sendOfflinePacketAfterOnlineLocked(ghostSettings.sendOfflinePacketAfterOnlineLocked))
    entries.append(.locksInfo("Locked toggles keep their current value when the Ghost Mode master switch is toggled."))

    entries.append(.actionsHeader("Actions".uppercased()))
    entries.append(.markReadAfterAction(ghostSettings.markReadAfterAction))
    entries.append(.useScheduledMessages(ghostSettings.useScheduledMessages))
    entries.append(.scheduledDelay("\(ghostSettings.scheduledDelaySeconds) sec"))
    entries.append(.sendWithoutSound(stuxnetSendWithoutSoundString(ghostSettings.sendWithoutSound)))
    entries.append(.suggestGhostBeforeStory(ghostSettings.suggestGhostBeforeStory))

    entries.append(.ghostInfo("Ghost Mode blocks all outgoing read confirmations, story views, online status and typing/upload progress packets."))

    return entries
}

private func stuxnetGhostSettingsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = stuxnetControllerArguments(context: context, pushController: { controller in
        pushControllerImpl?(controller)
    })

    let controller = stuxnetItemListController(context: context, title: "Ghost Mode", arguments: arguments, entries: { settings in
        return stuxnetGhostEntries(settings: settings, accountPeerId: context.account.peerId)
    })
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}

// MARK: - Privacy & Presence

private enum StuxnetPrivacySection: Int32 {
    case main
    case confirmations
}

private enum StuxnetPrivacyEntry: ItemListNodeEntry {
    case showLocalOnline(Bool)
    case showRealLastSeen(Bool)
    case autoClearClipboard(Bool)
    case hidePhoneNumber(Bool)
    case showPeerId(Bool)
    case filterZalgo(Bool)
    case screenshotEvasion(Bool)
    case streamerMode(Bool)
    case securityInfo(String)

    case confirmationsHeader(String)
    case confirmJoinChannel(Bool)
    case confirmViewStory(Bool)
    case confirmCall(Bool)
    case confirmSendSticker(Bool)
    case confirmSendGif(Bool)
    case confirmSendVoice(Bool)
    case confirmationsInfo(String)

    var section: ItemListSectionId {
        switch self {
        case .showLocalOnline, .showRealLastSeen, .autoClearClipboard, .hidePhoneNumber, .showPeerId, .filterZalgo, .screenshotEvasion, .streamerMode, .securityInfo:
            return StuxnetPrivacySection.main.rawValue
        case .confirmationsHeader, .confirmJoinChannel, .confirmViewStory, .confirmCall, .confirmSendSticker, .confirmSendGif, .confirmSendVoice, .confirmationsInfo:
            return StuxnetPrivacySection.confirmations.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case .showLocalOnline:
            return 0
        case .showRealLastSeen:
            return 1
        case .autoClearClipboard:
            return 2
        case .hidePhoneNumber:
            return 3
        case .showPeerId:
            return 4
        case .filterZalgo:
            return 5
        case .screenshotEvasion:
            return 6
        case .streamerMode:
            return 7
        case .securityInfo:
            return 8
        case .confirmationsHeader:
            return 9
        case .confirmJoinChannel:
            return 10
        case .confirmViewStory:
            return 11
        case .confirmCall:
            return 12
        case .confirmSendSticker:
            return 13
        case .confirmSendGif:
            return 14
        case .confirmSendVoice:
            return 15
        case .confirmationsInfo:
            return 16
        }
    }

    static func <(lhs: StuxnetPrivacyEntry, rhs: StuxnetPrivacyEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! StuxnetControllerArguments
        switch self {
        case let .showLocalOnline(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Show Local Online", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.showLocalOnline = value
                }
            })
        case let .showRealLastSeen(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Show Real Last Seen", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.showRealLastSeen = value
                }
            })
        case let .autoClearClipboard(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Auto-Clear Clipboard", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.autoClearClipboard = value
                }
            })
        case let .hidePhoneNumber(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Phone Number", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.hidePhoneNumber = value
                }
            })
        case let .showPeerId(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Show Peer ID", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.showPeerId = value
                }
            })
        case let .filterZalgo(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Filter Zalgo Text", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.filterZalgo = value
                }
            })
        case let .screenshotEvasion(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Screen Capture Guard", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.screenshotEvasion = value
                }
            })
        case let .streamerMode(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Streamer Mode", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.streamerMode = value
                }
            })
        case let .securityInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .confirmationsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .confirmJoinChannel(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Join Channels", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.confirmJoinChannel = value
                }
            })
        case let .confirmViewStory(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "View Stories", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.confirmViewStory = value
                }
            })
        case let .confirmCall(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Calls", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.confirmCall = value
                }
            })
        case let .confirmSendSticker(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Send Stickers", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.confirmSendSticker = value
                }
            })
        case let .confirmSendGif(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Send GIFs", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.confirmSendGif = value
                }
            })
        case let .confirmSendVoice(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Send Voice Messages", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.confirmSendVoice = value
                }
            })
        case let .confirmationsInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func stuxnetPrivacyEntries(settings: MiraSettings) -> [StuxnetPrivacyEntry] {
    var entries: [StuxnetPrivacyEntry] = []
    entries.append(.showLocalOnline(settings.showLocalOnline))
    entries.append(.showRealLastSeen(settings.showRealLastSeen))
    entries.append(.autoClearClipboard(settings.autoClearClipboard))
    entries.append(.hidePhoneNumber(settings.hidePhoneNumber))
    entries.append(.showPeerId(settings.showPeerId))
    entries.append(.filterZalgo(settings.filterZalgo))
    entries.append(.screenshotEvasion(settings.screenshotEvasion))
    entries.append(.streamerMode(settings.streamerMode))
    entries.append(.securityInfo("Blanks the app during screen recording/screenshots."))

    entries.append(.confirmationsHeader("Confirmations".uppercased()))
    entries.append(.confirmJoinChannel(settings.confirmJoinChannel))
    entries.append(.confirmViewStory(settings.confirmViewStory))
    entries.append(.confirmCall(settings.confirmCall))
    entries.append(.confirmSendSticker(settings.confirmSendSticker))
    entries.append(.confirmSendGif(settings.confirmSendGif))
    entries.append(.confirmSendVoice(settings.confirmSendVoice))
    entries.append(.confirmationsInfo("Ask for confirmation before the selected actions."))
    return entries
}

private func stuxnetPrivacySettingsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = stuxnetControllerArguments(context: context, pushController: { controller in
        pushControllerImpl?(controller)
    })

    let controller = stuxnetItemListController(context: context, title: "Privacy & Presence", arguments: arguments, entries: { settings in
        return stuxnetPrivacyEntries(settings: settings)
    })
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}

// MARK: - Spy & Message History

private enum StuxnetSpySection: Int32 {
    case main
    case marks
    case editing
}

private enum StuxnetSpyEntry: ItemListNodeEntry {
    case saveDeletedMessages(Bool)
    case saveMessagesHistory(Bool)
    case saveForBots(Bool)
    case semiTransparentDeletedMessages(Bool)
    case showDeletedMarkInChatList(Bool)

    case marksHeader(String)
    case deletedMark(String)
    case editedMark(String)

    case localMessageEditEnabled(Bool)
    case fakeMessagesEnabled(Bool)
    case fakeMessagesInfo(String)

    var section: ItemListSectionId {
        switch self {
        case .saveDeletedMessages, .saveMessagesHistory, .saveForBots, .semiTransparentDeletedMessages, .showDeletedMarkInChatList:
            return StuxnetSpySection.main.rawValue
        case .marksHeader, .deletedMark, .editedMark:
            return StuxnetSpySection.marks.rawValue
        case .localMessageEditEnabled, .fakeMessagesEnabled, .fakeMessagesInfo:
            return StuxnetSpySection.editing.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case .saveDeletedMessages:
            return 0
        case .saveMessagesHistory:
            return 1
        case .saveForBots:
            return 2
        case .semiTransparentDeletedMessages:
            return 3
        case .showDeletedMarkInChatList:
            return 4
        case .marksHeader:
            return 5
        case .deletedMark:
            return 6
        case .editedMark:
            return 7
        case .localMessageEditEnabled:
            return 8
        case .fakeMessagesEnabled:
            return 9
        case .fakeMessagesInfo:
            return 10
        }
    }

    static func <(lhs: StuxnetSpyEntry, rhs: StuxnetSpyEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! StuxnetControllerArguments
        switch self {
        case let .saveDeletedMessages(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Save Deleted Messages", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.saveDeletedMessages = value
                }
            })
        case let .saveMessagesHistory(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Save Message Edit History", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.saveMessagesHistory = value
                }
            })
        case let .saveForBots(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Save for Bots", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.saveForBots = value
                }
            })
        case let .semiTransparentDeletedMessages(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Semi-Transparent Deleted Messages", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.semiTransparentDeletedMessages = value
                }
            })
        case let .showDeletedMarkInChatList(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Show Deleted Mark in Chat List", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.showDeletedMarkInChatList = value
                }
            })
        case let .marksHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .deletedMark(value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Deleted Mark", label: value, sectionId: self.section, style: .blocks, action: {
                arguments.pushController(stuxnetOptionsPickerController(context: arguments.context, title: "Deleted Mark", options: [
                    ("🧹", "🧹"),
                    ("❌", "❌"),
                    ("🗑", "🗑"),
                    ("🚫", "🚫"),
                    ("(deleted)", "(deleted)")
                ], currentValue: { settings in
                    return settings.deletedMark
                }, updateValue: { settings, value in
                    settings.deletedMark = value
                }))
            })
        case let .editedMark(value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Edited Mark", label: value, sectionId: self.section, style: .blocks, action: {
                arguments.pushController(stuxnetOptionsPickerController(context: arguments.context, title: "Edited Mark", options: [
                    ("(edited)", "(edited)"),
                    ("(ред.)", "(ред.)"),
                    ("✎", "✎"),
                    ("edited", "edited")
                ], currentValue: { settings in
                    return settings.editedMark
                }, updateValue: { settings, value in
                    settings.editedMark = value
                }))
            })
        case let .localMessageEditEnabled(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Local Message Editing", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.localMessageEditEnabled = value
                }
            })
        case let .fakeMessagesEnabled(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Fake Messages in Chats", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.fakeMessagesEnabled = value
                }
            })
        case let .fakeMessagesInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func stuxnetSpyEntries(settings: MiraSettings) -> [StuxnetSpyEntry] {
    var entries: [StuxnetSpyEntry] = []
    entries.append(.saveDeletedMessages(settings.saveDeletedMessages))
    entries.append(.saveMessagesHistory(settings.saveMessagesHistory))
    entries.append(.saveForBots(settings.saveForBots))
    entries.append(.semiTransparentDeletedMessages(settings.semiTransparentDeletedMessages))
    entries.append(.showDeletedMarkInChatList(settings.showDeletedMarkInChatList))

    entries.append(.marksHeader("Marks".uppercased()))
    entries.append(.deletedMark(settings.deletedMark))
    entries.append(.editedMark(settings.editedMark))

    entries.append(.localMessageEditEnabled(settings.localMessageEditEnabled))
    entries.append(.fakeMessagesEnabled(settings.fakeMessagesEnabled))
    entries.append(.fakeMessagesInfo("Use a chat's menu > Manage Fake Messages to build a local conversation. Messages stay on this device and are never sent to Telegram."))
    return entries
}

private func stuxnetSpySettingsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = stuxnetControllerArguments(context: context, pushController: { controller in
        pushControllerImpl?(controller)
    })

    let controller = stuxnetItemListController(context: context, title: "Spy & Message History", arguments: arguments, entries: { settings in
        return stuxnetSpyEntries(settings: settings)
    })
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}

// MARK: - Fake Features

private enum StuxnetFakeSection: Int32 {
    case premium
    case stars
    case gifts
    case rating
}

private enum StuxnetFakeEntry: ItemListNodeEntry {
    case localPremium(Bool)
    case fakePremiumSince(Bool)

    case starsHeader(String)
    case fakeStarsEnabled(Bool)
    case fakeStarsBalance(String)
    case fakeStarsHistory

    case giftsHeader(String)
    case fakeGiftsEnabled(Bool)
    case fakeGiftCount(String)
    case manageFakeGifts

    case ratingHeader(String)
    case fakeRatingEnabled(Bool)
    case fakeRatingValue(String)

    var section: ItemListSectionId {
        switch self {
        case .localPremium, .fakePremiumSince:
            return StuxnetFakeSection.premium.rawValue
        case .starsHeader, .fakeStarsEnabled, .fakeStarsBalance, .fakeStarsHistory:
            return StuxnetFakeSection.stars.rawValue
        case .giftsHeader, .fakeGiftsEnabled, .fakeGiftCount, .manageFakeGifts:
            return StuxnetFakeSection.gifts.rawValue
        case .ratingHeader, .fakeRatingEnabled, .fakeRatingValue:
            return StuxnetFakeSection.rating.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case .localPremium:
            return 0
        case .fakePremiumSince:
            return 1
        case .starsHeader:
            return 2
        case .fakeStarsEnabled:
            return 3
        case .fakeStarsBalance:
            return 4
        case .fakeStarsHistory:
            return 5
        case .giftsHeader:
            return 6
        case .fakeGiftsEnabled:
            return 7
        case .fakeGiftCount:
            return 8
        case .manageFakeGifts:
            return 9
        case .ratingHeader:
            return 10
        case .fakeRatingEnabled:
            return 11
        case .fakeRatingValue:
            return 12
        }
    }

    static func <(lhs: StuxnetFakeEntry, rhs: StuxnetFakeEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! StuxnetControllerArguments
        switch self {
        case let .localPremium(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Local Premium", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.localPremium = value
                }
            })
        case let .fakePremiumSince(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Fake Premium Since", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.fakePremiumSince = value
                }
            })
        case let .starsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .fakeStarsEnabled(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Fake Stars Balance", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.fakeStarsEnabled = value
                }
            })
        case let .fakeStarsBalance(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Stars Balance", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.pushController(stuxnetManualIntegerController(context: arguments.context, title: "Stars Balance", currentValue: { settings in
                    settings.fakeStarsBalance
                }, range: 0 ... Int64.max, updateValue: { settings, value in
                    settings.fakeStarsBalance = value
                    _ = arguments.context.account.miraFakeStarsLedger.setBalance(value, note: "Stuxnet fake Stars balance")
                }, footer: "Local balance used only by Stuxnet fake Stars and transfers."))
            })
        case .fakeStarsHistory:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Stars transaction history", label: "Local", sectionId: self.section, style: .blocks, action: {
                arguments.pushController(stuxnetFakeStarsLedgerController(context: arguments.context))
            })
        case let .giftsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .fakeGiftsEnabled(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Fake Gifts", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.fakeGiftsEnabled = value
                }
            })
        case let .fakeGiftCount(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Profile gift slots", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.pushController(stuxnetManualIntegerController(context: arguments.context, title: "Profile gift slots", currentValue: { settings in
                    Int64(settings.fakeGiftCount)
                }, range: 0 ... Int64(Int32.max), updateValue: { settings, value in
                    settings.fakeGiftCount = Int32(value)
                }, footer: "Controls how many local gift slots are shown on your profile. It does not create or send server gifts."))
            })
        case .manageFakeGifts:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Manage Fake Gifts…", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.pushController(stuxnetFakeGiftsController(context: arguments.context))
            })
        case let .ratingHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .fakeRatingEnabled(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Fake Rating", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.fakeRatingEnabled = value
                }
            })
        case let .fakeRatingValue(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Rating value (Stars)", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.pushController(stuxnetManualIntegerController(context: arguments.context, title: "Rating value (Stars)", currentValue: { settings in
                    settings.fakeRatingValue
                }, range: 0 ... Int64.max, updateValue: { settings, value in
                    settings.fakeRatingValue = value
                    settings.fakeRatingLevel = MiraSettings.starRatingLevel(forStars: value)
                }, footer: "Enter the total rating value. The displayed Telegram-style level is calculated automatically from this value."))
            })
        }
    }
}

private func stuxnetFakeEntries(settings: MiraSettings, ledgerBalance: Int64? = nil) -> [StuxnetFakeEntry] {
    var entries: [StuxnetFakeEntry] = []
    entries.append(.localPremium(settings.localPremium))
    entries.append(.fakePremiumSince(settings.fakePremiumSince))

    entries.append(.starsHeader("Stars".uppercased()))
    entries.append(.fakeStarsEnabled(settings.fakeStarsEnabled))
    entries.append(.fakeStarsBalance(stuxnetFormattedNumber(ledgerBalance ?? settings.fakeStarsBalance)))
    entries.append(.fakeStarsHistory)

    entries.append(.giftsHeader("Gifts".uppercased()))
    entries.append(.fakeGiftsEnabled(settings.fakeGiftsEnabled))
    entries.append(.fakeGiftCount(stuxnetFormattedGiftInventory(settings.fakeGiftCount)))
    entries.append(.manageFakeGifts)

    entries.append(.ratingHeader("Rating".uppercased()))
    entries.append(.fakeRatingEnabled(settings.fakeRatingEnabled))
    let ratingValue = settings.fakeRatingValue
    let ratingLevel = settings.effectiveFakeRatingLevel
    entries.append(.fakeRatingValue("\(stuxnetFormattedNumber(ratingValue)) · Level \(ratingLevel)"))
    return entries
}

private enum StuxnetFakeStarsLedgerEntry: ItemListNodeEntry {
    case header(String)
    case balance(String)
    case transaction(Int, String)
    case empty(String)

    var section: ItemListSectionId {
        switch self {
        case .header, .balance:
            return 0
        case .transaction, .empty:
            return 1
        }
    }

    var stableId: Int {
        switch self {
        case .header:
            return 0
        case .balance:
            return 1
        case let .transaction(index, _):
            return 10 + index
        case .empty:
            return 10000
        }
    }

    static func < (lhs: StuxnetFakeStarsLedgerEntry, rhs: StuxnetFakeStarsLedgerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .balance(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .transaction(_, text), let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func stuxnetFakeStarsLedgerKindTitle(_ kind: MiraFakeStarsLedgerEntryKind) -> String {
    switch kind {
    case .initial:
        return "Balance adjustment"
    case .credit:
        return "Credit"
    case .debit:
        return "Debit"
    case .fakeGiftTransfer:
        return "Fake NFT transfer"
    case .fakeGiftConversion:
        return "Gift conversion"
    case .fakeStarsMessage:
        return "Fake Stars message"
    }
}

private func stuxnetFakeStarsLedgerController(context: AccountContext) -> ViewController {
    let signal = combineLatest(context.sharedContext.presentationData, context.account.miraFakeStarsLedger.changes)
    |> map { presentationData, snapshot -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [StuxnetFakeStarsLedgerEntry] = [
            .header("Local Stars"),
            .balance("Balance: \(stuxnetFormattedNumber(snapshot.balance)) Stars")
        ]
        if snapshot.entries.isEmpty {
            entries.append(.empty("No local transactions yet."))
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            for (index, entry) in snapshot.entries.reversed().enumerated() {
                let sign = entry.delta >= 0 ? "+" : ""
                let date = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(entry.date)))
                let note = entry.note.map { " · \($0)" } ?? ""
                entries.append(.transaction(index, "\(date) · \(stuxnetFakeStarsLedgerKindTitle(entry.kind)) · \(sign)\(entry.delta) · \(entry.balance)\(note)"))
            }
        }
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Stars history"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: true
        )
        return (controllerState, (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks), NSNull()))
    }
    return ItemListController(context: context, state: signal)
}

private func stuxnetFakeSettingsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = stuxnetControllerArguments(context: context, pushController: { controller in
        pushControllerImpl?(controller)
    })

    let controller = stuxnetItemListController(context: context, title: "Fake Features", arguments: arguments, entries: { settings in
        // Migrate the pre-ledger settings balance once. After that, message
        // and gift operations own the durable ledger value.
        if settings.fakeStarsBalance > 0 && context.account.miraFakeStarsLedger.entries.isEmpty {
            _ = context.account.miraFakeStarsLedger.setBalance(settings.fakeStarsBalance, note: "Migrated fake Stars balance")
        }
        return stuxnetFakeEntries(settings: settings, ledgerBalance: context.account.miraFakeStarsLedger.balance)
    })
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}

// MARK: - Voice Changer

private enum StuxnetVoiceChangerSection: Int32 {
    case main
    case preset
}

private enum StuxnetVoiceChangerEntry: ItemListNodeEntry {
    case enabled(Bool)
    case preset(String)

    var section: ItemListSectionId {
        switch self {
        case .enabled:
            return StuxnetVoiceChangerSection.main.rawValue
        case .preset:
            return StuxnetVoiceChangerSection.preset.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case .enabled:
            return 0
        case .preset:
            return 1
        }
    }

    static func <(lhs: StuxnetVoiceChangerEntry, rhs: StuxnetVoiceChangerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! StuxnetControllerArguments
        switch self {
        case let .enabled(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Voice Changer", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.voiceChangerEnabled = value
                }
            })
        case let .preset(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Preset", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.pushController(stuxnetOptionsPickerController(context: arguments.context, title: "Voice Changer Preset", options: (0 ... 13).map { (Int64($0), stuxnetVoiceChangerPresetName(Int32($0))) }, currentValue: { settings in
                    return Int64(settings.voiceChangerPreset)
                }, updateValue: { settings, value in
                    settings.voiceChangerPreset = Int32(value)
                }, footer: "Anonymous/Demon/Cyber/Masked chains also apply to calls (timbre-only)."))
            })
        }
    }
}

private func stuxnetVoiceChangerEntries(settings: MiraSettings) -> [StuxnetVoiceChangerEntry] {
    var entries: [StuxnetVoiceChangerEntry] = []
    entries.append(.enabled(settings.voiceChangerEnabled))
    entries.append(.preset(stuxnetVoiceChangerPresetName(settings.voiceChangerPreset)))
    return entries
}

private func stuxnetVoiceChangerSettingsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = stuxnetControllerArguments(context: context, pushController: { controller in
        pushControllerImpl?(controller)
    })

    let controller = stuxnetItemListController(context: context, title: "Voice Changer", arguments: arguments, entries: { settings in
        return stuxnetVoiceChangerEntries(settings: settings)
    })
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}

private func stuxnetInterfaceFontOptionName(_ id: Int32) -> String {
    switch id {
    case 1:
        return "Avenir Next"
    case 2:
        return "Futura"
    case 3:
        return "Georgia"
    case 4:
        return "Helvetica Neue"
    case 5:
        return "Times New Roman"
    case 6:
        return "Courier New"
    case 7:
        return "Menlo"
    case 8:
        return "Chalkboard SE"
    case 9:
        return "Copperplate"
    case 10:
        return "Didot"
    case 11:
        return "American Typewriter"
    case 12:
        return "Optima"
    case 13:
        return "Trebuchet MS"
    case 14:
        return "Verdana"
    default:
        return "System"
    }
}

private func stuxnetAvatarCornerStyleName(_ id: Int32) -> String {
    switch id {
    case 1:
        return "Rounded Square"
    case 2:
        return "Square"
    default:
        return "Default"
    }
}

// MARK: - Appearance & Misc

private enum StuxnetAppearanceEntry: ItemListNodeEntry {
    case disableAds(Bool)
    case disableStories(Bool)
    case showMessageSeconds(Bool)
    case compactChatList(Bool)
    case compactChatFolders(Bool)
    case videoMessagesUseBackCamera(Bool)
    case interfaceFont(String)
    case avatarCorners(String)
    case socialVideoEnabled(Bool)
    case socialVideoWifiOnly(Bool)
    case socialVideoConfirm(Bool)
    case socialVideoQuality(String)
    case socialVideoDestination(String)
    case socialVideoPlatform(MiraSocialVideoPlatform, Bool)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int {
        switch self {
        case .disableAds:
            return 0
        case .disableStories:
            return 1
        case .showMessageSeconds:
            return 2
        case .compactChatList:
            return 3
        case .compactChatFolders:
            return 4
        case .videoMessagesUseBackCamera:
            return 5
        case .interfaceFont:
            return 6
        case .avatarCorners:
            return 7
        case .socialVideoEnabled:
            return 8
        case .socialVideoWifiOnly:
            return 9
        case .socialVideoConfirm:
            return 10
        case .socialVideoQuality:
            return 11
        case .socialVideoDestination:
            return 12
        case let .socialVideoPlatform(platform, _):
            return 13 + Int(platform.rawValue)
        }
    }

    static func <(lhs: StuxnetAppearanceEntry, rhs: StuxnetAppearanceEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! StuxnetControllerArguments
        switch self {
        case let .disableAds(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Disable Ads", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.disableAds = value
                }
            })
        case let .disableStories(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Disable Stories", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.disableStories = value
                }
            })
        case let .showMessageSeconds(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Message Seconds", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.showMessageSeconds = value
                }
            })
        case let .compactChatList(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Compact Chat List", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.compactChatList = value
                }
            })
        case let .compactChatFolders(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Compact Folder Bar", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.compactChatFolders = value
                }
            })
        case let .videoMessagesUseBackCamera(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Use Back Camera for Video Messages", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.videoMessagesUseBackCamera = value
                }
            })
        case let .interfaceFont(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Interface Font", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.pushController(stuxnetOptionsPickerController(context: arguments.context, title: "Interface Font", options: (0 ... 14).map { (Int64($0), stuxnetInterfaceFontOptionName(Int32($0))) }, currentValue: { settings in
                    return Int64(settings.interfaceFont)
                }, updateValue: { settings, value in
                    settings.interfaceFont = Int32(value)
                }))
            })
        case let .avatarCorners(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Avatar Corners", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.pushController(stuxnetOptionsPickerController(context: arguments.context, title: "Avatar Corners", options: (0 ... 2).map { (Int64($0), stuxnetAvatarCornerStyleName(Int32($0))) }, currentValue: { settings in
                    return Int64(settings.avatarCornerStyle)
                }, updateValue: { settings, value in
                    settings.avatarCornerStyle = Int32(value)
                }))
            })
        case let .socialVideoEnabled(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Social Video Links", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.socialVideoSettings.enabled = value
                }
            })
        case let .socialVideoWifiOnly(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Wi-Fi Only", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.socialVideoSettings.wifiOnly = value
                }
            })
        case let .socialVideoConfirm(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Confirm before download", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.socialVideoSettings.confirmBeforeDownload = value
                }
            })
        case let .socialVideoQuality(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Video Quality", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.pushController(stuxnetOptionsPickerController(context: arguments.context, title: "Video Quality", options: MiraSocialVideoQuality.allCases.map { (Int64($0.rawValue), $0.title) }, currentValue: { settings in
                    return Int64(settings.socialVideoSettings.quality.rawValue)
                }, updateValue: { settings, value in
                    settings.socialVideoSettings.quality = MiraSocialVideoQuality(rawValue: Int32(value)) ?? .source
                }))
            })
        case let .socialVideoDestination(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Save to", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.pushController(stuxnetOptionsPickerController(context: arguments.context, title: "Save social videos to", options: MiraSocialVideoDestination.allCases.map { (Int64($0.rawValue), $0.title) }, currentValue: { settings in
                    return Int64(settings.socialVideoSettings.destination.rawValue)
                }, updateValue: { settings, value in
                    settings.socialVideoSettings.destination = MiraSocialVideoDestination(rawValue: Int32(value)) ?? .files
                }))
            })
        case let .socialVideoPlatform(platform, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: platform.title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.socialVideoSettings.setEnabled(value, for: platform)
                }
            })
        }
    }
}

private func stuxnetAppearanceEntries(settings: MiraSettings) -> [StuxnetAppearanceEntry] {
    var entries: [StuxnetAppearanceEntry] = []
    entries.append(.disableAds(settings.disableAds))
    entries.append(.disableStories(settings.disableStories))
    entries.append(.showMessageSeconds(settings.showMessageSeconds))
    entries.append(.compactChatList(settings.compactChatList))
    entries.append(.compactChatFolders(settings.compactChatFolders))
    entries.append(.videoMessagesUseBackCamera(settings.videoMessagesUseBackCamera))
    entries.append(.interfaceFont(stuxnetInterfaceFontOptionName(settings.interfaceFont)))
    entries.append(.avatarCorners(stuxnetAvatarCornerStyleName(settings.avatarCornerStyle)))
    entries.append(.socialVideoEnabled(settings.socialVideoSettings.enabled))
    entries.append(.socialVideoWifiOnly(settings.socialVideoSettings.wifiOnly))
    entries.append(.socialVideoConfirm(settings.socialVideoSettings.confirmBeforeDownload))
    entries.append(.socialVideoQuality(settings.socialVideoSettings.quality.title))
    entries.append(.socialVideoDestination(settings.socialVideoSettings.destination.title))
    for platform in MiraSocialVideoPlatform.allCases {
        entries.append(.socialVideoPlatform(platform, settings.socialVideoSettings.isEnabled(platform)))
    }
    return entries
}

private func stuxnetAppearanceSettingsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = stuxnetControllerArguments(context: context, pushController: { controller in
        pushControllerImpl?(controller)
    })

    let controller = stuxnetItemListController(context: context, title: "Appearance & Misc", arguments: arguments, entries: { settings in
        return stuxnetAppearanceEntries(settings: settings)
    })
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}
