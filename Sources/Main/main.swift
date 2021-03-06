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
import CloudLens

// construct a stream with four objects
var stream = CLStream(messages: "error 42", "warning", "info ", "error 255")

print("========== Detect errors ==========")

// print the objects in the stream
stream.process { obj in print(obj) }

// detect errors and add "error" key with error code to object
stream.process(onPattern: "^error (?<error:Number>\\d+)") { obj in print("error", obj["error"], "detected") }

// nothing really happens until run is invoked
stream.run()
// observe that the outputs of the two actions are interleaved

print("\r\n========== Count errors ==========")

// the ouput stream of this run is now the input stream of the next run

var count = 0

// reuse the existing error key that was produced earlier
stream.process(onKey: "error") { _ in count += 1 }.run()

stream.run()

print(count, "error(s)")

print("\r\n========== Report error count using deferred action ==========")

count = 0

stream.process(onKey: "error") { _ in count += 1 }

// the key CLKey.endOfStream defers the action until after the complete stream has been processed
stream.process(onKey: CLKey.endOfStream) { _ in print(count, "error(s)") }

stream.run()

print("\r\n========== Suppress info messages from the stream ==========")

// assigning .null to obj removes the object from the stream
stream.process(onPattern: "^info") { obj in obj = .null }
stream.process { obj in print(obj) }

stream.run()

print("\r\n========== Process example log file ==========")

// stream text file line by line
stream = CLStream(textFile: "log.txt")

// detect and tag failed tests
stream.process(onPattern: "^(?<failure>.*) > .* FAILED") { obj in print("FAILED:", obj["failure"]) }

// compute running time of tests and report long running tests
var start = 0.0

// parse timestamp into a time interval since 1970 (seconds)
stream.process(onPattern: "Starting test (?<description>.*) at (?<start:Date[yyyy-MM-dd' 'HH:mm:ss.SSS]>.{23})") { obj in
    start = obj["start"].doubleValue
}

// report tests that run for more than 12 seconds
stream.process(onPattern: "Finished test (?<description>.*) at (?<end:Date[yyyy-MM-dd' 'HH:mm:ss.SSS]>.{23})") { obj in
    obj["duration"].doubleValue = obj["end"].doubleValue - start
    if obj["duration"].doubleValue > 12 { print(obj["duration"], "\t", obj["description"]) }
}

// count failed tests
var failed = 0
stream.process(onKey: "failure") { _ in failed += 1 }
stream.process(onKey: CLKey.endOfStream) { _ in print(failed, "failed tests") }

// compute cumulated execution time
var totalTime = 0.0
stream.process(onKey: "duration") { obj in totalTime += obj["duration"].doubleValue}
stream.process(onKey: CLKey.endOfStream) { _ in print("Total Time:", totalTime, "seconds") }

stream.run()

// report long running tests relative to total execution time (above 10%)
stream.process(onKey: "duration") { obj in
    obj["percentage"].doubleValue = obj["duration"].doubleValue * 100.0 / totalTime
    if obj["percentage"].doubleValue > 10 { print("\(obj["percentage"])%", obj["description"]) }
}

stream.run()

print("\r\n========== Filter stack traces of failed tests ==========")

// define stream processors
extension CLStream {

    // print messages matching given pattern
    @discardableResult func grep(pattern: String) -> CLStream {
        return process(onPattern: pattern) { obj in print(obj["message"]) }
    }

    // group objects according to pattern
    // objects matching pattern are added to a "group" array in the most recent unmatched object
    @discardableResult func group(pattern: String) -> CLStream {
        var group: JSON? // most recent unmatched object
        process(onPattern: pattern) { obj in // object matches pattern
            group?["group"].append(newArrayElement: obj) // append object to "group" array
            obj = .null // suppress object from stream
        }
        process { obj in // object does not match pattern
            let last = group ?? .null
            group = obj // obj is new most recent unmatched object
            obj = last // emit previous unmatched object
        }
        return process(onKey: CLKey.endOfStream) { obj in obj = group ?? .null }
    }
}

// group indented log lines (stack traces)
stream.group(pattern: "^\\s")

// for each failed test filter corresponding stack trace with pattern of interest
stream.process(onKey: "failure") { obj in
    print("FAILED", obj["failure"])
    CLStream(obj["group"].arrayValue).grep(pattern: "at .*\\(Wsk.*\\)").run()
}

stream.run()
