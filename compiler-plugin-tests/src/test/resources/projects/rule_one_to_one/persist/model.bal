import ballerina/dataservice;
import ballerina/persist as _;
import ballerinax/persist.sql;

@dataservice:Expose
type Profile record {|
    readonly int id;
    @dataservice:ReadOnly {value: 1}
    int employeeId;
    @sql:Relation {keys: ["employeeId"]}
    Employee employee;
|};

@dataservice:Expose
type Employee record {|
    readonly int id;
    Profile? profile;
|};
