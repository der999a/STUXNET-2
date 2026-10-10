import Foundation
import UIKit
import Photos
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

private func stuxnetDeterministicStableId(_ value: String) -> Int {
    var result: UInt64 = 1469598103934665603
    for byte in value.utf8 {
        result ^= UInt64(byte)
        result &*= 1099511628211
    }
    return Int(truncatingIfNeeded: result & 0x3fffffff)
}

private func stuxnetNormalizedLocalHandle(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let handle = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
    return handle.isEmpty ? nil : handle
}

private func stuxnetSaturatingSum(_ values: [Int64]) -> Int64 {
    values.reduce(Int64(0)) { partial, value in
        let (result, overflow) = partial.addingReportingOverflow(max(0, value))
        return overflow ? Int64.max : result
    }
}

private final class StuxnetLocalChannelEditorArguments {
    var channel: MiraFakeChannel
    let save: (MiraFakeChannel) -> Void
    let remove: (() -> Void)?
    let openPosts: () -> Void
    var pickAvatar: () -> Void
    var present: ((ViewController) -> Void)?
    let update: () -> Void

    init(channel: MiraFakeChannel, save: @escaping (MiraFakeChannel) -> Void, remove: (() -> Void)?, openPosts: @escaping () -> Void, pickAvatar: @escaping () -> Void, update: @escaping () -> Void) {
        self.channel = channel
        self.save = save
        self.remove = remove
        self.openPosts = openPosts
        self.pickAvatar = pickAvatar
        self.update = update
    }
}

private enum StuxnetLocalChannelEditorEntry: ItemListNodeEntry {
    case input(Int, String, String, String, Bool)
    case role(String)
    case visibility(String)
    case avatar(String?)
    case posts(Int)
    case permissions(String)
    case stats(String)
    case delete
    case info(String)

    var section: ItemListSectionId {
        switch self {
        case .input, .role, .visibility, .avatar, .posts, .permissions, .stats:
            return 0
        case .delete, .info:
            return 1
        }
    }

    var stableId: Int {
        switch self {
        case let .input(id, _, _, _, _): return id
        case .role: return 20
        case .visibility: return 21
        case .posts: return 22
        case .avatar: return 23
        case .permissions: return 24
        case .stats: return 25
        case .delete: return 26
        case .info: return 27
        }
    }

