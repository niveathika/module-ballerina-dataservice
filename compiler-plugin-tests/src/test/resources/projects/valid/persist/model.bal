import ballerina/dataservice;

const READ_ONLY = [dataservice:READ];

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

@dataservice:Expose
type Project record {|
    readonly string code;
|};

@dataservice:Expose {operations: READ_ONLY}
type Location record {|
    readonly int id;
|};
