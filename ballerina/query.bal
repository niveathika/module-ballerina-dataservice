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
# + collection - The collection name of the entity in the service
# + resource - The persist resource name of the entity
# + datastore - The datastore of the entity
# + fields - The fields that callers can see, in model order
# + relations - The relations that callers can read
public type Entity readonly & record {|
    string name;
    string collection;
    string 'resource;
    Datastore datastore;
    Field[] fields;
    Relation[] relations = [];
|};

# A relation of an entity that callers can read.
#
# + field - The relation field
# + many - Whether the relation is to-many
# + fields - The fields of this entity that link it, in key order
# + targetFields - The fields of the related entity that they match, in the same order
# + target - The related entity, with its own fields and no relations
public type Relation record {|
    string 'field;
    boolean many;
    string[] fields;
    string[] targetFields;
    Entity target;
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
public isolated function toQuery(Entity entity, PageConfig config, map<map<anydata>>? filter = (),
        string[]? sort = (), int? size = (), int? offset = ()) returns Query|DataserviceError|ConversionError =>
    optionsQuery(entity, config, filter, sort, size, offset, []);

# Validates the query options of get related and builds its query, which reads the records related to one record.
#
# + entity - The entity of the record
# + relation - The relation field
# + row - The record, holding at least the fields that link the relation
# + config - The page sizes of the data service
# + filter - The conditions on the related records
# + sort - The field names of the related entity to sort by, each descending when it starts with `-`
# + size - The page size
# + offset - The number of records to skip
# + return - The query, an `INVALID_INPUT` error body, or a `ConversionError` for a value that does not parse
public isolated function toRelatedQuery(Entity entity, string relation, map<anydata> row, PageConfig config,
        map<map<anydata>>? filter = (), string[]? sort = (), int? size = (), int? offset = ())
        returns Query|DataserviceError|ConversionError {
    Relation related = relationOf(entity, relation);
    return optionsQuery(related.target, config, filter, sort, size, offset, [linkFilter(related, [row])]);
}

isolated function optionsQuery(Entity entity, PageConfig config, map<map<anydata>>? filter, string[]? sort,
        int? size, int? offset, Filter[] links) returns Query|DataserviceError|ConversionError {
    Filter[] conditions = [...links];
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
public isolated function toKeysQuery(Entity entity, KeyValue[][] keys) returns Query {
    Field[] keyFields = from Field 'field in entity.fields where 'field.key select 'field;
    return {
        whereClause: whereClause(entity, matchFilter(keyFields, keys)),
        orderByClause: <sql:ParameterizedQuery>orderByClause(entity, []),
        limitClause: ``,
        offsetClause: ``,
        size: keys.length()
    };
}

# Puts records read by `toKeysQuery` in the order of their keys.
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
public isolated function trimToPage(anydata[] rows, Query query) returns boolean {
    if rows.length() > query.size {
        rows.setLength(query.size);
        return true;
    }
    return false;
}

# Builds the query that reads the related records of a relation named in `fields`: for a to-one relation, those of
# every record of a page; for a to-many relation, those of one record, one more than `config.size` in key order.
#
# + entity - The entity of the records
# + relation - The relation field
# + sources - The records, holding at least the fields that link the relation
# + config - The page sizes of the data service
# + return - The query
public isolated function toIncludeQuery(Entity entity, string relation, map<anydata>[] sources, PageConfig config)
        returns Query {
    Relation related = relationOf(entity, relation);
    int size = related.many ? config.size : sources.length();
    return {
        whereClause: whereClause(related.target, linkFilter(related, sources)),
        orderByClause: <sql:ParameterizedQuery>orderByClause(related.target, []),
        limitClause: related.many ? `${size + 1}` : ``,
        offsetClause: ``,
        size
    };
}

# Tells whether `fields` names a relation, alone or with its fields.
#
# + fields - The field names to return
# + relation - The relation field
# + return - Whether the related records are included
public isolated function isIncluded(string[]? fields, string relation) returns boolean =>
    fields is string[] && fields.some(name => name == relation || name.startsWith(relation + "."));

# Adds the related record of a to-one relation to each narrowed record of a page, or nil when it has none.
#
# + partials - The narrowed records, which are changed in place
# + sources - The records as read, in the same order
# + entity - The entity of the records
# + relation - The relation field
# + related - The records that `toIncludeQuery` read
# + fields - The field names to return
public isolated function attachOne(map<anydata>[] partials, map<anydata>[] sources, Entity entity, string relation,
        map<anydata>[] related, string[] fields) {
    Relation rel = relationOf(entity, relation);
    string[] names = relatedFields(rel, fields);
    foreach int i in 0 ..< partials.length() {
        anydata[] link = from string name in rel.fields select sources[i][name];
        map<anydata>? found = ();
        foreach map<anydata> row in related {
            if (from string name in rel.targetFields select row[name]) == link {
                found = row;
                break;
            }
        }
        partials[i][rel.'field] = found is () ? () : selectFields(found, rel.target, names);
    }
}

# Adds the related records of a to-many relation to one narrowed record, as a list with `hasMore`.
#
# + partial - The narrowed record, which is changed in place
# + entity - The entity of the record
# + relation - The relation field
# + related - The records that `toIncludeQuery` read, cut to the page by `trimToPage`
# + hasMore - Whether more related records exist
# + fields - The field names to return
public isolated function attachMany(map<anydata> partial, Entity entity, string relation, map<anydata>[] related,
        boolean hasMore, string[] fields) {
    Relation rel = relationOf(entity, relation);
    string[] names = relatedFields(rel, fields);
    partial[rel.'field] = {
        items: from map<anydata> row in related select selectFields(row, rel.target, names),
        hasMore
    };
}

# Builds the error body for a to-one relation with no related record.
#
# + entity - The entity of the record
# + relation - The relation field
# + key - The values of the record's key fields, in key order
# + return - The `NOT_FOUND` error body
public isolated function relatedNotFound(Entity entity, string relation, KeyValue[] key) returns DataserviceError => {
    code: NOT_FOUND,
    message: string `The record with the key '${keyText(key)}' of the entity '${entity.name}' has no '${relation}'.`
};

# Checks the `fields` option of a read.
#
# + entity - The entity to read
# + fields - The field names to return
# + relations - Whether `fields` can name the entity's relations and their fields, such as `department.name`
# + return - An `INVALID_INPUT` error body when `fields` is empty or names a field that cannot be returned
public isolated function checkFields(Entity entity, string[]? fields, boolean relations = true)
        returns DataserviceError? {
    if fields is () {
        return ();
    }
    string[] names = from string name in fields where name != "" select name;
    if names.length() == 0 {
        return invalidInput("'fields' must name at least one field.");
    }
    foreach string name in names {
        int? dot = name.indexOf(".");
        Relation? related = relations ? findRelation(entity, dot is int ? name.substring(0, dot) : name) : ();
        boolean usable = dot is int ? related is Relation && findField(related.target, name.substring(dot + 1)) !is ()
            : findField(entity, name) !is () || related is Relation;
        if !usable {
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
public isolated function selectFields(map<anydata> value, Entity entity, string[] fields) returns map<anydata> {
    map<anydata> narrowed = {};
    foreach Field 'field in entity.fields {
        if ('field.key || fields.indexOf('field.name) !is ()) && value.hasKey('field.name) {
            narrowed['field.name] = value['field.name];
        }
    }
    return narrowed;
}

isolated function relatedFields(Relation relation, string[] fields) returns string[] {
    if fields.indexOf(relation.'field) !is () {
        return from Field 'field in relation.target.fields select 'field.name;
    }
    string prefix = relation.'field + ".";
    return from string name in fields where name.startsWith(prefix) select name.substring(prefix.length());
}

// Matches the related records of the sources; a source whose link has a nil value has none.
isolated function linkFilter(Relation relation, map<anydata>[] sources) returns Filter {
    Field[] targetFields = from string name in relation.targetFields select <Field>findField(relation.target, name);
    KeyValue[][] links = [];
    foreach map<anydata> item in sources {
        anydata[] link = from string name in relation.fields select item[name];
        if link.every(value => value is KeyValue) {
            links.push(from anydata value in link select <KeyValue>value);
        }
    }
    return matchFilter(targetFields, links);
}

isolated function matchFilter(Field[] fields, KeyValue[][] tuples) returns Filter {
    if fields.length() == 1 {
        return {'field: fields[0], operator: "anyOf", values: from KeyValue[] tuple in tuples select tuple[0]};
    }
    return {
        matchAll: false,
        filters: from KeyValue[] tuple in tuples
            select <Group>{
                matchAll: true,
                filters: from int i in 0 ..< fields.length()
                    select <Condition>{'field: fields[i], operator: "eq", values: [tuple[i]]}
            }
    };
}

isolated function relationOf(Entity entity, string name) returns Relation {
    Relation? relation = findRelation(entity, name);
    if relation is () {
        panic error(string `The entity '${entity.name}' has no relation '${name}'.`);
    }
    return relation;
}

isolated function findRelation(Entity entity, string name) returns Relation? {
    foreach Relation relation in entity.relations {
        if relation.'field == name {
            return relation;
        }
    }
    return ();
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
    if filter is Group && filter.matchAll && filter.filters.length() == 0 {
        return ``;
    }
    return filterSql(entity, filter);
}

isolated function filterSql(Entity entity, Filter filter) returns sql:ParameterizedQuery {
    if filter is Group && filter.filters.length() == 0 {
        return filter.matchAll ? `1 = 1` : `1 = 0`;
    }
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
