#global private

internal var CompilerInterfaceGeneratedValue = 0

// A short callback must reserve the native compiler method's outgoing call frame.
#message(Swag.CompilerMsgMask.PassAfterSemantic)
{
    let compiler = Swag.compiler()
    compiler.compileString("#init { CompilerInterfaceGeneratedValue = 42 }\n")
}

#test
{
    Swag.assert(CompilerInterfaceGeneratedValue == 42)
}
