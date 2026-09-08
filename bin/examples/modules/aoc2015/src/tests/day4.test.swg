#global if #command == Swag.CompilerCommand.Test and #cfg == "release"

#[Swag.TestTag("parallel")]
#test
{
    Swag.setWorkerCount(4)
    day4B()
}
