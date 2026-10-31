import Foundation

/// Body token grammar: `[[mg:name]]` with `name` matching `[a-z][a-z0-9_]*`.
public enum SecretConstantPlaceholders {
    public static let tokenPrefix = "[[mg:"
    public static let tokenSuffix = "]]"

    public static func isValidName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let first = name.first!
        guard first.isLowercase && first.isLetter else { return false }
        return name.dropFirst().allSatisfy { ch in
            ch.isLowercase && ch.isLetter || ch.isNumber || ch == "_"
        }
    }

    public static func token(for name: String) -> String {
        "\(tokenPrefix)\(name)\(tokenSuffix)"
    }

    public static func find(in body: String) -> [SecretConstantPlaceholderMatch] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\[\[mg:([a-z][a-z0-9_]*)\]\]"#,
            options: []
        ) else {
            return []
        }
        let nsBody = body as NSString
        let fullRange = NSRange(location: 0, length: nsBody.length)
        return regex.matches(in: body, options: [], range: fullRange).compactMap { match in
            guard match.numberOfRanges >= 2,
                  let full = Range(match.range, in: body),
                  let nameRange = Range(match.range(at: 1), in: body)
            else {
                return nil
            }
            let name = String(body[nameRange])
            let start = body.distance(from: body.startIndex, to: full.lowerBound)
            let end = body.distance(from: body.startIndex, to: full.upperBound)
            return SecretConstantPlaceholderMatch(name: name, start: start, end: end)
        }
    }

    public static func uniqueNames(in body: String) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for match in find(in: body) where seen.insert(match.name).inserted {
            ordered.append(match.name)
        }
        return ordered
    }
}

public struct SecretConstantPlaceholderMatch: Equatable, Sendable {
    public let name: String
    public let start: Int
    public let end: Int

    public init(name: String, start: Int, end: Int) {
        self.name = name
        self.start = start
        self.end = end
    }
}
