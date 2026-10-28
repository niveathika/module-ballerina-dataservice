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
* [3. Value conversions](#3-value-conversions)
* [4. Compiler plugin](#4-compiler-plugin)
* [5. Paging](#5-paging)
* [6. Field rules](#6-field-rules)

## 1. The `Expose` annotation

```ballerina
public enum Operation {
    READ = "read",
    CREATE = "create",
    UPDATE = "update",
    DELETE = "delete"
}

public type ExposeConfig record {|
    [Operation, Operation...] operations = [READ, CREATE, UPDATE, DELETE];
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
| `read` | Get many, get one |
| `create` | Create one, create many |
| `update` | Patch one |
| `delete` | Delete one |

`Expose` is a constant annotation. Its value is evaluated at compile time and is not kept at runtime. The type of
`operations` requires at least one operation, so an empty list is a compile error. An operation is written as an
`Operation` member, such as `dataservice:READ`, or as its string value, such as `"read"`.

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
    INTERNAL
}

public type DataserviceError record {|
    ErrorCode code;
    string message;
|};
```

A data service error falls into one of these categories. Each protocol package maps a category to its own form, such
as an HTTP status code.

| Category | `code` | Raised when | Source |
|---|---|---|---|
| Not found | `NOT_FOUND` | No record has the given key | `persist:NotFoundError` |
| Conflict | `CONFLICT` | A record with the key or a unique value already exists | `persist:AlreadyExistsError` |
| Constraint violation | `CONSTRAINT_VIOLATION` | A write violates a foreign key | `persist:ConstraintViolationError` |
| Invalid input | `INVALID_INPUT` | The input cannot be bound to the operation's type, a value is not in its format, a key is not a finite number, or a create holds too many records | The protocol module's binding error, a [`ConversionError`](#3-value-conversions), [`checkFiniteKey`](#23-checking-keys) or [`checkCreateSize`](#5-paging) |
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

## 3. Value conversions

The JSON form that Ballerina gives `byte[]` and the `time:*` record types does not suit a client: `time:Utc` is a tuple,
the other `time:*` types are records, and `byte[]` is an array of numbers. A protocol that sends these values as JSON
uses the following functions, so that every protocol uses the same formats.

```ballerina
public type ConversionErrorDetail record {|
    string format;
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
and whose detail holds the format.

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

`<value>` is the repeated operation as it is written, such as `dataservice:READ` or `"read"`. An operation written
as a member and as its string value is a duplicate. Each repeat is reported.

The plugin also checks the [field rules](#6-field-rules):

| Check | Code | Message |
|---|---|---|
| At most one rule on a field | `DATASERVICE_103`, error | `the field '<field>' of the entity '<Entity>' has more than one of @dataservice:ReadOnly, @dataservice:Immutable and @dataservice:Internal.` |
| No rule on a key field, except `ReadOnly` on a `@sql:Generated` key | `DATASERVICE_104`, error | `the key field '<field>' of the entity '<Entity>' cannot have @dataservice:<rule>.` |
| `ReadOnly` or `Internal` gives `value` on a field that is neither nullable nor generated | `DATASERVICE_105`, error | `the field '<field>' of the entity '<Entity>' needs a 'value' in @dataservice:<rule>, because it is neither nullable nor generated.` |
| `value` is of the field's type, or of the related entity's key for a relation field | `DATASERVICE_106`, error | `the 'value' in @dataservice:<rule> of the field '<field>' of the entity '<Entity>' is not a '<type>'.` |
| `ReadOnly` and `Immutable` only on the relation field that holds the foreign key | `DATASERVICE_107`, error | `@dataservice:<rule> cannot be used on the relation field '<field>' of the entity '<Entity>', which has no foreign key.` |
| No rule on a foreign key field declared with `@sql:Relation` | `DATASERVICE_108`, error | `@dataservice:<rule> cannot be used on the foreign key field '<field>' of the entity '<Entity>'. Use it on the relation field '<relation>'.` |
| The entity allows an action the rule affects | `DATASERVICE_109`, warning | `@dataservice:<rule> on the field '<field>' of the entity '<Entity>' has no effect, because the entity does not allow '<actions>'.` |

The relation field holding the foreign key follows persist's rule: the side of a one-to-many relation that is not an
array, and in a one-to-one relation the side that is not optional. `<actions>` names the actions the rule affects,
joined by `' or '`: `update` for `Immutable`, `create` and `update` for `ReadOnly`, and `read`, `create` and `update`
for `Internal`.

## 5. Paging

```ballerina
public type PageConfig readonly & record {|
    int size;
    int maxSize;
|};

public isolated function pageConfig(int size, int maxSize) returns PageConfig|error;
public isolated function checkCreateSize(int count, PageConfig config) returns DataserviceError?;
```

A generated service declares its page sizes as configurable values and checks them at startup with a module-level
`check` on `pageConfig`, so the program stops when a value is out of range:

| Case | Message |
|---|---|
| `maxSize` below 1 | `The configurable value 'dataserviceMaxPageSize' must be at least 1, found <value>.` |
| `size` below 1 or above `maxSize` | `The configurable value 'dataservicePageSize' must be between 1 and 'dataserviceMaxPageSize' (<max>), found <value>.` |

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

The service sets a `ReadOnly` or `Internal` field on create to the annotation's `value`, or to `()` without one. On
the relation field that holds a foreign key, the rule applies to the foreign key fields, and `value` is the related
entity's key, a tuple in key order for a composite key. On the other side of a relation, only `Internal` applies.
