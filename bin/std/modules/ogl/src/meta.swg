using Core, Swag, Core.StrConv

#[AttrUsage(AttributeUsage.Function)]
attr Extension()

struct OneFunc
{
    type:     #null const *TypeInfoFunc
    name:     string
}

#[Compiler]
var g_Functions: Array'OneFunc

#message(CompilerMsgMask.SemFunctions)
{
    let itf = @compiler
    let msg = itf.getMessage()
    if msg == null or msg.type == null or msg.name == null do
        return
    if msg.kind != CompilerMsgKind.SemFunctions do
        return
    if msg.type.kind != TypeInfoKind.Func do
        return

    let typeFunc = cast(const *TypeInfoFunc) assume msg.type
    if !Reflection.hasAttribute(typeFunc, Extension) do
        return
    g_Functions.add({type: typeFunc, name: cast(string) (assume msg.name)})
}

#message(CompilerMsgMask.PassAfterSemantic)
{
    let itf = @compiler
    var builderInit: StringBuilder

    builderInit.appendString("public func glInitExtensions()\n{\n")

    for e in g_Functions
    {
        var builderVars: StringBuilder

        // Declare a lambda variable for that extension.
        builderVars.appendString("var ext_")
        builderVars.appendString(e.name)
        builderVars.appendString(": #null ")
        builderVars.appendString(e.type.fullname)
        builderVars.appendString("\n")

        // Generate the wrapper function body.
        builderVars.appendString("public func ")
        builderVars.appendString(e.name)
        builderVars.appendString("(")
        for p, i in e.type.parameters
        {
            if i != 0 do
                builderVars.appendString(", ")
            builderVars.appendString(p.name)
            builderVars.appendString(": ")
            builderVars.appendString(p.pointedType.fullname)
        }

        if e.type.returnType == null or e.type.returnType == void
        {
            builderVars.appendString(")\n{\n\text_")
        }
        else
        {
            builderVars.appendString(")->")
            builderVars.appendString(e.type.returnType.fullname)
            builderVars.appendString("\n{\n\treturn ext_")
        }

        builderVars.appendString(e.name)
        builderVars.appendString("(")
        for p, i in e.type.parameters
        {
            if i != 0 do
                builderVars.appendString(", ")
            builderVars.appendString(p.name)
        }

        builderVars.appendString(");\n}\n\n")
        let wrapper = builderVars.moveToString()
        itf.compileString(wrapper.toString())

        // Initialize the variable with the getExtensionAddress.
        builderInit.appendString("\text_")
        builderInit.appendString(e.name)
        builderInit.appendString(" = cast(#null ")
        builderInit.appendString(e.type.fullname)
        builderInit.appendString(") getExtensionAddress(@dataof(\"")
        builderInit.appendString(e.name)
        builderInit.appendString("\"))\n")
    }

    builderInit.appendString("}\n")
    let initFunc = builderInit.moveToString()
    itf.compileString(initFunc.toString())
}
