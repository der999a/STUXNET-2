import Foundation
import TelegramCore
import Postbox
import SwiftSignalKit

public struct MiraGhostSettings: Codable, Equatable {
    public var sendReadMessages: Bool
    public var sendReadStories: Bool
    public var sendOnlinePackets: Bool
    public var sendUploadProgress: Bool
    public var sendOfflinePacketAfterOnline: Bool
    public var markReadAfterAction: Bool
    public var useScheduledMessages: Bool
    public var scheduledDelaySeconds: Int32
    public var sendWithoutSound: Int32
    public var suggestGhostBeforeStory: Bool
    public var sendReadMessagesLocked: Bool
    public var sendReadStoriesLocked: Bool
    public var sendOnlinePacketsLocked: Bool
    public var sendUploadProgressLocked: Bool
    public var sendOfflinePacketAfterOnlineLocked: Bool
    
    public static var defaultSettings: MiraGhostSettings {
        return MiraGhostSettings()
    }
    
    public init(
        sendReadMessages: Bool = true,
        sendReadStories: Bool = true,
        sendOnlinePackets: Bool = true,
        sendUploadProgress: Bool = true,
        sendOfflinePacketAfterOnline: Bool = false,
        markReadAfterAction: Bool = false,
        useScheduledMessages: Bool = false,
        scheduledDelaySeconds: Int32 = 12,
        sendWithoutSound: Int32 = 0,
        suggestGhostBeforeStory: Bool = false,
        sendReadMessagesLocked: Bool = false,
        sendReadStoriesLocked: Bool = false,
        sendOnlinePacketsLocked: Bool = false,
        sendUploadProgressLocked: Bool = false,
        sendOfflinePacketAfterOnlineLocked: Bool = false
    ) {
        self.sendReadMessages = sendReadMessages
        self.sendReadStories = sendReadStories
        self.sendOnlinePackets = sendOnlinePackets
        self.sendUploadProgress = sendUploadProgress
        self.sendOfflinePacketAfterOnline = sendOfflinePacketAfterOnline
        self.markReadAfterAction = markReadAfterAction
        self.useScheduledMessages = useScheduledMessages
        self.scheduledDelaySeconds = scheduledDelaySeconds
        self.sendWithoutSound = sendWithoutSound
        self.suggestGhostBeforeStory = suggestGhostBeforeStory
        self.sendReadMessagesLocked = sendReadMessagesLocked
        self.sendReadStoriesLocked = sendReadStoriesLocked
        self.sendOnlinePacketsLocked = sendOnlinePacketsLocked
        self.sendUploadProgressLocked = sendUploadProgressLocked
        self.sendOfflinePacketAfterOnlineLocked = sendOfflinePacketAfterOnlineLocked
    }
    
    public var isGhostActive: Bool {
        // A lock only prevents the master switch from changing a value; it
        // must not make Ghost Mode appear active while that packet is still
        // allowed to leave the device.
        return !self.sendReadMessages ||
            !self.sendReadStories ||
            !self.sendOnlinePackets ||
            !self.sendUploadProgress ||
            self.sendOfflinePacketAfterOnline
    }
    
