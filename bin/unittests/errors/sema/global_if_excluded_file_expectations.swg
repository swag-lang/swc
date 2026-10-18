// A file removed by a false global condition raises nothing, so its expectations are dropped
// with it rather than reported as never raised.
#global if #hastag("Swag.NeverDefinedForGlobalIfExclusion")
#global private

func excluded()
{
    discard missingSymbol     // swc-expected-error {{sema_err_unknown_symbol}}
}
