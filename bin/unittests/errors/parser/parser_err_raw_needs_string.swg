#global private

// '#raw' qualifies a string literal and nothing else.
#test
{
    let a = #raw 42     // swc-expected-error {{parser_err_raw_needs_string}}
}

#test
{
    let a = #raw 'x'     // swc-expected-error {{parser_err_raw_needs_string}}
}

// The delimiter-pair spelling is gone.
#test
{
    let a = #"still raw"#     // swc-expected-error {{parser_err_raw_string_delimiter}}
}

// The supported spellings stay valid.
#test
{
    let a = #raw "C:\path"
    let b = #raw """has a " inside"""
    @assert(a == "C:\\path")
    @assert(b == "has a \" inside")
}
