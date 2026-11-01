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

import ballerina/persist;
import ballerina/test;

@test:Config
function testNotFound() {
    test:assertEquals(toErrorBody(error persist:NotFoundError("no row"), "Employee", [99]), {
        code: NOT_FOUND,
        message: "A record with the key '99' does not exist for the entity 'Employee'."
    });
}

@test:Config
function testNotFoundCompositeKey() {
    DataserviceError body = toErrorBody(error persist:NotFoundError("no row"), "Assignment", ["P 1/a", 1]);
    test:assertEquals(body.message, "A record with the key 'P 1/a/1' does not exist for the entity 'Assignment'.");
}

@test:Config
function testKeyText() {
    DataserviceError body = toErrorBody(error persist:NotFoundError("no row"), "Rate",
            [1.5, 2.50d, true, "x"]);
    test:assertEquals(body.message, "A record with the key '1.5/2.50/true/x' does not exist for the entity 'Rate'.");
}

@test:Config
function testConflict() {
    test:assertEquals(toErrorBody(error persist:AlreadyExistsError("Duplicate entry '1'"), "Employee", [1]), {
        code: CONFLICT,
        message: "A record that conflicts with an existing record of the entity 'Employee' already exists."
    });
}

@test:Config
function testConstraintViolation() {
    test:assertEquals(toErrorBody(error persist:ConstraintViolationError("FK_EMP_DEPT violated"), "Employee"), {
        code: CONSTRAINT_VIOLATION,
        message: "The operation violates a constraint of the entity 'Employee'."
    });
}

@test:Config
function testPersistErrorIsInternal() {
    test:assertEquals(toErrorBody(error persist:Error("connection refused"), "Employee"), {
        code: INTERNAL,
        message: "An internal error occurred."
    });
}

@test:Config
function testOtherErrorIsInternal() {
    test:assertEquals(toErrorBody(error("boom")), {code: INTERNAL, message: "An internal error occurred."});
}

@test:Config
function testFiniteKey() {
    test:assertEquals(checkFiniteKey("Rate", [1.5, "x"]), ());
    test:assertEquals(checkFiniteKey("Rate", [1, float:NaN]), {
        code: INVALID_INPUT,
        message: "The key '1/NaN' of the entity 'Rate' is not a finite number."
    });
    test:assertEquals(checkFiniteKey("Rate", [-float:Infinity]), {
        code: INVALID_INPUT,
        message: "The key '-Infinity' of the entity 'Rate' is not a finite number."
    });
}

@test:Config
function testForbidden() {
    test:assertEquals(forbidden("Employee", "department", "Department"), <DataserviceError>{
        code: FORBIDDEN,
        message: "The relation 'department' of the entity 'Employee' needs a 'read' scope of the entity 'Department'."
    });
}

@test:Config
function testAuthErrors() {
    test:assertEquals(unauthenticated(), <DataserviceError>{
        code: UNAUTHENTICATED,
        message: "The request needs a valid credential."
    });
    test:assertEquals(noScope(), <DataserviceError>{
        code: FORBIDDEN,
        message: "The caller holds no scope that the operation needs."
    });
}
