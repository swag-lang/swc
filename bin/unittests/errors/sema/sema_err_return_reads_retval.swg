#global private

// Returning another value replaces the 'retval' variable, so that value cannot read the
// variable. Returning the variable, or '#move' of it, is the variable itself.
struct Text
{
    buf: [16] u8
    len: u64
}

impl Text
{
    mtd const view()->const [..] u8 => buf[0 until len]
}

func make(src: const [..] u8)->Text
{
    var r: retval
    for i in src.count do
        r.buf[i] = src[i]
    r.len = src.count
    return r
}

func trimmed()->Text
{
    var result: retval = make(" text ")
    return make(result.view()[1 until 5])     // swc-expected-error {{sema_err_return_reads_retval}}
}

func copied()->Text
{
    var result: retval = make("text")
    return {buf: result.buf, len: 2}     // swc-expected-error {{sema_err_return_reads_retval}}
}

func counted()->s32
{
    var result: retval = 3
    return result + 1     // swc-expected-error {{sema_err_return_reads_retval}}
}

// The variable itself, and '#move' of it, are accepted.
func returned()->Text
{
    var result: retval = make("text")
    return result
}

func moved()->Text
{
    var result: retval = make("text")
    return #move result
}

// Assigning the variable first is the accepted form.
func assigned()->Text
{
    var result: retval = make(" text ")
    result = make(result.view()[1 until 5])
    return result
}

// A value that does not read the variable replaces it.
func replaced(other: bool)->Text
{
    var result: retval = make("text")
    if other do
        return make("other")
    return result
}

#test
{
    discard trimmed()
    discard copied()
    discard counted()
    discard returned()
    discard moved()
    discard assigned()
    discard replaced(true)
}
