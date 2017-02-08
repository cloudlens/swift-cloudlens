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

import PackageDescription

let package = Package(
    name: "CloudLens",
    targets: [
        Target(
            name: "CloudLens"),
        Target(
            name: "Main",
            dependencies: [.Target(name: "CloudLens")])
    ],
    dependencies: [
        .Package(url: "https://github.com/IBM-Swift/SwiftyJSON.git", majorVersion: 15)
    ]
)

#if !os(Linux)
products.append(
    Product(name: "CloudLens", type: .Library(.Dynamic), modules: "CloudLens")
)
#endif
// delete the #if/#endif pair on Linux to build the CloudLens library for the Swift REPL
