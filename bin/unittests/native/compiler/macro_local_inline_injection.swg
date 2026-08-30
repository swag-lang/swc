#global private

#[Swag.Macro]
func inlineLocalMacroInject(count: s32, contextData: *void, stmt: #code(data: *void))
{
    #[Swag.Inline]
    func doWork(n: s32, ctxData: *void)
    {
        for n
        {
            #inject(stmt, data = ctxData)
        }
    }

    doWork(count, contextData)
}

#test
{
    var runs = 0
    inlineLocalMacroInject(3, &runs)
    {
        discard Swag.atomadd(cast(*s32) data, 1)
    }
    Swag.assert(runs == 3)
}
