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


import ballerina/test;

@test:Config
function testPageConfig() {
    test:assertEquals(pageConfig(100, 1000), {size: 100, maxSize: 1000});
    test:assertEquals(pageConfig(1, 1), {size: 1, maxSize: 1});
}

@test:Config
function testMaxPageSizeBelowOne() {
    PageConfig|error config = pageConfig(1, 0);
    test:assertTrue(config is error);
    if config is error {
        test:assertEquals(config.message(),
                "The configurable value 'dataserviceConfig.maxPageSize' must be at least 1, found 0.");
    }
}

@test:Config
function testPageSizeOutOfRange() {
    foreach int size in [0, 1001] {
        PageConfig|error config = pageConfig(size, 1000);
        test:assertTrue(config is error);
        if config is error {
            test:assertEquals(config.message(), string `The configurable value 'dataserviceConfig.pageSize' must be ` +
                    string `between 1 and 'dataserviceConfig.maxPageSize' (1000), found ${size}.`);
        }
    }
}

@test:Config
function testCreateSize() returns error? {
    PageConfig config = check pageConfig(2, 3);
    test:assertEquals(checkCreateSize(3, config), ());
    test:assertEquals(checkCreateSize(4, config), {
        code: INVALID_INPUT,
        message: "A create can hold at most 3 records."
    });
}
