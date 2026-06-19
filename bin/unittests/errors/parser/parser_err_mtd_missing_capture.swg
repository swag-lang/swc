#global fileprivate

// 'mtd' must be followed by a capture list ('||' or '|a,b|') before any arguments.
var Callback1: mtd(s32)->s32             // swc-expected-error {{parser_err_mtd_missing_capture}}
var Callback2: mtd()->void               // swc-expected-error {{parser_err_mtd_missing_capture}}

func bad1()
{
    let f = mtd(value: s32)->s32 => value        // swc-expected-error {{parser_err_mtd_missing_capture}}
}

func bad2()
{
    let g = mtd()->s32 => 42                     // swc-expected-error {{parser_err_mtd_missing_capture}}
}
