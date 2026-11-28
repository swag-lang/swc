func verifySharedArtifact()
{
    Swag.getContext().user0 = 0x1234_ABCD
    Swag.assert(SharedArtifactProvider.answer() == 42)
    Swag.assert(SharedArtifactProvider.contextValue() == 0x1234_ABCD)
    Swag.assert(SharedArtifactProvider.verifyArguments(Swag.args()))
}

#main
{
    verifySharedArtifact()
    Swag.print("shared artifact passed\n")
}
