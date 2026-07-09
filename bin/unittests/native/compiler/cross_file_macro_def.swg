#global internal

namespace CrossFileMacroRegression
{
    #[Swag.Macro]
    func runWhen(cond: #code->bool, stmt: #code)
    {
        if #inject(cond)
        {
            #inject(stmt)
        }
    }
}
