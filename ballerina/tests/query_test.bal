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
    collection: "employees",
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
    collection: "assignments",
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
    Query|DataserviceError|ConversionError result = toQuery(entity, pages, filter, sort, size, offset);
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
    Query|DataserviceError|ConversionError result = toQuery(entity, pages, filter, sort, size, offset);
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
    Query|DataserviceError|ConversionError result =
        toQuery(employeeEntity(), pages, {hiredOn: {anyOf: ["2024-13-01"]}});
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
        collection: "odds",
        'resource: "odds",
        datastore: MYSQL,
        fields: [{name: "id", column: "a`b", 'type: INT, key: true}]
    };
    test:assertEquals(sqlText(checkedQuery(entity).orderByClause), "`Odd`.`a``b` ASC");
    entity = {
        name: "Odd",
        collection: "odds",
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
    test:assertTrue(trimToPage(rows, query));
    test:assertEquals(rows, [1, 2]);
    test:assertFalse(trimToPage(rows, query));
    test:assertEquals(rows, [1, 2]);
}

@test:Config
function testKeysQuery() {
    Query query = toKeysQuery(employeeEntity(), [[3], [1]]);
    test:assertEquals(sqlText(query.whereClause), "\"Employee\".\"id\" IN (?, ?)");
    test:assertEquals(query.whereClause.insertions, [3, 1]);
    test:assertEquals(sqlText(query.orderByClause), "\"Employee\".\"id\" ASC");
    test:assertEquals(sqlText(query.limitClause), "");
    query = toKeysQuery(assignment, [["P1", 2], ["P2", 1]]);
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
function testOrderByKeysReversed() returns error? {
    map<anydata>[] rows = from int i in 0 ..< 50 select {projectCode: string `P${i}`, seq: i, hours: 1d};
    KeyValue[][] keys = from int i in 0 ..< 50 order by i descending select [string `P${i}`, i];
    check orderByKeys(rows, assignment, keys);
    test:assertEquals(from map<anydata> row in rows select row["seq"], from int i in 0 ..< 50 order by i descending
            select i);
}

@test:Config
function testOrderByKeysMissing() {
    map<anydata>[] rows = [{projectCode: "P1", seq: 1}, {projectCode: "P2", seq: 2}];
    error? missing = orderByKeys(rows, assignment, [["P2", 2], ["P1", 2]]);
    if missing !is error {
        test:assertFail("A missing record is not reported.");
    }
    test:assertEquals(missing.message(), "A created record of the entity 'Assignment' was not read back.");
}

@test:Config
function testOrderByDecimalKeys() returns error? {
    Entity entity = {name: "Rate", collection: "rates", 'resource: "rates", datastore: H2,
        fields: [{name: "amount", column: "amount", 'type: DECIMAL, key: true}]};
    map<anydata>[] rows = [{amount: 1.50d}, {amount: 2d}];
    check orderByKeys(rows, entity, [[2d], [1.5d]]);
    test:assertEquals(rows, [{amount: 2d}, {amount: 1.50d}]);
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
function testSelectFields() {
    map<anydata> employee = {id: 1, name: "Ann", email: (), hiredOn: "2024-01-02", status: "ACTIVE", rate: 1d};
    test:assertEquals(selectFields(employee, employeeEntity(), ["email", "name", "name"]),
        {id: 1, name: "Ann", email: ()});
}

final Entity departmentOwn = {
    name: "Department",
    collection: "departments",
    'resource: "departments",
    datastore: H2,
    fields: [{name: "id", column: "id", 'type: INT, key: true}, {name: "name", column: "name", 'type: STRING}]
};

final Entity employeeOwn = {
    name: "Employee",
    collection: "employees",
    'resource: "employees",
    datastore: H2,
    fields: [
        {name: "id", column: "id", 'type: INT, key: true},
        {name: "name", column: "name", 'type: STRING},
        {name: "departmentId", column: "department_id", 'type: INT, nullable: true}
    ]
};

final Entity employeeWithDepartment = {
    name: "Employee",
    collection: "employees",
    'resource: "employees",
    datastore: H2,
    fields: employeeOwn.fields,
    relations: [
        {'field: "department", many: false, fields: ["departmentId"], targetFields: ["id"], target: departmentOwn}
    ]
};

final Entity departmentWithEmployees = {
    name: "Department",
    collection: "departments",
    'resource: "departments",
    datastore: H2,
    fields: departmentOwn.fields,
    relations: [
        {'field: "employees", many: true, fields: ["id"], targetFields: ["departmentId"], target: employeeOwn}
    ]
};

final Entity projectWithAssignments = {
    name: "Assignment",
    collection: "assignments",
    'resource: "assignments",
    datastore: H2,
    fields: assignment.fields,
    relations: [
        {
            'field: "notes",
            many: true,
            fields: ["projectCode", "seq"],
            targetFields: ["code", "seq"],
            target: {
                name: "Note",
                collection: "notes",
                'resource: "notes",
                datastore: H2,
                fields: [
                    {name: "id", column: "id", 'type: INT, key: true},
                    {name: "code", column: "code", 'type: STRING},
                    {name: "seq", column: "seq", 'type: INT}
                ]
            }
        }
    ]
};

@test:Config
function testRelatedQueryToOne() returns error? {
    Query query = check toRelatedQuery(employeeWithDepartment, "department", {id: 4, departmentId: 2}, pages)
        .ensureType();
    test:assertEquals(sqlText(query.whereClause), "(\"Department\".\"id\" IN (?))");
    test:assertEquals(query.whereClause.insertions, [2]);
    test:assertEquals(sqlText(query.orderByClause), "\"Department\".\"id\" ASC");
    query = check toRelatedQuery(employeeWithDepartment, "department", {id: 4, departmentId: ()}, pages).ensureType();
    test:assertEquals(sqlText(query.whereClause), "(1 = 0)");
}

@test:Config
function testRelatedQueryToManyWithOptions() returns error? {
    Query query = check toRelatedQuery(departmentWithEmployees, "employees", {id: 2}, pages,
            {name: {startsWith: "A"}}, ["-name"], 10, 20).ensureType();
    test:assertEquals(sqlText(query.whereClause),
            "(\"Employee\".\"department_id\" IN (?) AND \"Employee\".\"name\" LIKE ? ESCAPE '!')");
    test:assertEquals(query.whereClause.insertions, [2, "A%"]);
    test:assertEquals(sqlText(query.orderByClause), "\"Employee\".\"name\" DESC, \"Employee\".\"id\" ASC");
    test:assertEquals(query.limitClause.insertions, [11]);
    test:assertEquals(query.offsetClause.insertions, [20]);
    Query|DataserviceError|ConversionError invalid = toRelatedQuery(departmentWithEmployees, "employees", {id: 2},
            pages, sort = ["salary"]);
    test:assertEquals(invalid is DataserviceError ? invalid.message : "",
            "The field 'salary' of the entity 'Employee' cannot be used in 'sort'.");
}

@test:Config
function testIncludeQueries() {
    Query query = toIncludeQuery(employeeWithDepartment, "department", [{departmentId: 2}, {departmentId: ()},
        {departmentId: 3}], pages);
    test:assertEquals(sqlText(query.whereClause), "\"Department\".\"id\" IN (?, ?)");
    test:assertEquals(query.whereClause.insertions, [2, 3]);
    test:assertEquals(sqlText(query.limitClause), "");
    query = toIncludeQuery(employeeWithDepartment, "department", [{departmentId: ()}], pages);
    test:assertEquals(sqlText(query.whereClause), "1 = 0");
    query = toIncludeQuery(departmentWithEmployees, "employees", [{id: 2}], pages);
    test:assertEquals(sqlText(query.whereClause), "\"Employee\".\"department_id\" IN (?)");
    test:assertEquals(query.limitClause.insertions, [101]);
    test:assertEquals(query.size, 100);
    query = toIncludeQuery(projectWithAssignments, "notes", [{projectCode: "P1", seq: 2}], pages);
    test:assertEquals(sqlText(query.whereClause), "((\"Note\".\"code\" = ? AND \"Note\".\"seq\" = ?))");
    query = toIncludeQuery(projectWithAssignments, "notes", [], pages);
    test:assertEquals(sqlText(query.whereClause), "1 = 0");
}

@test:Config
function testIsIncluded() {
    test:assertTrue(isIncluded(["name", "department"], "department"));
    test:assertTrue(isIncluded(["department.name"], "department"));
    test:assertFalse(isIncluded(["departmentId"], "department"));
    test:assertFalse(isIncluded((), "department"));
}

@test:Config
function testAttach() {
    map<anydata>[] sources = [{id: 4, name: "Ann", departmentId: 2}, {id: 5, name: "Bob", departmentId: ()},
        {id: 6, name: "Cy", departmentId: 9}];
    map<anydata>[] partials = from map<anydata> row in sources select selectFields(row, employeeOwn, ["name"]);
    attachOne(partials, sources, employeeWithDepartment, "department", [{id: 2, name: "Research"}],
            ["name", "department.name"]);
    test:assertEquals(partials, [
        {id: 4, name: "Ann", department: {id: 2, name: "Research"}},
        {id: 5, name: "Bob", department: ()},
        {id: 6, name: "Cy", department: ()}
    ]);
    sources = [{id: 4, departmentId: 1}, {id: 5, departmentId: 3}, {id: 6, departmentId: 1}];
    partials = from map<anydata> row in sources select selectFields(row, employeeOwn, ["id"]);
    attachOne(partials, sources, employeeWithDepartment, "department",
            [{id: 3, name: "Sales"}, {id: 2, name: "Research"}, {id: 1, name: "Legal"}], ["id", "department.name"]);
    test:assertEquals(partials, [
        {id: 4, department: {id: 1, name: "Legal"}},
        {id: 5, department: {id: 3, name: "Sales"}},
        {id: 6, department: {id: 1, name: "Legal"}}
    ]);
    map<anydata> department = {id: 2};
    attachMany(department, departmentWithEmployees, "employees", [{id: 4, name: "Ann", departmentId: 2}], true,
            ["employees"]);
    test:assertEquals(department, {id: 2, employees: {items: [{id: 4, name: "Ann", departmentId: 2}], hasMore: true}});
    department = {id: 2};
    attachMany(department, departmentWithEmployees, "employees", [{id: 4, name: "Ann", departmentId: 2}], false,
            ["employees.name"]);
    test:assertEquals(department, {id: 2, employees: {items: [{id: 4, name: "Ann"}], hasMore: false}});
}

@test:Config
function testToRelatedNotFoundError() {
    test:assertEquals(toRelatedNotFoundError(employeeWithDepartment, "department", [4]), <DataserviceError>{
        code: NOT_FOUND,
        message: "The record with the key '4' of the entity 'Employee' has no 'department'."
    });
}

@test:Config
function testCheckFieldsWithRelations() {
    test:assertEquals(checkFields(employeeWithDepartment, ["name", "department", "department.name"]), ());
    string[][] invalid = [["department.salary"], ["department.employees"], ["manager"], ["name.first"]];
    foreach string[] fields in invalid {
        test:assertEquals(checkFields(employeeWithDepartment, fields), <DataserviceError>{
            code: INVALID_INPUT,
            message: string `The field '${fields[0]}' of the entity 'Employee' cannot be used in 'fields'.`
        });
    }
    test:assertEquals(checkFields(employeeWithDepartment, ["department"], false), <DataserviceError>{
        code: INVALID_INPUT,
        message: "The field 'department' of the entity 'Employee' cannot be used in 'fields'."
    });
}
