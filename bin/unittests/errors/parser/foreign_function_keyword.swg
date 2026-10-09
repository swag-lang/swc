#global private

// Another language's function keyword is reported once, and the declaration still parses.

fn foreignTwice(x: s32)->s32 => x * 2     // swc-expected-error {{parser_err_foreign_function_keyword}}

function foreignHalf(x: s32)->s32 => x / 2     // swc-expected-error {{parser_err_foreign_function_keyword}}
