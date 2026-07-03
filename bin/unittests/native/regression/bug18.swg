#global private

#[Swag.Macro]
func inlineLocalMacroInject(count: s32, contextData: *void = null, stmt: #code void)
{
    #[Swag.Inline]
    func doWork(n: s32, ctxData: *void)
    {
        for n
        {
            #macro
            {
                let #alias0 = #up ctxData
                #inject(#up stmt)
            }
        }
    }

    doWork(count, contextData)
}

#test
{
    var runs = 0
    inlineLocalMacroInject(3, &runs)
    {
        discard @atomadd(cast(*s32) #alias0, 1)
    }
    @assert(runs == 3)
}