    static func < (lhs: StuxnetLocalChannelEditorEntry, rhs: StuxnetLocalChannelEditorEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! StuxnetLocalChannelEditorArguments
        switch self {
        case let .input(id, title, value, placeholder, isNumber):
            return ItemListSingleLineInputItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: NSAttributedString(string: title),
                text: value,
                placeholder: placeholder,
                type: isNumber ? .number : .regular(capitalization: true, autocorrection: false),
                sectionId: self.section,
                textUpdated: { value in
                    var channel = arguments.channel
                    switch id {
                    case 0: channel.title = value
                    case 1: channel.about = value
                    case 2: channel.username = stuxnetNormalizedLocalHandle(value)
                    case 3: channel.adminTag = stuxnetNormalizedLocalHandle(value)
                    case 4: channel.roleLabel = value.isEmpty ? nil : value
                    case 5: channel.ownerName = value.isEmpty ? nil : value
                    case 6: channel.ownerUsername = stuxnetNormalizedLocalHandle(value)
                    case 7: channel.subscribers = max(0, Int64(value) ?? 0)
                    case 8: channel.starsBalance = max(0, Int64(value) ?? 0)
                    case 9: channel.avatarPath = value.isEmpty ? nil : value
                    case 10: channel.inviteLink = value.isEmpty ? nil : value
                    default: break
                    }
                    arguments.channel = channel
                    arguments.update()
                },
                action: {}
            )
        case let .role(value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: nil, title: "Local role", label: value, sectionId: self.section, style: .blocks, action: {
                let sheet = ActionSheetController(presentationData: presentationData)
                let select: (MiraFakeChannel.Role, String) -> ActionSheetButtonItem = { role, title in
                    return ActionSheetButtonItem(title: title, color: .accent, action: { [weak sheet] in
                        var channel = arguments.channel
                        channel.role = role
                        arguments.channel = channel
                        arguments.update()
                        sheet?.dismissAnimated()
                    })
                }
                sheet.setItemGroups([
                    ActionSheetItemGroup(items: [
                        select(.owner, "Owner"),
                        select(.administrator, "Administrator"),
                        select(.member, "Member")
                    ]),
                    ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })])
                ])
                arguments.present?(sheet)
            })
        case let .visibility(value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: nil, title: "Visibility", label: value, sectionId: self.section, style: .blocks, action: {
                var channel = arguments.channel
                channel.visibility = channel.visibility == .publicChannel ? .privateChannel : .publicChannel
                arguments.channel = channel
                arguments.update()
            })
        case let .avatar(value):
            let label: String
            let labelStyle: ItemListDisclosureLabelStyle
            if let value, !value.isEmpty {
                label = URL(fileURLWithPath: value).lastPathComponent
                if let image = UIImage(contentsOfFile: value) {
                    labelStyle = .image(image: image, size: CGSize(width: 28.0, height: 28.0))
                } else {
                    labelStyle = .text
                }
            } else {
                label = "Choose from Photos"
                labelStyle = .text
            }
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: nil, title: "Channel avatar", label: label, labelStyle: labelStyle, sectionId: self.section, style: .blocks, action: arguments.pickAvatar)
        case let .posts(count):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: nil, title: "Local posts", label: "\(count)", sectionId: self.section, style: .blocks, action: arguments.openPosts)
        case let .permissions(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .stats(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .delete:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Delete local channel", kind: .destructive, alignment: .center, sectionId: self.section, style: .blocks, action: {
                arguments.remove?()
            })
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func stuxnetLocalChannelEditorController(context: AccountContext, channel: MiraFakeChannel, isNew: Bool) -> ViewController {
    let store = context.account.miraFakeChannelsStore
    var dismissImpl: (() -> Void)?
    var openPostsImpl: (() -> Void)?
    let revision = ValuePromise<Int>(0)
    var revisionValue = 0
    let update = {
        revisionValue += 1
        revision.set(revisionValue)
    }
    let arguments = StuxnetLocalChannelEditorArguments(channel: channel, save: { value in
        store.upsert(value)
    }, remove: isNew ? nil : {
        _ = store.remove(id: channel.id)
        dismissImpl?()
    }, openPosts: {
        openPostsImpl?()
    }, pickAvatar: {}, update: update)

    let signal = combineLatest(context.sharedContext.presentationData, store.changes, revision.get())
    |> map { presentationData, _, _ -> (ItemListControllerState, (ItemListNodeState, StuxnetLocalChannelEditorArguments)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(isNew ? "New Local Channel" : "Edit Local Channel"),
            leftNavigationButton: nil,
            rightNavigationButton: ItemListNavigationButton(content: .text("Save"), style: .regular, enabled: !store.isReadOnly && !arguments.channel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, action: {
                guard !arguments.channel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                arguments.save(arguments.channel)
                dismissImpl?()
            }),
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: true
        )
        let channel = arguments.channel
        var entries: [StuxnetLocalChannelEditorEntry] = [
            .input(0, "Name", channel.title, "Channel name", false),
            .input(1, "Description", channel.about, "About this channel", false),
            .input(2, "Username", channel.username ?? "", "local_channel", false),
            .input(3, "Owner / admin tag", channel.adminTag ?? "", "Owner", false),
            .input(4, "Role label", channel.roleLabel ?? "", "Owner / Administrator", false),
            .input(5, "Owner name", channel.ownerName ?? "", "Local owner display name", false),
            .input(6, "Owner username", channel.ownerUsername ?? "", "@owner", false),
            .input(7, "Subscribers", String(channel.subscribers), "0", true),
            .input(8, "Channel Stars", String(channel.starsBalance), "0", true),
            .avatar(channel.avatarPath),
            .input(9, "Avatar file path", channel.avatarPath ?? "", "Optional path (advanced)", false),
            .input(10, "Invite link", channel.inviteLink ?? "", "https://t.me/+...", false),
            .role(channel.role == .owner ? "Owner" : (channel.role == .administrator ? "Administrator" : "Member")),
            .visibility(channel.visibility == .publicChannel ? "Public" : "Private"),
            .posts(channel.posts.count),
            .permissions(channel.role == .member
                ? "Member preview: Telegram channel editing controls are hidden and publishing is disabled."
                : "Admin preview: this device shows Telegram-style channel editing and posting controls. Changes stay local and never call Telegram APIs."),
            .stats("Stats · \(channel.subscribers) subscribers · \(channel.posts.count) posts · \(stuxnetSaturatingSum(channel.posts.map(\.views))) views · \(stuxnetSaturatingSum(channel.posts.map { $0.comments ?? 0 })) comments · \(stuxnetSaturatingSum(channel.posts.map { stuxnetSaturatingSum([$0.stars, $0.starReactions ?? 0]) })) Stars")
        ]
        if !isNew {
            entries.append(.delete)
        }
        if store.isReadOnly {
            entries.append(.info("This local data was written by a newer or unreadable schema and is open read-only to prevent overwriting it."))
        }
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)
        return (controllerState, (listState, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        guard let controller else {
            return
        }
        guard let navigationController = controller.navigationController as? NavigationController else {
            controller.dismiss()
            return
        }
        if navigationController.topViewController === controller {
            _ = navigationController.popViewController(animated: true)
        } else if let index = navigationController.viewControllers.firstIndex(where: { $0 === controller }), navigationController.viewControllers.count > 1 {
            // A media picker or another local editor may have been pushed while
            // the save was completing. Remove this editor itself instead of
            // popping whichever controller happens to be on top.
            var viewControllers = navigationController.viewControllers
            viewControllers.remove(at: index)
            navigationController.setViewControllers(viewControllers, animated: false)
        } else {
            controller.dismiss()
        }
    }
    arguments.present = { [weak controller] child in
        controller?.present(child, in: .window(.root))
    }
    openPostsImpl = { [weak controller] in
        guard let controller else { return }
        guard !arguments.channel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.upsert(arguments.channel)
        let posts = stuxnetLocalChannelPostsController(context: context, channelId: arguments.channel.id)
        (controller.navigationController as? NavigationController)?.pushViewController(posts)
    }
    arguments.pickAvatar = { [weak controller, weak arguments] in
        guard let controller else { return }
        let (picker, _) = context.sharedContext.makeAvatarMediaPickerScreen(context: context, peerType: .channel, getSourceRect: { return nil }, canDelete: arguments?.channel.avatarPath != nil, performDelete: {
            guard let arguments else { return }
            var value = arguments.channel
            value.avatarPath = nil
            arguments.channel = value
            arguments.update()
        }, completion: { [weak arguments] result, _, _, transitionImage, _, _, _ in
            guard let arguments else { return }
            let applyImage: (UIImage) -> Void = { image in
                guard let data = image.jpegData(compressionQuality: 0.88) else { return }
                let directory = URL(fileURLWithPath: context.account.basePath).appendingPathComponent("mira-fake-media", isDirectory: true)
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent("channel-\(arguments.channel.id)-avatar.jpg")
                guard (try? data.write(to: url, options: [.atomic])) != nil else { return }
                var value = arguments.channel
                value.avatarPath = url.path
                arguments.channel = value
                arguments.update()
            }
            if let image = result as? UIImage {
                applyImage(image)
            } else if let asset = result as? PHAsset {
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.resizeMode = .fast
                options.isSynchronous = false
                PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 1024.0, height: 1024.0), contentMode: .aspectFill, options: options) { image, _ in
                    if let image {
                        Queue.mainQueue().async {
                            applyImage(image)
                        }
                    }
                }
            } else if let transitionImage {
                applyImage(transitionImage)
            }
        }, dismissed: {})
        guard let picker else { return }
        controller.present(picker, in: .window(.root))
    }
    return controller
}

