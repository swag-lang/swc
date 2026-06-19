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
    @assert(ExprEvalCount == 0)

    let first = #inject(expr)
    @assert(ExprEvalCount == 1)

    let second = #inject(expr)
    @assert(ExprEvalCount == 2)
    return first + second
}

#[Swag.Macro]
func runStmt(stmt: #code void)
{
    @assert(#stringof(#typeof(stmt)) == "#code void")
    @assert(StmtEvalCount == 0)
    #inject(stmt)
    @assert(StmtEvalCount == 1)
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
func checkNamed(lhs: s32, rhs: #code s32)
{
    @assert(lhs == 10)
    @assert(#stringof(rhs) == "base + 32")
    @assert(#inject(rhs) == 42)
}

#[Swag.Macro]
func checkDefault(expr: #code bool = bumpDefault())
{
    @assert(DefaultEvalCount == 0)
    @assert(#stringof(#typeof(expr)) == "#code bool")
    @assert(#inject(expr))
    @assert(DefaultEvalCount == 1)
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

func runImplicitExpr()->bool
{
    ExprEvalCount = 0
    return sumTwice(bumpExpr(21)) == 42 and ExprEvalCount == 2
}

func runExplicitStmt()->bool
{
    StmtEvalCount = 0
    runStmt(#code { bumpStmt() })
    return StmtEvalCount == 1
}

func runTrailingStmt()->bool
{
    StmtEvalCount = 0
    let execute = true
    runWhen(execute)
    {
        bumpStmt()
    }

    if StmtEvalCount != 1 do
        return false

    runWhen(false)
    {
        bumpStmt()
    }

    return StmtEvalCount == 1
}

func runNamed()->bool
{
    let base = 10
    checkNamed(lhs: 10, rhs: base + 32)
    return true
}

func runDefault()->bool
{
    DefaultEvalCount = 0
    checkDefault()
    return DefaultEvalCount == 1
}

func runForwarded()->bool
{
    let base = 10
    return forward(base + 5) == 15
}

func runForced()->bool
{
    let base = 10
    return forceExpr(#code base * 3) == 30
}

func runBreakReplacementAsContinue()->s32
{
    var count: s32 = 0
    for 4
    {
        count += 1
        #inject(#code { break }, break = continue)
    }

    return count
}

func runBreakReplacementAsScopeBreak()->s32
{
    var count: s32 = 0
    #scope(Outer)
    {
        for 4
        {
            count += 1
            #inject(#code { break }, break = break to Outer)
        }

        count = -10
    }

    return count
}

func runContinueReplacementAsScopeBreak()->s32
{
    var count: s32 = 0
    #scope(Outer)
    {
        for 4
        {
            count += 1
            #inject(#code { continue }, continue = break to Outer)
        }

        count = -10
    }

    return count
}

func runCombinedReplacements()->s32
{
    var count: s32 = 0
    #scope(Outer)
    {
        for 4
        {
            count += 1
            #inject(#code {
                if count == 1 do
                    break

                continue
            }, continue = break to Outer, break = continue)

            count = -10
        }

        count = -20
    }

    return count
}

const ImplicitExprOk = #run runImplicitExpr()
const ExplicitStmtOk = #run runExplicitStmt()
const TrailingStmtOk = #run runTrailingStmt()
const NamedArgsOk    = #run runNamed()
const DefaultArgOk   = #run runDefault()
const ForwardedOk    = #run runForwarded()
const ForcedOk       = #run runForced()
const BreakAsContinueOk      = #run runBreakReplacementAsContinue() == 4
const BreakAsScopeBreakOk    = #run runBreakReplacementAsScopeBreak() == 1
const ContinueAsScopeBreakOk = #run runContinueReplacementAsScopeBreak() == 1
const CombinedReplacementsOk = #run runCombinedReplacements() == 2

#assert(ImplicitExprOk)
#assert(ExplicitStmtOk)
#assert(TrailingStmtOk)
#assert(NamedArgsOk)
#assert(DefaultArgOk)
#assert(ForwardedOk)
#assert(ForcedOk)
#assert(BreakAsContinueOk)
#assert(BreakAsScopeBreakOk)
#assert(ContinueAsScopeBreakOk)
#assert(CombinedReplacementsOk)
