import Foundation

/// Incremental HTTP/1.1 framing. Reject malformed lengths before slicing Data.
enum HTTPRequestParser {
    enum Invalid: Error { case request }
    static let bodyLimit = 1 << 20
    static let headerLimit = 16 << 10

    static func parse(_ data: Data) throws -> HTTPRequest? {
        guard let split = data.range(of: Data("\r\n\r\n".utf8)) else {
            if data.count > headerLimit { throw Invalid.request }
            return nil
        }
        guard split.lowerBound <= headerLimit,
              let head = String(data: data[..<split.lowerBound], encoding: .utf8) else { throw Invalid.request }
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ")
        guard parts.count == 3, parts[2] == "HTTP/1.1" || parts[2] == "HTTP/1.0",
              parts[1].hasPrefix("/") else { throw Invalid.request }
        var length: Int?
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { throw Invalid.request }
            let name = pair[0].lowercased()
            if name == "transfer-encoding" { throw Invalid.request }
            if name == "content-length" {
                let raw = pair[1].trimmingCharacters(in: .whitespaces)
                guard length == nil, !raw.isEmpty, raw.allSatisfy({ $0.isASCII && $0.isNumber }),
                      let value = Int(raw), value <= bodyLimit else { throw Invalid.request }
                length = value
            }
        }
        let count = length ?? 0
        guard data.count - split.upperBound >= count else { return nil }
        let bodyData = data[split.upperBound..<(split.upperBound + count)]
        var body: [String: Any] = [:]
        if !bodyData.isEmpty {
            guard let object = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else { throw Invalid.request }
            body = object
        }
        guard let url = URLComponents(string: String(parts[1])) else { throw Invalid.request }
        var query: [String: String] = [:]
        for item in url.queryItems ?? [] { query[item.name] = item.value ?? "" }
        return HTTPRequest(method: String(parts[0]), path: url.path, query: query, body: body)
    }
}
