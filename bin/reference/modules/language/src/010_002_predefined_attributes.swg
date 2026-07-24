#global private
/**
# Predefined Attributes

The compiler runtime exports predefined attributes in the 'Swag' namespace.
This page follows the API shipped in 'bin/runtime/api.swg'; it is the compact
index, while the relevant language chapters demonstrate the attributes that
change everyday program behavior.

# Declaring Attributes

| Attribute | Purpose |
|---|---|
| 'AttrUsage(usage)' | Restrict the kinds of declarations an attribute accepts |
| 'AttrMulti()' | Allow the same attribute to appear more than once |

'Swag.AttributeUsage' is a flag enum. Combine values such as '.Function',
'.Struct', '.Enum', and '.Variable' with '|'.

# Compile-Time Execution and Code Generation

| Attribute | Purpose |
|---|---|
| 'ConstExpr()' | Allow a function or struct operation to run in a constant expression |
| 'Compiler()' | Keep a function, global, or constant in the compile-time environment |
| 'PrintAst(stages: string...)' | Print the selected declaration's AST for compiler diagnostics |
| 'PrintMicro(stages: string...)' | Print generated Micro IR at selected pipeline stages |
| 'Inline()' | Require inlining |
| 'NoInline()' | Ask the backend not to inline |
| 'PlaceHolder()' | Generate an empty function body |
| 'NoPrint()' | Disable '@print' in the annotated function |
| 'Optimize(level: bool)' | Enable or disable optimized code generation |

'PrintAst' and 'PrintMicro' are development aids: they write compiler output and
should not be used for program logic.

# Metaprogramming and Call Semantics

| Attribute | Purpose |
|---|---|
| 'Macro()' | Inline a function while preserving the caller's expression context |
| 'Mixin()' | Inject declarations or statements at the call site |
| 'CalleeReturn()' | Make 'return' in a macro or mixin return from the caller |
| 'Implicit()' | Permit an 'opCast' overload as an implicit conversion |
| 'Discardable()' | Permit a function result to be ignored |
| 'Deprecated(msg: #null string = null)' | Mark an API as deprecated |

# Operators, Matching, and Enums

| Attribute | Purpose |
|---|---|
| 'Operators(operators: string...)' | Generate selected structural operators |
| 'OperatorIgnore()' | Exclude one field from generated operators |
| 'Commutative(operators: string...)' | Allow selected binary overloads with the receiver on the right |
| 'Complete()' | Require exhaustive handling where the construct supports it |
| 'Incomplete()' | Mark an enum as intentionally open for non-exhaustive switches |
| 'EnumFlags()' | Define an enum whose values form a bit mask |
| 'NoDuplicate()' | Reject duplicate enum values |
| 'Match(what: MatchWhat, value: bool)' | Adjust compiler overload-matching rules |

'Swag.Match' is a low-level compiler contract. Application code should normally
express overload selection with types and 'where' constraints.

# Layout, Ownership, and Export

| Attribute | Purpose |
|---|---|
| 'Align(value: u8)' | Override alignment for a field or aggregate |
| 'Pack(value: u8)' | Set struct packing |
| 'Offset(name: string)' | Overlay a field on another named field |
| 'NoCopy()' | Forbid copying a struct |
| 'Opaque()' | Hide a struct's contents from exported module APIs |
| 'ExportType(what: ExportWhat)' | Export selected runtime reflection data |
| 'Tls()' | Give each thread its own instance of a global |
| 'Global()' | Give a local declaration static storage |
| 'Strict()' | Keep an alias distinct for implicit-conversion purposes |

'Swag.ExportWhat' currently provides '.Methods' and '.NoZero' flags, plus
'.None' and '.All'. Exporting methods makes 'TypeInfoStruct.methods' available;
it does not make a private method public in source code.

# Safety and Diagnostics

| Attribute | Purpose |
|---|---|
| 'Safety(what: SafetyWhat, value: bool)' | Enable or disable runtime guards |
| 'Sanity(what: SafetyWhat, value: bool)' | Enable or disable static proven-fault checks |
| 'Warning(what: string, level: WarningLevel)' | Enable, disable, or promote diagnostic IDs |
| 'BorrowSummary(returns, stores = 0, into = 0, frees = 0)' | Describe pointer escape and invalidation behavior |

'SafetyWhat' is shared by runtime safety and static sanity, although not every
flag has meaningful behavior in both systems. See the dedicated safety and
sanity chapters before overriding defaults.

'BorrowSummary' is emitted automatically for ordinary Swag functions. Write it
manually only for a foreign declaration whose ownership behavior the compiler
cannot inspect.

# Native Interoperability

```swag
#[Swag.Foreign(
    module: "native_module",
    function: "external_symbol",
    link: "native_import_library",
    callconv: .C)]
func localName(value: u32)->u32;
```

'function' defaults to the local declaration name, 'link' defaults to the
module name, and 'callconv' defaults to the target C ABI.

# Compatibility Metadata

'NoDoc()' remains exported in the runtime API for source compatibility.
The current 'swc' command set has no documentation-generation command, so this
attribute has no effect in the language-reference workflow.
*/
