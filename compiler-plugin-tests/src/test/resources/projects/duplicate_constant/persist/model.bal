import ballerina/dataservice;

const OPERATIONS = [dataservice:READ, dataservice:READ];

@dataservice:Expose {operations: OPERATIONS}
type Department record {|
    readonly int id;
    string name;
|};
