#global private

#test
{
    var arr: [3] s32 = [1, 2, 3]
    var sum = 0
    foreach v in arr do // swc-expected-error {{parser_err_foreach_removed}}
        sum += v
}