private final class StuxnetLocalChannelPostEditorArguments {
    var post: MiraFakeChannel.Post
    let save: (MiraFakeChannel.Post) -> Bool
    var pickMedia: () -> Void
    let update: () -> Void

    init(post: MiraFakeChannel.Post, save: @escaping (MiraFakeChannel.Post) -> Bool, pickMedia: @escaping () -> Void, update: @escaping () -> Void) {
        self.post = post
        self.save = save
        self.pickMedia = pickMedia
        self.update = update
    }
}

private enum StuxnetLocalChannelPostEditorEntry: ItemListNodeEntry {
    case input(Int, String, String, String, Bool)
    case media(String?)
    case footer(String)

    var section: ItemListSectionId { return 0 }
    var stableId: Int {
        switch self {
        case let .input(id, _, _, _, _): return id
        case .media: return 7
        case .footer: return 11
        }
    }
    static func < (lhs: StuxnetLocalChannelPostEditorEntry, rhs: StuxnetLocalChannelPostEditorEntry) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! StuxnetLocalChannelPostEditorArguments
        switch self {
        case let .input(id, title, value, placeholder, isNumber):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: title), text: value, placeholder: placeholder, type: isNumber ? .number : .regular(capitalization: true, autocorrection: true), sectionId: self.section, textUpdated: { value in
                var post = arguments.post
                switch id {
                case 0: post.text = value
                case 1: post.views = max(0, Int64(value) ?? 0)
                case 2: post.stars = max(0, Int64(value) ?? 0)
                case 3: post.mediaPath = value.isEmpty ? nil : value
                case 4: post.date = Int32(value) ?? post.date
                case 5:
                    post.reactions = value.split(separator: ",").reduce(into: [:]) { result, item in
                        let parts = item.split(separator: "=", maxSplits: 1).map(String.init)
                        guard parts.count == 2, let count = Int64(parts[1]), count >= 0 else { return }
                        let reaction = parts[0].trimmingCharacters(in: .whitespaces)
                        guard !reaction.isEmpty else { return }
                        result[reaction] = count
                    }
                case 6:
                    post.starReactions = max(0, Int64(value) ?? 0)
                case 8:
                    post.comments = max(0, Int64(value) ?? 0)
                default: break
                }
                arguments.post = post
            }, action: {})
        case let .media(path):
            let label = path.flatMap { value in value.isEmpty ? nil : URL(fileURLWithPath: value).lastPathComponent } ?? "Choose from Photos"
            let labelStyle: ItemListDisclosureLabelStyle
            if let path, let image = UIImage(contentsOfFile: path) {
                labelStyle = .image(image: image, size: CGSize(width: 28.0, height: 28.0))
            } else {
                labelStyle = .text
            }
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: nil, title: "Post media", label: label, labelStyle: labelStyle, sectionId: self.section, style: .blocks, action: arguments.pickMedia)
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func stuxnetLocalChannelPostEditorController(context: AccountContext, channelId: String, post: MiraFakeChannel.Post?) -> ViewController {
    let store = context.account.miraFakeChannelsStore
    var pickMediaImpl: (() -> Void)?
    var revisionValue = 0
    let revision = ValuePromise<Int>(0)
    let update = {
        revisionValue += 1
        revision.set(revisionValue)
    }
    let arguments = StuxnetLocalChannelPostEditorArguments(post: post ?? MiraFakeChannel.Post(text: ""), save: { value in
        guard !store.isReadOnly, store.channel(id: channelId) != nil else {
            return false
        }
        let oldPostStars = max(0, post?.stars ?? 0)
        let newPostStars = max(0, value.stars)
        let oldReactionStars = max(0, post?.starReactions ?? 0)
        let newReactionStars = max(0, value.starReactions ?? 0)
        let ledgerUpdated = context.account.miraFakeStarsLedger.adjustChannelStars(
            id: value.id,
            peerId: context.account.peerId.toInt64(),
            oldPostStars: oldPostStars,
            newPostStars: newPostStars,
            oldReactionStars: oldReactionStars,
            newReactionStars: newReactionStars,
            date: value.date
        )
        guard ledgerUpdated else {
            return false
        }
        let oldStars = stuxnetSaturatingSum([oldPostStars, oldReactionStars])
        let newStars = stuxnetSaturatingSum([newPostStars, newReactionStars])
        let channelDelta = newStars >= oldStars ? newStars - oldStars : -(oldStars - newStars)
        if channelDelta != 0 {
            store.update(id: channelId) { channel in
                let (updated, overflow) = channel.starsBalance.addingReportingOverflow(channelDelta)
                channel.starsBalance = overflow ? (channelDelta > 0 ? Int64.max : 0) : max(0, updated)
            }
        }
        store.addPost(channelId: channelId, post: value)
        return store.channel(id: channelId)?.posts.contains(where: { $0.id == value.id }) == true
    }, pickMedia: {
        pickMediaImpl?()
    }, update: update)
    var dismissImpl: (() -> Void)?
    let signal = combineLatest(context.sharedContext.presentationData, revision.get())
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, StuxnetLocalChannelPostEditorArguments)) in
        let value = arguments.post
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(post == nil ? "New Local Post" : "Edit Local Post"), leftNavigationButton: nil, rightNavigationButton: ItemListNavigationButton(content: .text("Save"), style: .regular, enabled: !store.isReadOnly && store.channel(id: channelId) != nil, action: {
            if arguments.save(arguments.post) {
                dismissImpl?()
            }
        }), backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)
        let entries: [StuxnetLocalChannelPostEditorEntry] = [
            .input(0, "Text", value.text, "Post text", false),
            .input(1, "Views", String(value.views), "0", true),
            .input(2, "Stars", String(value.stars), "0", true),
            .media(value.mediaPath),
            .input(3, "Media path", value.mediaPath ?? "", "Optional local media path", false),
            .input(4, "Date (Unix seconds)", String(value.date), "Current time", true),
            .input(5, "Reactions", value.reactions.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", "), "👍=12, ❤️=4", false),
            .input(6, "Stars from reactions", String(value.starReactions ?? 0), "0", true),
            .input(8, "Comments", String(value.comments ?? 0), "0", true),
            .footer("Posts, reactions and Stars are local projections and never publish to Telegram.")
        ]
        return (controllerState, (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks), arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        guard let controller else {
            return
        }
        guard let navigationController = controller.navigationController as? NavigationController else {
            controller.dismiss()
            return
        }
        if navigationController.topViewController === controller {
            _ = navigationController.popViewController(animated: true)
        } else if let index = navigationController.viewControllers.firstIndex(where: { $0 === controller }), navigationController.viewControllers.count > 1 {
            var viewControllers = navigationController.viewControllers
            viewControllers.remove(at: index)
            navigationController.setViewControllers(viewControllers, animated: false)
        } else {
            controller.dismiss()
        }
    }
    pickMediaImpl = { [weak controller, weak arguments] in
        guard let controller, let arguments else { return }
        let picker = context.sharedContext.makeMediaPickerScreen(context: context, hasSearch: true, completion: { [weak arguments] result in
            guard let arguments else { return }
            let applyImage: (UIImage) -> Void = { image in
                guard let data = image.jpegData(compressionQuality: 0.88) else { return }
                let directory = URL(fileURLWithPath: context.account.basePath).appendingPathComponent("mira-fake-media", isDirectory: true)
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent("post-\(arguments.post.id).jpg")
                guard (try? data.write(to: url, options: [.atomic])) != nil else { return }
                var value = arguments.post
                value.mediaPath = url.path
                arguments.post = value
                arguments.update()
            }
            if let image = result as? UIImage {
                applyImage(image)
            } else if let asset = result as? PHAsset {
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.resizeMode = .fast
                PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 2048.0, height: 2048.0), contentMode: .aspectFit, options: options) { image, _ in
                    if let image {
                        Queue.mainQueue().async {
                            applyImage(image)
                        }
                    }
                }
            }
        })
        (controller.navigationController as? NavigationController)?.pushViewController(picker)
    }
    return controller
}