    public mutating func setGhostModeEnabled(_ enabled: Bool) {
        if !self.sendReadMessagesLocked {
            self.sendReadMessages = !enabled
        }
        if !self.sendReadStoriesLocked {
            self.sendReadStories = !enabled
        }
        if !self.sendOnlinePacketsLocked {
            self.sendOnlinePackets = !enabled
        }
        if !self.sendUploadProgressLocked {
            self.sendUploadProgress = !enabled
        }
        if !self.sendOfflinePacketAfterOnlineLocked {
            self.sendOfflinePacketAfterOnline = enabled
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        self.sendReadMessages = try container.decodeIfPresent(Bool.self, forKey: "sendReadMessages") ?? true
        self.sendReadStories = try container.decodeIfPresent(Bool.self, forKey: "sendReadStories") ?? true
        self.sendOnlinePackets = try container.decodeIfPresent(Bool.self, forKey: "sendOnlinePackets") ?? true
        self.sendUploadProgress = try container.decodeIfPresent(Bool.self, forKey: "sendUploadProgress") ?? true
        self.sendOfflinePacketAfterOnline = try container.decodeIfPresent(Bool.self, forKey: "sendOfflinePacketAfterOnline") ?? false
        self.markReadAfterAction = try container.decodeIfPresent(Bool.self, forKey: "markReadAfterAction") ?? false
        self.useScheduledMessages = try container.decodeIfPresent(Bool.self, forKey: "useScheduledMessages") ?? false
        // Negative delays are invalid; enqueue widens timestamp arithmetic so
        // valid longer delays do not need an arbitrary duration cap here.
        let decodedDelay = try container.decodeIfPresent(Int32.self, forKey: "scheduledDelaySeconds") ?? 12
        self.scheduledDelaySeconds = max(decodedDelay, 0)
        let decodedSendWithoutSound = try container.decodeIfPresent(Int32.self, forKey: "sendWithoutSound") ?? 0
        self.sendWithoutSound = (0 ... 2).contains(decodedSendWithoutSound) ? decodedSendWithoutSound : 0
        self.suggestGhostBeforeStory = try container.decodeIfPresent(Bool.self, forKey: "suggestGhostBeforeStory") ?? false
        self.sendReadMessagesLocked = try container.decodeIfPresent(Bool.self, forKey: "sendReadMessagesLocked") ?? false
        self.sendReadStoriesLocked = try container.decodeIfPresent(Bool.self, forKey: "sendReadStoriesLocked") ?? false
        self.sendOnlinePacketsLocked = try container.decodeIfPresent(Bool.self, forKey: "sendOnlinePacketsLocked") ?? false
        self.sendUploadProgressLocked = try container.decodeIfPresent(Bool.self, forKey: "sendUploadProgressLocked") ?? false
        self.sendOfflinePacketAfterOnlineLocked = try container.decodeIfPresent(Bool.self, forKey: "sendOfflinePacketAfterOnlineLocked") ?? false
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encode(self.sendReadMessages, forKey: "sendReadMessages")
        try container.encode(self.sendReadStories, forKey: "sendReadStories")
        try container.encode(self.sendOnlinePackets, forKey: "sendOnlinePackets")
        try container.encode(self.sendUploadProgress, forKey: "sendUploadProgress")
        try container.encode(self.sendOfflinePacketAfterOnline, forKey: "sendOfflinePacketAfterOnline")
        try container.encode(self.markReadAfterAction, forKey: "markReadAfterAction")
        try container.encode(self.useScheduledMessages, forKey: "useScheduledMessages")
        try container.encode(self.scheduledDelaySeconds, forKey: "scheduledDelaySeconds")
        try container.encode(self.sendWithoutSound, forKey: "sendWithoutSound")
        try container.encode(self.suggestGhostBeforeStory, forKey: "suggestGhostBeforeStory")
        try container.encode(self.sendReadMessagesLocked, forKey: "sendReadMessagesLocked")
        try container.encode(self.sendReadStoriesLocked, forKey: "sendReadStoriesLocked")
        try container.encode(self.sendOnlinePacketsLocked, forKey: "sendOnlinePacketsLocked")
        try container.encode(self.sendUploadProgressLocked, forKey: "sendUploadProgressLocked")
        try container.encode(self.sendOfflinePacketAfterOnlineLocked, forKey: "sendOfflinePacketAfterOnlineLocked")
    }
}

/// A supported social-video host. The raw value is also used as a bit in
/// `MiraSocialVideoSettings.platforms` so the preference remains primitive and
/// backwards-compatible with Telegram's shared-data encoder.
public enum MiraSocialVideoPlatform: Int32, Codable, CaseIterable, Equatable {
    case youtube = 1
    case instagram = 2
    case tiktok = 4
    case twitter = 8
    case vk = 16
    case rutube = 32

    public var title: String {
        switch self {
        case .youtube:
            return "YouTube"
        case .instagram:
            return "Instagram"
        case .tiktok:
            return "TikTok"
        case .twitter:
            return "X / Twitter"
        case .vk:
            return "VK Video"
        case .rutube:
            return "Rutube"
        }
    }
}

public enum MiraSocialVideoQuality: Int32, Codable, CaseIterable, Equatable {
    case source = 0
    case p720 = 720
    case p1080 = 1080

    public var title: String {
        switch self {
        case .source:
            return "Source"
        case .p720:
            return "720p"
        case .p1080:
            return "1080p"
        }
    }
}

public enum MiraSocialVideoDestination: Int32, Codable, CaseIterable, Equatable {
    /// Resolve the link locally and enqueue the resulting media in the chat
    /// where the link was sent. The source URL is never persisted as a file
    /// in the user's Files or Photos library by this mode.
    case files = 0
    /// Legacy destinations are retained so existing settings decode safely.
    case photos = 1
    case chat = 2

    public var title: String {
        switch self {
        case .chat:
            return "Send to current chat"
        case .files:
            return "Files"
        case .photos:
            return "Photos"
        }
    }
}

public struct MiraSocialVideoSettings: Codable, Equatable {
    public var enabled: Bool
    public var platforms: Int32
    public var wifiOnly: Bool
    public var quality: MiraSocialVideoQuality
    public var confirmBeforeDownload: Bool
    public var destination: MiraSocialVideoDestination

    public static let allPlatforms: Int32 = MiraSocialVideoPlatform.allCases.reduce(Int32(0)) { result, platform in
        result | platform.rawValue
    }

