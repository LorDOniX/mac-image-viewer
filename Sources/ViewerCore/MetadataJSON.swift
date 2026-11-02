import Foundation

public enum MetadataJSON {
    public static func encode(_ metadata: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: normalize(metadata), options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    private static func normalize(_ value: Any) -> Any {
        switch value {
        case let dictionary as [String: Any]: return dictionary.mapValues(normalize)
        case let array as [Any]: return array.map(normalize)
        case let data as Data: return ["encoding": "base64", "data": data.base64EncodedString()]
        case let date as Date: return ISO8601DateFormatter().string(from: date)
        case let number as NSNumber:
            return number.doubleValue.isFinite ? number : number.stringValue
        case let string as String: return string
        case is NSNull: return NSNull()
        default: return String(describing: value)
        }
    }
}
