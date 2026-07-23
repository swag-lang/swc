#global private

// Extracting a null payload from 'any' into a bare (non-null) type is guarded
// like an implicit 'assume' under Safety(.Null).

#test
{
    #[Swag.Safety(.Null, true)]
    func nullAnyExtractPanic()->bool
    {
        var ns:    #null string = null
        let boxed: any = ns
        let back = cast(string) boxed     // swc-expected-error {{safety_err_runtime}}
        return back == null
    }

    const value = #run nullAnyExtractPanic()
}

#test
{
    #[Swag.Safety(.Null, true)]
    func nullAnyExtractPointerPanic()->bool
    {
        var np:    #null *s32 = null
        let boxed: any = np
        let back = cast(*s32) boxed     // swc-expected-error {{safety_err_runtime}}
        return back == null
    }

    const value = #run nullAnyExtractPointerPanic()
}

#test
{
    // Without the safety guard the value flows through unchanged.
    #[Swag.Safety(.Null, false)]
    func nullAnyExtractDisabled()->bool
    {
        var ns:    #null string = null
        let boxed: any = ns
        let back = cast(string) boxed
        return back == null
    }

    @assert(nullAnyExtractDisabled())
}

#test
{
    // Legitimate paths stay silent: nullable destination, non-null payload,
    // non-nullable-capable target.
    #[Swag.Safety(.Null, true)]
    func nullAnyExtractOk()->bool
    {
        var ns:    #null string = null
        var boxed: any = ns
        if cast(#null string) boxed != null do
            return false

        boxed = "hello"
        if cast(string) boxed != "hello" do
            return false

        boxed = 42's32
        return cast(s32) boxed == 42
    }

    @assert(nullAnyExtractOk())
}