    public init(
        enabled: Bool = false,
        platforms: Int32 = MiraSocialVideoSettings.allPlatforms,
        wifiOnly: Bool = true,
        quality: MiraSocialVideoQuality = .source,
        confirmBeforeDownload: Bool = true,
        destination: MiraSocialVideoDestination = .chat
    ) {
        self.enabled = enabled
        self.platforms = platforms & MiraSocialVideoSettings.allPlatforms
        self.wifiOnly = wifiOnly
        self.quality = quality
        self.confirmBeforeDownload = confirmBeforeDownload
        self.destination = destination
    }

    public func isEnabled(_ platform: MiraSocialVideoPlatform) -> Bool {
        return (self.platforms & platform.rawValue) != 0
    }

    public mutating func setEnabled(_ enabled: Bool, for platform: MiraSocialVideoPlatform) {
        if enabled {
            self.platforms |= platform.rawValue
        } else {
            self.platforms &= ~platform.rawValue
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: "enabled") ?? false
        let decodedPlatforms = try container.decodeIfPresent(Int32.self, forKey: "platforms") ?? MiraSocialVideoSettings.allPlatforms
        self.platforms = decodedPlatforms & MiraSocialVideoSettings.allPlatforms
        self.wifiOnly = try container.decodeIfPresent(Bool.self, forKey: "wifiOnly") ?? true
        let rawQuality = try container.decodeIfPresent(Int32.self, forKey: "quality") ?? MiraSocialVideoQuality.source.rawValue
        self.quality = MiraSocialVideoQuality(rawValue: rawQuality) ?? .source
        self.confirmBeforeDownload = try container.decodeIfPresent(Bool.self, forKey: "confirmBeforeDownload") ?? true
        let rawDestination = try container.decodeIfPresent(Int32.self, forKey: "destination") ?? MiraSocialVideoDestination.chat.rawValue
        // Version 1 used 0 = Files and 1 = Photos. Keep those persisted
        // values readable while new settings default to the chat destination.
        self.destination = MiraSocialVideoDestination(rawValue: rawDestination) ?? .chat
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode(self.enabled, forKey: "enabled")
        try container.encode(self.platforms & MiraSocialVideoSettings.allPlatforms, forKey: "platforms")
        try container.encode(self.wifiOnly, forKey: "wifiOnly")
        try container.encode(self.quality.rawValue, forKey: "quality")
        try container.encode(self.confirmBeforeDownload, forKey: "confirmBeforeDownload")
        try container.encode(self.destination.rawValue, forKey: "destination")
    }
}

public struct MiraSocialVideoLink: Equatable {
    public let platform: MiraSocialVideoPlatform
    public let url: URL

    public init(platform: MiraSocialVideoPlatform, url: URL) {
        self.platform = platform
        self.url = url
    }
}

/// Local-only social-video URL recognition. This intentionally performs no
/// redirects, metadata lookups, downloads, or other network activity.
public enum MiraSocialVideoLinkParser {
    public static func parse(_ text: String) -> MiraSocialVideoLink? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let candidate: String
        if trimmed.range(of: "^[A-Za-z][A-Za-z0-9+.-]*://", options: .regularExpression) == nil {
            candidate = "https://" + trimmed
        } else {
            candidate = trimmed
        }
        guard var components = URLComponents(string: candidate),
              let host = components.host?.lowercased(),
              components.user == nil,
              components.password == nil,
              components.port == nil,
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let normalizedHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let path = components.path.lowercased()
        let platform: MiraSocialVideoPlatform?
        switch normalizedHost {
        case "youtube.com", "m.youtube.com", "youtu.be":
            if normalizedHost == "youtu.be" {
                platform = path.count > 1 ? .youtube : nil
            } else {
                let supportedPath = path.hasPrefix("/watch") || path.hasPrefix("/shorts/") || path.hasPrefix("/live/") || path.hasPrefix("/embed/")
                platform = supportedPath ? .youtube : nil
            }
        case "instagram.com":
            platform = (path.hasPrefix("/reel/") || path.hasPrefix("/share/reel/") || path.hasPrefix("/p/") || path.hasPrefix("/tv/")) ? .instagram : nil
        case "tiktok.com", "m.tiktok.com", "vm.tiktok.com", "vt.tiktok.com":
            // vm./vt. hosts are TikTok's share-link redirectors and do not
            // include `/video/` until the redirect is followed.
            platform = normalizedHost == "tiktok.com" || normalizedHost == "m.tiktok.com" ? (path.contains("/video/") ? .tiktok : nil) : (path.count > 1 ? .tiktok : nil)
        case "twitter.com", "x.com":
            platform = path.contains("/status/") ? .twitter : nil
        case "vk.com":
            platform = path.hasPrefix("/video") ? .vk : nil
        case "rutube.ru":
            platform = path.hasPrefix("/video/") ? .rutube : nil
        default:
            platform = nil
        }
        guard let platform else {
            return nil
        }

