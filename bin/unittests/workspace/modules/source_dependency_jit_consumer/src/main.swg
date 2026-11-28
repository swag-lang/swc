#run
{
    Swag.getContext().user0 = 0x1234_ABCD
    Swag.assert(SourceDependencyProvider.answer() == 2)
    Swag.assert(SourceDependencyProvider.contextValue() == 0x1234_ABCD)
    Swag.assert(SourceDependencyProvider.verifyArguments(Swag.args()))
    Swag.print("compile-time source dependency passed\n")
}

#main {}
