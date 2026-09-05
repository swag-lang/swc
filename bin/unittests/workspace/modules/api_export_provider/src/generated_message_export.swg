#message(CompilerMsgMask.PassAfterSemantic)
{
    let itf = Swag.compiler()
    itf.compileString(
        #stringof("public func depGeneratedExport()->s32\n",
                  "{\n",
                  "    return DEP_VALUE * 6\n",
                  "}\n"))
}
