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

import ballerina/lang.array;
import ballerina/lang.regexp;
import ballerina/time;

const ISO_DATE = "an ISO 8601 date";
const ISO_TIME = "an ISO 8601 time";
const ISO_DATE_TIME = "an ISO 8601 date-time";
const BASE64 = "a base64 string";

final regexp:RegExp DATE_PATTERN = re `(\d{4})-(\d{2})-(\d{2})`;
final regexp:RegExp TIME_PATTERN = re `(\d{2}):(\d{2}):(\d{2}(?:\.\d+)?)`;

# The detail of a `ConversionError`.
#
# + format - The format the value is not in, such as `an ISO 8601 date`
# + field - The field the value is given for, when it is a value of a query option
public type ConversionErrorDetail record {|
    string format;
    string 'field?;
|};

# Represents a value that is not in the JSON format of its type.
public type ConversionError distinct error<ConversionErrorDetail>;

# Converts a `byte[]` value to a base64 string.
#
# + value - The value
# + return - The value in base64, with the standard alphabet and padding
public isolated function bytesToString(byte[] value) returns string => value.toBase64();

# Converts a base64 string to a `byte[]` value.
#
# + value - The base64 string, with the standard alphabet and padding
# + return - The decoded value, or a `ConversionError` if the string is not base64
public isolated function bytesFromString(string value) returns byte[]|ConversionError {
    // array:fromBase64 also accepts unpadded input, which the format excludes.
    if value.length() % 4 != 0 {
        return conversionError(BASE64);
    }
    byte[]|error bytes = array:fromBase64(value);
    return bytes is byte[] ? bytes : conversionError(BASE64, bytes);
}

# Converts a `time:Date` value to an ISO 8601 date, such as `2024-01-02`.
#
# + value - The value
# + return - The date
public isolated function dateToString(time:Date value) returns string =>
    string `${pad(value.year, 4)}-${pad(value.month, 2)}-${pad(value.day, 2)}`;

# Converts an ISO 8601 date, such as `2024-01-02`, to a `time:Date` value.
#
# + value - The date
# + return - The value, or a `ConversionError` if the string is not a valid date
public isolated function dateFromString(string value) returns time:Date|ConversionError {
    time:Date? date = parseDate(value);
    return date is time:Date ? date : conversionError(ISO_DATE);
}

# Converts a `time:TimeOfDay` value to an ISO 8601 time, such as `10:15:30` or `10:15:30.5`.
#
# + value - The value
# + return - The time
public isolated function timeOfDayToString(time:TimeOfDay value) returns string =>
    timeText(value.hour, value.minute, value.second);

# Converts an ISO 8601 time, such as `10:15:30` or `10:15:30.5`, to a `time:TimeOfDay` value.
#
# + value - The time
# + return - The value, or a `ConversionError` if the string is not a valid time
public isolated function timeOfDayFromString(string value) returns time:TimeOfDay|ConversionError {
    time:TimeOfDay? timeOfDay = parseTime(value);
    return timeOfDay is time:TimeOfDay ? timeOfDay : conversionError(ISO_TIME);
}

# Converts a `time:Civil` value to an ISO 8601 date-time without an offset, such as `2024-01-02T10:15:30`.
#
# + value - The value; its offset, if any, is not written
# + return - The date-time
public isolated function civilToString(time:Civil value) returns string =>
    string `${dateToString({year: value.year, month: value.month, day: value.day})}T${
        timeText(value.hour, value.minute, value.second)}`;

# Converts an ISO 8601 date-time without an offset, such as `2024-01-02T10:15:30`, to a `time:Civil` value.
#
# + value - The date-time
# + return - The value, or a `ConversionError` if the string is not a valid date-time without an offset
public isolated function civilFromString(string value) returns time:Civil|ConversionError {
    int? separator = value.indexOf("T");
    if separator is int {
        time:Date? date = parseDate(value.substring(0, separator));
        time:TimeOfDay? timeOfDay = parseTime(value.substring(separator + 1));
        if date is time:Date && timeOfDay is time:TimeOfDay {
            return {
                year: date.year,
                month: date.month,
                day: date.day,
                hour: timeOfDay.hour,
                minute: timeOfDay.minute,
                second: timeOfDay.second
            };
        }
    }
    return conversionError(ISO_DATE_TIME);
}

# Converts a `time:Utc` value to an ISO 8601 date-time in UTC, such as `2024-01-02T10:15:30Z`.
#
# + value - The value
# + return - The date-time
public isolated function utcToString(time:Utc value) returns string => time:utcToString(value);

# Converts an ISO 8601 date-time with an offset, such as `2024-01-02T10:15:30Z`, to a `time:Utc` value.
#
# + value - The date-time; an offset other than `Z` is converted to UTC
# + return - The value, or a `ConversionError` if the string is not a valid date-time with an offset
public isolated function utcFromString(string value) returns time:Utc|ConversionError {
    time:Utc|error utc = time:utcFromString(value);
    return utc is time:Utc ? utc : conversionError(ISO_DATE_TIME, utc);
}

isolated function parseDate(string value) returns time:Date? {
    regexp:Groups? groups = DATE_PATTERN.fullMatchGroups(value);
    if groups is () {
        return ();
    }
    time:Date date = {year: groupInt(groups, 1), month: groupInt(groups, 2), day: groupInt(groups, 3)};
    return time:dateValidate(date) is () ? date : ();
}

isolated function parseTime(string value) returns time:TimeOfDay? {
    regexp:Groups? groups = TIME_PATTERN.fullMatchGroups(value);
    if groups is () {
        return ();
    }
    int hour = groupInt(groups, 1);
    int minute = groupInt(groups, 2);
    decimal|error second = decimal:fromString(groupText(groups, 3));
    if hour > 23 || minute > 59 || second is error || second >= 60d {
        return ();
    }
    return {hour, minute, second};
}

isolated function groupText(regexp:Groups groups, int index) returns string {
    regexp:Span? span = groups[index];
    return span is regexp:Span ? span.substring() : "";
}

// The patterns admit only digits in these groups, so the conversion cannot fail.
isolated function groupInt(regexp:Groups groups, int index) returns int =>
    checkpanic int:fromString(groupText(groups, index));

isolated function timeText(int hour, int minute, time:Seconds? second) returns string =>
    string `${pad(hour, 2)}:${pad(minute, 2)}:${secondText(second ?: 0d)}`;

isolated function secondText(time:Seconds second) returns string {
    decimal whole = second.floor();
    decimal fraction = second - whole;
    string text = pad(<int>whole, 2);
    if fraction == 0d {
        return text;
    }
    string digits = fraction.toString();
    int end = digits.length();
    while digits[end - 1] == "0" {
        end -= 1;
    }
    return text + digits.substring(digits.indexOf(".") ?: 0, end);
}

isolated function pad(int value, int width) returns string {
    string text = value.toString();
    return text.padZero(width);
}

isolated function conversionError(string format, error? cause = ()) returns ConversionError =>
    error ConversionError(string `The value is not ${format}.`, cause, format = format);
