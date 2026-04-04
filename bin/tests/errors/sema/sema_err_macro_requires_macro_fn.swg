#global fileprivate

struct MacroScopeConfig
{
    delta: s32
}

func badNormal()
{
    #macro // swc-expected-error {{sema_err_macro_requires_macro_fn}}
    {
        let value = 1
    }
}

#[Swag.Mixin]
func badMixin()
{
    #macro // swc-expected-error {{sema_err_macro_requires_macro_fn}}
    {
        let value = 1
    }
}

const TriggerBadMixin = #run
{
    badMixin()
    return 0
}

#[Swag.Macro]
func missingUpOnCodeParam(stmt: #code void)
{
    #macro
    {
        #inject(stmt) // swc-expected-error {{sema_err_unknown_symbol}}
    }
}

#[Swag.Macro]
func missingUpOnLocal()
{
    var value = 40
    #macro
    {
        value += 2 // swc-expected-error {{sema_err_unknown_symbol}}
    }
}

#[Swag.Macro]
func missingUpOnValueParam(inputCfg: MacroScopeConfig)
{
    #macro
    {
        let value = inputCfg.delta // swc-expected-error {{sema_err_unknown_symbol}}
    }
}

#[Swag.Macro]
func missingUpOnCompilerIf(flag: bool)
{
    #macro
    {
        #if flag do // swc-expected-error {{sema_err_unknown_symbol}}
            let value = 1
    }
}

#[Swag.Macro]
func missingUpOnTypeAlias()
{
    alias ScopeValue = s32
    var value: ScopeValue = 1
    #macro
    {
        var typed: ScopeValue = #up value // swc-expected-error {{sema_err_unknown_symbol}}
    }
}

const TriggerMissingUpOnCodeParam = #run
{
    missingUpOnCodeParam(#code {})
    return 0
}

const TriggerMissingUpOnLocal = #run
{
    missingUpOnLocal()
    return 0
}

const TriggerMissingUpOnValueParam = #run
{
    var cfg: MacroScopeConfig
    cfg.delta = 1
    missingUpOnValueParam(cfg)
    return 0
}

const TriggerMissingUpOnCompilerIf = #run
{
    missingUpOnCompilerIf(true)
    return 0
}

const TriggerMissingUpOnType = #run
{
    missingUpOnTypeAlias()
    return 0
}
