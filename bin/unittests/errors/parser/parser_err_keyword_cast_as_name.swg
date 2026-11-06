#global private

struct KeywordBlock
{
    wrapped: bool
    height:  f32
}

// 'cast' only opens a conversion. Written where a name was meant, it is reported once per use,
// and the member accesses and operators around it raise nothing more.
func readKeyword(block: KeywordBlock)->bool
{
    return cast.wrapped and cast.height > 1     // swc-expected-error {{parser_err_keyword_cast_as_name}} {{parser_err_keyword_cast_as_name}}
}
