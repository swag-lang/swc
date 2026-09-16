#global private

struct PatternBorrow { value: s32 = 42 }
interface IPatternBorrow {}
impl IPatternBorrow for PatternBorrow {}

func patternBorrowIf()->*PatternBorrow?
{
    var local: PatternBorrow
    let view:  IPatternBorrow = &local
    if view is PatternBorrow as borrowed do
        return borrowed     // swc-expected-error {{sanity_err_borrow_escape}}
    return null
}

func patternBorrowSwitch()->*PatternBorrow?
{
    var local: PatternBorrow
    let view:  IPatternBorrow = &local
    switch view
    {
    case PatternBorrow as borrowed:
        return borrowed     // swc-expected-error {{sanity_err_borrow_escape}}
    default: return null
    }
}

func patternBorrowCaller(value: *PatternBorrow)->*PatternBorrow?
{
    let view: IPatternBorrow = value
    switch view
    {
    case PatternBorrow as borrowed: return borrowed
    default: return null
    }
}