private enum StuxnetLocalChannelPostsEntry: ItemListNodeEntry {
    case compose(String, Bool)
    case add
    case post(MiraFakeChannel.Post)
    case footer(String)

    var section: ItemListSectionId { return 0 }
    var stableId: Int {
        switch self {
        case .compose: return 0
        case .add: return 1
        case let .post(post): return stuxnetDeterministicStableId(post.id) + 1
        case .footer: return Int.max
        }
    }
    static func < (lhs: StuxnetLocalChannelPostsEntry, rhs: StuxnetLocalChannelPostsEntry) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! StuxnetLocalChannelPostsArguments
        switch self {
        case let .compose(text, enabled):
            return ItemListMultilineInputItem(
                presentationData: presentationData,
                systemStyle: .glass,
                text: text,
                placeholder: enabled ? "Write a channel post" : "Only the owner or administrator can post",
                maxLength: ItemListMultilineInputItemTextLimit(value: 4096, display: true),
                sectionId: self.section,
                style: .blocks,
                textUpdated: { value in
                    arguments.composeText = value
                    arguments.updated()
                },
                shouldUpdateText: { value in
                    return enabled || value.isEmpty
                },
                updatedFocus: nil,
                inlineAction: ItemListMultilineInputInlineAction(
                    icon: UIImage(bundleImageName: "Chat/Input/Text/SendIcon") ?? UIImage(systemName: "paperplane.fill")!,
                    action: enabled ? arguments.publish : nil
                ),
                noInsets: false
            )
        case .add:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Add local post", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.add)
        case let .post(post):
            let title: String
            if !post.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                title = post.text
            } else if post.mediaPath != nil {
                title = "Media post"
            } else {
                title = "Untitled post"
            }
            let reactionStars = post.starReactions ?? 0
            let reactionCount = post.reactions.values.reduce(0, +)
            let postStars = stuxnetSaturatingSum([post.stars, reactionStars])
            var label = "\(post.views) views · \(postStars) Stars"
            if reactionCount > 0 {
                label += " · \(reactionCount) reactions"
            }
            if let comments = post.comments, comments > 0 {
                label += " · \(comments) comments"
            }
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.edit(post)
            })
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private final class StuxnetLocalChannelPostsArguments {
    let add: () -> Void
    let edit: (MiraFakeChannel.Post) -> Void
    var publish: () -> Void
    let updated: () -> Void
    var composeText: String

    init(add: @escaping () -> Void, edit: @escaping (MiraFakeChannel.Post) -> Void, publish: @escaping () -> Void, updated: @escaping () -> Void) {
        self.add = add
        self.edit = edit
        self.publish = publish
        self.updated = updated
        self.composeText = ""
    }
}

