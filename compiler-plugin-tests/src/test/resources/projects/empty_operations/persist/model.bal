import ballerina/dataservice;

@dataservice:Expose {operations: []}
type Department record {|
    readonly int id;
|};
