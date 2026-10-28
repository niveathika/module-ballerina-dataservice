import ballerina/dataservice;
import ballerina/persist as _;

@dataservice:Expose
type Employee record {|
    @dataservice:Immutable
    readonly int id;
    Department department;
|};

@dataservice:Expose
type Department record {|
    readonly int id;
    string name;
    Employee[] employees;
|};
