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
// observe that the outputs of the two actions are interleaved

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
