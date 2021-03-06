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
        switch self.type {
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
        if self.arrayObject == nil {
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

/// The type of special keys.
public enum CLKey: JSONSubscriptType {
    /// A key that denotes the end of the stream.
    case endOfStream

    public var jsonKey: JSONKey {
        switch self {
        case .endOfStream:
            return JSONKey.index(-1)
        }
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
        return regex.matches(in: string, options: [], range: NSRange(location: 0, length: string.characters.count))
    }

    func firstMatch(in string: String) -> NSTextCheckingResult? {
        return regex.firstMatch(in: string, options: [], range: NSRange(location: 0, length: string.characters.count))
    }

    func numberOfCaptureGroups() -> Int {
        return regex.numberOfCaptureGroups
    }

    func stringByReplacingMatches(in string: String, withTemplate templ: String) -> String {
        return regex.stringByReplacingMatches(in: string, options: [], range: NSRange(location: 0, length: string.characters.count), withTemplate: templ)
    }
}

fileprivate let groupPattern = Regex(pattern: "\\(\\?<([a-zA-Z][a-zA-Z0-9]*)(?::([a-zA-Z][a-zA-Z0-9]*)(?:\\[([^\\]]+)\\])?)?>([^\\(]*)\\)")

fileprivate let complexCharacters = CharacterSet(charactersIn: "*?+[(){}^$|\\./")

fileprivate let cloudLensString = "\u{2601}\u{1f50d}"

fileprivate typealias Group = (name: String, type: String?, format: String?)

/// A CloudLens stream is a lazy sequence of JSON objects.
///
/// The _process_ method adds a processing stage to the stream, possibly transforming,
/// adding, or removing objects from the stream.
/// Processing is delayed until the _run_ method is invoked on the Stream instance.
/// Each object in the stream goes through every processing stage before processing begins for the next object.
///
/// # Example:
/// ````
/// let stream = CLStream(messages: "foo", "bar")
/// stream.process { obj in print(1, obj) }
/// stream.process { obj in print(2, obj) }
/// stream.run()
/// ````
/// # Output:
/// ````
/// 1 {"message":"foo"}
/// 2 {"message":"foo"}
/// 1 {"message":"bar"}
/// 2 {"message":"bar"}
/// ````
public class CLStream {
    fileprivate var stream: () -> JSON? = { nil }

    /// Creates a new CLStream instance from a lazy sequence of JSON objects.
    ///
    /// The _generator_ should return nil to indicate the end of the stream.
    ///
    /// - Parameter generator: the sequence generator.
    public init(_ generator: @escaping () -> JSON?) {
        stream = generator
    }

    /// Creates a new CLStream instance from the content of the array.
    ///
    /// - Parameter jsonArray: the array of JSON objects to stream.
    public convenience init(_ jsonArray: [JSON]) {
        var slice = ArraySlice(jsonArray)
        self.init { slice.isEmpty ? nil as JSON? : slice.removeFirst() }
    }

    /// Creates a new CLStream instance from an array of messages.
    ///
    /// For each message m, a JSON object {"message":m} is added to the stream.
    ///
    /// - Parameter messages: the array of messages to stream.
    public convenience init(messages: [String]) {
        var slice = ArraySlice(messages)
        self.init { slice.isEmpty ? nil as JSON? : ["message": slice.removeFirst()] }
    }

    /// Creates a new CLStream instance from a list of messages.
    ///
    /// For each message m, a JSON object {"message":m} is added to the stream.
    ///
    /// - Parameter messages: the messages to stream.
    public convenience init(messages: String...) {
        self.init(messages: messages)
    }

    /// Creates a new CLStream instance by streaming the content of a text file line by line.
    ///
    /// For each line m, a JSON object {"message":m} is added to the stream.
    ///
    /// - Parameter file: the name of the file.
    public convenience init(textFile file: String) {
        guard let fd = fopen(file, "r") else {
            abort("Error opening file \"\(file)\"")
        }
        self.init {
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

    /// Creates a new CLStream instance by reading a JSON object from a file.
    ///
    /// If the file contains a JSON array, then the array elements are streamed one at a time.
    /// Otherwise the stream has a single element.
    ///
    /// - Parameter file: the name of the file.
    public convenience init(jsonFile file: String) {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: file))
            let json = JSON(data: data)
            if json.error != nil {
                abort("Error parsing file \"\(file)\"")
            }
            if json.type == .array {
                self.init(json.arrayValue)
            } else {
                self.init([json])
            }
        } catch {
            abort("Error opening file \"\(file)\"")
        }
    }

    fileprivate func executeOnStream(onKey key: [JSONSubscriptType], _ action: @escaping (inout JSON) -> Void) {
        let last = stream
        var slice = ArraySlice([JSON]())
        stream = {
            while true {
                if !slice.isEmpty { return slice.removeFirst() }
                if var json = last() {
                    if json[key].exists() {
                        action(&json)
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

    fileprivate func executeAtEndOfStream(_ action: @escaping (inout JSON) -> Void) {
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

    /// Iterates over the stream applying all processing stages to every object in the stream.
    ///
    /// By default, the output stream is preserved enabling further processing.
    /// But if _history_ is set to false, the output stream is not preserved.
    ///
    /// - Parameter history: whether to preserve the output stream.
    /// - Returns: _self_ to permit chaining processing stages.
    /// - Complexity: The output stream is preserved by accumulating the stream elements into an array.
    @discardableResult public func run(withHistory history: Bool = true) -> CLStream {
        if history {
            var jsonArray = [JSON]()
            while let json = stream() {
                jsonArray.append(json)
            }
            var slice = ArraySlice(jsonArray)
            stream = { slice.isEmpty ? nil as JSON? : slice.removeFirst() }
        } else {
            while stream() != nil {}
            stream = { nil }
        }
        return self
    }

    /// Adds a processing stage to the stream.
    ///
    /// The _process_ method invokes an action on each object in the stream that satisfies the given predicate.
    /// Objects that do not satisfy the predicate are unaffected.
    ///
    /// The predicate is optional and assumed to be true if absent. The predicate is composed of a _pattern_ and a _key_.
    /// If only a _pattern_ is specified the _key_ defaults to "message".
    /// If only a _key_ is specified the _pattern_ defaults to the empty string.
    /// The predicates tests whether the _key_ is a valid path in the JSON object and
    /// that the associated String value matches the regular expression _pattern_.
    ///
    /// The _pattern_ may define named groups.
    /// Upon a successful match, the JSON objects is augmented with new fields that bind each group name
    /// to the corresponding substring in the match.
    ///
    /// # Example:
    /// ````
    /// let stream = CLStream(messages: "warning", "error 42")
    /// stream.process(onPattern: "error (?<error>\\d+)") { obj in print(obj) }
    /// stream.run()
    /// ````
    /// # Output:
    /// ````
    /// {"error":"42","message":"error 42"}
    /// ````
    ///
    /// The _pattern_ cannot contain anonymous groups.
    /// A group type may be associated with the group name, for example: `"(?<error:Number>\\d+)"`.
    /// Supported types are Number, String, and Date.
    /// String is the default type.
    /// A date format can be specified, for example: `"(?<date:Date[yyyy-MM-dd' 'HH:mm:ss.SSS]>^.{23})"`.
    ///
    /// The _action_ can remove the current object in the stream by assigning JSON.null to it, for example:
    /// "`process { obj in obj = .null }`". It can replace the object with mutiple objects using the _emit_ method.
    ///
    /// The key _CLKey.endofStream_ may be used to defer an action until after the complete stream has been processed,
    /// for example: "`process(onKey: CLKey.endOfStream) { _ print(count) }`".
    ///
    /// - Parameter pattern: the regular expression.
    /// - Parameter key: the path in the JSON object.
    /// - Parameter action: the action to invoke on matched objects.
    /// - Returns: _self_ to permit chaining processing stages.
    @discardableResult public func process(onPattern pattern: String = "", onKey key: JSONSubscriptType..., execute action: ((inout JSON) -> Void)? = nil) -> CLStream {
        if key.first as? CLKey == .endOfStream {
            if let action = action {
                executeAtEndOfStream(action)
            }
        } else {
            var key = key
            var action = action
            if pattern != "" { // empty pattern always matches
                key = key.isEmpty ? ["message"] : key
                if pattern.rangeOfCharacter(from: complexCharacters) == nil {
                    action = match(substring: pattern, onKey: key, execute: action)
                } else {
                    action = match(regex: pattern, onKey: key, execute: action)
                }
            }
            if let action = action {
                executeOnStream(onKey: key, action)
            }
        }
        return self
    }

    fileprivate func match(substring pattern: String, onKey key: [JSONSubscriptType], execute action: ((inout JSON) -> Void)? = nil) -> ((inout JSON) -> Void)? {
        if let action = action {
            return { json in
                if let message = json[key].string, message.contains(pattern) {
                    action(&json)
                }
            }
        } else {
            return nil
        }
    }

    fileprivate func match(regex pattern: String, onKey key: [JSONSubscriptType], execute action: ((inout JSON) -> Void)? = nil) -> ((inout JSON) -> Void)? {
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
        return { json in
            if let message = json[key].string, let match = regex.firstMatch(in: message) {
                for n in 1..<match.numberOfRanges {
                    let string = message.substring(range: match.rangeAt(n))
                    let (name, type, format) = groups[n-1]
                    if let string = string {
                        switch type {
                        case .some("Date"):
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = format
                            json[name].double = dateFormatter.date(from: string)?.timeIntervalSince1970
                        case .some("Number"):
                            json[name].number = NumberFormatter().number(from: string)
                        default:
                            json[name].string = string
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

    /// Permits replacing the current object in the stream with the given array of objects.
    ///
    /// # Example:
    /// Use _emit_ to repeat every object in the stream.
    /// ````
    /// stream.process { obj in
    ///     obj = Stream.emit([obj, obj])
    /// }
    /// ````
    ///
    /// - Parameter jsonArray: the array of JSON objects to stream.
    public static func emit(_ jsonArray: [JSON]) -> JSON {
        return JSON([cloudLensString: JSON(jsonArray)])
    }
}
