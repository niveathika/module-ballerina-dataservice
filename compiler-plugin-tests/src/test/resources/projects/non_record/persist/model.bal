import ballerina/dataservice;

@dataservice:Expose {operations: [dataservice:READ]}
type Code string;
