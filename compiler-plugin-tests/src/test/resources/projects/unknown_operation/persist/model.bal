import ballerina/dataservice;

@dataservice:Expose {operations: ["write"]}
type Department record {|
    readonly int id;
|};