private func stuxnetLocalChannelPostsController(context: AccountContext, channelId: String) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    var revisionValue = 0
    let revision = ValuePromise<Int>(0)
    let update = {
        revisionValue += 1
        revision.set(revisionValue)
    }
    let store = context.account.miraFakeChannelsStore
    let arguments = StuxnetLocalChannelPostsArguments(add: {
        guard !store.isReadOnly, let channel = store.channel(id: channelId), channel.role != .member else {
            return
        }
        pushControllerImpl?(stuxnetLocalChannelPostEditorController(context: context, channelId: channelId, post: nil))
    }, edit: { post in
        pushControllerImpl?(stuxnetLocalChannelPostEditorController(context: context, channelId: channelId, post: post))
    }, publish: {}, updated: update)
    arguments.publish = { [weak arguments] in
        guard let arguments else {
            return
        }
        let text = arguments.composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !store.isReadOnly, !text.isEmpty, let channel = store.channel(id: channelId), channel.role != .member else {
            return
        }
        store.addPost(channelId: channelId, post: MiraFakeChannel.Post(text: text, date: MiraFakeChannel.currentTimestamp()))
        arguments.composeText = ""
        update()
    }
    let signal = combineLatest(context.sharedContext.presentationData, store.changes, revision.get())
    |> map { presentationData, channels, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let channel = channels.first(where: { $0.id == channelId })
        let posts = channel?.posts ?? []
        let canPublish = !store.isReadOnly && (channel?.role == .owner || channel?.role == .administrator)
        var entries: [StuxnetLocalChannelPostsEntry] = [.compose(arguments.composeText, canPublish), .add]
        entries.append(contentsOf: posts.map { .post($0) })
        if posts.isEmpty { entries.append(.footer("Posts, views, Stars and reactions are local channel data.")) }
        let roleText = channel?.role == .owner ? "Owner" : (channel?.role == .administrator ? "Administrator" : "Member")
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("\(roleText) · Posts"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)
        let list = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)
        return (state, (list, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] next in
        (controller?.navigationController as? NavigationController)?.pushViewController(next)
    }
    return controller
}

