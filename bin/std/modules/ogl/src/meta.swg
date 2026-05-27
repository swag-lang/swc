using Core, Swag, Core.StrConv

#[AttrUsage(AttributeUsage.Function)]
attr Extension()

struct OneFunc
{
    type:     typeinfo
    name:     string
}

#[Compiler]
var g_Functions: Array'OneFunc

#message(CompilerMsgMask.SemFunctions)
{
    let itf = @compiler
    let msg = itf.getMessage()
    if msg == null or msg.type == null do
        return
    if !Reflection.hasAttribute(msg.type, Extension) do
        return
    g_Functions.add({msg.type, msg.name})
}

#message(CompilerMsgMask.PassAfterSemantic)
{
    var builderVars: StringBuilder
    var builderInit: StringBuilder

    builderInit.appendString("public func glInitExtensions()\n{\n")

    foreach e in g_Functions
    {
        // Declare a lambda variable for that extension
        builderVars.appendFormat("var ext_%: %\n", e.name, (cast(const *TypeInfoFunc) e.type).name)

        // Make a wrapper function
        builderVars.appendFormat("public func %(", e.name)
        foreach p, i in (cast(const *TypeInfoFunc) e.type).parameters
        {
            if i != 0 do
                builderVars.appendString(", ")
            builderVars.appendFormat("p%: %", i, p.pointedType.name)
        }

        if (cast(const *TypeInfoFunc) e.type).returnType == void
        {
            builderVars.appendFormat(")\n{\n")
        }
        else
        {
            builderVars.appendFormat(")->%\n{\n", (cast(const *TypeInfoFunc) e.type).returnType.name)
        }

        builderVars.appendFormat("\treturn ext_%(", e.name)
        foreach p, i in (cast(const *TypeInfoFunc) e.type).parameters
        {
            if i != 0 do
                builderVars.appendString(", ")
            builderVars.appendFormat("p%", i)
        }

        builderVars.appendString(");\n}\n\n")

        // Initialize the variable with the getExtensionAddress
        builderInit.appendFormat("\text_% = cast(%) getExtensionAddress(@dataof(\"%\"))\n", e.name, (cast(const *TypeInfoFunc) e.type).name, e.name)
    }

    let itf = @compiler
    var str = builderVars.toString()
    itf.compileString(str.toString())

    builderInit.appendString("}\n")
    str = builderInit.toString()
    itf.compileString(str.toString())
}
