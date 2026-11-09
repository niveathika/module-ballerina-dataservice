import ballerina/dataservice;

@dataservice:Expose
enum Status {
    ACTIVE,
    INACTIVE
}
