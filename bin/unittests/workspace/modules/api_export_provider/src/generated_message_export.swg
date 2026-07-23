#message(CompilerMsgMask.PassAfterSemantic)
{
    let itf = @compiler
    itf.compileString(
        "public func depGeneratedExport()->s32\n" ++
    "{\n" ++
    "    return DEP_VALUE * 6\n" ++
    "}\n")
}
