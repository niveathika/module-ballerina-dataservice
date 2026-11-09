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

import ballerina/constraint;
import ballerina/test;
import ballerina/time;

type Hire record {|
    @constraint:String {maxLength: 3}
    string name?;
    @constraint:Date {option: constraint:PAST}
    time:Date hiredOn?;
|};

@test:Config
function testConstraintsHold() {
    Hire hire = {name: "Ann", hiredOn: {year: 2020, month: 1, day: 2}};
    test:assertEquals(checkConstraints(hire, "Employee"), ());
    Hire empty = {};
    test:assertEquals(checkConstraints(empty, "Employee"), ());
}

@test:Config
function testBrokenConstraint() {
    Hire hire = {hiredOn: {year: 2999, month: 1, day: 2}};
    test:assertEquals(checkConstraints(hire, "Employee"), <DataserviceError>{
        code: INVALID_INPUT,
        message: "The field 'hiredOn' of the entity 'Employee' breaks its 'pastDate' constraint."
    });
    hire = {name: "Annabel"};
    test:assertEquals(checkConstraints(hire, "Employee"), <DataserviceError>{
        code: INVALID_INPUT,
        message: "The field 'name' of the entity 'Employee' breaks its 'maxLength' constraint."
    });
}