        // Fragments are client-only and cannot identify a video. Dropping one
        // makes equality and local duplicate detection deterministic.
        components.scheme = scheme
        components.host = normalizedHost
        components.fragment = nil
        guard let url = components.url else {
            return nil
        }
        return MiraSocialVideoLink(platform: platform, url: url)
    }
}

public enum MiraLocalPeerRole: String, Codable, Equatable {
    case none
    case owner
    case administrator

    public var displayName: String {
        switch self {
        case .none:
            return "No role"
        case .owner:
            return "Owner"
        case .administrator:
            return "Administrator"
        }
    }
}

/// Local-only presentation overrides keyed by a stable Telegram peer id.
/// These values are intentionally kept outside Telegram's peer models so they
/// cannot be serialized into API requests or alter server permissions.
public struct MiraLocalPeerOverride: Codable, Equatable {
    public var username: String?
    /// Optional display-only handle/tag. This is intentionally independent
    /// from username so a fake owner/admin label can be shown without
    /// changing the peer's projected username.
    public var tag: String?
    public var phone: String?
    public var firstName: String?
    public var lastName: String?
    public var role: MiraLocalPeerRole

    public init(username: String? = nil, tag: String? = nil, phone: String? = nil, firstName: String? = nil, lastName: String? = nil, role: MiraLocalPeerRole = .none) {
        self.username = MiraLocalPeerOverride.normalizedHandle(username)
        self.tag = MiraLocalPeerOverride.normalizedHandle(tag)
        self.phone = MiraLocalPeerOverride.normalizedText(phone)
        self.firstName = MiraLocalPeerOverride.normalizedText(firstName)
        self.lastName = MiraLocalPeerOverride.normalizedText(lastName)
        self.role = role
    }

    public var isEmpty: Bool {
        return self.username == nil && self.tag == nil && self.phone == nil && self.firstName == nil && self.lastName == nil && self.role == .none
    }

    public var displayName: String? {
        let value = [self.firstName, self.lastName].compactMap { $0 }.joined(separator: " ")
        return value.isEmpty ? nil : value
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedHandle(_ value: String?) -> String? {
        guard let value = normalizedText(value) else { return nil }
        let withoutAt = value.hasPrefix("@") ? String(value.dropFirst()) : value
        return withoutAt.isEmpty ? nil : withoutAt
    }
}

public struct MiraSettings: Codable, Equatable {
    public var ghost: [String: MiraGhostSettings]
    /// Account-scoped Ghost Mode overrides. Keys use the account's stable peer id
    /// (`account:<peerId>`); the legacy `ghost` dictionary remains the fallback
    /// for older settings and per-chat overrides.
    public var ghostByAccount: [String: MiraGhostSettings]
    public var useGlobalGhostMode: Bool
    /// Local-only username, phone and channel role presentation overrides.
    /// Keys are decimal `PeerId.toInt64()` values.
    public var localPeerOverrides: [String: MiraLocalPeerOverride]
    
    public var saveDeletedMessages: Bool
    public var saveMessagesHistory: Bool
    public var saveForBots: Bool
    
    public var localPremium: Bool
    public var fakeStarsEnabled: Bool
    public var fakeStarsBalance: Int64
    public var fakeGiftsEnabled: Bool
    public var fakeGiftCount: Int32
    public var fakeRatingEnabled: Bool
    /// Total Star rating value entered by the user. `fakeRatingLevel` is kept
    /// as a legacy storage key for settings written by older builds.
    public var fakeRatingValue: Int64
    public var fakeRatingLevel: Int32
    public var fakePremiumSince: Bool
    
    public var deletedMark: String
    public var editedMark: String
    public var semiTransparentDeletedMessages: Bool
    
    public var disableAds: Bool
    public var disableStories: Bool
    public var showPeerId: Bool
    public var filterZalgo: Bool
    public var streamerMode: Bool
    public var screenshotEvasion: Bool
    
    public var voiceChangerEnabled: Bool
    public var voiceChangerPreset: Int32
    public var videoMessagesUseBackCamera: Bool
    public var showLocalOnline: Bool
    public var showRealLastSeen: Bool
    public var localMessageEditEnabled: Bool
    public var autoClearClipboard: Bool
    public var hidePhoneNumber: Bool
    public var showDeletedMarkInChatList: Bool
    public var showMessageSeconds: Bool
    public var compactChatList: Bool
    public var compactChatFolders: Bool
    public var fakeMessagesEnabled: Bool
    public var confirmJoinChannel: Bool
    public var confirmViewStory: Bool
    public var confirmCall: Bool
    public var confirmSendSticker: Bool
    public var confirmSendGif: Bool
    public var confirmSendVoice: Bool
    public var interfaceFont: Int32
    public var avatarCornerStyle: Int32
    public var socialVideoSettings: MiraSocialVideoSettings
    
