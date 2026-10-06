import Foundation
import Postbox

public class MiraLocallyDeletedMessageAttribute: MessageAttribute {
    public let date: Int32

    public init(date: Int32) {
        self.date = date
    }

    required public init(decoder: PostboxDecoder) {
        self.date = decoder.decodeInt32ForKey("d", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.date, forKey: "d")
    }
}

public extension Message {
    var miraLocallyDeletedAttribute: MiraLocallyDeletedMessageAttribute? {
        for attribute in self.attributes {
            if let attribute = attribute as? MiraLocallyDeletedMessageAttribute {
                return attribute
            }
        }
        return nil
    }

    var isMiraLocallyDeleted: Bool {
        return self.miraLocallyDeletedAttribute != nil
    }
}
