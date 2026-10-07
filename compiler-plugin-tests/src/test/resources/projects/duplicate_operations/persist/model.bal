import ballerina/dataservice;

@dataservice:Expose {operations: [dataservice:READ, dataservice:DELETE, "read"]}
type Department record {|
    readonly int id;
    string name;
|};
