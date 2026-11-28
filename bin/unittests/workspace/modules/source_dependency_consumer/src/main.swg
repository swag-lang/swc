func verifySourceDependency()
{
    Swag.getContext().user0 = 0x1234_ABCD
    Swag.assert(SourceDependencyProvider.answer() == 42)
    Swag.assert(SourceDependencyProvider.contextValue() == 0x1234_ABCD)
    Swag.assert(SourceDependencyProvider.verifyArguments(Swag.args()))
}

#main
{
    verifySourceDependency()
    Swag.print("source dependency passed\n")
}
