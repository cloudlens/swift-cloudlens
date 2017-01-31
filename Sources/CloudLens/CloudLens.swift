/*
 *  This file is part of the CloudLens project.
 *
 * Copyright 2015-2017 IBM Corporation
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import Foundation
import SwiftyJSON

extension JSON: CustomStringConvertible {
    public var description: String {
        return self.rawString(options: []) ?? "JSON is invalid"
    }
}

extension JSON: CustomReflectable {
    public var customMirror: Mirror {
        switch(self.type) {
        case .number:
            return Mirror(reflecting: self.stringValue)
        default:
            return Mirror(reflecting: self.object)
        }
    }
}

extension JSON {
    mutating public func append(newArrayElement newElement: JSON) {
        if self.arrayObject == nil {
            self = []
        }
        self.arrayObject?.append(newElement.rawValue)
    }

    mutating public func removeValue(forKey key: String) {
        let _ = self.dictionaryObject?.removeValue(forKey: key)
    }
}

#if os(Linux)
    fileprivate typealias NSRegularExpression = RegularExpression
    fileprivate typealias NSTextCheckingResult = TextCheckingResult

    fileprivate extension TextCheckingResult {
        func rangeAt(_ idx: Int) -> NSRange {
            return self.range(at: idx)
        }
    }
#endif

extension String {
    func substring(range: NSRange?) -> String? {
        guard let range = range, range.location != NSNotFound else { return nil }
        return self.substring(with: self.index(self.startIndex, offsetBy: range.location)
            ..< self.index(self.startIndex, offsetBy: range.location + range.length))
    }
}

fileprivate func abort(_ errorMessage: String) -> Never {
    print(errorMessage)
    exit(1)
}

fileprivate struct Regex {
    let regex: NSRegularExpression
    
    init(pattern: String) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            abort("Error in regular expression \"\(pattern)\"")
        }
        self.regex = regex
    }
    
    func matches(in string: String) -> [NSTextCheckingResult] {
        return regex.matches(in: string, options: [], range: NSMakeRange(0, string.characters.count))
    }
    
    func firstMatch(in string: String) -> NSTextCheckingResult? {
        return regex.firstMatch(in: string, options: [], range: NSMakeRange(0, string.characters.count))
    }

    func numberOfCaptureGroups() -> Int {
        return regex.numberOfCaptureGroups
    }

    func stringByReplacingMatches(in string: String, withTemplate templ: String) -> String {
        return regex.stringByReplacingMatches(in: string, options: [], range: NSMakeRange(0, string.characters.count), withTemplate: templ)
    }
}

fileprivate let groupPattern = Regex(pattern: "\\(\\?<([a-zA-Z][a-zA-Z0-9]*)(?::([a-zA-Z][a-zA-Z0-9]*)(?:\\[([^\\]]+)\\])?)?>([^\\(]*)\\)")

fileprivate let complexCharacters = CharacterSet(charactersIn: "*?+[(){}^$|\\./")

fileprivate let cloudLensString = "\u{2601}\u{1f50d}"

fileprivate typealias Group = (name: String, type: String?, format: String?)

public class Script {
    fileprivate var stream: () -> JSON? = { nil }
    
    public init() {}
    
    public func stream(_ jsonArray: [JSON]) {
        var slice: ArraySlice<JSON> = ArraySlice(jsonArray)
        stream = { slice.isEmpty ? nil as JSON? : slice.removeFirst() }
    }

    public func stream(messages: String...) {
        stream(messages: messages)
    }
    
    public func stream(messages: [String]) {
        var slice = ArraySlice(messages)
        stream = { slice.isEmpty ? nil as JSON? : ["message": slice.removeFirst()] }
    }
    
    public func stream(file: String) {
        guard let fd = fopen(file, "r") else {
            abort("Error opening file \"\(file)\"")
        }
        stream = {
            var line: UnsafeMutablePointer<Int8>?
            var linecap = 0
            defer { free(line) }
            if getline(&line, &linecap, fd) > 0, let line = line {
                line.advanced(by: Int(strcspn(line, "\r\n"))).pointee = 0
                return ["message": String(cString: line)]
            }
            fclose(fd)
            return nil
        }
    }
    
    fileprivate func processAtEnd(execute action: @escaping (inout JSON) -> ()) {
        let last = stream
        var slice = ArraySlice([JSON]())
        var endOfStream = false
        stream = {
            while true {
                if endOfStream { return slice.isEmpty ? nil as JSON? : slice.removeFirst() }
                if let json = last() { return json }
                endOfStream = true
                var json = JSON.null
                action(&json)
                if json == .null { return nil }
                if let jsonArray = json[cloudLensString].array {
                    slice = ArraySlice(jsonArray)
                    continue
                }
                return json
            }
        }
    }

    @discardableResult public func run(withHistory: Bool = true) -> [JSON] {
        if withHistory {
            var jsonArray = [JSON]()
            while let json = stream() {
                jsonArray.append(json)
            }
            stream(jsonArray)
            return jsonArray
        } else {
            while stream() != nil {}
            stream = { nil }
            return []
        }
    }

    public func process(onPattern pattern: String? = nil, onKey key: JSONSubscriptType..., atEnd: Bool = false, execute action: ((inout JSON) -> ())? = nil) {
        guard !atEnd else {
            if let action = action {
                processAtEnd(execute: action)
            }
            return;
        }
        var body = action
        if let pattern = pattern, pattern != "" { // nil or empty patterns are no op
            let key = key.isEmpty ? ["message"] : key
            if pattern.rangeOfCharacter(from: complexCharacters) == nil { // simple pattern
                if let action = action {
                    body = { json in
                        if let message = json[key].string, message.contains(pattern) {
                            action(&json)
                        }
                    }
                }
            } else { // regex
                var groups = [Group]()
                for match in groupPattern.matches(in: pattern) {
                    guard let name = pattern.substring(range: match.rangeAt(1)) else {
                        abort("Error in regular expression \"\(pattern)\"")
                    }
                    groups.append((name: name, type: pattern.substring(range: match.rangeAt(2)), format: pattern.substring(range: match.rangeAt(3))))
                }
                let regex = Regex(pattern: groupPattern.stringByReplacingMatches(in: pattern, withTemplate: "\\($4\\)"))
                guard groups.count == regex.numberOfCaptureGroups() else {
                    abort("Unnamed groups in regular expression \"\(pattern)\"")
                }
                body = { json in
                    if let message = json[key].string, let match = regex.firstMatch(in: message) {
                        for n in 1..<match.numberOfRanges {
                            let string = message.substring(range: match.rangeAt(n))
                            let (name, type, format) = groups[n-1]
                            if let string = string {
                                json[name].string = string
                                if let type = type {
                                    switch type {
                                    case "Date":
                                        let dateFormatter = DateFormatter()
                                        if let format = format {
                                            dateFormatter.dateFormat = format
                                        }
                                        json[name].double = dateFormatter.date(from: string)?.timeIntervalSince1970
                                    case "Number":
                                        json[name].number = NumberFormatter().number(from: string)
                                    default:
                                        ()
                                    }
                                }
                            } else {
                                json.removeValue(forKey: name)
                            }
                        }
                        if let action = action {
                            action(&json)
                        }
                    }
                }
            }
        }
        if let body = body {
            let last = stream
            var slice = ArraySlice([JSON]())
            stream = {
                while true {
                    if !slice.isEmpty { return slice.removeFirst() }
                    if var json = last() {
                        if json[key].exists() {
                            body(&json)
                            if json == .null {
                                slice = ArraySlice([])
                                continue
                            }
                            if let jsonArray = json[cloudLensString].array {
                                slice = ArraySlice(jsonArray)
                                continue
                            }
                        }
                        return json
                    }
                    return nil
                }
            }
        }
    }

    public static func invoke(_ lens: (Script) -> () -> (), _ jsonArray: [JSON]) {
        let sc = Script()
        sc.stream(jsonArray)
        lens(sc)()
        sc.run()
    }

    public static func invoke(_ lens: (Script) -> () -> (), _ jsonArray: inout [JSON]) {
        let sc = Script()
        sc.stream(jsonArray)
        lens(sc)()
        jsonArray = sc.run()
    }

    public static func invoke<T>(_ lens: (Script) -> (T) -> (), _ jsonArray: [JSON], _ t: T) {
        let sc = Script()
        sc.stream(jsonArray)
        lens(sc)(t)
        sc.run()
    }

    public static func invoke<T>(_ lens: (Script) -> (T) -> (), _ jsonArray: inout [JSON], _ t: T) {
        let sc = Script()
        sc.stream(jsonArray)
        lens(sc)(t)
        jsonArray = sc.run()
    }

    public static func invoke<T, U>(_ lens: (Script) -> (T, U) -> (), _ jsonArray: [JSON], _ t: T, _ u: U) {
        let sc = Script()
        sc.stream(jsonArray)
        lens(sc)(t, u)
        sc.run()
    }

    public static func invoke<T, U>(_ lens: (Script) -> (T, U) -> (), _ jsonArray: inout [JSON], _ t: T, _ u: U) {
        let sc = Script()
        sc.stream(jsonArray)
        lens(sc)(t, u)
        jsonArray = sc.run()
    }

    public static func emit(_ jsonArray: [JSON]) -> JSON {
        return JSON([cloudLensString: JSON(jsonArray)])
    }
}
