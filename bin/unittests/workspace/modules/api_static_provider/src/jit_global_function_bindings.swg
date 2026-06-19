#global fileprivate

struct GlobalFunctionBindingError
{
    using base: Swag.BaseError
    code: s32 = 0
}

alias ErrorPathBindingVerifierFn = func()

var g_ErrorPathBindingVerifier: ErrorPathBindingVerifierFn = &verifyGlobalFunctionBindingErrorPath

func verifyGlobalFunctionBindingErrorPath()
{
    catch raiseGlobalFunctionBindingError(17)
}

func raiseGlobalFunctionBindingError(code: s32) throw
{
    throw GlobalFunctionBindingError{code: code}
}
