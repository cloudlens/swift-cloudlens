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

//: CloudLens Playground

import CloudLens

let sc = Script()

sc.stream(messages: "error 42", "warning", "info", "error 255")
sc.process { obj in print(obj) }

sc.run()

sc.process(onPattern: "error (?<error:Number>\\d+)") { obj in print("error", obj["error"], "detected") }
var count = 0
sc.process(onKey: "error") { _ in count += 1 }
sc.process(atEnd: true) { _ in print(count, "error(s)") }

sc.run()

sc.process(onPattern: "info") { obj in obj = .null }
sc.process { obj in print(obj) }

sc.run()
