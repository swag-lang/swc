#global if #command == Swag.CompilerCommand.Test

#test { verifySourceDependency() }

// Later integer arguments cross the independently compiled source module boundary in Swag
// registers.
#test
{
    Swag.require(SourceDependencyProvider.verifyRegisterArguments(11, 22, 33, 44, 55, 66))
}
