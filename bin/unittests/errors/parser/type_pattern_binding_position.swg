#global private

interface IPatternShape { mtd area()->s32 }
struct PatternSquare { side: s32 }

func patternNegated(shape: IPatternShape)->s32
{
    if not (shape is PatternSquare as square) do     // swc-expected-error {{parser_err_type_pattern_binding_position}}
        return -1
    return 0
}

func patternCombined(shape: IPatternShape, ready: bool)->s32
{
    if ready and shape is PatternSquare as square do     // swc-expected-error {{parser_err_type_pattern_binding_position}}
        return 1
    return 0
}
