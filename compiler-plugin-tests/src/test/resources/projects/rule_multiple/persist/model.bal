import ballerina/dataservice;
import ballerina/persist as _;

@dataservice:Expose
type Employee record {|
    readonly int id;
    @dataservice:ReadOnly {value: "x"}
    @dataservice:Internal {value: "y"}
    string name;
    Department department;
|};

@dataservice:Expose
type Department record {|
    readonly int id;
    string name;
    Employee[] employees;
|};
