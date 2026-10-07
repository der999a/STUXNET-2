import Foundation
import Postbox
import SwiftSignalKit

func miraIsSavableDeletedMessage(transaction: Transaction, message: Message, accountPeerId: PeerId? = nil) -> Bool {
    if message.id.namespace != Namespaces.Message.Cloud {
        return false
    }
    if message.id.peerId.namespace == Namespaces.Peer.SecretChat {
        return false
    }
    for media in message.media {
        if media is TelegramMediaAction {
            return false
        }
    }
    if let authorId = message.author?.id, let user = transaction.getPeer(authorId) as? TelegramUser, user.botInfo != nil {
        if !MiraCoreGate.shared.snapshot(forAccountPeerId: accountPeerId).saveForBots {
            return false
        }
    }
    return true
}

func miraPartitionDeletedMessages(transaction: Transaction, ids: [MessageId], accountPeerId: PeerId? = nil) -> (mark: [MessageId], delete: [MessageId]) {
    if !MiraCoreGate.shared.snapshot(forAccountPeerId: accountPeerId).saveDeletedMessages {
        return ([], ids)
    }
    var mark: [MessageId] = []
    var delete: [MessageId] = []
    for id in ids {
        if let message = transaction.getMessage(id), miraIsSavableDeletedMessage(transaction: transaction, message: message, accountPeerId: accountPeerId) {
            mark.append(id)
        } else {
            delete.append(id)
        }
    }
    return (mark, delete)
}

func miraMarkMessagesAsLocallyDeleted(transaction: Transaction, ids: [MessageId], additionalAttributeUpdates: ((inout [MessageAttribute]) -> Void)? = nil) {
    if ids.isEmpty {
        return
    }
    let timestamp = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
    for id in ids {
        transaction.updateMessage(id, update: { currentMessage in
            if currentMessage.attributes.contains(where: { $0 is MiraLocallyDeletedMessageAttribute }) {
                return .skip
            }
            let storeForwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
            var attributes = currentMessage.attributes
            additionalAttributeUpdates?(&attributes)
            attributes.append(MiraLocallyDeletedMessageAttribute(date: timestamp))
            return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
        })
    }
}

func miraTouchMessage(transaction: Transaction, id: MessageId) {
    transaction.updateMessage(id, update: { currentMessage in
        let storeForwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
        return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: currentMessage.attributes, media: currentMessage.media))
    })
}

func miraSnapshotMessageEditIfNeeded(accountPeerId: PeerId, previousMessage: Message, updatedMessage: StoreMessage) {
    if !MiraCoreGate.shared.snapshot(forAccountPeerId: accountPeerId).saveMessagesHistory {
        return
    }
    if previousMessage.id.namespace != Namespaces.Message.Cloud {
        return
    }
    if previousMessage.id.peerId.namespace == Namespaces.Peer.SecretChat {
        return
    }
    if previousMessage.text == updatedMessage.text {
        return
    }
    guard let store = MiraMessageHistoryStore.store(for: accountPeerId) else {
        return
    }
    var previousEditDate: Int32?
    for attribute in previousMessage.attributes {
        if let attribute = attribute as? EditedMessageAttribute {
            previousEditDate = attribute.date
            break
        }
    }
    let record = MiraMessageEditRecord(
        messagePeerId: previousMessage.id.peerId.toInt64(),
        messageNamespace: previousMessage.id.namespace,
        messageId: previousMessage.id.id,
        text: previousMessage.text,
        entities: previousMessage.textEntitiesAttribute?.entities ?? [],
        date: previousMessage.timestamp,
        editDate: previousEditDate
    )
    store.appendEdit(record)
}
