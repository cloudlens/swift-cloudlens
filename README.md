# The CloudLens Library for Swift

[![Travis](https://travis-ci.org/cloudlens/swift-cloudlens.svg?branch=master)](https://travis-ci.org/cloudlens/swift-cloudlens)
![Swift](https://img.shields.io/badge/swift-v3.0.x-blue.svg)
![OS](https://img.shields.io/badge/os-macOS%20%7C%20Linux-lightgray.svg)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

CloudLens is a Swift library for processing machine-generated text streams such as log streams. CloudLens supports plain text as well as JSON-encoded streams.

Analyzing logs is challenging. Logs contain a mix of text and semi-structured meta-data such as timestamps. Logs are often aggregated from multiple sources with under-specified, heterogeneous formats. Parsing techniques based on schemas or grammars are not practical. In contrast, CloudLens is built on the premise that parsing need not be exhaustive and relies on pattern matching for data extraction. Matches can augment the raw text with structured attributes and trigger actions. For instance, a single line of CloudLens code can detect error messages in a log stream, extract the error code for future analyzis, and count errors.

```swift
stream.process(onPattern: "error (?<error:Number>\\d+)") { _ in errorCount += 1 }
```

Thanks to [IBM’s Swift Sandbox](https://developer.ibm.com/swift/2015/12/03/introducing-the-ibm-swift-sandbox/), it is possible to try CloudLens online using this [link](https://swiftlang.ng.bluemix.net/#/repl?gitPackage=https://github.com/cloudlens/swift-cloudlens&swiftVersion=swift-3.0.2-RELEASE-ubuntu15.10). Simply press Play to run the example. The code editor is fully functional but the sandbox cannot access the network, so testing is limited to the supplied [log.txt](https://s3.amazonaws.com/archive.travis-ci.org/jobs/144778470/log.txt) file originally produced by [Travis CI](https://travis-ci.org) for [Apache OpenWhisk](http://openwhisk.org).

CloudLens has been tested on macOS and Linux. CloudLens uses IBM’s fork of [SwiftyJSON](https://github.com/IBM-Swift/SwiftyJSON) for Linux compatibility.

* [Installation](#installation)
* [Tutorial](#tutorial)
* [License](#license)

# Installation

Clone the repository:

```bash
git clone https://github.com/cloudlens/swift-cloudlens.git
```

CloudLens is built using the Swift Package Manager. To build, execute in the root CloudLens folder:

```bash
swift build --config release
```

The build process automatically fetches required dependencies from GitHub. 

## Test program

The build process automatically compiles a simple test program available in [Sources/Main/main.swift](https://github.com/cloudlens/swift-cloudlens/blob/master/Sources/Main/main.swift).
To run the example program, execute:

```bash
.build/release/Main
```

## Run-Eval-Print Loop

To load CloudLens in the Swift REPL, execute in the root CloudLens folder:

```bash
swift -I.build/release -L.build/release -lCloudLens
```

Then import the CloudLens module with:

```swift
import CloudLens
```

To build the necessary library on Linux, please follow instructions at the end of [Package.swift](https://github.com/cloudlens/swift-cloudlens/blob/master/Package.swift).

## Xcode Development and Playground

A workspace is provided to support CloudLens development in Xcode.
It includes a CloudLens playground to make it easy to experiment with CloudLens.

```bash
open CloudLens.xcworkspace
```

To build and run the example program in Xcode, make sure to select the “Main" target and activate the console.

# Tutorial

A CloudLens program constructs and processes _streams_ of JSON objects. JSON support is provided by the [SwiftyJSON](https://github.com/IBM-Swift/SwiftyJSON) library.

## Streams

A CloudLens stream (an instance of the `CLStream` class) is a lazy sequence of JSON objects. A stream can be derived from various sources. The following code constructs a stream with four elements. Each stream element is a JSON object with a single field `"message"` of type String:

```swift
let stream = CLStream(messages: "error 42", "warning", "info", "error 255")
```

The next example constructs a stream from a text file.
Each line becomes a JSON object with a single field `"message"` that contains the line's text.

```swift
let stream = CLStream(textFile: "log.txt")
```

The next example constructs a stream from a file containing an array of JSON objects.

```swift
let stream = CLStream(jsonFile: "array.json")
```

In general, a stream can be constructed from any function of type `() -> JSON?`.

Streams are constructed lazily when possible. For example, for stream constructed from a text file, the file is read line by line, as needed.

## Actions

The `process` method of the `CLStream` class registers actions to be executed on the stream elements. The `run` method triggers the execution of these actions.

For instance, this code specifies an action to be executed on all stream elements:

```swift
stream.process { obj in print(obj) }
```

But nothing happens until `run` is invoked:

```swift
stream.run()
```

The two methods return `self` so the following syntax is also possible:

```swift
CLStream(messages: "error 42", "warning", "info", "error 255")
	.process { obj in print(obj) }
	.run()
```

This example outputs:

```json
{"message":"error 42"}
{"message":"warning"}
{"message":"info"}
{"message":"error 255"}
```

## Execution Order

Stream elements are processed in order.
When multiple actions are specified, actions are executed in order for each stream element. Moreover, all actions for a given stream element are executed before the next stream element is considered. For instance this code

```swift
let stream = CLStream(messages: "foo", "bar")
stream.process { obj in print(1, obj) }
stream.process { obj in print(2, obj) }
stream.run()
```

outputs:

```json
1 {"message":"foo"}
2 {"message":"foo"}
1 {"message":"bar"}
2 {"message":"bar"}
```

## Chaining

By default, `run` preserves the output stream, which becomes the input stream for subsequent actions. For instance this code

```swift
let stream = CLStream(messages: "foo", "bar")
stream.process { obj in print(1, obj) }
stream.run()
stream.process { obj in print(2, obj) }
stream.run()
```

outputs:

```json
1 {"message":"foo"}
1 {"message":"bar"}
2 {"message":"foo"}
2 {"message":"bar"}
```

Alternatively, the following invocation of `run` discards the output stream elements as they are produced:

```swift
stream.run(withHistory: false)
```

The later is recommended to avoid buffering the entire stream.

## Mutations

It is possible to mutate, replace, or remove the stream element being processed. 

```swift
// to mutate the stream element
stream.process { obj in obj["timestamp"] = String(describing: Date()) }

// to remove the element from the stream
stream.process { obj in obj = .null }

// to replace the element in the stream
stream.process { obj in obj = otherObject }

// to replace one stream element with multiple objects
stream.process { obj in obj = CLStream.emit([thisObject, thatObject]) }
```

## Patterns and Keys

Actions can be guarded by activation conditions.

```swift
stream.process(onPattern: "error", onKey: "message") { obj in print(obj) }
```

If a _key_ is specified, the action only executes for JSON objects that have a value for the given key. In addition, if a _pattern_ is specified, the field value must match the pattern. If a pattern is specified but no key, the key defaults to `"message"`. Objects that do not satisfy the activation condition are unaffected by the action.

Keys can be [paths](https://github.com/IBM-Swift/SwiftyJSON#subscript) in JSON objects. Patterns can be simple strings or [regular expressions](https://developer.apple.com/reference/foundation/nsregularexpression).

## Named Capture Groups

A regular expression pattern cannot include numbered capture groups but it may include named capture groups. Upon a successful match, the JSON object is augmented with new fields that bind each group name to the corresponding substring in the match. For instance,

```swift
let stream = CLStream(messages: "error 42", "warning", "info", "error 255")
stream.process(onPattern: "error (?<error>\\d+)") { obj in print(obj) }
stream.run()
```

outputs:

```json
{"error":"42","message":"error 42"}
{"error":"255","message":"error 255"}
```

Named captured groups can be given an explicit type using the :_type_ syntax, for example  `"(?<error:Number>\\d+)"`. The supported types are `Number`, `String`, and `Date`, with `String` the implicit default. A `Date` type should include a Date format specification as in `"(?<date:Date[yyyy-MM-dd' 'HH:mm:ss.SSS]>^.{23})"`.

## Deferred Actions

The special key `CLKey.endOfStream` may be used to defer an action until after the complete stream has been processed:

```swift
let stream = CLStream(messages: "error 42", "warning", "info", "error 255")
var count = 0;
stream.process(onKey: "error") { _ in count += 1 }
stream.process(onKey: CLKey.endOfStream) { _ in print(count, "error(s)") }
stream.run()
```

outputs:

```
2 error(s)
```

A deferred action, may append new elements at the end of the stream:

```swift
stream.process(onKey: CLKey.endOfStream) { obj in obj = ["message": "\(count) error(s)"] }
```

## Lenses

CloudLens can be extented with new processing _lenses_ easily, for example:

```swift
extension CLStream {
    @discardableResult func grep(_ pattern: String) -> CLStream {
        return process(onPattern: pattern) { obj in print(obj["message"]) }
    }
}

CLStream(messages: "error 42", "warning", "info", "error 255")
	.grep("error")
	.run()
```

# License

Copyright 2015-2017 IBM Corporation

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
