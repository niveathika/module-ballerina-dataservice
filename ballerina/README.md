# Ballerina Data Service Library

## Overview

The `ballerina/dataservice` package supports the data services that `bal persist` generates from a persist model. A data service exposes the entities of the model over a protocol such as HTTP, with no hand-written service code.

The package holds the `@dataservice:Expose` annotation, which selects the entities a data service exposes and the actions each allows, and the protocol-neutral runtime that generated services call.

## Quick start

1. Add the persist entry with a data service to the package:

    ```bash
    bal persist add --datastore h2 --dataservice http
    ```

2. Annotate each entity to expose in `persist/model.bal`. A bare annotation allows every action:

    ```ballerina
    import ballerina/dataservice;
    import ballerina/persist as _;

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

3. Build the package. The persist client and the data service are generated into `generated/`:

    ```bash
    bal build
    ```

For the details, see the [specification](https://github.com/ballerina-platform/module-ballerina-dataservice/blob/main/docs/spec/spec.md).
