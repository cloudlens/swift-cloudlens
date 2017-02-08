# The CloudLens Library for Swift

![Platform](https://img.shields.io/badge/platforms-macOS%20%7C%20Linux-333333.svg)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

CloudLens is a Swift library for processing machine-generated text streams such as log streams. CloudLens supports plain text as well as JSON-encoded streams.

Thanks to [IBM’s Swift Sandbox](https://developer.ibm.com/swift/2015/12/03/introducing-the-ibm-swift-sandbox/), it is possible to try CloudLens online using this [link](https://swiftlang.ng.bluemix.net/#/repl?gitPackage=https://github.com/cloudlens/swift-cloudlens&swiftVersion=swift-3.0.2-RELEASE-ubuntu15.10). Simply press Play to run the example. The code editor is fully functional but the sandbox cannot access the network, so testing is limited to the supplied [log.txt](https://s3.amazonaws.com/archive.travis-ci.org/jobs/144778470/log.txt) file originally produced by [Travis CI](https://travis-ci.org) for [Apache OpenWhisk](http://openwhisk.org).

CloudLens has been tested on macOS and Linux. CloudLens uses IBM’s fork of [SwiftyJSON](https://github.com/IBM-Swift/SwiftyJSON) for Linux compatibility.

* [Installation](#installation)
* [Tutorial](#tutorial)

# Installation

Clone the repository:

`git clone https://github.com/cloudlens/swift-cloudlens.git`

CloudLens is built using the Swift Package Manager. To build, execute in the root CloudLens folder:

```swift build --config release```

The build process automatically fetches required dependencies from GitHub. 

## Test program

The build process automatically compiles a simple test program available in [Sources/Main/main.swift](https://github.com/cloudlens/swift-cloudlens/blob/master/Sources/Main/main.swift).
To run the example program, execute:

`.build/release/Main`

## Run-Eval-Print Loop

To load CloudLens in the Swift REPL, execute in the root CloudLens folder:

`swift -I.build/release -L.build/release -lCloudLens`

Then import the CloudLens module with:

`import CloudLens`

To build the necessary library on Linux, please follow instructions at the end of [Package.swift](https://github.com/cloudlens/swift-cloudlens/blob/master/Package.swift).

## Xcode Development and Playground

A workspace is provided to support CloudLens development in Xcode.
It includes a CloudLens playground to make it easy to experiment with CloudLens.

`open CloudLens.xcworkspace`

To build and run the example program in Xcode, make sure to select the “Main” scheme and activate the console.

# Tutorial