    public static var defaultSettings: MiraSettings {
        return MiraSettings()
    }

    public var effectiveLocalPremium: Bool {
        return self.localPremium || self.fakePremiumSince
    }

    /// Telegram sends the authoritative level with the profile data. Fake
    /// profiles do not have that server value, so derive a deterministic level
    /// from the entered Star total in one place instead of exposing a second,
    /// contradictory setting. The thresholds are monotonic and saturate at
    /// the range accepted by the profile badge renderer.
    public static func starRatingLevel(forStars stars: Int64) -> Int32 {
        guard stars > 0 else {
            return 0
        }
        var level: Int32 = 0
        var threshold: Int64 = 1_000
        while level < 100 && stars >= threshold {
            level += 1
            if threshold > Int64.max / 2 {
                break
            }
            threshold *= 2
        }
        return level
    }

    public var effectiveFakeRatingLevel: Int32 {
        return MiraSettings.starRatingLevel(forStars: self.fakeRatingValue)
    }
    
    public init(
        ghost: [String: MiraGhostSettings] = [:],
        ghostByAccount: [String: MiraGhostSettings] = [:],
        useGlobalGhostMode: Bool = true,
        localPeerOverrides: [String: MiraLocalPeerOverride] = [:],
        saveDeletedMessages: Bool = true,
        saveMessagesHistory: Bool = true,
        saveForBots: Bool = false,
        localPremium: Bool = false,
        fakeStarsEnabled: Bool = false,
        fakeStarsBalance: Int64 = 0,
        fakeGiftsEnabled: Bool = false,
        fakeGiftCount: Int32 = 0,
        fakeRatingEnabled: Bool = false,
        fakeRatingValue: Int64 = 0,
        fakeRatingLevel: Int32 = 0,
        fakePremiumSince: Bool = false,
        deletedMark: String = "🧹",
        editedMark: String = "(edited)",
        semiTransparentDeletedMessages: Bool = false,
        disableAds: Bool = true,
        disableStories: Bool = false,
        showPeerId: Bool = false,
        filterZalgo: Bool = false,
        streamerMode: Bool = false,
        screenshotEvasion: Bool = false,
        voiceChangerEnabled: Bool = false,
        voiceChangerPreset: Int32 = 0,
        videoMessagesUseBackCamera: Bool = false,
        showLocalOnline: Bool = true,
        showRealLastSeen: Bool = false,
        localMessageEditEnabled: Bool = true,
        autoClearClipboard: Bool = false,
        hidePhoneNumber: Bool = false,
        showDeletedMarkInChatList: Bool = true,
        showMessageSeconds: Bool = false,
        compactChatList: Bool = false,
        compactChatFolders: Bool = false,
        fakeMessagesEnabled: Bool = true,
        confirmJoinChannel: Bool = false,
        confirmViewStory: Bool = false,
        confirmCall: Bool = false,
        confirmSendSticker: Bool = false,
        confirmSendGif: Bool = false,
        confirmSendVoice: Bool = false,
        interfaceFont: Int32 = 0,
        avatarCornerStyle: Int32 = 0,
        socialVideoSettings: MiraSocialVideoSettings = MiraSocialVideoSettings()
    ) {
        self.ghost = ghost
        self.ghostByAccount = ghostByAccount
        self.useGlobalGhostMode = useGlobalGhostMode
        self.localPeerOverrides = localPeerOverrides
        self.saveDeletedMessages = saveDeletedMessages
        self.saveMessagesHistory = saveMessagesHistory
        self.saveForBots = saveForBots
        self.localPremium = localPremium
        self.fakeStarsEnabled = fakeStarsEnabled
        self.fakeStarsBalance = max(0, fakeStarsBalance)
        self.fakeGiftsEnabled = fakeGiftsEnabled
        self.fakeGiftCount = max(0, fakeGiftCount)
        self.fakeRatingEnabled = fakeRatingEnabled
        self.fakeRatingValue = max(0, fakeRatingValue)
        self.fakeRatingLevel = fakeRatingLevel
        self.fakePremiumSince = fakePremiumSince
        self.deletedMark = deletedMark
        self.editedMark = editedMark
        self.semiTransparentDeletedMessages = semiTransparentDeletedMessages
        self.disableAds = disableAds
        self.disableStories = disableStories
        self.showPeerId = showPeerId
        self.filterZalgo = filterZalgo
        self.streamerMode = streamerMode
        self.screenshotEvasion = screenshotEvasion
        self.voiceChangerEnabled = voiceChangerEnabled
        self.voiceChangerPreset = voiceChangerPreset
        self.videoMessagesUseBackCamera = videoMessagesUseBackCamera
        self.showLocalOnline = showLocalOnline
        self.showRealLastSeen = showRealLastSeen
        self.localMessageEditEnabled = localMessageEditEnabled
        self.autoClearClipboard = autoClearClipboard
        self.hidePhoneNumber = hidePhoneNumber
        self.showDeletedMarkInChatList = showDeletedMarkInChatList
        self.showMessageSeconds = showMessageSeconds
        self.compactChatList = compactChatList
        self.compactChatFolders = compactChatFolders
        self.fakeMessagesEnabled = fakeMessagesEnabled
        self.confirmJoinChannel = confirmJoinChannel
        self.confirmViewStory = confirmViewStory
        self.confirmCall = confirmCall
        self.confirmSendSticker = confirmSendSticker
        self.confirmSendGif = confirmSendGif
        self.confirmSendVoice = confirmSendVoice
        self.interfaceFont = interfaceFont
        self.avatarCornerStyle = avatarCornerStyle
        self.socialVideoSettings = socialVideoSettings
    }
    
