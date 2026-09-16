#global private

interface IPatternError {}
struct PatternError {}
impl IPatternError for PatternError {}

func patternDuplicate(value: IPatternError)
{
    switch value
    {
    case PatternError:         break
    case PatternError as item: break     // swc-expected-error {{sema_err_switch_case_duplicate}}
    }
}

func patternScope(value: IPatternError)
{
    if value is PatternError as item do
        Swag.assert(item != null)
    discard item     // swc-expected-error {{sema_err_unknown_symbol}}
}

func patternElseScope(value: IPatternError)
{
    if value is PatternError as item do
        Swag.assert(item != null)
    else do
        discard item     // swc-expected-error {{sema_err_unknown_symbol}}
}

struct PatternPlain { value: s32 }
struct PatternChild { using base: PatternPlain }

func patternNeedsMetadata(value: *PatternPlain)->bool
{
    return value is PatternChild     // swc-expected-error {{sema_err_downcast_dynamic}}
}

func patternNumeric(value: s32)->bool
{
    return value is s64     // swc-expected-error {{sema_err_cannot_cast}}
}

func patternCaseValue(value: IPatternError)
{
    switch value
    {
    case 42: break     // swc-expected-error {{sema_err_switch_dynamic_case}}
    }
}

func patternMutable(value: *PatternError) {}

func patternConstIf(value: const IPatternError)
{
    if value is PatternError as item do
        patternMutable(item)     // swc-expected-error {{sema_err_cannot_cast_const}}
}

func patternConstSwitch(value: const IPatternError)
{
    switch value
    {
    case PatternError as item:
        patternMutable(item)     // swc-expected-error {{sema_err_cannot_cast_const}}
    }
}
