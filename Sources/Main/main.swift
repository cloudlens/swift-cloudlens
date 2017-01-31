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

var sc = Script()

sc.stream(messages: "error 42", "warning", "info", "error 255")

sc.process { obj in print(obj) }
sc.process(onPattern: "error (?<error:Number>\\d+)") { obj in print("error", obj["error"], "detected") }

sc.run()

var count = 0
sc.process(onKey: "error") { _ in count += 1 }

sc.run()

print(count, "error(s)")

sc.process(onPattern: "info") { obj in obj = .null }
sc.process { obj in print(obj) }

sc.run()

sc.stream(file: "log.txt")

sc.process(onPattern: "^(?<failure>.*) > .* FAILED") { obj in print("FAILED:", obj["failure"]) }

var start = 0.0
sc.process(onPattern: "Starting test (?<desc>.*) at (?<start:Date[yyyy-MM-dd' 'HH:mm:ss.SSS]>.*)") { obj in
    start = obj["start"].doubleValue
}
sc.process(onPattern: "Finished test (?<desc>.*) at (?<end:Date[yyyy-MM-dd' 'HH:mm:ss.SSS]>.*)") { obj in
    obj["duration"].doubleValue = obj["end"].doubleValue - start
    if obj["duration"].doubleValue > 12 { print(obj["duration"], "\t", obj["desc"]) }
}

var failed = 0
sc.process(onKey: "failure") { _ in failed += 1 }
sc.process(atEnd: true) { _ in print(failed, "failed tests") }

sc.process(onPattern: "^$") { obj in obj = .null }

var totalTime = 0.0
sc.process(onKey: "duration") { obj in totalTime += obj["duration"].doubleValue}
sc.process(atEnd: true) { _ in print("Total Time:", totalTime, "seconds") }

sc.run()

sc.process(onKey: "duration") { obj in
    obj["prop"].doubleValue = obj["duration"].doubleValue * 100.0 / totalTime
    if obj["prop"].doubleValue > 10 { print("\(obj["prop"])%", obj["desc"]) }
}

sc.run()

extension Script {
    func grep(pattern: String) {
        process(onPattern: pattern) { obj in print(obj["message"]) }
    }

    func group(pattern: String) {
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
        process(atEnd: true) { obj in obj = group ?? .null }
    }
}

sc.group(pattern: "^\\s")

sc.process(onKey: "failure") { obj in
    print("FAILED", obj["failure"])
    Script.invoke(Script.grep, obj["group"].arrayValue, "at .*\\(Wsk.*\\)")
}

sc.run()
