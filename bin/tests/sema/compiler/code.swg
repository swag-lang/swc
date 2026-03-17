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

#test
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

#test
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

#test
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
