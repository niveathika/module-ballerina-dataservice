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
import ballerina/time;

@test:Config
function testBytesRoundTrip() returns error? {
    byte[] value = [0, 1, 2, 250, 255];
    string text = bytesToString(value);
    test:assertEquals(text, "AAEC+v8=");
    test:assertEquals(check bytesFromString(text), value);
    test:assertEquals(bytesToString([]), "");
    test:assertEquals(check bytesFromString(""), []);
}

@test:Config {dataProvider: invalidBase64}
function testInvalidBase64(string value) {
    assertConversionError(bytesFromString(value), "a base64 string");
}

function invalidBase64() returns string[][] => [["AAEC-v8="], ["AAEC+v8"], ["not base64!"]];

@test:Config
function testDateRoundTrip() returns error? {
    test:assertEquals(dateToString({year: 2024, month: 1, day: 2}), "2024-01-02");
    test:assertEquals(check dateFromString("2024-01-02"), {year: 2024, month: 1, day: 2});
    test:assertEquals(check dateFromString("2024-02-29"), {year: 2024, month: 2, day: 29});
}

@test:Config {dataProvider: invalidDates}
function testInvalidDate(string value) {
    assertConversionError(dateFromString(value), "an ISO 8601 date");
}

function invalidDates() returns string[][] =>
    [["2023-02-29"], ["2024-13-01"], ["2024-1-2"], ["02/01/2024"], ["2024-01-02T10:15:30"], [""]];

@test:Config
function testTimeOfDayRoundTrip() returns error? {
    test:assertEquals(timeOfDayToString({hour: 10, minute: 15, second: 30}), "10:15:30");
    test:assertEquals(timeOfDayToString({hour: 10, minute: 15, second: 30.5}), "10:15:30.5");
    test:assertEquals(timeOfDayToString({hour: 10, minute: 15, second: 30.500d}), "10:15:30.5");
    test:assertEquals(timeOfDayToString({hour: 1, minute: 2, second: 3.25}), "01:02:03.25");
    test:assertEquals(timeOfDayToString({hour: 10, minute: 15}), "10:15:00");
    test:assertEquals(check timeOfDayFromString("10:15:30"), {hour: 10, minute: 15, second: 30d});
    test:assertEquals(check timeOfDayFromString("10:15:30.5"), {hour: 10, minute: 15, second: 30.5d});
}

@test:Config
function testTimeOfDayFractionDigits() {
    test:assertEquals(timeOfDayToString({hour: 10, minute: 15, second: 30.0000001d}), "10:15:30.0000001");
    test:assertEquals(timeOfDayToString({hour: 10, minute: 15, second: 30.000000000000000000000000001d}),
        "10:15:30.000000000000000000000000001");
    test:assertEquals(timeOfDayToString({hour: 10, minute: 15, second: 30.1000000d}), "10:15:30.1");
    test:assertEquals(timeOfDayToString({hour: 10, minute: 15, second: 30.0100d}), "10:15:30.01");
    test:assertEquals(timeOfDayToString({hour: 10, minute: 15, second: 30.000d}), "10:15:30");
}

@test:Config {dataProvider: invalidTimes}
function testInvalidTimeOfDay(string value) {
    assertConversionError(timeOfDayFromString(value), "an ISO 8601 time");
}

function invalidTimes() returns string[][] =>
    [["10:15"], ["24:00:00"], ["10:60:00"], ["10:15:60"], ["10:15:30Z"], ["10:15:30."], ["ten"]];

@test:Config
function testCivilRoundTrip() returns error? {
    time:Civil civil = {year: 2024, month: 1, day: 2, hour: 10, minute: 15, second: 30};
    test:assertEquals(civilToString(civil), "2024-01-02T10:15:30");
    time:Civil withOffset = {year: 2024, month: 1, day: 2, hour: 10, minute: 15, second: 30, utcOffset: {hours: 5}};
    test:assertEquals(civilToString(withOffset), "2024-01-02T10:15:30");
    test:assertEquals(check civilFromString("2024-01-02T10:15:30"), civil);
    test:assertEquals(civilToString(check civilFromString("2024-01-02T10:15:30.5")), "2024-01-02T10:15:30.5");
    test:assertEquals(civilToString({year: 2024, month: 1, day: 2, hour: 10, minute: 15, second: 30.0000001d}),
        "2024-01-02T10:15:30.0000001");
    test:assertEquals(civilToString(check civilFromString("2024-01-02T10:15:30.000000100")),
        "2024-01-02T10:15:30.0000001");
}

@test:Config {dataProvider: invalidCivils}
function testInvalidCivil(string value) {
    assertConversionError(civilFromString(value), "an ISO 8601 date-time");
}

function invalidCivils() returns string[][] =>
    [["2024-01-02T10:15:30Z"], ["2024-01-02T10:15:30+05:30"], ["2024-01-02 10:15:30"], ["2024-01-02"],
    ["2024-02-30T10:15:30"]];

@test:Config
function testUtcRoundTrip() returns error? {
    time:Utc utc = check time:utcFromString("2024-01-02T10:15:30Z");
    test:assertEquals(utcToString(utc), "2024-01-02T10:15:30Z");
    test:assertEquals(check utcFromString("2024-01-02T10:15:30Z"), utc);
    test:assertEquals(check utcFromString("2024-01-02T15:45:30+05:30"), utc);
}

@test:Config {dataProvider: invalidUtcs}
function testInvalidUtc(string value) {
    assertConversionError(utcFromString(value), "an ISO 8601 date-time");
}

function invalidUtcs() returns string[][] => [["2024-01-02T10:15:30"], ["2024-01-02"], ["yesterday"]];

function assertConversionError(anydata|ConversionError result, string format) {
    if result !is ConversionError {
        test:assertFail(string `expected a ConversionError for ${format}, got ${result.toString()}`);
    }
    test:assertEquals(result.detail().format, format);
    test:assertEquals(result.message(), string `The value is not ${format}.`);
}
