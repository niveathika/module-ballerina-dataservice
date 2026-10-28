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
import ballerina/lang.regexp;

final regexp:RegExp BROKEN_CONSTRAINT = re `'\$\.([^:']+):([^']+)'`;

# Checks the `ballerina/constraint` annotations of a record that a service converted from its wire type.
#
# + value - The record, of a type that carries the model's constraint annotations
# + entity - The name of the entity
# + return - An `INVALID_INPUT` error body naming the first field the record breaks a constraint of, and the
# constraint as `ballerina/constraint` names it, such as `maxLength` or `pastDate`
public isolated function checkConstraints(record {} value, string entity) returns DataserviceError? {
    anydata|error result = constraint:validate(value, typeof value);
    if result !is error {
        return ();
    }
    regexp:Groups? groups = BROKEN_CONSTRAINT.findGroups(result.message());
    if groups is () {
        return {code: INVALID_INPUT, message: string `The entity '${entity}' breaks a constraint.`};
    }
    return {
        code: INVALID_INPUT,
        message: string `The field '${groupText(groups, 1)}' of the entity '${entity}' breaks its '${
            groupText(groups, 2)}' constraint.`
    };
}
