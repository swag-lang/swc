using Swag

public alias DepPlaceholderScalar = s32

#[Swag.PlaceHolder]
public func depPlaceholderExport(value: DepPlaceholderScalar)->DepPlaceholderScalar;

#message(CompilerMsgMask.PassAfterSemantic)
{
    let itf = @compiler
    itf.compileString(
        "public func depPlaceholderExport(value: s32)->s32\n" ++
        "{\n" ++
        "    return value + DEP_VALUE\n" ++
        "}\n")
}
