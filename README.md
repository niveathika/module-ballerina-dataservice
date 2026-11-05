# Ballerina Data Service Library

[![Build](https://github.com/ballerina-platform/module-ballerina-dataservice/actions/workflows/build-timestamped-master.yml/badge.svg)](https://github.com/ballerina-platform/module-ballerina-dataservice/actions/workflows/build-timestamped-master.yml)
[![codecov](https://codecov.io/gh/ballerina-platform/module-ballerina-dataservice/branch/main/graph/badge.svg)](https://codecov.io/gh/ballerina-platform/module-ballerina-dataservice)
[![Security Scan](https://github.com/ballerina-platform/module-ballerina-dataservice/actions/workflows/security-scan.yml/badge.svg)](https://github.com/ballerina-platform/module-ballerina-dataservice/actions/workflows/security-scan.yml)
[![GraalVM Check](https://github.com/ballerina-platform/module-ballerina-dataservice/actions/workflows/build-with-bal-test-graalvm.yml/badge.svg)](https://github.com/ballerina-platform/module-ballerina-dataservice/actions/workflows/build-with-bal-test-graalvm.yml)
[![GitHub Last Commit](https://img.shields.io/github/last-commit/ballerina-platform/module-ballerina-dataservice.svg)](https://github.com/ballerina-platform/module-ballerina-dataservice/commits/main)
[![GitHub Issues](https://img.shields.io/github/issues/ballerina-platform/ballerina-library/module/dataservice.svg?label=Open%20Issues)](https://github.com/ballerina-platform/ballerina-library/labels/module%2Fdataservice)

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

## Build from the source

### Setting up the prerequisites

1. Download and install Java SE Development Kit (JDK) version 25. You can download it from either of the following sources:

    * [Oracle JDK](https://www.oracle.com/java/technologies/downloads/)
    * [OpenJDK](https://adoptium.net/)

   > **Note:** After installation, remember to set the `JAVA_HOME` environment variable to the directory where JDK was installed.

2. Download and install [Ballerina Swan Lake](https://ballerina.io/).

3. Export Github Personal access token with read package permissions as follows,

    ```bash
    export packageUser=<Username>
    export packagePAT=<Personal access token>
    ```

### Build options

Execute the commands below to build from the source.

1. To build the package:

   ```bash
   ./gradlew clean build
   ```

2. To run the tests:

   ```bash
   ./gradlew clean test
   ```

3. To build without the tests:

   ```bash
   ./gradlew clean build -x test
   ```

4. To debug the package with a remote debugger:

   ```bash
   ./gradlew clean build -Pdebug=<port>
   ```

5. To debug with the Ballerina language:

   ```bash
   ./gradlew clean build -PbalJavaDebug=<port>
   ```

6. Publish the generated artifacts to the local Ballerina Central repository:

    ```bash
    ./gradlew clean build -PpublishToLocalCentral=true
    ```

7. Publish the generated artifacts to the Ballerina Central repository:

   ```bash
   ./gradlew clean build -PpublishToCentral=true
   ```

## Contribute to Ballerina

As an open-source project, Ballerina welcomes contributions from the community.

For more information, go to the [contribution guidelines](https://github.com/ballerina-platform/ballerina-lang/blob/master/CONTRIBUTING.md).

## Code of conduct

All the contributors are encouraged to read the [Ballerina Code of Conduct](https://ballerina.io/code-of-conduct).

## Useful links

* For more information go to the [`dataservice` package](https://central.ballerina.io/ballerina/dataservice/latest).
* Chat live with us via our [Discord server](https://discord.gg/ballerinalang).
* Post all technical questions on Stack Overflow with the [#ballerina](https://stackoverflow.com/questions/tagged/ballerina) tag.
