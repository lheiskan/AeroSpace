import Common
import CoreGraphics
import TOMLKit

private let keyMappingParser: [String: any ParserProtocol<KeyMapping>] = [
    "preset": Parser(\.preset, parsePreset),
    "key-notation-to-key-code": Parser(\.rawKeyNotationToKeyCode, parseKeyNotationToKeyCode),
    "match-key-event-by": Parser(\.matchKeyEventBy, parseMatchKeyEventBy),
]

enum KeyOrModifiers: Equatable, Sendable {
    case keyCode(UInt32)
    case modifiers(CGEventFlags)
}

struct KeyMapping: ConvenienceCopyable, Equatable, Sendable {
    enum Preset: String, CaseIterable, Sendable {
        case qwerty, dvorak, colemak
    }

    enum MatchKeyEventBy: String, CaseIterable, Sendable {
        case keyCode = "key-code"
        case keySymbol = "key-symbol"
    }

    init(
        preset: Preset = .qwerty,
        rawKeyNotationToKeyCode: [String: KeyOrModifiers] = [:],
        matchKeyEventBy: MatchKeyEventBy = .keyCode
    ) {
        self.preset = preset
        self.rawKeyNotationToKeyCode = rawKeyNotationToKeyCode
        self.matchKeyEventBy = matchKeyEventBy
    }

    fileprivate var preset: Preset = .qwerty
    fileprivate var rawKeyNotationToKeyCode: [String: KeyOrModifiers] = [:]
    fileprivate(set) var matchKeyEventBy: MatchKeyEventBy = .keyCode

    func resolve(_ symbol: String) -> UInt32? {
        if let keyOrModifiers = rawKeyNotationToKeyCode[symbol],
           case .keyCode(let keyCode) = keyOrModifiers {
            return keyCode
        }
        return getKeyMapPreset(preset)[symbol]
    }

    func resolveModifiers(_ alias: String) -> CGEventFlags? {
        if let keyOrModifiers = rawKeyNotationToKeyCode[alias],
           case .modifiers(let flags) = keyOrModifiers {
            return flags
        }
        return nil
    }
}

func parseKeyMapping(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace, _ errors: inout [TomlParseError]) -> KeyMapping {
    parseTable(raw, KeyMapping(), keyMappingParser, backtrace, &errors)
}

private func parsePreset(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<KeyMapping.Preset> {
    parseString(raw, backtrace).flatMap { parseEnum($0, KeyMapping.Preset.self).toParsedToml(backtrace) }
}

private func parseKeyNotationToKeyCode(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace, _ errors: inout [TomlParseError]) -> [String: KeyOrModifiers] {
    var result: [String: KeyOrModifiers] = [:]
    guard let table = raw.table else {
        errors.append(expectedActualTypeError(expected: .table, actual: raw.type, backtrace))
        return result
    }

    let modifiersMap: [String: CGEventFlags] = [
        "shift": .maskShift,
        "lshift": .maskShiftL,
        "rshift": .maskShiftR,
        "alt": .maskAlternate,
        "lalt": .maskAlternateL,
        "ralt": .maskAlternateR,
        "ctrl": .maskControl,
        "lctrl": .maskControlL,
        "rctrl": .maskControlR,
        "cmd": .maskCommand,
        "lcmd": .maskCommandL,
        "rcmd": .maskCommandR,
        "fn": .maskSecondaryFn,
    ]

    for (key, value): (String, TOMLValueConvertible) in table {
        if isValidKeyNotation(key) {
            let backtrace = backtrace + .key(key)
            if let valueString = parseString(value, backtrace).getOrNil(appendErrorTo: &errors) {
                // Check if it's a modifier combination (contains dashes)
                if valueString.contains("-") {
                    // Parse as modifier combination
                    let parts = valueString.split(separator: "-")
                    var combinedFlags = CGEventFlags()
                    var hasError = false

                    for part in parts {
                        let modifierName = String(part)
                        if let flag = modifiersMap[modifierName] {
                            combinedFlags.insert(flag)
                        } else {
                            errors.append(.semantic(backtrace, "'\(modifierName)' is not a valid modifier in '\(valueString)'"))
                            hasError = true
                            break
                        }
                    }

                    if !hasError && !combinedFlags.isEmpty {
                        result[key] = .modifiers(combinedFlags)
                    } else if !hasError {
                        errors.append(.semantic(backtrace, "Modifier alias '\(key)' must contain at least one modifier"))
                    }
                } else {
                    // Parse as key code
                    if let keyCode = keyNotationToKeyCode[valueString] {
                        result[key] = .keyCode(keyCode)
                    } else {
                        errors.append(.semantic(backtrace, "'\(valueString)' is invalid key code"))
                    }
                }
            }
        } else {
            errors.append(.semantic(backtrace, "'\(key)' is invalid key notation"))
        }
    }
    return result
}

private func isValidKeyNotation(_ str: String) -> Bool {
    str.rangeOfCharacter(from: .whitespacesAndNewlines) == nil && !str.contains("-")
}

private func parseMatchKeyEventBy(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<KeyMapping.MatchKeyEventBy> {
    parseString(raw, backtrace).flatMap { parseEnum($0, KeyMapping.MatchKeyEventBy.self).toParsedToml(backtrace) }
}
