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
var sc = CLStream(messages: "error 42", "warning", "info ", "error 255")

print("========== Detect errors ==========")

// print the objects in the stream
sc.process { obj in print(obj) }

// detect errors and add "error" key with error code to object
sc.process(onPattern: "^error (?<error:Number>\\d+)") { obj in print("error", obj["error"], "detected") }

// nothing really happens until run is invoked
sc.run()
// observe the two output of the two actions are interleaved

print("\n========== Count errors ==========")

// the ouput stream of this run is now the input stream of the next run

var count = 0

// reuse the existing error key that was produced earlier
sc.process(onKey: "error") { _ in count += 1 }

sc.run()

print(count, "error(s)")

print("\n========== Report error count using deferred action ==========")

count = 0

sc.process(onKey: "error") { _ in count += 1 }

// the EndOfStreamKey defers the action until after the complete stream has been processed
sc.process(onKey: EndOfStreamKey) { _ in print(count, "error(s)") }

sc.run()

print("\n========== Suppress info messages from the stream ==========")

// assigning .null to obj removes the object from the stream
sc.process(onPattern: "^info") { obj in obj = .null }
sc.process { obj in print(obj) }

sc.run()

print("\n========== Process example log file ==========")

// stream text file line by line
sc = CLStream(file: "log.txt")

// detect failed test
sc.process(onPattern: "^(?<failure>.*) > .* FAILED") { obj in print("FAILED:", obj["failure"]) }

// compute running time of tests and report long running tests
var start = 0.0
sc.process(onPattern: "Starting test (?<desc>.*) at (?<start:Date[yyyy-MM-dd' 'HH:mm:ss.SSS]>.*)") { obj in
    start = obj["start"].doubleValue
}
sc.process(onPattern: "Finished test (?<desc>.*) at (?<end:Date[yyyy-MM-dd' 'HH:mm:ss.SSS]>.*)") { obj in
    obj["duration"].doubleValue = obj["end"].doubleValue - start
    if obj["duration"].doubleValue > 12 { print(obj["duration"], "\t", obj["desc"]) }
}

// count failed tests
var failed = 0
sc.process(onKey: "failure") { _ in failed += 1 }
sc.process(onKey: EndOfStreamKey) { _ in print(failed, "failed tests") }

// compute cumulated execution time
var totalTime = 0.0
sc.process(onKey: "duration") { obj in totalTime += obj["duration"].doubleValue}
sc.process(onKey: EndOfStreamKey) { _ in print("Total Time:", totalTime, "seconds") }

sc.run()

// report long running tests relative to total execution time
sc.process(onKey: "duration") { obj in
    obj["prop"].doubleValue = obj["duration"].doubleValue * 100.0 / totalTime
    if obj["prop"].doubleValue > 10 { print("\(obj["prop"])%", obj["desc"]) }
}

sc.run()

print("\n========== Filter stack traces of failed tests ==========")

// define stream processors
extension CLStream {
    
    // print messages matching given pattern
    @discardableResult func grep(pattern: String) -> CLStream {
        return process(onPattern: pattern) { obj in print(obj["message"]) }
    }

    // group objects according to pattern
    @discardableResult func group(pattern: String) -> CLStream {
        var group: JSON?
        process(onPattern: pattern) { obj in // entry processes regex
            group?["group"].append(newArrayElement: obj) // append entry to group array
            obj = .null // suppress entry
        }
        process { obj in // remaining entries do not process regex
            let last = group ?? .null
            group = obj
            obj = last
        }
        return process(onKey: EndOfStreamKey) { obj in obj = group ?? .null }
    }
}

// group indented log lines (stack traces)
sc.group(pattern: "^\\s")

// for each failed test filter corresponding stack traces with pattern of interest
sc.process(onKey: "failure") { obj in
    print("FAILED", obj["failure"])
    CLStream(obj["group"].arrayValue).grep(pattern: "at .*\\(Wsk.*\\)").run()
}

sc.run()

