import ballerina/dataservice;

@dataservice:Expose {operations: [dataservice:READ]}
type Department record {|
    readonly int id;
|};
