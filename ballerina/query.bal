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

import ballerina/lang.regexp;
import ballerina/sql;

# The SQL datastore of an entity.
public enum Datastore {
    MYSQL,
    MSSQL,
    POSTGRESQL,
    H2
}

# The type of an entity field.
public enum FieldType {
    INT,
    FLOAT,
    DECIMAL,
    STRING,
    BOOLEAN,
    ENUM,
    BYTES,
    DATE,
    TIME_OF_DAY,
    CIVIL,
    UTC
}

# A field of an entity.
#
# + name - The field name in the model
# + column - The column name in the database
# + type - The type of the field
# + nullable - Whether the field can be nil
# + key - Whether the field is a key field
# + generated - Whether the database generates the field's value
public type Field record {|
    string name;
    string column;
    FieldType 'type;
    boolean nullable = false;
    boolean key = false;
    boolean generated = false;
|};

# The description of an entity that queries are built from.
#
# + name - The entity name
# + resource - The persist resource name of the entity
# + datastore - The datastore of the entity
# + fields - The fields that callers can see, in model order
public type Entity readonly & record {|
    string name;
    string 'resource;
    Datastore datastore;
    Field[] fields;
|};

# The clauses of a query for the persist SQL client.
#
# + whereClause - The `WHERE` clause
# + orderByClause - The `ORDER BY` clause
# + limitClause - The `LIMIT` clause, one row more than the page to tell whether more records exist
# + offsetClause - The number of rows to skip
# + size - The page size
public type Query record {|
    sql:ParameterizedQuery whereClause;
    sql:ParameterizedQuery orderByClause;
    sql:ParameterizedQuery limitClause;
    sql:ParameterizedQuery offsetClause;
    int size;
|};

type Condition record {|
    Field 'field;
    string operator;
    sql:Value[] values;
|};

type Group record {|
    boolean matchAll;
    Filter[] filters;
|};

type Filter Condition|Group;

# Validates the query options of a read and builds its query.
#
# + entity - The entity to read
# + config - The page sizes of the data service
# + filter - The conditions, as a map from field name to a map from operator to value
# + sort - The field names to sort by, each descending when it starts with `-`
# + size - The page size
# + offset - The number of records to skip
# + return - The query, an `INVALID_INPUT` error body, or a `ConversionError` for a value that does not parse
public isolated function query(Entity entity, PageConfig config, map<map<anydata>>? filter = (),
        string[]? sort = (), int? size = (), int? offset = ()) returns Query|DataserviceError|ConversionError {
    Filter[] conditions = [];
    if filter is map<map<anydata>> {
        foreach [string, map<anydata>] [name, operators] in filter.entries() {
            Field? 'field = findField(entity, name);
            if 'field is () || 'field.'type == BYTES {
                return unusable(entity, name, "filter");
            }
            foreach [string, anydata] [operator, value] in operators.entries() {
                Condition|DataserviceError|ConversionError condition = toCondition(entity, 'field, operator, value);
                if condition !is Condition {
                    return condition;
                }
                conditions.push(condition);
            }
        }
    }
    sql:ParameterizedQuery|DataserviceError orderBy = orderByClause(entity, sort ?: []);
    if orderBy is DataserviceError {
        return orderBy;
    }
    int pageSize = size ?: config.size;
    if pageSize < 1 {
        return invalidInput("The page size must be at least 1.");
    }
    if pageSize > config.maxSize {
        pageSize = config.maxSize;
    }
    int skip = offset ?: 0;
    if skip < 0 {
        return invalidInput("The offset must be at least 0.");
    }
    if skip > int:MAX_VALUE - pageSize {
        return invalidInput("The offset and the page size together exceed the largest integer.");
    }
    int 'limit = pageSize < int:MAX_VALUE ? pageSize + 1 : pageSize;
    return {
        whereClause: whereClause(entity, {matchAll: true, filters: conditions}),
        orderByClause: orderBy,
        limitClause: `${'limit}`,
        offsetClause: skip > 0 ? `${skip}` : ``,
        size: pageSize
    };
}

