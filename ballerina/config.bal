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

# The runtime settings that every protocol's configuration includes.
#
# + port - The port of the listener
# + pageSize - The number of records in a page when the caller gives no size
# + maxPageSize - The largest page, and the most records one create can hold
public type Config record {|
    int port = 9090;
    int pageSize = 100;
    int maxPageSize = 1000;
|};
