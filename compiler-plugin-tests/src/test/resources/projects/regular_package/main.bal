import ballerina/dataservice;

@dataservice:Expose {operations: [dataservice:READ, dataservice:READ]}
type Code string;