# Builds the query that reads records by their keys, in key order.
#
# + entity - The entity to read
# + keys - The key values of each record, in key order
# + return - The query
public isolated function keysQuery(Entity entity, KeyValue[][] keys) returns Query {
    Field[] keyFields = from Field 'field in entity.fields where 'field.key select 'field;
    Filter matches;
    if keyFields.length() == 1 {
        matches = {'field: keyFields[0], operator: "anyOf", values: from KeyValue[] key in keys select key[0]};
    } else {
        matches = {
            matchAll: false,
            filters: from KeyValue[] key in keys
                select <Group>{
                    matchAll: true,
                    filters: from int i in 0 ..< keyFields.length()
                        select <Condition>{'field: keyFields[i], operator: "eq", values: [key[i]]}
                }
        };
    }
        return {
        whereClause: whereClause(entity, matches),
        orderByClause: <sql:ParameterizedQuery>orderByClause(entity, []),
        limitClause: ``,
        offsetClause: ``,
        size: keys.length()
    };
}

# Puts records read by `keysQuery` in the order of their keys.
#
# + rows - The records, which are reordered in place
# + entity - The entity of the records
# + keys - The key values of each record, in the order to put the records in
# + return - An error when a record of a key is missing
public isolated function orderByKeys(map<anydata>[] rows, Entity entity, KeyValue[][] keys) returns error? {
    string[] keyNames = from Field 'field in entity.fields where 'field.key select 'field.name;
    map<anydata>[] found = rows.slice(0);
    foreach int i in 0 ..< keys.length() {
        map<anydata>? row = ();
        foreach map<anydata> candidate in found {
            if (from string name in keyNames select candidate[name]) == keys[i] {
                row = candidate;
                break;
            }
        }
        if row is () {
            return error(string `A created record of the entity '${entity.name}' was not read back.`);
        }
        rows[i] = row;
    }
    rows.setLength(keys.length());
}

# Removes the extra row that a query reads beyond its page.
#
# + rows - The rows the query returned, which are cut to the page in place
# + query - The query
# + return - Whether records exist after the page
public isolated function page(anydata[] rows, Query query) returns boolean {
    if rows.length() > query.size {
        rows.setLength(query.size);
        return true;
    }
    return false;
}

# Checks the `fields` option of a read.
#
# + entity - The entity to read
# + fields - The field names to return
# + return - An `INVALID_INPUT` error body when `fields` is empty or names a field that cannot be returned
public isolated function checkFields(Entity entity, string[]? fields) returns DataserviceError? {
    if fields is () {
        return ();
    }
    string[] names = from string name in fields where name != "" select name;
    if names.length() == 0 {
        return invalidInput("'fields' must name at least one field.");
    }
    foreach string name in names {
        if findField(entity, name) is () {
            return unusable(entity, name, "fields");
        }
    }
    return ();
}

# Narrows a record to the named fields and its key fields.
#
# + value - The record
# + entity - The entity of the record
# + fields - The field names to keep
# + return - The narrowed record
public isolated function narrow(map<anydata> value, Entity entity, string[] fields) returns map<anydata> {
    map<anydata> narrowed = {};
    foreach Field 'field in entity.fields {
        if ('field.key || fields.indexOf('field.name) !is ()) && value.hasKey('field.name) {
            narrowed['field.name] = value['field.name];
        }
    }
    return narrowed;
}