private final class StuxnetFakeChannelsArguments {
    let add: () -> Void
    let edit: (MiraFakeChannel) -> Void

    init(add: @escaping () -> Void, edit: @escaping (MiraFakeChannel) -> Void) {
        self.add = add
        self.edit = edit
    }
}

private enum StuxnetFakeChannelsEntry: ItemListNodeEntry {
    case add
    case channel(MiraFakeChannel)
    case footer(String)

    var section: ItemListSectionId { return 0 }
    var stableId: Int {
        switch self {
        case .add: return 0
        case let .channel(channel): return stuxnetDeterministicStableId(channel.id) + 1
        case .footer: return Int.max
        }
    }
    static func < (lhs: StuxnetFakeChannelsEntry, rhs: StuxnetFakeChannelsEntry) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! StuxnetFakeChannelsArguments
        switch self {
        case .add:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Create local channel", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.add)
        case let .channel(channel):
            let role = channel.roleLabel ?? (channel.role == .owner ? "Owner" : (channel.role == .administrator ? "Admin" : "Member"))
            let owner = channel.ownerName.map { " · \($0)" } ?? ""
            let tag = channel.adminTag.map { " · @\($0)" } ?? ""
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: nil, title: channel.title, label: "\(role)\(tag)\(owner) · \(channel.subscribers)", sectionId: self.section, style: .blocks, action: {
                arguments.edit(channel)
            })
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func stuxnetFakeChannelsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    let store = context.account.miraFakeChannelsStore
    let arguments = StuxnetFakeChannelsArguments(add: {
        pushControllerImpl?(stuxnetLocalChannelEditorController(context: context, channel: MiraFakeChannel(title: ""), isNew: true))
    }, edit: { channel in
        pushControllerImpl?(stuxnetLocalChannelEditorController(context: context, channel: channel, isNew: false))
    })
    let signal = combineLatest(context.sharedContext.presentationData, store.changes)
    |> map { presentationData, channels -> (ItemListControllerState, (ItemListNodeState, StuxnetFakeChannelsArguments)) in
        var entries: [StuxnetFakeChannelsEntry] = [.add]
        entries.append(contentsOf: channels.map { .channel($0) })
        if store.isReadOnly {
            entries.append(.footer("Local channel data is read-only because its schema is newer or unreadable."))
        } else if channels.isEmpty {
            entries.append(.footer("Channels created here are local to this account and do not exist on Telegram."))
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Local Channels"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)
        return (controllerState, (listState, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] next in
        (controller?.navigationController as? NavigationController)?.pushViewController(next)
    }
    return controller
}

private final class StuxnetLocalProfileOverrideArguments {
    var value: MiraLocalProfileOverride
    let save: (MiraLocalProfileOverride) -> Void

    init(value: MiraLocalProfileOverride, save: @escaping (MiraLocalProfileOverride) -> Void) {
        self.value = value
        self.save = save
    }
}

private enum StuxnetLocalProfileOverrideEntry: ItemListNodeEntry {
    case input(Int, String, String, String)
    case footer(String)

    var section: ItemListSectionId { return 0 }
    var stableId: Int {
        switch self {
        case let .input(id, _, _, _): return id
        case .footer: return 10
        }
    }
    static func < (lhs: StuxnetLocalProfileOverrideEntry, rhs: StuxnetLocalProfileOverrideEntry) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! StuxnetLocalProfileOverrideArguments
        switch self {
        case let .input(id, title, value, placeholder):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: title), text: value, placeholder: placeholder, type: .regular(capitalization: false, autocorrection: false), sectionId: self.section, textUpdated: { value in
                var override = arguments.value
                switch id {
                case 0: override.username = value.isEmpty ? nil : value
                case 1: override.tag = value.isEmpty ? nil : value
                case 2: override.phoneNumber = value.isEmpty ? nil : value
                case 3: override.firstName = value.isEmpty ? nil : value
                case 4: override.lastName = value.isEmpty ? nil : value
                default: break
                }
                arguments.value = override
            }, action: {})
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

/// Settings entry point for local username/phone/name projection of the
/// current account. The override never invokes Telegram profile RPCs.
public func stuxnetLocalProfilePreviewController(context: AccountContext) -> ViewController {
    let store = context.account.miraLocalProfileOverridesStore
    let key = String(context.account.peerId.toInt64())
    let arguments = StuxnetLocalProfileOverrideArguments(
        value: store.`override`(forKey: key) ?? MiraLocalProfileOverride(id: key),
        save: { value in
            store.set(value)
            // Keep the codec-backed settings editor in sync with the account
            // local projection used by profile and chat renderers.
            let settingsValue = MiraLocalPeerOverride(
                username: value.username,
                tag: value.tag,
                phone: value.phoneNumber,
                firstName: value.firstName,
                lastName: value.lastName
            )
            let _ = updateMiraSettingsInteractively(accountManager: context.sharedContext.accountManager) { settings in
                settings.setLocalPeerOverride(settingsValue, forPeerId: context.account.peerId.toInt64())
            }.start()
        }
    )
    var dismissImpl: (() -> Void)?
    let signal = combineLatest(context.sharedContext.presentationData, store.changes)
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, StuxnetLocalProfileOverrideArguments)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Local Profile Preview"),
            leftNavigationButton: nil,
            rightNavigationButton: ItemListNavigationButton(content: .text("Save"), style: .regular, enabled: !store.isReadOnly, action: {
                arguments.save(arguments.value)
                dismissImpl?()
            }),
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: true
        )
        let value = arguments.value
        let entries: [StuxnetLocalProfileOverrideEntry] = [
            .input(0, "Username", value.username ?? "", "username"),
            .input(1, "Display tag", value.tag ?? "", "@tag"),
            .input(2, "Phone number", value.phoneNumber ?? "", "+1 555 0100"),
            .input(3, "First name", value.firstName ?? "", "First name"),
            .input(4, "Last name", value.lastName ?? "", "Last name"),
            .footer(store.isReadOnly ? "Local profile data is read-only because its schema is newer or unreadable." : "These values change only this device's profile preview. Telegram account details remain unchanged.")
        ]
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)
        return (controllerState, (listState, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        guard let controller else {
            return
        }
        guard let navigationController = controller.navigationController as? NavigationController else {
            controller.dismiss()
            return
        }
        if navigationController.topViewController === controller {
            _ = navigationController.popViewController(animated: true)
        } else if let index = navigationController.viewControllers.firstIndex(where: { $0 === controller }), navigationController.viewControllers.count > 1 {
            var viewControllers = navigationController.viewControllers
            viewControllers.remove(at: index)
            navigationController.setViewControllers(viewControllers, animated: false)
        } else {
            controller.dismiss()
        }
    }
    return controller
}
