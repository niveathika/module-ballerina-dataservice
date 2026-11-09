import ballerina/dataservice;

@dataservice:Expose {operations: [dataservice:READ, dataservice:DELETE], scopes: {read: [], delete: ["hr:admin"]}}
type Department record {|
    readonly int id;
    string name;
|};
