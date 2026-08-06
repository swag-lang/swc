#global private

/**
# Warnings

A warning reports code that compiles but is very likely a mistake. Unlike an
error it does not stop the build, so it needs a way to be silenced where it is
wrong and a way to be promoted where it must not be ignored.

Every warning is named by its diagnostic identifier — the same string
'--diagnostic-id' prints next to it, for instance 'sema_warn_unreachable_code'.
The name '"all"' stands for every warning wherever a warning list is accepted.

Three layers decide how a warning is reported. From the outermost in:

| Layer | Where |
|---|---|
| Command line | '--warn-as-error', '--warn-as-warning', '--warn-disable' |
| Build configuration | 'cfg.warnings.asErrors', 'cfg.warnings.asWarnings', 'cfg.warnings.disabled' |
| Source | '#[Swag.Warning]' on a declaration, a block, or a file |

A decision that names a warning outranks a decision that says '"all"', and at
equal reach the innermost layer wins. So 'swc build --warn-as-error all' turns
every warning into an error for that build, while a site that already declared
'#[Swag.Warning("sema_warn_unreachable_code", .Disable)]' stays silent: naming a
warning is a deliberate act, and it is not overridden from further out.
*/

/**
# Silencing a Warning at One Site

'#[Swag.Warning]' takes a warning name and a 'Swag.WarningLevel': '.Disable'
does not report it at all, '.Warning' reports it as a warning, and '.Error'
reports it as an error.
*/
#[Swag.Warning("sema_warn_unreachable_code", .Disable)]
func firstDraft()->s32
{
    return 1
    return 2     // Deliberate: the second branch of the computation, still to be written
}

/**
The attribute reaches everything it is written on. On a declaration it covers
that declaration, on a block it covers the statements inside, and with '#global'
it covers the whole file.

```swag
#global #[Swag.Warning("all", .Error)]
```

Several decisions compose, so a file can go silent except for the one warning it
still wants to hear about.
*/
#[Swag.Warning("all", .Disable), Swag.Warning("sema_warn_unreachable_code", .Error)]
func everythingOffExceptOne()->s32
{
    return 1
}

/**
# Unreachable Code

'sema_warn_unreachable_code' reports a statement that follows a jump in the same
block: 'return', 'break', 'continue', 'fallthrough', or 'fail'. The statement
compiles, but nothing can ever run it.

Only those five count. '@panic' and 'unreachable' announce that control never
reaches them, but neither is guaranteed to leave the block: '@panic' returns to
its caller whenever a panic hook is installed, which is what the '#test' runner
does so one failing test does not end the run, and 'unreachable' lowers to
nothing once '#[Swag.Safety(.Unreachable, false)]' turns its guard off. The code
after either one is not reported.

```swag
func size()->s32
{
    return 1
    let unused = 2     // warning: unreachable code
    return unused
}
```

Only the first such statement in a block is reported: everything after it is
unreachable for the same reason.
*/
#test
{
    @assert(firstDraft() == 1)
    @assert(everythingOffExceptOne() == 1)
}

/**
# Setting the Policy for a Whole Module

Each field of 'cfg.warnings' takes warning names separated with '|'.

```swag
#run
{
    let cfg = @compiler.getBuildCfg()!
    cfg.warnings.asErrors = "all"
    cfg.warnings.disabled = "sema_warn_unreachable_code"
}
```

That module reports every warning as an error, except unreachable code, which it
does not report at all.
*/
