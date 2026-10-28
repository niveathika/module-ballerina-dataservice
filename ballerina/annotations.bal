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

# An action that a data service allows on an entity.
public enum Operation {
    READ = "read",
    CREATE = "create",
    UPDATE = "update",
    DELETE = "delete"
}

# Configures the `Expose` annotation.
#
# + operations - The actions the entity allows; every action by default
public type ExposeConfig record {|
    [Operation, Operation...] operations = [READ, CREATE, UPDATE, DELETE];
|};

# Exposes a persist entity in the generated data service.
public const annotation ExposeConfig Expose on source type;

# Configures a field rule.
#
# + value - The value the service sets on create, which must be a constant of the field's type
public type FieldRuleConfig record {|
    anydata value?;
|};

# Marks a field that is returned but never written. A value sent on create or update is ignored.
public const annotation FieldRuleConfig ReadOnly on source record field;

# Marks a field that is set on create and never changed.
public const annotation Immutable on source record field;

# Marks a field that is never returned or accepted.
public const annotation FieldRuleConfig Internal on source record field;
