import ballerina/dataservice;
import ballerina/persist as _;
import ballerinax/persist.sql;

@dataservice:Expose
type Employee record {|
    readonly int id;
    @dataservice:Immutable
    int deptId;
    @sql:Relation {keys: ["deptId"]}
    Department department;
|};

@dataservice:Expose
type Department record {|
    readonly int id;
    string name;
    Employee[] employees;
|};
