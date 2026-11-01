# Specification: Ballerina Data Service Library

_Owners_: @niveathika  
_Reviewers_:  
_Created_: 2026/10/22  
_Updated_: 2026/10/23  
_Edition_: Swan Lake

## Introduction

This is the specification for the `ballerina/dataservice` package of the [Ballerina language](https://ballerina.io/).
The package supports the data services that `bal persist` generates from a persist model. It holds the annotation
that selects what a data service exposes, and the protocol-neutral runtime that generated services call: the error
body and codes, the mapping from persist errors to them, and the value conversions every protocol shares. Each
protocol has its own package, such as `ballerina/dataservice.http`. How the persist tool generates a service is
specified in the [persist tool specification](https://github.com/ballerina-platform/persist-tools/blob/main/docs/spec/spec.md#7-data-service-generation).

The functions that generated code calls are a stable API. New behaviour is added through new functions or optional
parameters.

The conforming implementation of the specification is released and included in the distribution. Any deviation from
the specification is considered a bug.

## Contents

* [1. The `Expose` annotation](#1-the-expose-annotation)
* [2. Errors](#2-errors)
    * [2.1. The error body](#21-the-error-body)
    * [2.2. Mapping persist errors](#22-mapping-persist-errors)
    * [2.3. Checking keys](#23-checking-keys)
    * [2.4. Auth errors](#24-auth-errors)
* [3. Value conversions](#3-value-conversions)
* [4. Compiler plugin](#4-compiler-plugin)
* [5. Paging](#5-paging)
* [6. Field rules](#6-field-rules)
* [7. Queries](#7-queries)
    * [7.1. The entity description](#71-the-entity-description)
    * [7.2. Query options](#72-query-options)
    * [7.3. Reading by keys](#73-reading-by-keys)
    * [7.4. Fields](#74-fields)
    * [7.5. Relations](#75-relations)
* [8. Constraints](#8-constraints)

## 1. The `Expose` annotation

```ballerina
public enum Operation {
    READ = "read",
    CREATE = "create",
    UPDATE = "update",
    DELETE = "delete"
}

public type Scopes record {|
    string[] read?;
    string[] create?;
    string[] update?;
    string[] delete?;
|};

public type ExposeConfig record {|
    [Operation, Operation...] operations = [READ, CREATE, UPDATE, DELETE];
    Scopes scopes?;
|};

public const annotation ExposeConfig Expose on source type;
```

An entity of a persist model is exposed by a data service only when its record type has the `@dataservice:Expose`
annotation. The entity then allows the actions in `operations`, which are every action by default.

| Annotation | Exposed | Actions |
|---|---|---|
| none | no | — |
| `@dataservice:Expose` | yes | `read`, `create`, `update`, `delete` |
| `@dataservice:Expose {operations: [dataservice:READ, dataservice:UPDATE]}` | yes | `read`, `update` |

Each action enables these operations:

| Action | Operations |
|---|---|
| `read` | Get many, get one, get related |
| `create` | Create one, create many |
| `update` | Patch one |
| `delete` | Delete one |

`Expose` is a constant annotation. Its value is evaluated at compile time and is not kept at runtime. The type of
`operations` requires at least one operation, so an empty list is a compile error. An operation is written as an
`Operation` member, such as `dataservice:READ`, or as its string value, such as `"read"`.

`scopes` gives the scopes each action requires when `options.dataservice.auth` is `true`. A caller needs any one scope
of an action's list, and an empty list requires only an authenticated caller. An action not listed requires
`<resource>:<action>`, where `<resource>` is the entity's persist resource name, as in `employees:read`. Without auth,
no scope is checked.

Whether a data service is generated is decided by `options.dataservice` in the `[[tool.persist]]` entry of
`Ballerina.toml`. The annotations only select what the service exposes.

## 2. Errors

### 2.1. The error body

```ballerina
public enum ErrorCode {
    NOT_FOUND,
    CONFLICT,
    CONSTRAINT_VIOLATION,
    INVALID_INPUT,
    UNAUTHENTICATED,
    FORBIDDEN,
    INTERNAL
}

public type DataserviceError record {|
    ErrorCode code;
    string message;
|};
```

A data service error falls into one of these categories. Each protocol package maps a category to its own form, such
as an HTTP status code, and answers every error with this body, including those its protocol module raises before the
operation runs.

| Category | `code` | Raised when | Source |
|---|---|---|---|
| Not found | `NOT_FOUND` | No record has the given key | `persist:NotFoundError` |
| Conflict | `CONFLICT` | A record with the key or a unique value already exists | `persist:AlreadyExistsError` |
| Constraint violation | `CONSTRAINT_VIOLATION` | A write violates a foreign key | `persist:ConstraintViolationError` |
| Invalid input | `INVALID_INPUT` | The input cannot be bound to the operation's type, a value is not in its format or breaks a constraint, a key is not a finite number, or a create holds too many records | The protocol module's binding error, a [`ConversionError`](#3-value-conversions), [`checkFiniteKey`](#23-checking-keys) or [`checkCreateSize`](#5-paging) |
| Unauthenticated | `UNAUTHENTICATED` | With auth, the caller has no credential, or one that no provider accepts | [`unauthenticated`](#24-auth-errors) |
| Forbidden | `FORBIDDEN` | With auth, the caller holds no scope of the operation's action, or, for get related or a relation in `fields`, no `read` scope of the related entity | [`noScope`](#24-auth-errors) or [`forbidden`](#24-auth-errors) |
| Internal | `INTERNAL` | Any other failure | `persist:Error` and others |

### 2.2. Mapping persist errors

```ballerina
public type KeyValue int|string|float|decimal|boolean;

public isolated function toErrorBody(error err, string entity = "", KeyValue[] key = [])
        returns DataserviceError;
```

`toErrorBody` maps an error that the persist client returned to the error body. `entity` is the entity's
name and `key` holds the values of the record's key fields, in key order. The message is written by this function, not
taken from the error, because the SQL datastores put driver text, such as table and constraint names, in their error
messages:

| Error | `code` | `message` |
|---|---|---|
| `persist:NotFoundError` | `NOT_FOUND` | `A record with the key '<key>' does not exist for the entity '<Entity>'.` |
| `persist:AlreadyExistsError` | `CONFLICT` | `A record that conflicts with an existing record of the entity '<Entity>' already exists.` |
| `persist:ConstraintViolationError` | `CONSTRAINT_VIOLATION` | `The operation violates a constraint of the entity '<Entity>'.` |
| Any other error | `INTERNAL` | `An internal error occurred.` |

`<key>` is each key value written with `toString`, joined by `/` in key order, so the composite key `["P1", 1]` is
written `P1/1`, `1.5` stays `1.5`, and a `decimal` keeps its scale.

For a constraint violation and an internal error, the function logs the error, with the entity's name, at the `ERROR`
level. The error's own message is not returned to the caller.

### 2.3. Checking keys

```ballerina
public isolated function checkFiniteKey(string entity, KeyValue[] key) returns DataserviceError?;
```

`checkFiniteKey` returns an `INVALID_INPUT` error body when a `float` value of the key is `NaN` or infinite, with the
message `The key '<key>' of the entity '<Entity>' is not a finite number.`, where `<key>` is written as in
[2.2](#22-mapping-persist-errors). A protocol calls it before it reads, updates or deletes a record by a key that has a
`float` field.

### 2.4. Auth errors

```ballerina
public isolated function unauthenticated() returns DataserviceError;
public isolated function noScope() returns DataserviceError;
public isolated function forbidden(string entity, string relation, string target) returns DataserviceError;
```

`unauthenticated` returns the `UNAUTHENTICATED` error body with the message `The request needs a valid credential.`,
and `noScope` the `FORBIDDEN` error body with the message `The caller holds no scope that the operation needs.` A
protocol package answers its protocol module's auth errors with them.

`forbidden` returns the `FORBIDDEN` error body with the message
`The relation '<relation>' of the entity '<Entity>' needs a 'read' scope of the entity '<Target>'.`
With auth, get related and a relation in `fields` require the entity's own `read` scopes. When those do not cover the
related entity's, because the related entity's `read` list is not empty and the entity's list is empty or holds a
scope the related entity's does not, the protocol module checks the caller's credential against the related entity's
`read` scopes, and answers with this body when it holds none of them.

## 3. Value conversions

The JSON form that Ballerina gives `byte[]` and the `time:*` record types does not suit a client: `time:Utc` is a tuple,
the other `time:*` types are records, and `byte[]` is an array of numbers. A protocol that sends these values as JSON
uses the following functions, so that every protocol uses the same formats.

```ballerina
public type ConversionErrorDetail record {|
    string format;
    string 'field?;
|};

public type ConversionError distinct error<ConversionErrorDetail>;
```

| Type | To string | From string | Format | `format` in `ConversionError` |
|---|---|---|---|---|
| `byte[]` | `bytesToString` | `bytesFromString` | Base64, RFC 4648 standard alphabet, padded | `a base64 string` |
| `time:Date` | `dateToString` | `dateFromString` | `2024-01-02` | `an ISO 8601 date` |
| `time:TimeOfDay` | `timeOfDayToString` | `timeOfDayFromString` | `10:15:30` or `10:15:30.5` | `an ISO 8601 time` |
| `time:Civil` | `civilToString` | `civilFromString` | `2024-01-02T10:15:30`, without an offset | `an ISO 8601 date-time` |
| `time:Utc` | `utcToString` | `utcFromString` | `2024-01-02T10:15:30Z` | `an ISO 8601 date-time` |

Each `<type>ToString` function takes a value of the type and returns its string form. Each `<type>FromString` function
takes a string and returns a value of the type, or a `ConversionError` whose message is `The value is not <format>.`
and whose detail holds the format. A `ConversionError` for a value of a query option also holds the field the value is
given for; see [7.2](#72-query-options).

- **`byte[]`:** the string must use the standard alphabet and padding. An unpadded string is a `ConversionError`.
- **`time:Date`:** written as `YYYY-MM-DD`. The string must be a valid calendar date.
- **`time:TimeOfDay`:** written as `HH:MM:SS`, followed by the fraction of a second only when it is not zero. A missing
  `second` is written as `00`. The string must be `HH:MM:SS` with an optional fraction; `HH:MM` alone is a
  `ConversionError`.
- **`time:Civil`:** the date and the time joined by `T`. An offset in the value is not written. A string with an
  offset, including `Z`, is a `ConversionError`.
- **`time:Utc`:** written with `time:utcToString`. A string with the offset `Z` or `+hh:mm` is accepted and converted
  to UTC, as `time:utcFromString` does.

## 4. Compiler plugin

A persist model is not compiled with its package: `bal build` reads it through the persist tool, and the compiler sees
it only when the file is compiled on its own, as the IDE does. The compiler plugin validates the annotations of such a
file, and the persist tool repeats the same checks every time it generates a data service.

The plugin acts only on a single-file project whose file is in a package's `persist` directory, `persist/<file>`, or
in a named model's directory, `persist/<model>/<file>`, where the directory above `persist` holds `Ballerina.toml`.
It does nothing in any other source.

| Check | Reported by | Message |
|---|---|---|
| `@dataservice:Expose` is on a record type | The plugin, `DATASERVICE_101` | `the @dataservice:Expose annotation is allowed only on a record type in the persist model.` |
| `operations` is non-empty and has only `Operation` values | The compiler, through the type of `operations` | The compiler's type error |
| `operations` has no duplicates | The plugin, `DATASERVICE_102` | `duplicate operation '<value>' in the @dataservice:Expose annotation of the entity '<Entity>'.` |

| Each scope is non-empty and has no whitespace | The plugin, `DATASERVICE_110` | `invalid scope '<value>' in the @dataservice:Expose annotation of the entity '<Entity>'.` |
| `scopes` names only actions in `operations` | The plugin, `DATASERVICE_111` | `the @dataservice:Expose annotation of the entity '<Entity>' sets scopes for '<action>', which is not in 'operations'.` |

`<value>` is the repeated operation as it is written, such as `dataservice:READ` or `"read"`. An operation written
as a member and as its string value is a duplicate. Each repeat is reported.

The plugin also checks the [field rules](#6-field-rules):

| Check | Code | Message |
|---|---|---|
| At most one rule on a field | `DATASERVICE_103`, error | `the field '<field>' of the entity '<Entity>' has more than one of @dataservice:ReadOnly, @dataservice:Immutable and @dataservice:Internal.` |
| No rule on a key field, except `ReadOnly` on a `@sql:Generated` key | `DATASERVICE_104`, error | `the key field '<field>' of the entity '<Entity>' cannot have @dataservice:<rule>.` |
| `ReadOnly` or `Internal` gives `value` on a field that is neither nullable nor generated | `DATASERVICE_105`, error | `the field '<field>' of the entity '<Entity>' needs a 'value' in @dataservice:<rule>, because it is neither nullable nor generated.` |
| `value` is of the field's type | `DATASERVICE_106`, error | `the 'value' in @dataservice:<rule> of the field '<field>' of the entity '<Entity>' is not a '<type>'.` |
| No `ReadOnly` or `Immutable` on a relation field | `DATASERVICE_107`, error | `@dataservice:<rule> cannot be used on the relation field '<field>' of the entity '<Entity>'. Use it on the foreign key field, declared with @sql:Relation.` |
| The foreign key fields of one relation have the same rule | `DATASERVICE_108`, error | `the foreign key fields of the relation '<relation>' of the entity '<Entity>' must have the same field rule.` |
| No `ReadOnly` or `Internal` on the foreign key of a one-to-one relation when the entity allows `create` | `DATASERVICE_112`, error | `@dataservice:<rule> cannot be used on the foreign key field '<field>' of the entity '<Entity>', because its relation is one to one and every create would set the same value.` |
| The entity allows an action the rule affects | `DATASERVICE_109`, warning | `@dataservice:<rule> on the field '<field>' of the entity '<Entity>' has no effect, because the entity does not allow '<actions>'.` |

A relation is one to one when neither of its relation fields is an array. `<actions>` names the actions the rule
affects, joined by `' or '`: `update` for `Immutable`, `create` and `update` for `ReadOnly`, `read`, `create` and
`update` for `Internal`, and `read` for `Internal` on a relation field.

## 5. Paging

```ballerina
public type PageConfig readonly & record {|
    int size;
    int maxSize;
|};

public isolated function pageConfig(int size, int maxSize) returns PageConfig|error;
public isolated function checkCreateSize(int count, PageConfig config) returns DataserviceError?;
```

A generated service declares its page sizes as the `pageSize` and `maxPageSize` fields of its configurable
`dataserviceConfig` record, and checks them at startup with a module-level `check` on `pageConfig`, so the program
stops when a value is out of range:

| Case | Message |
|---|---|
| `maxSize` below 1 | `The configurable value 'dataserviceConfig.maxPageSize' must be at least 1, found <value>.` |
| `size` below 1 or above `maxSize` | `The configurable value 'dataserviceConfig.pageSize' must be between 1 and 'dataserviceConfig.maxPageSize' (<max>), found <value>.` |

`size` is the number of records in a page when the caller gives no size. `maxSize` is the largest page, and the most
records that one create can hold. `checkCreateSize` returns an `INVALID_INPUT` error body with the message
`A create can hold at most <max> records.` when `count` is above `maxSize`.

## 6. Field rules

```ballerina
public type FieldRuleConfig record {|
    anydata value?;
|};

public const annotation FieldRuleConfig ReadOnly on source record field;
public const annotation Immutable on source record field;
public const annotation FieldRuleConfig Internal on source record field;
```

A field rule on a model field says what a data service does with the field:

| Annotation | Returned | Accepted on create | Accepted on update |
|---|:-:|:-:|:-:|
| `ReadOnly` | yes | no, ignored | no, ignored |
| `Immutable` | yes | yes | no, rejected |
| `Internal` | no | no, rejected | no, rejected |

The service sets a `ReadOnly` or `Internal` field on create to the annotation's `value`, or to `()` without one. A
foreign key field declared with `@sql:Relation` takes the rules like any field. A relation field takes only
`Internal`, which withholds that direction of the relation; an `Internal` foreign key withholds both directions.

## 7. Queries

A data service reads records through the persist SQL client's `whereClause`, `orderByClause`, `limitClause` and
`offsetClause`. This module validates the query options of a read and writes those clauses from a description of the
entity. Values are bound as parameters; field and column names come only from the description.

### 7.1. The entity description

```ballerina
public enum Datastore {
    MYSQL,
    MSSQL,
    POSTGRESQL,
    H2
}

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

public type Field record {|
    string name;
    string column;
    FieldType 'type;
    boolean nullable = false;
    boolean key = false;
    boolean generated = false;
|};

public type Entity readonly & record {|
    string name;
    string collection;
    string 'resource;
    Datastore datastore;
    Field[] fields;
    Relation[] relations = [];
|};

public type Relation record {|
    string 'field;
    boolean many;
    string[] fields;
    string[] targetFields;
    Entity target;
|};
```

The generated service holds one `Entity` per exposed entity. `fields` holds, in model order, the fields that callers
can see; a field with the `Internal` rule is left out, so no query option can use it. `name` is the entity name, which
the persist SQL client also uses as the table alias, and `column` is the field's column name. `collection` is the
entity's collection name in the service, such as `projectAssignments`, and `'resource` is its persist resource name,
such as `projectassignments`.

`relations` holds the relations that callers can read: those whose related entity is also read by the service and
that no `Internal` rule hides. `fields` and `targetFields` pair the fields that link the two entities: the foreign key
fields and the related entity's key on the owning side, and the key and the related entity's foreign key fields on the
other side. `target` describes the related entity with its own fields and no relations, so every read is one hop.

### 7.2. Query options

```ballerina
public type Query record {|
    sql:ParameterizedQuery whereClause;
    sql:ParameterizedQuery orderByClause;
    sql:ParameterizedQuery limitClause;
    sql:ParameterizedQuery offsetClause;
    int size;
|};

public isolated function query(Entity entity, PageConfig config, map<map<anydata>>? filter = (),
        string[]? sort = (), int? size = (), int? offset = ()) returns Query|DataserviceError|ConversionError;
public isolated function page(anydata[] rows, Query query) returns boolean;
```

`query` validates the options and returns the clauses to pass to the persist client.

- **Filter:** a map from field name to a map from operator to value. Every condition must hold. A field of type
  `BYTES` cannot be filtered.

  | Operator | SQL | Field types |
  |---|---|---|
  | `eq`, `ne` | `=`, `<>` | every type but `BYTES` |
  | `lt`, `lte`, `gt`, `gte` | `<`, `<=`, `>`, `>=` | every type but `BYTES`, `BOOLEAN` and `ENUM` |
  | `anyOf` | `IN (...)`; an empty list matches no record | every type but `BYTES` |
  | `contains`, `startsWith` | `LIKE` with `ESCAPE '!'` | `STRING` |
  | `isNull` | `IS NULL` for `true`, `IS NOT NULL` for `false` | nullable fields |

  A value of a `DATE`, `TIME_OF_DAY`, `CIVIL` or `UTC` field is the string form of [3](#3-value-conversions). In
  `contains` and `startsWith`, `%`, `_` and `!` match themselves, as does `[` on MSSQL.
- **Sort:** field names, each descending when it starts with `-`. The key fields not named are added in ascending
  order, so the order is total. Nulls sort last in ascending order and first in descending order: with
  `NULLS LAST` and `NULLS FIRST` on PostgreSQL and H2, and with a `CASE WHEN ... IS NULL` term on MySQL and MSSQL. An
  empty name is ignored.
- **Size:** `config.size` when not given, and `config.maxSize` when larger. `limitClause` reads one row more than the
  page, and `page` removes that row from the rows read and returns whether it was there.
- **Offset:** `0` when not given, in which case `offsetClause` is empty.
- **Identifiers:** written as `` `name` `` on MySQL, `[name]` on MSSQL and `"name"` on PostgreSQL and H2, with the
  quote character doubled inside a name, and qualified by the entity name.

`query` returns an `INVALID_INPUT` error body for invalid options:

| Case | Message |
|---|---|
| An unknown field, or one that cannot be used for the option | `The field '<field>' of the entity '<Entity>' cannot be used in '<filter\|sort>'.` |
| An operator that does not apply to the field's type | `The operator '<operator>' cannot be used on the field '<field>' of the entity '<Entity>'.` |
| A field named more than once in `sort` | `The field '<field>' is named more than once in 'sort'.` |
| A size below 1 | `The page size must be at least 1.` |
| An offset below 0 | `The offset must be at least 0.` |
| An offset for which `offset + size` exceeds the largest integer | `The offset and the page size together exceed the largest integer.` |

A filter value that does not parse, or is not of the field's type, is returned as a `ConversionError` whose detail
holds the field name, so that a protocol writes its own message for it.

### 7.3. Reading by keys

```ballerina
public isolated function keysQuery(Entity entity, KeyValue[][] keys) returns Query;
public isolated function orderByKeys(map<anydata>[] rows, Entity entity, KeyValue[][] keys) returns error?;
```

`keysQuery` returns the query that reads the records with the given keys, in key order, without a limit. A single key
matches with `IN`; a composite key matches with `OR` over the key tuples. A create reads its records back with it, and
`orderByKeys` then puts them in the order of the given keys, in place. It returns an error when a key has no record.

### 7.4. Fields

```ballerina
public isolated function checkFields(Entity entity, string[]? fields) returns DataserviceError?;
public isolated function narrow(map<anydata> value, Entity entity, string[] fields) returns map<anydata>;
```

`checkFields(entity, fields, relations = true)` returns an `INVALID_INPUT` error body when `fields` names no field, with
the message
`'fields' must name at least one field.`, or names a field that is not in the description, with the message
`The field '<field>' of the entity '<Entity>' cannot be used in 'fields'.`. Empty names are ignored. With
`relations`, `fields` can also name a relation, which includes the whole related record, or a field of the related
entity as `<relation>.<field>`. A relation of the related entity, such as `department.employees`, cannot be named.
`narrow` keeps the key fields and the named fields of a record, in model order. A record is read in full and then
narrowed.

### 7.5. Relations

```ballerina
public isolated function relatedQuery(Entity entity, string relation, map<anydata> row, PageConfig config,
        map<map<anydata>>? filter = (), string[]? sort = (), int? size = (), int? offset = ())
        returns Query|DataserviceError|ConversionError;
public isolated function noRelated(Entity entity, string relation, KeyValue[] key) returns DataserviceError;
public isolated function includes(string[]? fields, string relation) returns boolean;
public isolated function includeQuery(Entity entity, string relation, map<anydata>[] sources, PageConfig config)
        returns Query;
public isolated function attachOne(map<anydata>[] partials, map<anydata>[] sources, Entity entity, string relation,
        map<anydata>[] related, string[] fields);
public isolated function attachMany(map<anydata> partial, Entity entity, string relation, map<anydata>[] related,
        boolean hasMore, string[] fields);
```

- **Get related:** `relatedQuery` reads the records related to `row`, which holds the fields that link the relation:
  the foreign key on the owning side, or the key on the other side. It takes the query options of
  [7.2](#72-query-options) on the related entity, and its errors name the related entity. A link with a nil value
  matches no record.
- **Empty to-one:** `noRelated` returns the `NOT_FOUND` body
  `The record with the key '<key>' of the entity '<Entity>' has no '<relation>'.`
- **Relations in `fields`:** `includes` tells whether `fields` names a relation. For a to-one relation,
  `includeQuery` reads the related records of a whole page with one query whose filter is `anyOf` their links, and
  `attachOne` adds each record's related record to its narrowed record, or nil when there is none. For a to-many
  relation, `includeQuery` reads the related records of one record, `config.size` plus one in key order, `page` cuts
  them, and `attachMany` adds them as `{"items": [...], "hasMore": ...}`. The related records are narrowed to the
  `<relation>.<field>` names, or kept whole when the relation is named alone.
- **Composite links** match as `OR` over the link tuples.

## 8. Constraints

```ballerina
public isolated function checkConstraints(record {} value, string entity) returns DataserviceError?;
```

A protocol whose wire types hold dates, times and `byte[]` values as strings cannot check the model's
`ballerina/constraint` annotations on those fields on the request. It converts the request to the persist type, which
carries the annotations, and checks the result with `checkConstraints`. It returns `()` when every constraint holds,
and otherwise an `INVALID_INPUT` error body for the first broken one, with the message
`The field '<field>' of the entity '<Entity>' breaks its '<constraint>' constraint.`, where `<constraint>` is the
name `ballerina/constraint` gives it, such as `maxLength` or `pastDate`.

