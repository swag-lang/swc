#global private

const A = "hello world"
#assert(A[100] == '\0')     // swc-expected-error {{sema_err_index_out_of_range}}
#assert(A[0xFFFF_FFFF_FFFF_FFFF'u64] == '\0')     // swc-expected-error {{sema_err_index_out_of_range}}
#assert(cast(const cstring, ("abc").buffer)[3] == '\0')     // swc-expected-error {{sema_err_index_out_of_range}}

#test
{
    const H = [1, 2]
    var b = H[2]     // swc-expected-error {{sema_err_index_out_of_range}}
}

// A constant index past a fixed-size array is known before the program runs, even when the array
// is a variable.
func indexPastVariableArray()->s32
{
    var values: [3] s32
    return values[3]     // swc-expected-error {{index 3 is out of range for a sequence of size 3}}
}

func indexPastInnerDimension()->s32
{
    var grid: [2, 4] s32
    return grid[1, 4]     // swc-expected-error {{index 4 is out of range for a sequence of size 4}}
}

func indexInsideVariableArray()->s32
{
    var values: [3] s32
    return values[2]
}
