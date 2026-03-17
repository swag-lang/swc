#global fileprivate

var ExprEvalCount    = 0
var StmtEvalCount    = 0
var DefaultEvalCount = 0

func bumpExpr(value: s32)->s32
{
    ExprEvalCount += 1
    return value
}

func bumpStmt()
{
    StmtEvalCount += 1
}

func bumpDefault()->bool
{
    DefaultEvalCount += 1
    return true
}

#[Swag.Macro]
func sumTwice(expr: #code s32)->s32
{
    @assert(#stringof(#typeof(expr)) == "#code s32")
    return #inject(expr) + #inject(expr)
}

#[Swag.Macro]
func repeatStmt(stmt: #code void)
{
    @assert(#stringof(#typeof(stmt)) == "#code void")
    #inject(stmt)
    #inject(stmt)
}

#[Swag.Macro]
func checkNamed(lhs: s32, rhs: #code s32)->s32
{
    @assert(#stringof(rhs) == "base + 32")
    return lhs + #inject(rhs)
}

#[Swag.Macro]
func checkDefault(expr: #code bool = bumpDefault())->bool
{
    @assert(#stringof(#typeof(expr)) == "#code bool")
    return #inject(expr)
}

#[Swag.Macro]
func consumeForwarded(expr: #code s32)->s32
{
    @assert(#stringof(expr) == "base + 5")
    return #inject(expr)
}

#[Swag.Macro]
func forward(expr: #code s32)->s32
{
    return consumeForwarded(expr)
}

#[Swag.Macro]
func forceExpr(expr: #code s32)->s32
{
    @assert(#stringof(expr) == "base * 3")
    return #inject(expr)
}

#[Swag.Macro]
func runWhen(cond: #code bool, stmt: #code void)
{
    @assert(#stringof(#typeof(cond)) == "#code bool")
    if #inject(cond)
    {
        #inject(stmt)
    }
}

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
    ExprEvalCount = 0
    @assert(sumTwice(bumpExpr(21)) == 42)
    @assert(ExprEvalCount == 2)
}

#test
{
    StmtEvalCount = 0
    repeatStmt(#code { bumpStmt() })
    @assert(StmtEvalCount == 2)
}

#test
{
    let base = 10
    @assert(checkNamed(lhs: 10, rhs: base + 32) == 52)
    @assert(forward(base + 5) == 15)
    @assert(forceExpr(#code base * 3) == 30)
}

#test
{
    DefaultEvalCount = 0
    @assert(checkDefault())
    @assert(DefaultEvalCount == 1)
}

#test
{
    StmtEvalCount = 0
    let execute = true
    runWhen(execute, #code { bumpStmt() })
    @assert(StmtEvalCount == 1)

    runWhen(false, #code { bumpStmt() })
    @assert(StmtEvalCount == 1)
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
