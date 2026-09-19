#global private

// Extracting a null payload from 'any' into a bare (non-null) type is guarded
// like an implicit '!' under Safety(.Null).

#test
{
    #[Swag.Safety(.Null, true)]
    func nullAnyExtractPanic()->bool
    {
        var ns:    string? = null
        let boxed: any     = ns
        let back           = cast #assume(string) boxed     // swc-expected-error {{safety_err_runtime}}
        return back == null
    }

    const value = #run nullAnyExtractPanic()
}

#test
{
    // Pointer targets use the dynamic-cast path: the nullable boxed type does not
    // match the requested non-null pointer type.
    #[Swag.Safety(.DynCast, true)]
    func nullAnyPointerDynamicCastPanic()->bool
    {
        var np:    *s32? = null
        let boxed: any   = np
        let back         = cast #assume(*s32) boxed     // swc-expected-error {{safety_err_runtime}}
        return back == null
    }

    const value = #run nullAnyPointerDynamicCastPanic()
}

#test
{
    // Without the safety guard the value flows through unchanged.
    #[Swag.Safety(.Null, false)]
    func nullAnyExtractDisabled()->bool
    {
        var ns:    string? = null
        let boxed: any     = ns
        let back           = cast #assume(string) boxed
        return back == null
    }

    Swag.assert(nullAnyExtractDisabled())
}

#test
{
    // Legitimate paths stay silent: nullable destination, non-null payload,
    // non-nullable-capable target.
    #[Swag.Safety(.Null, true)]
    func nullAnyExtractOk()->bool
    {
        var ns:    string? = null
        var boxed: any     = ns
        if cast #assume(string?) boxed != null do
            return false

        boxed = "hello"
        if cast #assume(string) boxed != "hello" do
            return false

        boxed = 42's32
        return cast #assume(s32) boxed == 42
    }

    Swag.assert(nullAnyExtractOk())
}
