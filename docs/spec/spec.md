# Specification: Ballerina Data Service Library

_Authors_: @niveathika \
_Reviewers_: TBD \
_Created_: 2026/10/07 \
_Updated_: 2026/10/12 \
_Edition_: Swan Lake

## Introduction

This is the specification for the `dataservice` library of the [Ballerina language](https://ballerina.io/). The library supports data services that `bal persist` generates over a persist model, as defined in the [data service proposal](https://github.com/ballerina-platform/ballerina-spec/issues/1503).

The library does not generate or run a service. It provides:

- the `@dataservice:Expose` annotation, which a persist model uses to expose an entity and choose its actions,
- a compiler plugin that validates the annotation, and
- the protocol-neutral types that generated data services return.

The library does not depend on any protocol module. Types that are specific to an entity or to a protocol are generated with the service.

## Contents

1. [Operations](#1-operations)
2. [The `Expose` annotation](#2-the-expose-annotation)
3. [Compiler validation](#3-compiler-validation)
4. [Errors](#4-errors)

## 1. Operations

An `Operation` is an action that a data service allows on an entity.

```ballerina
public enum Operation {
    READ = "read",
    CREATE = "create",
    UPDATE = "update",
    DELETE = "delete"
}
```

Each action enables a fixed set of operations:

| Action | Operations |
|---|---|
| `READ` | Get many, get one |
| `CREATE` | Create one, create many |
| `UPDATE` | Patch one |
| `DELETE` | Delete one |

## 2. The `Expose` annotation

```ballerina
public type ExposeConfig record {|
    [Operation, Operation...] operations?;
|};

public const annotation ExposeConfig Expose on source type;
```

The annotation is placed on an entity in a persist model. Exposure is opt-in: a data service exposes an entity only when the entity has the annotation. The entity allows the actions in `operations`. Without `operations`, it allows the actions in `options.dataservice.operations` of `Ballerina.toml`, or every action when that is not set either.

`Expose` is a constant annotation: its value is evaluated at compile time and is not available at runtime. `operations` is therefore a constant expression, such as a list constructor or a constant declared in the model, and it cannot be empty.

```ballerina
import ballerina/persist as _;
import ballerina/dataservice;

@dataservice:Expose
type Employee record {|
    readonly int id;
    string name;
|};

@dataservice:Expose {operations: [dataservice:READ]}
type Department record {|
    readonly int id;
    string name;
|};
```

`Department` allows only reads. `Employee` allows the actions set in `Ballerina.toml`, or every action. An entity without the annotation is not exposed.

An operation may be written as an `Operation` member or as its string value. `dataservice:READ` and `"read"` are the same operation.

## 3. Compiler validation

An empty `operations` list and an unknown operation are type errors. In addition, the compiler plugin reports the following errors.

| Code | Reported when |
|---|---|
| `DATASERVICE_101` | `@dataservice:Expose` is used on a type that is not a record type in a persist model. A persist model is a file in the package's `persist` directory, or in a subdirectory of it, compiled as a single file. |
| `DATASERVICE_102` | `operations` lists the same operation more than once, including through a constant. |

Checks that need the whole model, such as a data service that exposes no entity, are made by `bal persist` when it generates the service.

## 4. Errors

A generated data service returns errors in one body, with a code for each category.

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

| Code | Raised when |
|---|---|
| `NOT_FOUND` | No record has the given key. |
| `CONFLICT` | A record with the key or a unique value already exists. |
| `CONSTRAINT_VIOLATION` | A write violates a foreign key. |
| `INVALID_INPUT` | The input cannot be bound to the operation's type. |
| `INTERNAL` | Any other failure. The detail is logged and not returned. |

How each code is carried, such as an HTTP status code, is defined by the protocol of the generated service.
