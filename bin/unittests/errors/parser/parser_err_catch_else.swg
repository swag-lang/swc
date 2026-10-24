#global private

func catchElseCount()->s32 fail
{
    return 1
}

// 'catch' names a replacement with 'orelse' and takes its handler directly.
#test
{
    let value = catch catchElseCount() orelse 2
    catch catchElseCount() { discard value }
}

#test
{
    let value = catch catchElseCount() else 2     // swc-expected-error {{parser_err_catch_else}}
    discard value
}

#test
{
    catch catchElseCount() else { }     // swc-expected-error {{parser_err_catch_else}}
}
