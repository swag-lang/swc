#global fileprivate

#[Swag.Macro]
func breakAsContinue(stmt: #code void)
{
    #inject(stmt, break = continue)
}

#[Swag.Macro]
func breakAsScopeBreak(stmt: #code void)
{
    #inject(stmt, break = break to Outer)
}

#[Swag.Macro]
func continueAsScopeBreak(stmt: #code void)
{
    #inject(stmt, continue = break to Outer)
}

#[Swag.Macro]
func remapLoopFlow(stmt: #code void)
{
    #inject(stmt, continue = break to Outer, break = continue)
}

#[Swag.Macro]
func runWhen(cond: #code bool, stmt: #code void)
{
    if #inject(cond)
    {
        #inject(stmt)
    }
}

#[Swag.Macro]
func defaultBeforeStmt(value: s32 = 40, stmt: #code void)
{
    #inject(stmt)
}

#[Swag.Macro]
func(T) genericCodeValue(expr: #code T)->T
{
    return #inject(expr)
}

#[Swag.Macro]
func(T) genericCodeWhen(cond: #code T, stmt: #code void)
{
    if #inject(cond)
    {
        #inject(stmt)
    }
}

#[Swag.Macro]
func forwardGenericCodeValue(expr: #code s32)->s32
{
    return genericCodeValue(expr)
}

#[Swag.Macro]
func forwardGenericCodeFlag(expr: #code bool)->bool
{
    return genericCodeValue(expr)
}

#[Swag.Macro]
func forwardGenericCodeWhen(cond: #code bool, stmt: #code void)
{
    genericCodeWhen(cond, #code {
        #inject(stmt)
    })
}

func semaTest001()
{
    var count = 0
    for 4
    {
        count += 1
        breakAsContinue(#code {
            break
        })
    }

    @assert(count == 4)
}

func semaTest002()
{
    var count = 0
#scope(Outer)
    {
        for 4
        {
            count += 1
            breakAsScopeBreak(#code {
                break
            })
        }

        count = -10
    }

    @assert(count == 1)
}

func semaTest003()
{
    var count = 0
    runWhen(true)
    {
        count += 1
    }

    runWhen(false)
    {
        count = -10
    }

    @assert(count == 1)
}

func semaTest004()
{
    var count = 0
    defaultBeforeStmt()
    {
        count += 1
    }
    @assert(count == 1)
}

func semaTest005()
{
    let value = forwardGenericCodeValue(#code 42)
    #assert(#typeof(value) == s32)

    let flag = forwardGenericCodeFlag(#code value == 42)
    #assert(#typeof(flag) == bool)

    var count = 0
    forwardGenericCodeWhen(#code flag)
    {
        count += 1
    }
    @assert(count == 1)
}

func semaTest006()
{
    var count = 0
#scope(Outer)
    {
        for 4
        {
            count += 1
            remapLoopFlow(#code {
                if count == 1 do
                    break

                continue
            })

            count = -10
        }

        count = -20
    }

    @assert(count == 2)
}

func semaTest007()
{
    var count = 0
#scope(Outer)
    {
        for 4
        {
            count += 1
            continueAsScopeBreak(#code {
                continue
            })
        }

        count = -10
    }

    @assert(count == 1)
}
