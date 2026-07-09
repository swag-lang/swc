#global private

var Trace: s64 = 0

func appendTrace(value: s64)
{
    Trace = Trace * 10 + value
}

#[Swag.Macro]
func macroWithDefer(stmt: #code)
{
    defer appendTrace(9)
    #macro
    {
        #inject(#up stmt)
    }
}

func runMacroDeferContinue()->s64
{
    Trace = 0
    for 4
    {
        macroWithDefer()
        {
            if @index != 3 do
                continue
        }

        appendTrace(1)
    }

    return Trace
}

#test
{
    @assert(runMacroDeferContinue() == 99991)
}
