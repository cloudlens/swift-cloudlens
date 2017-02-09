# The CloudLens Library for Swift

[![Travis](https://travis-ci.org/cloudlens/swift-cloudlens.svg?branch=master)](https://travis-ci.org/cloudlens/swift-cloudlens)
![Swift](https://img.shields.io/badge/swift-3.0-brightgreen.svg)
![Platform](https://img.shields.io/badge/platforms-macOS%20%7C%20Linux-333333.svg)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

CloudLens is a Swift library for processing machine-generated text streams such as log streams. CloudLens supports plain text as well as JSON-encoded streams.

Thanks to [IBM’s Swift Sandbox](https://developer.ibm.com/swift/2015/12/03/introducing-the-ibm-swift-sandbox/), it is possible to try CloudLens online using this [link](https://swiftlang.ng.bluemix.net/#/repl?gitPackage=https://github.com/cloudlens/swift-cloudlens&swiftVersion=swift-3.0.2-RELEASE-ubuntu15.10). Simply press Play to run the example. The code editor is fully functional but the sandbox cannot access the network, so testing is limited to the supplied [log.txt](https://s3.amazonaws.com/archive.travis-ci.org/jobs/144778470/log.txt) file originally produced by [Travis CI](https://travis-ci.org) for [Apache OpenWhisk](http://openwhisk.org).

CloudLens has been tested on macOS and Linux. CloudLens uses IBM’s fork of [SwiftyJSON](https://github.com/IBM-Swift/SwiftyJSON) for Linux compatibility.

* [Installation](#installation)
* [Tutorial](#tutorial)

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

To build and run the example program in Xcode, make sure to select the “Main” target and activate the console.

# Tutorial

A CloudLens program constructs and processes _streams_.

## Streams

A CloudLens stream is a lazy sequence of JSON objects. A stream can be derived from various sources. The following code constructs a stream with four elements. Each stream element is a JSON object with a single field `message` of type String:

```swift
let stream = CLStream(messages: "error 42", "warning", "info", "error 255”)
```

The next example constructs a stream from an input file.
Each line becomes a JSON object with a single field `message` that contains the line's text.

```swift
let stream = CLStream(textFile: "log.txt")
```

In general, a stream can be constructed from any function of type `() -> JSON?`.

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

Alternatively, the following invocation of `run` eagerly discards the output stream elements.

```swift
stream.run(withHistory: false)
```

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

