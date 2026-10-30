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


# The page sizes of a data service.
#
# + size - The number of records in a page when the caller gives no size
# + maxSize - The largest page, and the most records one create can hold
public type PageConfig readonly & record {|
    int size;
    int maxSize;
|};

# Checks the page sizes that a data service is configured with.
#
# + size - The value of `dataserviceConfig.pageSize`
# + maxSize - The value of `dataserviceConfig.maxPageSize`
# + return - The page sizes, or an error naming the value that is out of range
public isolated function pageConfig(int size, int maxSize) returns PageConfig|error {
    if maxSize < 1 {
        return error(string `The configurable value 'dataserviceConfig.maxPageSize' must be at least 1, ` +
                string `found ${maxSize}.`);
    }
    if size < 1 || size > maxSize {
        return error(string `The configurable value 'dataserviceConfig.pageSize' must be between 1 and ` +
                string `'dataserviceConfig.maxPageSize' (${maxSize}), found ${size}.`);
    }
    return {size, maxSize};
}

# Checks that a create holds no more records than a page.
#
# + count - The number of records to create
# + config - The page sizes of the data service
# + return - An `INVALID_INPUT` error body when there are too many records
public isolated function checkCreateSize(int count, PageConfig config) returns DataserviceError? {
    if count > config.maxSize {
        return {code: INVALID_INPUT, message: string `A create can hold at most ${config.maxSize} records.`};
    }
    return ();
}
