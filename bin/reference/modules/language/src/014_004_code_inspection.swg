#global private

/**
# Code Inspection

'#message' registers a compile-time handler for compiler events. Inside the
handler, '@compiler.getMessage()' describes the event and
'@compiler.compileString()' adds generated Swag source to the current module.

Use the narrowest message mask possible. Per-symbol masks such as
'SemFunctions' may run many times; pass masks such as 'PassAfterSemantic' run
once for the module.
*/

internal var CodeInspectionHookRan = false

#message(Swag.CompilerMsgMask.PassAfterSemantic)
{
    let itf = @compiler
    let msg = notnull itf.getMessage()

    if msg.kind != Swag.CompilerMsgKind.PassAfterSemantic do
        return
    itf.compileString("#init { CodeInspectionHookRan = true }\n")
}

#test
{
    @assert(CodeInspectionHookRan)
}

/**
The message payload depends on its 'kind':

- 'SemFunctions' provides the function name and a 'TypeInfoFunc'.
- 'SemTypes' provides a reflected type.
- 'SemGlobals' provides a global name and type.
- pass events identify a compilation phase rather than one declaration.

Always check nullable payload fields before dereferencing them in a handler that
subscribes to more than one event kind.
*/
