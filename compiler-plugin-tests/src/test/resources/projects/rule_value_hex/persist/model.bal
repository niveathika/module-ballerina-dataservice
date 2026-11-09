import ballerina/dataservice;
import ballerina/persist as _;

@dataservice:Expose
type Item record {|
    readonly int id;
    @dataservice:ReadOnly {value: 0x1p4}
    decimal hours;
    @dataservice:ReadOnly {value: 0x1p4}
    float rate;
    @dataservice:ReadOnly {value: 0x10}
    decimal count;
|};
