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

private final class StuxnetSettingsControllerArguments {
    let updateSettings: (@escaping (inout MiraSettings) -> Void) -> Void
    let updateGhostSettings: (@escaping (inout MiraGhostSettings) -> Void) -> Void
    let openDelayPicker: () -> Void
    let openSendWithoutSoundPicker: () -> Void
    let openStarsBalancePicker: () -> Void
    let openGiftCountPicker: () -> Void
    let openRatingLevelPicker: () -> Void

    init(updateSettings: @escaping (@escaping (inout MiraSettings) -> Void) -> Void, updateGhostSettings: @escaping (@escaping (inout MiraGhostSettings) -> Void) -> Void, openDelayPicker: @escaping () -> Void, openSendWithoutSoundPicker: @escaping () -> Void, openStarsBalancePicker: @escaping () -> Void, openGiftCountPicker: @escaping () -> Void, openRatingLevelPicker: @escaping () -> Void) {
        self.updateSettings = updateSettings
        self.updateGhostSettings = updateGhostSettings
        self.openDelayPicker = openDelayPicker
        self.openSendWithoutSoundPicker = openSendWithoutSoundPicker
        self.openStarsBalancePicker = openStarsBalancePicker
        self.openGiftCountPicker = openGiftCountPicker
        self.openRatingLevelPicker = openRatingLevelPicker
    }
}

private enum StuxnetSettingsControllerSection: Int32 {
    case ghost
    case spy
    case fake
    case other
}

private enum StuxnetSettingsControllerEntry: ItemListNodeEntry {
    case ghostHeader(String)
    case ghostMode(Bool)
    case ghostSendReadMessages(Bool)
    case ghostSendReadStories(Bool)
    case ghostSendOnlinePackets(Bool)
    case ghostSendUploadProgress(Bool)
    case ghostSendOfflinePacketAfterOnline(Bool)
    case ghostMarkReadAfterAction(Bool)
    case ghostUseScheduledMessages(Bool)
    case ghostScheduledDelay(String)
    case ghostSendWithoutSound(String)

    case spyHeader(String)
    case saveDeletedMessages(Bool)
    case saveMessagesHistory(Bool)
    case saveForBots(Bool)

    case fakeHeader(String)
    case localPremium(Bool)
    case fakeStarsEnabled(Bool)
    case fakeStarsBalance(String)
    case fakeGiftsEnabled(Bool)
    case fakeGiftCount(String)
    case fakeRatingEnabled(Bool)
    case fakeRatingLevel(String)

    case otherHeader(String)
    case disableAds(Bool)
    case disableStories(Bool)
    case showPeerId(Bool)
    case filterZalgo(Bool)

    var section: ItemListSectionId {
        switch self {
        case .ghostHeader, .ghostMode, .ghostSendReadMessages, .ghostSendReadStories, .ghostSendOnlinePackets, .ghostSendUploadProgress, .ghostSendOfflinePacketAfterOnline, .ghostMarkReadAfterAction, .ghostUseScheduledMessages, .ghostScheduledDelay, .ghostSendWithoutSound:
            return StuxnetSettingsControllerSection.ghost.rawValue
        case .spyHeader, .saveDeletedMessages, .saveMessagesHistory, .saveForBots:
            return StuxnetSettingsControllerSection.spy.rawValue
        case .fakeHeader, .localPremium, .fakeStarsEnabled, .fakeStarsBalance, .fakeGiftsEnabled, .fakeGiftCount, .fakeRatingEnabled, .fakeRatingLevel:
            return StuxnetSettingsControllerSection.fake.rawValue
        case .otherHeader, .disableAds, .disableStories, .showPeerId, .filterZalgo:
            return StuxnetSettingsControllerSection.other.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case .ghostHeader:
            return 0
        case .ghostMode:
            return 1
        case .ghostSendReadMessages:
            return 2
        case .ghostSendReadStories:
            return 3
        case .ghostSendOnlinePackets:
            return 4
        case .ghostSendUploadProgress:
            return 5
        case .ghostSendOfflinePacketAfterOnline:
            return 6
        case .ghostMarkReadAfterAction:
            return 7
        case .ghostUseScheduledMessages:
            return 8
        case .ghostScheduledDelay:
            return 9
        case .ghostSendWithoutSound:
            return 10
        case .spyHeader:
            return 11
        case .saveDeletedMessages:
            return 12
        case .saveMessagesHistory:
            return 13
        case .saveForBots:
            return 14
        case .fakeHeader:
            return 15
        case .localPremium:
            return 16
        case .fakeStarsEnabled:
            return 17
        case .fakeStarsBalance:
            return 18
        case .fakeGiftsEnabled:
            return 19
        case .fakeGiftCount:
            return 20
        case .fakeRatingEnabled:
            return 21
        case .fakeRatingLevel:
            return 22
        case .otherHeader:
            return 23
        case .disableAds:
            return 24
        case .disableStories:
            return 25
        case .showPeerId:
            return 26
        case .filterZalgo:
            return 27
        }
    }

