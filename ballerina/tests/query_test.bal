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

import ballerina/sql;
import ballerina/test;
import ballerina/time;

final PageConfig pages = {size: 100, maxSize: 1000};

isolated function employeeEntity(Datastore datastore = H2) returns Entity => {
    name: "Employee",
    'resource: "employees",
    datastore,
    fields: [
        {name: "id", column: "id", 'type: INT, key: true},
        {name: "name", column: "name", 'type: STRING},
        {name: "email", column: "email_address", 'type: STRING, nullable: true},
        {name: "hiredOn", column: "hired_on", 'type: DATE},
        {name: "status", column: "status", 'type: ENUM},
        {name: "rate", column: "rate", 'type: DECIMAL},
        {name: "photo", column: "photo", 'type: BYTES, nullable: true}
    ]
};

final Entity assignment = {
    name: "Assignment",
    'resource: "assignments",
    datastore: H2,
    fields: [
        {name: "projectCode", column: "projectCode", 'type: STRING, key: true},
        {name: "seq", column: "seq", 'type: INT, key: true},
        {name: "hours", column: "hours", 'type: DECIMAL}
    ]
};

isolated function sqlText(sql:ParameterizedQuery query) returns string => string:'join("?", ...query.strings);

isolated function checkedQuery(Entity entity, map<map<anydata>>? filter = (), string[]? sort = (),
        int? size = (), int? offset = ()) returns Query {
    Query|DataserviceError|ConversionError result = query(entity, pages, filter, sort, size, offset);
    if result is ConversionError {
        test:assertFail(string `Unexpected error: ${result.message()}`);
    }
    if result is DataserviceError {
        test:assertFail(string `Unexpected error: ${result.message}`);
    }
    return result;
}

isolated function invalidMessage(Entity entity, map<map<anydata>>? filter = (), string[]? sort = (),
        int? size = (), int? offset = ()) returns string {
    Query|DataserviceError|ConversionError result = query(entity, pages, filter, sort, size, offset);
    if result !is DataserviceError {
        test:assertFail("Expected an INVALID_INPUT body");
    }
    test:assertEquals(result.code, INVALID_INPUT);
    return result.message;
}

@test:Config
function testDefaultQuery() {
    Query query = checkedQuery(employeeEntity());
    test:assertEquals(sqlText(query.whereClause), "");
    test:assertEquals(sqlText(query.orderByClause), "\"Employee\".\"id\" ASC");
    test:assertEquals(query.limitClause.insertions, [101]);
    test:assertEquals(sqlText(query.offsetClause), "");
    test:assertEquals(query.size, 100);
}

@test:Config
function testFilter() {
    Query query = checkedQuery(employeeEntity(), {
        id: {gte: 2, lt: 10},
        hiredOn: {gte: "2024-01-01"},
        status: {anyOf: ["ACTIVE", "ON_LEAVE"]},
        rate: {ne: 1},
        name: {contains: "50%_off!"}
    });
    test:assertEquals(sqlText(query.whereClause), "(\"Employee\".\"id\" >= ? AND \"Employee\".\"id\" < ? AND " +
            "\"Employee\".\"hired_on\" >= ? AND \"Employee\".\"status\" IN (?, ?) AND \"Employee\".\"rate\" <> ? AND " +
            "\"Employee\".\"name\" LIKE ? ESCAPE '!')");
    time:Date hiredOn = {year: 2024, month: 1, day: 1};
    test:assertEquals(query.whereClause.insertions, [2, 10, hiredOn, "ACTIVE", "ON_LEAVE", 1d, "%50!%!_off!!%"]);
}

@test:Config
function testStartsWithAndNulls() {
    Query query = checkedQuery(employeeEntity(), {name: {startsWith: "A"}, email: {isNull: true}});
    test:assertEquals(sqlText(query.whereClause),
            "(\"Employee\".\"name\" LIKE ? ESCAPE '!' AND \"Employee\".\"email_address\" IS NULL)");
    test:assertEquals(query.whereClause.insertions, ["A%"]);
    query = checkedQuery(employeeEntity(), {email: {isNull: false, eq: "a@b.c"}});
    test:assertEquals(sqlText(query.whereClause),
            "(\"Employee\".\"email_address\" IS NOT NULL AND \"Employee\".\"email_address\" = ?)");
}

@test:Config
function testEmptyAnyOfMatchesNothing() {
    Query query = checkedQuery(employeeEntity(), {id: {anyOf: []}});
    test:assertEquals(sqlText(query.whereClause), "(1 = 0)");
}

@test:Config
function testMssqlEscapesBracketInLike() {
    Query query = checkedQuery(employeeEntity(MSSQL), {name: {contains: "[a]"}});
    test:assertEquals(sqlText(query.whereClause), "([Employee].[name] LIKE ? ESCAPE '!')");
    test:assertEquals(query.whereClause.insertions, ["%![a]%"]);
}

@test:Config
function testUnusableFilterField() {
    test:assertEquals(invalidMessage(employeeEntity(), {salary: {eq: 1}}),
            "The field 'salary' of the entity 'Employee' cannot be used in 'filter'.");
    test:assertEquals(invalidMessage(employeeEntity(), {photo: {isNull: true}}),
            "The field 'photo' of the entity 'Employee' cannot be used in 'filter'.");
}

@test:Config
function testOperatorNotAllowed() {
    map<map<anydata>>[] filters = [
        {status: {lt: "ACTIVE"}},
        {id: {contains: "1"}},
        {name: {isNull: true}},
        {name: {like: "a"}}
    ];
    string[] messages = [
        "The operator 'lt' cannot be used on the field 'status' of the entity 'Employee'.",
        "The operator 'contains' cannot be used on the field 'id' of the entity 'Employee'.",
        "The operator 'isNull' cannot be used on the field 'name' of the entity 'Employee'.",
        "The operator 'like' cannot be used on the field 'name' of the entity 'Employee'."
    ];
    foreach int i in 0 ..< filters.length() {
        test:assertEquals(invalidMessage(employeeEntity(), filters[i]), messages[i]);
    }
}

@test:Config
function testFilterValueThatDoesNotParse() {
    Query|DataserviceError|ConversionError result = query(employeeEntity(), pages, {hiredOn: {anyOf: ["2024-13-01"]}});
    if result !is ConversionError {
        test:assertFail("Expected a ConversionError");
    }
    test:assertEquals(result.detail(), {format: "an ISO 8601 date", 'field: "hiredOn"});
}

@test:Config
function testSort() {
    Query query = checkedQuery(employeeEntity(), sort = ["-hiredOn", "email"]);
    test:assertEquals(sqlText(query.orderByClause), "\"Employee\".\"hired_on\" DESC, " +
            "\"Employee\".\"email_address\" ASC NULLS LAST, \"Employee\".\"id\" ASC");
    query = checkedQuery(employeeEntity(), sort = ["-email", "-id"]);
    test:assertEquals(sqlText(query.orderByClause),
            "\"Employee\".\"email_address\" DESC NULLS FIRST, \"Employee\".\"id\" DESC");
}

@test:Config
function testSortNullsWithCase() {
    Query query = checkedQuery(employeeEntity(MYSQL), sort = ["email", "-name"]);
    test:assertEquals(sqlText(query.orderByClause), "CASE WHEN `Employee`.`email_address` IS NULL THEN 1 ELSE 0 END, " +
            "`Employee`.`email_address` ASC, `Employee`.`name` DESC, `Employee`.`id` ASC");
    query = checkedQuery(employeeEntity(MSSQL), sort = ["-email"]);
    test:assertEquals(sqlText(query.orderByClause), "CASE WHEN [Employee].[email_address] IS NULL THEN 0 ELSE 1 END, " +
            "[Employee].[email_address] DESC, [Employee].[id] ASC");
}

@test:Config
function testInvalidSort() {
    test:assertEquals(invalidMessage(employeeEntity(), sort = ["-salary"]),
            "The field 'salary' of the entity 'Employee' cannot be used in 'sort'.");
    test:assertEquals(invalidMessage(employeeEntity(), sort = ["photo"]),
            "The field 'photo' of the entity 'Employee' cannot be used in 'sort'.");
    test:assertEquals(invalidMessage(employeeEntity(), sort = ["name", "-name"]),
            "The field 'name' is named more than once in 'sort'.");
}

@test:Config
function testQuotesInIdentifiers() {
    Entity entity = {
        name: "Odd",
        'resource: "odds",
        datastore: MYSQL,
        fields: [{name: "id", column: "a`b", 'type: INT, key: true}]
    };
    test:assertEquals(sqlText(checkedQuery(entity).orderByClause), "`Odd`.`a``b` ASC");
    entity = {
        name: "Odd",
        'resource: "odds",
        datastore: POSTGRESQL,
        fields: [{name: "id", column: "a\"b", 'type: INT, key: true}]
    };
    test:assertEquals(sqlText(checkedQuery(entity).orderByClause), "\"Odd\".\"a\"\"b\" ASC");
}

@test:Config
function testSizeAndOffset() {
    Query query = checkedQuery(employeeEntity(), size = 20, offset = 40);
    test:assertEquals(query.size, 20);
    test:assertEquals(query.limitClause.insertions, [21]);
    test:assertEquals(query.offsetClause.insertions, [40]);
    test:assertEquals(checkedQuery(employeeEntity(), size = 5000).size, 1000);
    test:assertEquals(invalidMessage(employeeEntity(), size = 0), "The page size must be at least 1.");
    test:assertEquals(invalidMessage(employeeEntity(), offset = -1), "The offset must be at least 0.");
    test:assertEquals(invalidMessage(employeeEntity(), size = 10, offset = int:MAX_VALUE - 9),
            "The offset and the page size together exceed the largest integer.");
}

@test:Config
function testPage() {
    Query query = checkedQuery(employeeEntity(), size = 2);
    int[] rows = [1, 2, 3];
    test:assertTrue(page(rows, query));
    test:assertEquals(rows, [1, 2]);
    test:assertFalse(page(rows, query));
    test:assertEquals(rows, [1, 2]);
}

@test:Config
function testKeysQuery() {
    Query query = keysQuery(employeeEntity(), [[3], [1]]);
    test:assertEquals(sqlText(query.whereClause), "\"Employee\".\"id\" IN (?, ?)");
    test:assertEquals(query.whereClause.insertions, [3, 1]);
    test:assertEquals(sqlText(query.orderByClause), "\"Employee\".\"id\" ASC");
    test:assertEquals(sqlText(query.limitClause), "");
    query = keysQuery(assignment, [["P1", 2], ["P2", 1]]);
    test:assertEquals(sqlText(query.whereClause), "((\"Assignment\".\"projectCode\" = ? AND " +
            "\"Assignment\".\"seq\" = ?) OR (\"Assignment\".\"projectCode\" = ? AND \"Assignment\".\"seq\" = ?))");
    test:assertEquals(query.whereClause.insertions, ["P1", 2, "P2", 1]);
}

@test:Config
function testOrderByKeys() returns error? {
    map<anydata>[] rows = [{projectCode: "P1", seq: 2, hours: 1.5d}, {projectCode: "P2", seq: 1, hours: 2d}];
    check orderByKeys(rows, assignment, [["P2", 1], ["P1", 2]]);
    test:assertEquals(rows, [{projectCode: "P2", seq: 1, hours: 2d}, {projectCode: "P1", seq: 2, hours: 1.5d}]);
    error? missing = orderByKeys(rows, assignment, [["P2", 1], ["P3", 2]]);
    test:assertTrue(missing is error);
}

@test:Config
function testCheckFields() {
    test:assertEquals(checkFields(employeeEntity(), ()), ());
    test:assertEquals(checkFields(employeeEntity(), ["name", "photo"]), ());
    DataserviceError empty = {code: INVALID_INPUT, message: "'fields' must name at least one field."};
    test:assertEquals(checkFields(employeeEntity(), []), empty);
    test:assertEquals(checkFields(employeeEntity(), [""]), empty);
    test:assertEquals(checkFields(employeeEntity(), ["name", "department.name"]), <DataserviceError>{
        code: INVALID_INPUT,
        message: "The field 'department.name' of the entity 'Employee' cannot be used in 'fields'."
    });
}

@test:Config
function testNarrow() {
    map<anydata> employee = {id: 1, name: "Ann", email: (), hiredOn: "2024-01-02", status: "ACTIVE", rate: 1d};
    test:assertEquals(narrow(employee, employeeEntity(), ["email", "name", "name"]), {id: 1, name: "Ann", email: ()});
}
