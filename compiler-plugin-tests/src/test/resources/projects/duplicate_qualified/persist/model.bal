import ballerina/dataservice;

@dataservice:Expose {operations: [dataservice:CREATE, dataservice:CREATE, dataservice:CREATE]}
type Department record {|
    readonly int id;
|};
