import ballerina/dataservice;

@dataservice:Expose {scopes: {read: ["hr:read", ""], delete: ["hr admin"]}}
type Department record {|
    readonly int id;
    string name;
|};