    static func <(lhs: StuxnetSettingsControllerEntry, rhs: StuxnetSettingsControllerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! StuxnetSettingsControllerArguments
        switch self {
        case let .ghostHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .ghostMode(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Ghost Mode", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostSettings { ghostSettings in
                    ghostSettings.setGhostModeEnabled(value)
                }
            })
        case let .ghostSendReadMessages(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Send Read Confirmations", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostSettings { ghostSettings in
                    ghostSettings.sendReadMessages = value
                }
            })
        case let .ghostSendReadStories(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Send Story Views", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostSettings { ghostSettings in
                    ghostSettings.sendReadStories = value
                }
            })
        case let .ghostSendOnlinePackets(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Send Online Status", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostSettings { ghostSettings in
                    ghostSettings.sendOnlinePackets = value
                }
            })
        case let .ghostSendUploadProgress(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Send Typing & Upload Progress", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostSettings { ghostSettings in
                    ghostSettings.sendUploadProgress = value
                }
            })
        case let .ghostSendOfflinePacketAfterOnline(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Send Offline Packet After Online", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostSettings { ghostSettings in
                    ghostSettings.sendOfflinePacketAfterOnline = value
                }
            })
        case let .ghostMarkReadAfterAction(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Mark as Read After Action", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostSettings { ghostSettings in
                    ghostSettings.markReadAfterAction = value
                }
            })
        case let .ghostUseScheduledMessages(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Delayed Sending in Ghost Mode", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostSettings { ghostSettings in
                    ghostSettings.useScheduledMessages = value
                }
            })
        case let .ghostScheduledDelay(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Delay", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openDelayPicker()
            })
        case let .ghostSendWithoutSound(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Send Without Sound", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openSendWithoutSoundPicker()
            })
        case let .spyHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
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
        case let .fakeHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .localPremium(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Local Premium", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.localPremium = value
                }
            })
        case let .fakeStarsEnabled(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Fake Stars Balance", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.fakeStarsEnabled = value
                }
            })
        case let .fakeStarsBalance(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Stars Balance", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openStarsBalancePicker()
            })
        case let .fakeGiftsEnabled(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Fake Gifts", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.fakeGiftsEnabled = value
                }
            })
        case let .fakeGiftCount(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Gift Count", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openGiftCountPicker()
            })
        case let .fakeRatingEnabled(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Fake Rating", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    settings.fakeRatingEnabled = value
                }
            })
        case let .fakeRatingLevel(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Rating Level", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openRatingLevelPicker()
            })
        case let .otherHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
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
        }
    }
}

private func stuxnetSettingsControllerEntries(settings: MiraSettings) -> [StuxnetSettingsControllerEntry] {
    var entries: [StuxnetSettingsControllerEntry] = []

    let ghostSettings = settings.ghostSettings(forPeerId: nil)

    entries.append(.ghostHeader("Ghost Mode".uppercased()))
    entries.append(.ghostMode(ghostSettings.isGhostActive))
    entries.append(.ghostSendReadMessages(ghostSettings.sendReadMessages))
    entries.append(.ghostSendReadStories(ghostSettings.sendReadStories))
    entries.append(.ghostSendOnlinePackets(ghostSettings.sendOnlinePackets))
    entries.append(.ghostSendUploadProgress(ghostSettings.sendUploadProgress))
    entries.append(.ghostSendOfflinePacketAfterOnline(ghostSettings.sendOfflinePacketAfterOnline))
    entries.append(.ghostMarkReadAfterAction(ghostSettings.markReadAfterAction))
    entries.append(.ghostUseScheduledMessages(ghostSettings.useScheduledMessages))
    entries.append(.ghostScheduledDelay("\(ghostSettings.scheduledDelaySeconds) sec"))
    entries.append(.ghostSendWithoutSound(stuxnetSendWithoutSoundString(ghostSettings.sendWithoutSound)))

    entries.append(.spyHeader("Spy".uppercased()))
    entries.append(.saveDeletedMessages(settings.saveDeletedMessages))
    entries.append(.saveMessagesHistory(settings.saveMessagesHistory))
    entries.append(.saveForBots(settings.saveForBots))

    entries.append(.fakeHeader("Fake Features".uppercased()))
    entries.append(.localPremium(settings.localPremium))
    entries.append(.fakeStarsEnabled(settings.fakeStarsEnabled))
    entries.append(.fakeStarsBalance(stuxnetFormattedNumber(settings.fakeStarsBalance)))
    entries.append(.fakeGiftsEnabled(settings.fakeGiftsEnabled))
    entries.append(.fakeGiftCount(stuxnetFormattedNumber(Int64(settings.fakeGiftCount))))
    entries.append(.fakeRatingEnabled(settings.fakeRatingEnabled))
    entries.append(.fakeRatingLevel(stuxnetFormattedNumber(Int64(settings.fakeRatingLevel))))

    entries.append(.otherHeader("Other".uppercased()))
    entries.append(.disableAds(settings.disableAds))
    entries.append(.disableStories(settings.disableStories))
    entries.append(.showPeerId(settings.showPeerId))
    entries.append(.filterZalgo(settings.filterZalgo))

    return entries
}

