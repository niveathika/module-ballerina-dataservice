import ballerina/dataservice;

@dataservice:Expose {operations: [dataservice:READ, "read"]}
type Department record {|
    readonly int id;
|};
