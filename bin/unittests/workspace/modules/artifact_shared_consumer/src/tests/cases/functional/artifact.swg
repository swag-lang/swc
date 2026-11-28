#global if #command == Swag.CompilerCommand.Test

#test { verifySharedArtifact() }

// The first imported call must preserve every Swag argument before the loader has resolved it.
#test
{
    Swag.require(SharedArtifactProvider.verifyRegisterArguments(11, 22, 33, 44, 55, 66))
    Swag.require(SharedArtifactProvider.verifyRegisterArguments(11, 22, 33, 44, 55, 66))
}
