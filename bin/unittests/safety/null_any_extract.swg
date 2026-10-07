#global private

// Extracting a null payload from 'any' into a bare (non-null) type is guarded
// by the explicit assumption under Safety(.Assume).

#test
{
    #[Swag.Safety(.Assume, true)]
    func nullAnyExtractPanic()->bool
    {
        var ns:    string? = null
        let boxed: any     = ns
        let back           = assume cast(string, boxed)     // swc-expected-error {{safety_err_runtime}}
        return back == null
    }

    const value = #run nullAnyExtractPanic()
}

#test
{
    // Pointer targets use the dynamic-cast path: the nullable boxed type does not
    // match the requested non-null pointer type.
    #[Swag.Safety(.Assume, true)]
    func nullAnyPointerDynamicCastPanic()->bool
    {
        var np:    *s32? = null
        let boxed: any   = np
        let back         = assume cast(*s32, boxed)     // swc-expected-error {{safety_err_runtime}}
        return back == null
    }

    const value = #run nullAnyPointerDynamicCastPanic()
}

#test
{
    // Without the safety guard the value flows through unchanged.
    #[Swag.Safety(.Assume, false)]
    func nullAnyExtractDisabled()->bool
    {
        var ns:    string? = null
        let boxed: any     = ns
        let back           = assume cast(string, boxed)
        return back == null
    }

    Swag.assert(nullAnyExtractDisabled())
}

#test
{
    // Legitimate paths stay silent: nullable destination, non-null payload,
    // non-nullable-capable target.
    #[Swag.Safety(.Assume, true)]
    func nullAnyExtractOk()->bool
    {
        var ns:    string? = null
        var boxed: any     = ns
        if assume cast(string?, boxed) != null do
            return false

        boxed = "hello"
        if assume cast(string, boxed) != "hello" do
            return false

        boxed = 42's32
        return assume cast(s32, boxed) == 42
    }

    Swag.assert(nullAnyExtractOk())
}
