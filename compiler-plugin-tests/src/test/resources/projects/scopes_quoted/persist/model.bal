import ballerina/dataservice;

@dataservice:Expose {
    operations: [dataservice:READ, dataservice:DELETE],
    scopes: {"read": ["hr:read"], 'delete: ["hr:admin"], "update": ["hr:write"]}
}
type Department record {|
    readonly int id;
    string name;
|};
