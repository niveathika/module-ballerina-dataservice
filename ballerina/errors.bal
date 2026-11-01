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

import ballerina/log;
import ballerina/persist;

# The category of a data service error.
public enum ErrorCode {
    NOT_FOUND,
    CONFLICT,
    CONSTRAINT_VIOLATION,
    INVALID_INPUT,
    UNAUTHENTICATED,
    FORBIDDEN,
    INTERNAL
}

# The body of an error that a data service returns.
#
# + code - The error category
# + message - A description of the error
public type DataserviceError record {|
    ErrorCode code;
    string message;
|};

# A value of an entity's key field.
public type KeyValue int|string|float|decimal|boolean;

# Maps an error from the persist client to the data service error body.
#
# + err - The error the persist client returned
# + entity - The name of the entity
# + key - The values of the record's key fields, in key order
# + return - The error body for the error's category
public isolated function toErrorBody(error err, string entity = "", KeyValue[] key = [])
        returns DataserviceError {
    if err is persist:NotFoundError {
        return {
            code: NOT_FOUND,
            message: string `A record with the key '${keyText(key)}' does not exist for the entity '${entity}'.`
        };
    }
    if err is persist:AlreadyExistsError {
        return {
            code: CONFLICT,
            message: string `A record that conflicts with an existing record of the entity '${entity}' already exists.`
        };
    }
    // The SQL datastores put driver text in these errors, so it is logged rather than returned.
    if err is persist:ConstraintViolationError {
        logError(err, entity);
        return {code: CONSTRAINT_VIOLATION, message: string `The operation violates a constraint of the entity '${entity}'.`};
    }
    logError(err, entity);
    return {code: INTERNAL, message: "An internal error occurred."};
}

# Builds the error body for a request without a credential, or with one that no authentication provider accepts.
#
# + return - The `UNAUTHENTICATED` error body
public isolated function unauthenticated() returns DataserviceError => {
    code: UNAUTHENTICATED,
    message: "The request needs a valid credential."
};

# Builds the error body for a caller that holds no scope of the operation's action.
#
# + return - The `FORBIDDEN` error body
public isolated function noScope() returns DataserviceError => {
    code: FORBIDDEN,
    message: "The caller holds no scope that the operation needs."
};

# Builds the error body for a relation the caller cannot read, because it holds no `read` scope of the related
# entity.
#
# + entity - The name of the entity
# + relation - The relation field
# + target - The name of the related entity
# + return - The `FORBIDDEN` error body
public isolated function forbidden(string entity, string relation, string target) returns DataserviceError => {
    code: FORBIDDEN,
    message: string `The relation '${relation}' of the entity '${entity}' needs a 'read' scope of the entity ` +
        string `'${target}'.`
};

# Checks that every `float` value of a key is a finite number.
#
# + entity - The name of the entity
# + key - The values of the record's key fields, in key order
# + return - An `INVALID_INPUT` error body when a value is `NaN` or infinite
public isolated function checkFiniteKey(string entity, KeyValue[] key) returns DataserviceError? {
    foreach KeyValue value in key {
        if value is float && !value.isFinite() {
            return {
                code: INVALID_INPUT,
                message: string `The key '${keyText(key)}' of the entity '${entity}' is not a finite number.`
            };
        }
    }
    return ();
}

isolated function keyText(KeyValue[] key) returns string =>
    string:'join("/", ...from KeyValue value in key select value.toString());

isolated function logError(error err, string entity) {
    if entity == "" {
        log:printError("A data service operation failed.", 'error = err);
    } else {
        log:printError("A data service operation failed.", 'error = err, entity = entity);
    }
}
