import ballerina/dataservice;
import ballerina/persist as _;
import ballerinax/persist.sql;

@dataservice:Expose
type Employee record {|
    readonly int id;
    @dataservice:Immutable
    string slotCode;
    int slotSeq;
    @sql:Relation {keys: ["slotCode", "slotSeq"]}
    Slot slot;
|};

type Slot record {|
    readonly string code;
    readonly int seq;
    Employee[] employees;
|};
