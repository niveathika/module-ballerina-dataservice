import ballerina/dataservice;
import ballerina/persist as _;
import ballerinax/persist.sql;

@dataservice:Expose
type Employee record {|
    @sql:Generated
    @dataservice:ReadOnly
    readonly int id;
    @dataservice:Immutable
    string code;
    @dataservice:ReadOnly {value: "new"}
    string state;
    @dataservice:Internal
    string? notes;
    @dataservice:Internal {value: 1}
    int tenantId;
    @dataservice:ReadOnly {value: 8}
    decimal hours;
    @dataservice:ReadOnly {value: -1.5}
    float rate;
    @dataservice:ReadOnly {value: 2}
    int deptId;
    @sql:Relation {keys: ["deptId"]}
    @dataservice:Internal
    Department department;
    @dataservice:Immutable
    string slotCode;
    @dataservice:Immutable
    int slotSeq;
    @sql:Relation {keys: ["slotCode", "slotSeq"]}
    Slot slot;
|};

@dataservice:Expose
type Department record {|
    readonly int id;
    string name;
    @dataservice:Internal
    Employee[] employees;
    Profile[] profiles;
|};

type Slot record {|
    readonly string code;
    readonly int seq;
    Employee[] employees;
|};

@dataservice:Expose {operations: [dataservice:READ, dataservice:UPDATE]}
type Profile record {|
    readonly int id;
    @dataservice:Internal {value: 1}
    int employeeId;
    @sql:Relation {keys: ["employeeId"]}
    Owner owner;
    @dataservice:ReadOnly {value: 1}
    int deptId;
    @sql:Relation {keys: ["deptId"]}
    Department department;
|};

type Owner record {|
    readonly int id;
    Profile? profile;
|};
