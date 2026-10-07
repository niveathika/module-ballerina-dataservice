import ballerina/dataservice;

@dataservice:Expose {operations: [dataservice:READ, dataservice:UPDATE]}
type Department record {|
    readonly int id;
    string name;
|};

@dataservice:Expose {operations: ["read"]}
type Employee record {|
    readonly int id;
    string name;
|};

type Project record {|
    readonly string code;
|};
