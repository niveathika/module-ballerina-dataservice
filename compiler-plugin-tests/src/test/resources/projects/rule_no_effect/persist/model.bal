import ballerina/dataservice;
import ballerina/persist as _;

@dataservice:Expose {operations: [dataservice:READ]}
type Employee record {|
    readonly int id;
    @dataservice:ReadOnly
    string? name;
    Department department;
|};

@dataservice:Expose
type Department record {|
    readonly int id;
    string name;
    Employee[] employees;
|};
