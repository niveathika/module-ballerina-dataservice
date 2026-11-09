import ballerina/dataservice;
import ballerina/persist as _;

@dataservice:Expose {operations: [dataservice:CREATE]}
type Employee record {|
    readonly int id;
    @dataservice:Internal
    Department department;
|};

@dataservice:Expose
type Department record {|
    readonly int id;
    string name;
    Employee[] employees;
|};
