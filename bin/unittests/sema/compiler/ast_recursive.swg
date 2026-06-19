#global fileprivate

#[Swag.Compiler]
func recursiveAst0()->string
{
    return "const RecursiveGeneratedValue = 123"
}

#[Swag.Compiler]
func recursiveAst1()->string
{
    return "#ast recursiveAst0()"
}

#[Swag.Compiler]
func recursiveAst2()->string
{
    return "#ast recursiveAst1()"
}

#[Swag.Compiler]
func recursiveAst3()->string
{
    return "#ast recursiveAst2()"
}

#ast recursiveAst3()

#assert(RecursiveGeneratedValue == 123)
