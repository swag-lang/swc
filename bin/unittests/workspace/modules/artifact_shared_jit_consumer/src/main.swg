#run
{
    Swag.getContext().user0 = 0x1234_ABCD
    Swag.assert(SharedArtifactProvider.answer() == 42)
    Swag.assert(SharedArtifactProvider.contextValue() == 0x1234_ABCD)
    Swag.assert(SharedArtifactProvider.verifyArguments(Swag.args()))
    Swag.print("compile-time shared artifact passed\n")
}

#main {}
