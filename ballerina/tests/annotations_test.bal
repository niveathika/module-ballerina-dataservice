// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/test;

@test:Config
function testExposeConfigDefaultsToEveryAction() {
    ExposeConfig config = {};
    test:assertEquals(config.operations, [READ, CREATE, UPDATE, DELETE]);
}

@test:Config
function testOperationValues() {
    test:assertEquals([READ, CREATE, UPDATE, DELETE], ["read", "create", "update", "delete"]);
}

type Order record {|
    readonly int id;
    @Immutable
    int customerId;
    @ReadOnly {value: "pending"}
    string status;
    @Internal
    string? internalNotes;
|};

@test:Config
function testFieldRulesOnARecord() {
    Order 'order = {id: 1, customerId: 2, status: "pending", internalNotes: ()};
    test:assertEquals('order.status, "pending");
}