isolated function toCondition(Entity entity, Field 'field, string operator, anydata value)
        returns Condition|DataserviceError|ConversionError {
    if !isAllowed('field, operator) {
        return invalidInput(string `The operator '${operator}' cannot be used on the field '${
            'field.name}' of the entity '${entity.name}'.`);
    }
    if operator == "isNull" {
        if value !is boolean {
            return fieldError(conversionError("a boolean"), 'field);
        }
        return {'field, operator, values: [value]};
    }
    anydata[] given = [value];
    if operator == "anyOf" {
        if value !is anydata[] {
            return fieldError(conversionError("a list"), 'field);
        }
        given = value;
    }
    sql:Value[] values = [];
    foreach anydata item in given {
        sql:Value|ConversionError converted = toSqlValue('field, item);
        if converted is ConversionError {
            return fieldError(converted, 'field);
        }
        values.push(converted);
    }
    return {'field, operator, values};
}

isolated function isAllowed(Field 'field, string operator) returns boolean {
    match operator {
        "eq"|"ne"|"anyOf" => {
            return true;
        }
        "lt"|"lte"|"gt"|"gte" => {
            return 'field.'type != BOOLEAN && 'field.'type != ENUM;
        }
        "contains"|"startsWith" => {
            return 'field.'type == STRING;
        }
        "isNull" => {
            return 'field.nullable;
        }
    }
    return false;
}

isolated function toSqlValue(Field 'field, anydata value) returns sql:Value|ConversionError {
    match 'field.'type {
        INT => {
            if value is int {
                return value;
            }
            return conversionError("an int");
        }
        FLOAT => {
            if value is float|int|decimal {
                return <float>value;
            }
            return conversionError("a float");
        }
        DECIMAL => {
            if value is decimal|int|float {
                return <decimal>value;
            }
            return conversionError("a decimal");
        }
        BOOLEAN => {
            if value is boolean {
                return value;
            }
            return conversionError("a boolean");
        }
    }
    if value !is string {
        return conversionError("a string");
    }
    match 'field.'type {
        DATE => {
            return dateFromString(value);
        }
        TIME_OF_DAY => {
            return timeOfDayFromString(value);
        }
        CIVIL => {
            return civilFromString(value);
        }
        UTC => {
            return utcFromString(value);
        }
    }
    return value;
}

isolated function fieldError(ConversionError err, Field 'field) returns ConversionError =>
    error ConversionError(err.message(), err.cause(), format = err.detail().format, 'field = 'field.name);

isolated function whereClause(Entity entity, Filter filter) returns sql:ParameterizedQuery {
    if filter is Group && filter.filters.length() == 0 {
        return ``;
    }
    return filterSql(entity, filter);
}

isolated function filterSql(Entity entity, Filter filter) returns sql:ParameterizedQuery {
    if filter is Group {
        sql:ParameterizedQuery joined = `(`;
        foreach int i in 0 ..< filter.filters.length() {
            if i > 0 {
                joined = sql:queryConcat(joined, filter.matchAll ? ` AND ` : ` OR `);
            }
            joined = sql:queryConcat(joined, filterSql(entity, filter.filters[i]));
        }
        return sql:queryConcat(joined, `)`);
    }
    sql:ParameterizedQuery column = text(columnName(entity, filter.'field));
    sql:Value[] values = filter.values;
    match filter.operator {
        "eq" => {
            return sql:queryConcat(column, ` = ${values[0]}`);
        }
        "ne" => {
            return sql:queryConcat(column, ` <> ${values[0]}`);
        }
        "lt" => {
            return sql:queryConcat(column, ` < ${values[0]}`);
        }
        "lte" => {
            return sql:queryConcat(column, ` <= ${values[0]}`);
        }
        "gt" => {
            return sql:queryConcat(column, ` > ${values[0]}`);
        }
        "gte" => {
            return sql:queryConcat(column, ` >= ${values[0]}`);
        }
        "isNull" => {
            return sql:queryConcat(column, values[0] == true ? ` IS NULL` : ` IS NOT NULL`);
        }
        "contains"|"startsWith" => {
            string pattern = escapeLike(entity.datastore, <string>values[0]) + "%";
            if filter.operator == "contains" {
                pattern = "%" + pattern;
            }
            return sql:queryConcat(column, ` LIKE ${pattern} ESCAPE '!'`);
        }
    }
    if values.length() == 0 {
        return `1 = 0`;
    }
    sql:ParameterizedQuery list = sql:queryConcat(column, ` IN (`);
    foreach int i in 0 ..< values.length() {
        list = sql:queryConcat(list, i > 0 ? `, ${values[i]}` : `${values[i]}`);
    }
    return sql:queryConcat(list, `)`);
}

isolated function orderByClause(Entity entity, string[] sort) returns sql:ParameterizedQuery|DataserviceError {
    string[] terms = [];
    string[] named = [];
    foreach string entry in sort {
        if entry == "" {
            continue;
        }
        boolean reverse = entry.startsWith("-");
        string name = reverse ? entry.substring(1) : entry;
        Field? 'field = findField(entity, name);
        if 'field is () || 'field.'type == BYTES {
            return unusable(entity, name, "sort");
        }
        if named.indexOf(name) !is () {
            return invalidInput(string `The field '${name}' is named more than once in 'sort'.`);
        }
        named.push(name);
        terms.push(...orderTerms(entity, 'field, reverse));
    }
    foreach Field 'field in entity.fields {
        if 'field.key && named.indexOf('field.name) is () {
            terms.push(...orderTerms(entity, 'field, false));
        }
    }
    return text(string:'join(", ", ...terms));
}

isolated function orderTerms(Entity entity, Field 'field, boolean reverse) returns string[] {
    string column = columnName(entity, 'field);
    string direction = reverse ? "DESC" : "ASC";
    if !'field.nullable {
        return [string `${column} ${direction}`];
    }
    if entity.datastore == POSTGRESQL || entity.datastore == H2 {
        return [string `${column} ${direction} NULLS ${reverse ? "FIRST" : "LAST"}`];
    }
    return [string `CASE WHEN ${column} IS NULL THEN ${reverse ? 0 : 1} ELSE ${reverse ? 1 : 0} END`,
        string `${column} ${direction}`];
}

isolated function columnName(Entity entity, Field 'field) returns string =>
    quote(entity.datastore, entity.name) + "." + quote(entity.datastore, 'field.column);

isolated function quote(Datastore datastore, string name) returns string {
    match datastore {
        MYSQL => {
            return "`" + re `\u{60}`.replaceAll(name, "``") + "`";
        }
        MSSQL => {
            return "[" + re `\]`.replaceAll(name, "]]") + "]";
        }
    }
    return "\"" + re `"`.replaceAll(name, "\"\"") + "\"";
}

isolated function escapeLike(Datastore datastore, string value) returns string {
    string:RegExp special = datastore == MSSQL ? re `[!%_\[]` : re `[!%_]`;
    return special.replaceAll(value, isolated function(regexp:Groups groups) returns string =>
        "!" + groups[0].substring());
}

isolated function text(string value) returns sql:ParameterizedQuery {
    sql:ParameterizedQuery query = ``;
    query.strings = [value];
    return query;
}

isolated function findField(Entity entity, string name) returns Field? {
    foreach Field 'field in entity.fields {
        if 'field.name == name {
            return 'field;
        }
    }
    return ();
}

isolated function unusable(Entity entity, string name, string option) returns DataserviceError =>
    invalidInput(string `The field '${name}' of the entity '${entity.name}' cannot be used in '${option}'.`);

isolated function invalidInput(string message) returns DataserviceError => {code: INVALID_INPUT, message};