public func stuxnetSettingsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?

    let accountManager = context.sharedContext.accountManager

    let updateGlobalGhostSettings: (@escaping (inout MiraGhostSettings) -> Void) -> Void = { f in
        let _ = updateMiraSettingsInteractively(accountManager: accountManager, { settings in
            var ghostSettings = settings.ghost["0"] ?? .defaultSettings
            f(&ghostSettings)
            settings.ghost["0"] = ghostSettings
        }).start()
    }

    let arguments = StuxnetSettingsControllerArguments(updateSettings: { f in
        let _ = updateMiraSettingsInteractively(accountManager: accountManager, f).start()
    }, updateGhostSettings: { f in
        updateGlobalGhostSettings(f)
    }, openDelayPicker: {
        pushControllerImpl?(stuxnetOptionsPickerController(context: context, title: "Delay", options: [
            (5, "5 sec"),
            (10, "10 sec"),
            (12, "12 sec"),
            (30, "30 sec"),
            (60, "60 sec"),
            (120, "120 sec")
        ], currentValue: { settings in
            return Int64(settings.ghostSettings(forPeerId: nil).scheduledDelaySeconds)
        }, updateValue: { settings, value in
            var ghostSettings = settings.ghost["0"] ?? .defaultSettings
            ghostSettings.scheduledDelaySeconds = Int32(value)
            settings.ghost["0"] = ghostSettings
        }))
    }, openSendWithoutSoundPicker: {
        pushControllerImpl?(stuxnetOptionsPickerController(context: context, title: "Send Without Sound", options: [
            (0, "Never"),
            (1, "In Ghost Mode"),
            (2, "Always")
        ], currentValue: { settings in
            return Int64(settings.ghostSettings(forPeerId: nil).sendWithoutSound)
        }, updateValue: { settings, value in
            var ghostSettings = settings.ghost["0"] ?? .defaultSettings
            ghostSettings.sendWithoutSound = Int32(value)
            settings.ghost["0"] = ghostSettings
        }))
    }, openStarsBalancePicker: {
        pushControllerImpl?(stuxnetOptionsPickerController(context: context, title: "Stars Balance", options: [
            (1_000, "1,000"),
            (10_000, "10,000"),
            (100_000, "100,000"),
            (1_000_000, "1,000,000"),
            (10_000_000, "10,000,000")
        ], currentValue: { settings in
            return settings.fakeStarsBalance
        }, updateValue: { settings, value in
            settings.fakeStarsBalance = value
        }))
    }, openGiftCountPicker: {
        pushControllerImpl?(stuxnetOptionsPickerController(context: context, title: "Gift Count", options: [
            (10, "10"),
            (50, "50"),
            (100, "100"),
            (500, "500"),
            (1_000, "1,000")
        ], currentValue: { settings in
            return Int64(settings.fakeGiftCount)
        }, updateValue: { settings, value in
            settings.fakeGiftCount = Int32(value)
        }))
    }, openRatingLevelPicker: {
        pushControllerImpl?(stuxnetOptionsPickerController(context: context, title: "Rating Level", options: [
            (10, "10"),
            (50, "50"),
            (100, "100"),
            (500, "500"),
            (1_000, "1,000")
        ], currentValue: { settings in
            return Int64(settings.fakeRatingLevel)
        }, updateValue: { settings, value in
            settings.fakeRatingLevel = Int32(value)
        }))
    })

    let signal = combineLatest(context.sharedContext.presentationData, miraSettingsSignal(accountManager: accountManager))
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Stuxnet"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: stuxnetSettingsControllerEntries(settings: settings), style: .blocks)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}

private final class StuxnetOptionsPickerArguments {
    let select: (Int64) -> Void

    init(select: @escaping (Int64) -> Void) {
        self.select = select
    }
}

private enum StuxnetOptionsPickerEntry: ItemListNodeEntry {
    case option(Int, Int64, String, Bool)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int {
        switch self {
        case let .option(index, _, _, _):
            return index
        }
    }

    static func <(lhs: StuxnetOptionsPickerEntry, rhs: StuxnetOptionsPickerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! StuxnetOptionsPickerArguments
        switch self {
        case let .option(_, value, title, isSelected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .right, checked: isSelected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.select(value)
            })
        }
    }
}

private func stuxnetOptionsPickerController(context: AccountContext, title: String, options: [(Int64, String)], currentValue: @escaping (MiraSettings) -> Int64, updateValue: @escaping (inout MiraSettings, Int64) -> Void) -> ViewController {
    let accountManager = context.sharedContext.accountManager

    let arguments = StuxnetOptionsPickerArguments(select: { value in
        let _ = updateMiraSettingsInteractively(accountManager: accountManager, { settings in
            updateValue(&settings, value)
        }).start()
    })

    let signal = combineLatest(context.sharedContext.presentationData, miraSettingsSignal(accountManager: accountManager))
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let current = currentValue(settings)

        var entries: [StuxnetOptionsPickerEntry] = []
        var index = 0
        for (value, optionTitle) in options {
            entries.append(.option(index, value, optionTitle, value == current))
            index += 1
        }

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)

        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
