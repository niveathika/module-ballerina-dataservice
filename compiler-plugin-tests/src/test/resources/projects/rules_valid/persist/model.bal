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
    Department department;
    @dataservice:Immutable
    Slot slot;
|};

@dataservice:Expose
type Department record {|
    readonly int id;
    string name;
    @dataservice:Internal
    Employee[] employees;
|};

type Slot record {|
    readonly string code;
    readonly int seq;
    Employee[] employees;
|};
