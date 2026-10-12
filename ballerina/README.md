## Overview

The `ballerina/dataservice` package supports data services that `bal persist` generates over a persist model. It provides the `@dataservice:Expose` annotation, which exposes an entity in a data service and sets the actions it allows, and the error types that generated data services return.

A data service is enabled in the `[[tool.persist]]` entry of `Ballerina.toml`, and is generated on `bal build`.

## Quick start

1. Enable an HTTP data service in `Ballerina.toml`.

    ```toml
    [[tool.persist]]
    id = "generate-db-client"
    targetModule = "hr"
    filePath = "persist/model.bal"
    options.datastore = "inmemory"
    options.dataservice.protocol = "http"
    ```

2. Expose entities in `persist/model.bal`. `Employee` allows every action and `Department` allows only reads.

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

3. Build and run the package. The service listens on port `9090` under `/api`.

    ```bash
    bal run
    curl http://localhost:9090/api/departments
    ```
