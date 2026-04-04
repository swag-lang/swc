#global fileprivate

var Callback: mtd(s32)->s32 // swc-expected-error {{parser_err_mtd_missing_capture}}

func bad()
{
    let f = mtd(value: s32)->s32 => value // swc-expected-error {{parser_err_mtd_missing_capture}}
}
