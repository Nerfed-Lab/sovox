import Foundation

/// Percent encoding for x-callback-url and ms-outlook payloads.
///
/// .urlQueryAllowed is unusable here. It permits & + # = ? to pass through
/// unescaped, which truncates the Outlook body at the first one. It also
/// permits non ASCII letters, which produces an invalid URL string.
/// The set below is exactly the RFC 3986 unreserved set, spelled out so no
/// Foundation change can widen it underneath us.
enum URLEncoding {
    static let unreserved: CharacterSet = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    static func decode(_ value: String) -> String? {
        value.removingPercentEncoding
    }

    /// Builds a URL from a scheme, a path and already unencoded parameters.
    static func url(scheme: String, path: String, parameters: [(String, String)]) -> URL? {
        var string = scheme + "://" + path
        if !parameters.isEmpty {
            let query = parameters
                .map { encode($0.0) + "=" + encode($0.1) }
                .joined(separator: "&")
            string += "?" + query
        }
        return URL(string: string)
    }
}
