// 在调用 C 可变参数格式化之前检查外部 JSON 模板的参数及指针风险。
import Foundation

/// 保守接受 Apple SDK 常用 printf 占位符，不支持写指针、C 字符串及动态宽度。
enum SafeFormatter {
    /// 模板不兼容时返回 nil，让调用方继续使用本地资源。
    static func render(_ template: String, arguments: [CVarArg], locale: Locale) -> String? {
        guard !arguments.isEmpty else { return template }
        let characters = Array(template)
        var cursor = 0
        var next = 0
        var positional: Bool?
        var used = Set<Int>()
        var renderedArguments = arguments
        while cursor < characters.count {
            guard characters[cursor] == "%" else { cursor += 1; continue }
            cursor += 1
            guard cursor < characters.count else { return nil }
            if characters[cursor] == "%" { cursor += 1; continue }
            let start = cursor
            while cursor < characters.count && characters[cursor].isASCII && characters[cursor].isNumber { cursor += 1 }
            let explicit = cursor < characters.count && characters[cursor] == "$"
            let index: Int
            if explicit {
                guard let position = Int(String(characters[start..<cursor])), position > 0 else { return nil }
                index = position - 1
                cursor += 1
            } else {
                cursor = start
                index = next
                next += 1
            }
            if let positional, positional != explicit { return nil }
            positional = explicit
            let flagStart = cursor
            while cursor < characters.count && "-+ #0".contains(characters[cursor]) { cursor += 1 }
            let flags = characters[flagStart..<cursor]
            for part in 0..<2 {
                if part == 1 {
                    guard cursor < characters.count && characters[cursor] == "." else { break }
                    cursor += 1
                }
                let beginning = cursor
                while cursor < characters.count && characters[cursor].isASCII && characters[cursor].isNumber { cursor += 1 }
                if cursor > beginning {
                    guard let size = Int(String(characters[beginning..<cursor])), size <= 10_000 else { return nil }
                }
            }
            var length = ""
            while cursor < characters.count && "hlqzjtL".contains(characters[cursor]) {
                length.append(characters[cursor]); cursor += 1
            }
            guard cursor < characters.count, index < arguments.count else { return nil }
            let conversion = characters[cursor]
            cursor += 1
            // 原生 stringsdict 的 %#@variable@ 只能来自系统资源，不能来自外部 JSON。
            if conversion == "@", flags.contains(where: { $0 != "-" }) { return nil }
            guard accepts(arguments[index], conversion: conversion, length: length) else { return nil }
            // Apple 导出统一使用 lld；显式提升小整数，避免依赖不匹配的 varargs ABI。
            if "di".contains(conversion), ["l", "ll", "q", "z", "j", "t"].contains(length) {
                switch arguments[index] {
                case let value as Int8: renderedArguments[index] = Int64(value)
                case let value as Int16: renderedArguments[index] = Int64(value)
                case let value as Int32: renderedArguments[index] = Int64(value)
                default: break
                }
            }
            used.insert(index)
        }
        // 译文（尤其 plural 的 one）可以不使用全部参数；额外参数不产生读取。
        // 显式位置不能跳号，否则 Foundation 无法可靠推断被跳过参数的 ABI。
        if positional == true, let maximum = used.max(), used != Set(0...maximum) { return nil }
        return String(format: template, locale: locale, arguments: renderedArguments)
    }

    /// 按实际 CVarArg 类型检查 ABI，避免把整数当对象或把对象当指针读取。
    private static func accepts(_ value: CVarArg, conversion: Character, length: String) -> Bool {
        let type = Swift.type(of: value)
        if conversion == "@" {
            return length.isEmpty && (type == String.self || (type is AnyClass && (value is NSString || value is NSNumber)))
        }
        if "fFeEgGaA".contains(conversion) {
            return (length.isEmpty || length == "l") && (type == Double.self || type == Float.self)
        }
        guard "diuoxXc".contains(conversion), ["", "h", "hh", "l", "ll", "q", "z", "j", "t"].contains(length) else { return false }
        if conversion == "c" && !length.isEmpty { return false }
        let wide = ["l", "ll", "q", "z", "j", "t"].contains(length)
        if wide {
            if "di".contains(conversion), [Int8.self, Int16.self, Int32.self].contains(where: { $0 == type }) { return true }
            return type == Int.self || type == UInt.self || type == Int64.self || type == UInt64.self
        }
        if type == Int8.self || type == UInt8.self || type == Int16.self || type == UInt16.self
            || type == Int32.self || type == UInt32.self { return true }
        // Swift 常用 Int 可用于 32 位格式，但拒绝会被截断的值。
        if type == Int.self, let number = value as? Int { return Int32(exactly: number) != nil }
        if type == UInt.self, let number = value as? UInt { return UInt32(exactly: number) != nil }
        return false
    }
}
