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
    /// Adds a new element at the end of the JSON array.
    ///
    /// If the JSON object is not already an array, it is replaced
    /// with an array containing only the specified element.
    ///
    /// - Parameter newArrayElement: The element to append to the array.
    mutating public func append(newArrayElement newElement: JSON) {
        if self.arrayObject != nil {
            self = []
        }
        self.arrayObject?.append(newElement.rawValue)
    }

    /// Removes the given key and its associated value from the JSON dictionary.
    ///
    /// If the JSON object is not a dictionary, nothing happens.
    ///
    /// - Parameter key: The key to remove along with its associated value.
    mutating public func removeValue(forKey key: String) {
        let _ = self.dictionaryObject?.removeValue(forKey: key)
    }
}

/// The type of the end of stream key.
public struct EndOfStreamType: JSONSubscriptType {
    fileprivate init() {}
    
    public var jsonKey:JSONKey { return JSONKey.index(Int.max) }
}

/// A key that denotes the end of the stream.
public let EndOfStreamKey = EndOfStreamType()

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
    fileprivate func substring(range: NSRange?) -> String? {
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

/// A CloudLens script.
///
/// A CloudLens script is a pipeline of commands. The pipeline is initially empty.
/// Commands are appended at the end of the pipeline by invoking the methods stream and process.
/// The stream command generates a stream of JSON objects. It supports a variety of sources.
/// The process command processes JSON objects in the stream,
/// possibly transforming, inserting, or removing objects from the stream.
///
/// Commands are not executed immediately but rather when the run method is invoked on the script instance.
/// Objects are streamed through the pipeline of commands one object at a time.
///
/// # Example:
/// ````
/// var sc = Script()
/// sc.stream(messages: "foo", "bar")
/// sc.process { obj in print(1, obj) }
/// sc.process { obj in print(2, obj) }
/// sc.run()
/// ````
/// # Output:
/// ````
/// 1 {"message":"foo"}
/// 2 {"message":"foo"}
/// 1 {"message":"bar"}
/// 2 {"message":"bar"}
/// ````
public class Script {
    fileprivate var stream: () -> JSON? = { nil }
    
    /// Creates a new script instance.
    ///
    /// The script is initially empty.
    public init() {}
    
    /// Streams the array elements.
    ///
    /// - Parameter jsonArray: the JSON objects to stream.
    public func stream(_ jsonArray: [JSON]) {
        var slice: ArraySlice<JSON> = ArraySlice(jsonArray)
        stream = { slice.isEmpty ? nil as JSON? : slice.removeFirst() }
    }

    /// Streams the messages.
    ///
    /// For each message m, a JSON object {"message":m} is inserted into the stream.
    ///
    /// - Parameter messages: the messages to stream.
    public func stream(messages: String...) {
        stream(messages: messages)
    }
    
    /// Streams the messages in the array.
    ///
    /// For each message m, a JSON object {"message":m} is inserted into the stream.
    ///
    /// - Parameter messages: an array of messages to stream.
    public func stream(messages: [String]) {
        var slice = ArraySlice(messages)
        stream = { slice.isEmpty ? nil as JSON? : ["message": slice.removeFirst()] }
    }
    
    /// Streams the content of a text file line by line.
    ///
    /// For each line m, a JSON object {"message":m} is inserted into the stream.
    ///
    /// - Parameter file: the name of the file.
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
    
    fileprivate func processAtEndOfStream(execute action: @escaping (inout JSON) -> ()) {
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

    /// Runs the script.
    ///
    /// By default, the run method accumulates the objects in the output stream into an array and returns the resulting array.
    /// The script is cleared and the stream command is invoked on the resulting array.
    /// If history is set to false, the run method discards the output stream, clears the script, and returns an empty array.
    ///
    /// - Parameter history: whether to accumulate the output stream.
    @discardableResult public func run(withHistory history: Bool = true) -> [JSON] {
        if history {
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

    /// Processes stream elements.
    ///
    /// - Parameter pattern: the regular expression to filter the stream with.
    /// - Parameter key: the path of the field in the JSON object to pattern match against.
    /// - Parameter action: the action to invoke on matched objects.
    public func process(onPattern pattern: String? = nil, onKey key: JSONSubscriptType..., execute action: ((inout JSON) -> ())? = nil) {
        guard key.isEmpty || !(key[0] is EndOfStreamType) else {
            if let action = action {
                processAtEndOfStream(execute: action)
            }
            return
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

    /// Permits replacing the current object in the stream with the given array of objects.
    ///
    /// # Example:
    /// ````
    /// sc.process { obj in
    ///     obj = Script.emit([obj, obj])
    /// }
    /// ````
    ///
    /// - Parameter jsonArray: the JSON objects to stream.
    public static func emit(_ jsonArray: [JSON]) -> JSON {
        return JSON([cloudLensString: JSON(jsonArray)])
    }
}
