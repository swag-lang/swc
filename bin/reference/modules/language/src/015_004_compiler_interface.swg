#global private
/**
# The Compiler Interface

'Swag.compiler()' exposes 'Swag.ICompiler' while code is executing at compile time.
At runtime the intrinsic is 'null', so keep it inside '#run', '#message',
macros, mixins, or other compile-time-only code.

The current interface has three methods:

| Method | Valid context | Result |
|---|---|---|
| 'getBuildCfg()' | Compile-time code | Mutable configuration for the current module |
| 'getMessage()' | A '#message' handler | Payload for the event being handled |
| 'compileString(source)' | Compile-time code | Parse and add generated source to the module |

# Reading the Build Configuration

A module setup file commonly uses '#run' to configure its build:

```swag
#run
{
    let cfg = Swag.compiler().getBuildCfg()!
    cfg.moduleVersion  = 1
    cfg.moduleRevision = 0
    cfg.backendKind    = .Executable
}
```

Command-line options are resolved before this setup executes. The effective
configuration is also available for inspection, but changing target paths or
backend settings after compilation has started is not a supported way to
override CLI options.

# Receiving Compiler Messages

Subscribe with a mask from 'Swag.CompilerMsgMask':

```swag
#message(Swag.CompilerMsgMask.SemFunctions)
{
    let message = Swag.compiler().getMessage()!
    if message.type == null or message.name == null do
        return

    let functionType = cast(const *Swag.TypeInfoFunc) message.type
    // Inspect functionType.parameters, functionType.returnType, and attributes.
}
```

The payload fields are nullable because their meaning depends on the event.
Check 'message.kind' and the fields you need before casting.

# Compiling Generated Source

'compileString' adds source to the same module. Generated code follows normal
visibility rules; an injected file cannot name a symbol declared 'private' in a
different source file.

```swag
#message(Swag.CompilerMsgMask.PassAfterSemantic)
{
    Swag.compiler().compileString(
        "internal func generatedAnswer()->s32 { return 42 }\n")
}
```

Prefer '#ast' when an expression or a small declaration can be generated
locally. Use 'compileString' for module-wide generation driven by compiler
events. Keep generated names deterministic and include a final newline so
diagnostic locations remain readable.

The runnable code-inspection section demonstrates a complete handler whose
generated '#init' block is exercised by a test.
*/