    public func ghostSettings(forPeerId peerId: EnginePeer.Id?) -> MiraGhostSettings {
        let globalSettings = self.ghost["0"] ?? .defaultSettings
        if self.useGlobalGhostMode {
            return globalSettings
        }
        guard let peerId = peerId else {
            return globalSettings
        }
        return self.ghost["\(peerId.toInt64())"] ?? globalSettings
    }

    public func localPeerOverride(forPeerId peerId: Int64) -> MiraLocalPeerOverride? {
        return self.localPeerOverrides[String(peerId)]
    }

    public mutating func setLocalPeerOverride(_ override: MiraLocalPeerOverride, forPeerId peerId: Int64) {
        let key = String(peerId)
        if override.isEmpty {
            self.localPeerOverrides.removeValue(forKey: key)
        } else {
            self.localPeerOverrides[key] = override
        }
    }

    public mutating func removeLocalPeerOverride(forPeerId peerId: Int64) {
        self.localPeerOverrides.removeValue(forKey: String(peerId))
    }

    /// Returns the Ghost Mode settings for an account, preserving the previous
    /// global/per-chat behavior when no account override has been configured.
    public func ghostSettings(forAccountPeerId accountPeerId: PeerId?, peerId: EnginePeer.Id? = nil) -> MiraGhostSettings {
        let accountSettings: MiraGhostSettings
        if let accountPeerId = accountPeerId, let value = self.ghostByAccount["account:\(accountPeerId.toInt64())"] {
            accountSettings = value
        } else {
            accountSettings = self.ghost["0"] ?? .defaultSettings
        }

        guard !self.useGlobalGhostMode, let peerId = peerId else {
            return accountSettings
        }
        return self.ghost["\(peerId.toInt64())"] ?? accountSettings
    }

    /// Stores an account-scoped Ghost Mode override. Passing nil leaves the
    /// existing global settings untouched.
    public mutating func setGhostSettings(_ settings: MiraGhostSettings, forAccountPeerId accountPeerId: PeerId?) {
        guard let accountPeerId = accountPeerId else {
            self.ghost["0"] = settings
            return
        }
        self.ghostByAccount["account:\(accountPeerId.toInt64())"] = settings
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        self.ghost = (try? container.decodeIfPresent([String: MiraGhostSettings].self, forKey: "ghost")) ?? [:]
        self.ghostByAccount = (try? container.decodeIfPresent([String: MiraGhostSettings].self, forKey: "ghostByAccount")) ?? [:]
        self.useGlobalGhostMode = try container.decodeIfPresent(Bool.self, forKey: "useGlobalGhostMode") ?? true
        self.localPeerOverrides = (try? container.decodeIfPresent([String: MiraLocalPeerOverride].self, forKey: "localPeerOverrides")) ?? [:]
        self.saveDeletedMessages = try container.decodeIfPresent(Bool.self, forKey: "saveDeletedMessages") ?? true
        self.saveMessagesHistory = try container.decodeIfPresent(Bool.self, forKey: "saveMessagesHistory") ?? true
        self.saveForBots = try container.decodeIfPresent(Bool.self, forKey: "saveForBots") ?? false
        self.localPremium = try container.decodeIfPresent(Bool.self, forKey: "localPremium") ?? false
        self.fakeStarsEnabled = try container.decodeIfPresent(Bool.self, forKey: "fakeStarsEnabled") ?? false
        self.fakeStarsBalance = max(0, try container.decodeIfPresent(Int64.self, forKey: "fakeStarsBalance") ?? 0)
        self.fakeGiftsEnabled = try container.decodeIfPresent(Bool.self, forKey: "fakeGiftsEnabled") ?? false
        self.fakeGiftCount = max(0, try container.decodeIfPresent(Int32.self, forKey: "fakeGiftCount") ?? 0)
        self.fakeRatingEnabled = try container.decodeIfPresent(Bool.self, forKey: "fakeRatingEnabled") ?? false
        let legacyRatingLevel = try container.decodeIfPresent(Int32.self, forKey: "fakeRatingLevel") ?? 0
        self.fakeRatingValue = max(0, try container.decodeIfPresent(Int64.self, forKey: "fakeRatingValue") ?? Int64(legacyRatingLevel))
        self.fakeRatingLevel = legacyRatingLevel
        self.fakePremiumSince = try container.decodeIfPresent(Bool.self, forKey: "fakePremiumSince") ?? false
        self.deletedMark = try container.decodeIfPresent(String.self, forKey: "deletedMark") ?? "🧹"
        self.editedMark = try container.decodeIfPresent(String.self, forKey: "editedMark") ?? "(edited)"
        self.semiTransparentDeletedMessages = try container.decodeIfPresent(Bool.self, forKey: "semiTransparentDeletedMessages") ?? false
        self.disableAds = try container.decodeIfPresent(Bool.self, forKey: "disableAds") ?? true
        self.disableStories = try container.decodeIfPresent(Bool.self, forKey: "disableStories") ?? false
        self.showPeerId = try container.decodeIfPresent(Bool.self, forKey: "showPeerId") ?? false
        self.filterZalgo = try container.decodeIfPresent(Bool.self, forKey: "filterZalgo") ?? false
        self.streamerMode = try container.decodeIfPresent(Bool.self, forKey: "streamerMode") ?? false
        self.screenshotEvasion = try container.decodeIfPresent(Bool.self, forKey: "screenshotEvasion") ?? false
        self.voiceChangerEnabled = try container.decodeIfPresent(Bool.self, forKey: "voiceChangerEnabled") ?? false
        let decodedVoiceChangerPreset = try container.decodeIfPresent(Int32.self, forKey: "voiceChangerPreset") ?? 0
        self.voiceChangerPreset = (0 ... 13).contains(decodedVoiceChangerPreset) ? decodedVoiceChangerPreset : 0
        self.videoMessagesUseBackCamera = try container.decodeIfPresent(Bool.self, forKey: "videoMessagesUseBackCamera") ?? false
        self.showLocalOnline = try container.decodeIfPresent(Bool.self, forKey: "showLocalOnline") ?? true
        self.showRealLastSeen = try container.decodeIfPresent(Bool.self, forKey: "showRealLastSeen") ?? false
        self.localMessageEditEnabled = try container.decodeIfPresent(Bool.self, forKey: "localMessageEditEnabled") ?? true
        self.autoClearClipboard = try container.decodeIfPresent(Bool.self, forKey: "autoClearClipboard") ?? false
        self.hidePhoneNumber = try container.decodeIfPresent(Bool.self, forKey: "hidePhoneNumber") ?? false
        self.showDeletedMarkInChatList = try container.decodeIfPresent(Bool.self, forKey: "showDeletedMarkInChatList") ?? true
        self.showMessageSeconds = try container.decodeIfPresent(Bool.self, forKey: "showMessageSeconds") ?? false
        self.compactChatList = try container.decodeIfPresent(Bool.self, forKey: "compactChatList") ?? false
        self.compactChatFolders = try container.decodeIfPresent(Bool.self, forKey: "compactChatFolders") ?? false
        self.fakeMessagesEnabled = try container.decodeIfPresent(Bool.self, forKey: "fakeMessagesEnabled") ?? true
        self.confirmJoinChannel = try container.decodeIfPresent(Bool.self, forKey: "confirmJoinChannel") ?? false
        self.confirmViewStory = try container.decodeIfPresent(Bool.self, forKey: "confirmViewStory") ?? false
        self.confirmCall = try container.decodeIfPresent(Bool.self, forKey: "confirmCall") ?? false
        self.confirmSendSticker = try container.decodeIfPresent(Bool.self, forKey: "confirmSendSticker") ?? false
        self.confirmSendGif = try container.decodeIfPresent(Bool.self, forKey: "confirmSendGif") ?? false
        self.confirmSendVoice = try container.decodeIfPresent(Bool.self, forKey: "confirmSendVoice") ?? false
        self.interfaceFont = try container.decodeIfPresent(Int32.self, forKey: "interfaceFont") ?? 0
        self.avatarCornerStyle = try container.decodeIfPresent(Int32.self, forKey: "avatarCornerStyle") ?? 0
        self.socialVideoSettings = (try? container.decodeIfPresent(MiraSocialVideoSettings.self, forKey: "socialVideoSettings")) ?? MiraSocialVideoSettings()
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encode(self.ghost, forKey: "ghost")
        try container.encode(self.ghostByAccount, forKey: "ghostByAccount")
        try container.encode(self.useGlobalGhostMode, forKey: "useGlobalGhostMode")
        try container.encode(self.localPeerOverrides, forKey: "localPeerOverrides")
        try container.encode(self.saveDeletedMessages, forKey: "saveDeletedMessages")
        try container.encode(self.saveMessagesHistory, forKey: "saveMessagesHistory")
        try container.encode(self.saveForBots, forKey: "saveForBots")
        try container.encode(self.localPremium, forKey: "localPremium")
        try container.encode(self.fakeStarsEnabled, forKey: "fakeStarsEnabled")
        try container.encode(self.fakeStarsBalance, forKey: "fakeStarsBalance")
        try container.encode(self.fakeGiftsEnabled, forKey: "fakeGiftsEnabled")
        try container.encode(self.fakeGiftCount, forKey: "fakeGiftCount")
        try container.encode(self.fakeRatingEnabled, forKey: "fakeRatingEnabled")
        try container.encode(self.fakeRatingValue, forKey: "fakeRatingValue")
        try container.encode(self.fakeRatingLevel, forKey: "fakeRatingLevel")
        try container.encode(self.fakePremiumSince, forKey: "fakePremiumSince")
        try container.encode(self.deletedMark, forKey: "deletedMark")
        try container.encode(self.editedMark, forKey: "editedMark")
        try container.encode(self.semiTransparentDeletedMessages, forKey: "semiTransparentDeletedMessages")
        try container.encode(self.disableAds, forKey: "disableAds")
        try container.encode(self.disableStories, forKey: "disableStories")
        try container.encode(self.showPeerId, forKey: "showPeerId")
        try container.encode(self.filterZalgo, forKey: "filterZalgo")
        try container.encode(self.streamerMode, forKey: "streamerMode")
        try container.encode(self.screenshotEvasion, forKey: "screenshotEvasion")
        try container.encode(self.voiceChangerEnabled, forKey: "voiceChangerEnabled")
        try container.encode(self.voiceChangerPreset, forKey: "voiceChangerPreset")
        try container.encode(self.videoMessagesUseBackCamera, forKey: "videoMessagesUseBackCamera")
        try container.encode(self.showLocalOnline, forKey: "showLocalOnline")
        try container.encode(self.showRealLastSeen, forKey: "showRealLastSeen")
        try container.encode(self.localMessageEditEnabled, forKey: "localMessageEditEnabled")
        try container.encode(self.autoClearClipboard, forKey: "autoClearClipboard")
        try container.encode(self.hidePhoneNumber, forKey: "hidePhoneNumber")
        try container.encode(self.showDeletedMarkInChatList, forKey: "showDeletedMarkInChatList")
        try container.encode(self.showMessageSeconds, forKey: "showMessageSeconds")
        try container.encode(self.compactChatList, forKey: "compactChatList")
        try container.encode(self.compactChatFolders, forKey: "compactChatFolders")
        try container.encode(self.fakeMessagesEnabled, forKey: "fakeMessagesEnabled")
        try container.encode(self.confirmJoinChannel, forKey: "confirmJoinChannel")
        try container.encode(self.confirmViewStory, forKey: "confirmViewStory")
        try container.encode(self.confirmCall, forKey: "confirmCall")
        try container.encode(self.confirmSendSticker, forKey: "confirmSendSticker")
        try container.encode(self.confirmSendGif, forKey: "confirmSendGif")
        try container.encode(self.confirmSendVoice, forKey: "confirmSendVoice")
        try container.encode(self.interfaceFont, forKey: "interfaceFont")
        try container.encode(self.avatarCornerStyle, forKey: "avatarCornerStyle")
        try container.encode(self.socialVideoSettings, forKey: "socialVideoSettings")
    }
}

public func updateMiraSettingsInteractively(accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (inout MiraSettings) -> Void) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.miraSettings, { entry in
            var currentSettings: MiraSettings
            if let entry = entry?.get(MiraSettings.self) {
                currentSettings = entry
            } else {
                currentSettings = .defaultSettings
            }
            f(&currentSettings)
            return SharedPreferencesEntry(currentSettings)
        })
    }
}

public func miraSettingsSignal(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<MiraSettings, NoError> {
    return accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.miraSettings])
    |> map { sharedData -> MiraSettings in
        if let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.miraSettings]?.get(MiraSettings.self) {
            return settings
        } else {
            return .defaultSettings
        }
    }
}

public func currentMiraSettings(accountManager: AccountManager<TelegramAccountManagerTypes>) -> MiraSettings {
    let semaphore = DispatchSemaphore(value: 0)
    var result = MiraSettings.defaultSettings
    let _ = (accountManager.transaction { transaction -> MiraSettings? in
        if let value = transaction.getSharedData(ApplicationSpecificSharedDataKeys.miraSettings)?.get(MiraSettings.self) {
            return value
        } else {
            return nil
        }
    }).start(next: { value in
        if let value {
            result = value
        }
        semaphore.signal()
    })
    semaphore.wait()
    return result
}
