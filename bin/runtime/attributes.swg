namespace Swag
{
    // Declarations an attribute can be applied to, as given to [[AttrUsage]].
    enum AttributeUsage: u32
    {
        Enum              = 0x00000001     // Attribute can be used on an enum
        EnumValue         = 0x00000002     // Attribute can be used on an enum value
        StructVariable    = 0x00000004     // Attribute can be used on a struct field
        GlobalVariable    = 0x00000008     // Attribute can be used on a global variable
        Variable          = 0x00000010     // Attribute can be used on any variable
        Struct            = 0x00000020     // Attribute can be used on a struct
        Function          = 0x00000040     // Attribute can be used on a function
        FunctionParameter = 0x00000080     // Attribute can be used on a function parameter
        File              = 0x00000100     // Attribute can be used with '#global'
        Constant          = 0x00000200     // Attribute can be used on a constant
        Alias             = 0x00000400     // Attribute can be used on an alias
        Scope             = 0x00000800     // Attribute acts on a lexical scope instead of a declaration
        Multi             = 0x01000000     // Attribute can be used more than once
        Gen               = 0x02000000
        All               = 0x04000000
    }

    // Calling convention of a function, as given to [[Foreign]].
    enum CallConv: u8
    {
        C              // Target C ABI for the selected platform
        WindowsX64     // Concrete Windows x64 ABI
        Swag           // Swag compiled/JIT ABI for the current target runtime
    }

    // #########################################################
    // Attributes
    // #########################################################

    // Declares which declarations the attribute that carries it can be applied to.
    attr AttrUsage(usage: AttributeUsage)

    // Allows the attribute that carries it to appear more than once on one declaration.
    attr AttrMulti()

    // Assigns one category to a '#test' function for selection with '--test-tag'.
    //
    // Categories beginning with `integration.` run only when explicitly selected.
    #[AttrUsage(AttributeUsage.Function)]
    attr TestTag(name: string)

    // Allows the function, or the struct, to be evaluated at compile time.
    #[AttrUsage(AttributeUsage.Function | AttributeUsage.Struct)]
    attr ConstExpr()

    // Promises that a call does not write memory visible to its caller.
    //
    // The compiler may keep memory values across the call. Only use this on functions
    // whose full implementation, including functions they call, upholds the promise.
    #[AttrUsage(AttributeUsage.Function)]
    attr ReadOnly()

    // Prints the micro instructions generated for a function, a struct, or a file.
    //
    // Without a parameter, the instructions are printed right before the emit pass. Otherwise
    // each parameter names a stage, spelled `pre-<pass>` or `post-<pass>`.
    #[AttrUsage(AttributeUsage.Function | AttributeUsage.Struct | AttributeUsage.File)]
    attr PrintMicro(stages: string...)

    // Prints the AST of a function, a struct, or a file.
    //
    // Without a parameter, prints after semantic analysis. The available stages are
    // `pre-sema` and `post-sema`.
    #[AttrUsage(AttributeUsage.Function | AttributeUsage.Struct | AttributeUsage.File)]
    attr PrintAst(stages: string...)

    // Restricts a function, global variable, or constant to compile time: it is never emitted in generated code.
    #[AttrUsage(AttributeUsage.Function | AttributeUsage.GlobalVariable | AttributeUsage.Constant)]
    attr Compiler()

    // Inlines the function at every call site.
    #[AttrUsage(AttributeUsage.Function)]
    attr Inline()

    // Asks the backend never to inline the function.
    #[AttrUsage(AttributeUsage.Function)]
    attr NoInline()

    // Declares a body-less function that is generated empty and left out of the module API.
    //
    // A generator reads such placeholders at compile time and supplies the real implementations.
    #[AttrUsage(AttributeUsage.Function)]
    attr PlaceHolder()

    // Makes the function a macro: its body is expanded at each call site, in a scope of its own.
    #[AttrUsage(AttributeUsage.Function)]
    attr Macro()

    // Makes the function a mixin: its body is expanded at each call site, in the caller's scope.
    #[AttrUsage(AttributeUsage.Function)]
    attr Mixin()

    // Lets an 'opCast' overload apply as an implicit conversion.
    #[AttrUsage(AttributeUsage.Function)]
    attr Implicit()

    // Asserts that an opaque 'opSet' body fully initializes its destination.
    //
    // Ordinary Swag bodies are inferred automatically. Reserve this assertion for bodies
    // the compiler cannot inspect, such as foreign or generated implementations.
    #[AttrUsage(AttributeUsage.Function)]
    attr FullInit()

    // The operator an overload hook is being asked to implement.
    //
    // The compiler passes it as the generic value argument of 'opBinary', 'opBinaryRight',
    // 'opUnary', 'opAssign' and 'opIndexAssign'. Each spelling has its own member, so a hook
    // never has to guess: 'Sub' and 'Neg' are distinct even though both are written '-'.
    // The member order is part of the compiler contract; do not reorder or renumber.
    enum Operator
    {
        // Binary operators: + - * / % & | ^ << >>
        Add
        Sub
        Mul
        Div
        Mod
        BitAnd
        BitOr
        BitXor
        Shl
        Shr

        // Unary operators: not + - ~
        Not
        Pos
        Neg
        BitNot

        // Compound assignments: += -= *= /= %= &= |= ^= <<= >>=
        AddAssign
        SubAssign
        MulAssign
        DivAssign
        ModAssign
        BitAndAssign
        BitOrAssign
        BitXorAssign
        ShlAssign
        ShrAssign
    }

    impl Operator
    {
        // Returns the source spelling of the operator.
        //
        // Generated code and diagnostics use it to name the operator an overload implements.
        #[ConstExpr]
        mtd symbol()->string
        {
            switch #complete me
            {
            case .Add:          return "+"
            case .Sub:          return "-"
            case .Mul:          return "*"
            case .Div:          return "/"
            case .Mod:          return "%"
            case .BitAnd:       return "&"
            case .BitOr:        return "|"
            case .BitXor:       return "^"
            case .Shl:          return "<<"
            case .Shr:          return ">>"
            case .Not:          return "not"
            case .Pos:          return "+"
            case .Neg:          return "-"
            case .BitNot:       return "~"
            case .AddAssign:    return "+="
            case .SubAssign:    return "-="
            case .MulAssign:    return "*="
            case .DivAssign:    return "/="
            case .ModAssign:    return "%="
            case .BitAndAssign: return "&="
            case .BitOrAssign:  return "|="
            case .BitXorAssign: return "^="
            case .ShlAssign:    return "<<="
            case .ShrAssign:    return ">>="
            }
        }
    }

    // Lets an 'opBinary' overload also apply when its receiver is the right operand.
    //
    // For a generic 'opBinary', the optional parameters restrict this to the listed operators.
    #[AttrUsage(AttributeUsage.Function)]
    attr Commutative(operators: Operator...)

    // Generates operator overloads for the struct.
    #[AttrUsage(AttributeUsage.Struct)]
    attr Operators(operators: string...)

    // Excludes a struct field from generated operator overloads.
    #[AttrUsage(AttributeUsage.StructVariable)]
    attr OperatorIgnore()

    // Makes a 'return' in the macro or mixin leave the macro itself rather than its caller.
    #[AttrUsage(AttributeUsage.Function)]
    attr CalleeReturn()

    // Declares that a call to the function never comes back, like 'Swag.panic'.
    //
    // The code after a call is reported as unreachable, and a function with a return type
    // needs no 'return' after it. The function itself has no return type, contains no
    // 'return', and ends every path with 'Swag.panic', 'unreachable', or a call to another
    // 'NoReturn' function.
    #[AttrUsage(AttributeUsage.Function)]
    attr NoReturn()

    // Declares a function implemented outside the current module.
    //
    // 'module' defaults to the module the declaring file belongs to, which only a generated
    // module API leaves out. 'function' defaults to the flattened public API name there, and
    // to the declaration name for a function of a native library.
    #[AttrUsage(AttributeUsage.Function)]
    attr Foreign(module: string = "", function: string = "", link: string = "", callconv: CallConv = Swag.CallConv.Swag)

    // Chooses the ABI for functions and function values declared in this scope.
    //
    // Use `.C` for callbacks and vtables supplied to native libraries. An annotated
    // function declaration is entered with that convention; an annotated function type
    // calls its target with that convention. The unannotated convention is `.Swag`.
    #[AttrUsage(AttributeUsage.Function |
                AttributeUsage.Struct |
                AttributeUsage.StructVariable |
                AttributeUsage.Alias |
                AttributeUsage.File |
                AttributeUsage.Scope)]
    attr CallingConvention(value: CallConv)

    // Lets a caller ignore the function's result without writing 'discard'.
    #[AttrUsage(AttributeUsage.Function | AttributeUsage.Variable)]
    attr Discardable()

    // Reads every unmarked fallible call in the function body as 'try'.
    //
    // The function must be declared with 'fail'. A call that spells 'catch', 'expect', or
    // 'assume' keeps its own handling, and a written 'try' is reported as redundant. The
    // attribute governs the body it is written on: a function or lambda declared inside it
    // spells its own error handling. A macro or a mixin cannot carry it, because its body
    // belongs to the caller.
    #[AttrUsage(AttributeUsage.Function)]
    attr Propagate()

    // Marks a declaration as deprecated: each use is reported, with 'msg' when one is given.
    #[AttrUsage(AttributeUsage.Function | AttributeUsage.Struct | AttributeUsage.Enum | AttributeUsage.EnumValue)]
    attr Deprecated(msg: string? = null)

    // Sets the packing of the struct: the largest alignment given to its fields, in bytes.
    #[AttrUsage(AttributeUsage.Struct)]
    attr Pack(value: u8)

    // Forbids copying the struct.
    #[AttrUsage(AttributeUsage.Struct)]
    attr NoCopy()

    // Marks a struct that stores callbacks invoked with the object owning the field.
    //
    // A callback connected through 'owner.field' with an operator or a method of the struct
    // receives 'owner' with its static type, which starts with the type the callback declares.
    // The owner passes itself as the first argument when it invokes them, and the struct is
    // not copyable, so callbacks never reach another owner.
    #[AttrUsage(AttributeUsage.Struct)]
    attr Signal()

    // Enables dynamic type tests and checked downcasts through pointers to this struct.
    //
    // Adds one compiler-managed metadata pointer to its storage. Structs that embed a
    // dynamic parent by value with 'using' inherit this capability and reuse its slot.
    // Ordinary pointers retain their size. Pointer-valued 'using' fields do not propagate
    // dynamic identity.
    #[AttrUsage(AttributeUsage.Struct)]
    attr DynCast()

    // Exports the struct without its fields: users see its name and methods only.
    //
    // 'runtimeDefault' and 'requiresInit' carry initialization metadata in generated
    // module APIs. Source declarations normally leave both at their defaults.
    #[AttrUsage(AttributeUsage.Struct)]
    attr Opaque(runtimeDefault: bool = false, requiresInit: bool = false)

    // Places the struct field at the offset of the field 'name', so both share storage.
    #[AttrUsage(AttributeUsage.StructVariable)]
    attr Offset(name: string)

    // Makes the enum a set of flags, combined with bitwise operators.
    #[AttrUsage(AttributeUsage.Enum)]
    attr EnumFlags()

    // Forbids two values of the enum from being equal.
    #[AttrUsage(AttributeUsage.Enum)]
    attr NoDuplicate()

    // Declares that the values of the enum are not the full set.
    //
    // A value outside them is expected at runtime, so a switch on it is not meant to be exhaustive.
    #[AttrUsage(AttributeUsage.Enum | AttributeUsage.File)]
    attr Incomplete()

    // Runtime reflection data that [[ExportType]] adds to the type information of a struct.
    #[Swag.EnumFlags]
    enum ExportWhat: u32
    {
        Methods = 0x00000001
        NoZero  = 0x00000002
        None    = 0x00000000
        All     = 0xFFFFFFFF
    }

    // Adds runtime reflection data to the type information of the struct.
    //
    // With `.Methods`, the type information lists the methods of the struct's 'impl' blocks.
    #[AttrUsage(AttributeUsage.Struct)]
    attr ExportType(what: ExportWhat)

    // Leaves the declaration, or the whole file, out of the generated documentation.
    #[AttrUsage(AttributeUsage.All | AttributeUsage.File)]
    attr NoDoc()

    // Enables or disables static sanity checks in a declaration, a block, or a file.
    //
    // The static checks are the borrow analysis and the proven-fault sanitizer (use after move,
    // stack escapes, proven null dereferences, ...), selected with the [[SafetyWhat]] flags.
    // Unlike [[Safety]], they add no runtime cost and are enabled in every build configuration.
    #[AttrUsage(AttributeUsage.All | AttributeUsage.File | AttributeUsage.Scope), AttrMulti]
    attr Sanity(what: SafetyWhat, value: bool)

    // Computed borrow summary of a function, consumed by the static borrow analysis.
    //
    // Bit 'i' of 'returns' means the return value may borrow parameter #i; bit 'i' of
    // 'stores' means parameter #i may be stored in storage that outlives the call;
    // bit 'i*8+j' of 'into' means parameter #j may be stored into storage reachable
    // from parameter #i after the call returns (packed 8x8); bit 'i' of 'frees' means the call invalidates
    // what parameter #i points to (it reaches [[IAllocator.free]] or
    // [[IAllocator.realloc]]); bit 'i' of 'reallocates' means the call may move or
    // release the heap payload parameter #i OWNS, which is what invalidates the views
    // taken into it; bit 'i' of 'returnsPayload' means the returned value is a view INTO
    // that payload rather than merely a value that can reach parameter #i, which is what
    // tells a container accessor apart from a factory handing back an object that keeps a
    // back-reference. Emitted automatically in generated module APIs so summaries cross
    // module boundaries; can also be written manually on a [[Foreign]] function.
    // Bit 'i' of 'returnsStorage' means the result aliases parameter #i's storage,
    // rather than carrying a reference to it in a separate allocation. It only applies
    // to bits also set in 'returns'. Its default preserves the direct-alias assumption
    // of annotations that omit it; generated APIs emit the computed mask explicitly.
    // 'observesExternal' means the call may observe application borrowed storage through
    // globals, thread-local state, hidden aliases, or callbacks. Its default is conservative.
    // A manual 'false' on a [[Foreign]] declaration promises that the native operation
    // only observes application storage through its explicit arguments and invokes no
    // callback that can observe other application storage. Parameter retention remains
    // governed by the other masks. Ordinary function bodies always contribute their
    // computed effects, even when this argument is explicitly 'false'.
    //
    // 'returnsIndirect' and 'storesIndirect' use the same parameter bits as 'returns'
    // and 'stores', but describe borrows carried by the value reached after one
    // dereference of the parameter, rather than the address of that value. Bit
    // 'i*8+j' of 'intoIndirect' means those borrows from parameter #j's pointee may
    // be retained in storage reachable from parameter #i. The destination remains
    // direct. For example, copying 'source[]' into 'destination[]' can retain a
    // pointer field inside the source value without retaining the source's address.
    // These masks add facts; their zero defaults do not erase any direct-mask bits.
    // Bit 'i' of 'freesIndirect' means the call invalidates the pointer held in
    // parameter #i's pointee, without releasing the box holding that pointer.
    // Its zero default preserves summaries generated before this mask existed.
    // Deeper indirection without a separate proof remains conservative.
    #[AttrUsage(AttributeUsage.Function)]
    attr BorrowSummary(returns: u64, stores: u64 = 0, into: u64 = 0, frees: u64 = 0, reallocates: u64 = 0, returnsPayload: u64 = 0, returnsStorage: u64 = 0xFFFFFFFFFFFFFFFF, observesExternal: bool = true, returnsIndirect: u64 = 0, storesIndirect: u64 = 0, intoIndirect: u64 = 0, freesIndirect: u64 = 0)

    // Safety checks, selected by [[Safety]] at runtime and by [[Sanity]] at compile time.
    #[Swag.EnumFlags]
    enum SafetyWhat: u16
    {
        BoundCheck  = 0x0001     // Out-of-bounds index or slice
        Overflow    = 0x0002     // Arithmetic overflow, and conversions that lose bits or precision
        Math        = 0x0004     // Math functions called outside their domain, such as a negative 'Swag.sqrt'
        DynCast     = 0x0008     // Implicit extraction from erased types
        Switch      = 0x0010     // Unexpected value reaching a switch
        Bool        = 0x0020     // 'bool' holding neither 'true' nor 'false'
        NaN         = 0x0040     // 'NaN' used in float arithmetic
        Unreachable = 0x0080     // 'unreachable' being reached
        Null        = 0x0100     // Dereference of a null pointer
        Memory      = 0x0200     // Memory misuse, mostly found by the sanity pass
        Expect      = 0x0400     // Check presence for 'unwrap' and asserted accesses; 'expect' always panics on error
        Lifecycle   = 0x0800     // Use of moved-from values, and poisoning of abandoned or dropped storage
        Assert      = 0x1000     // Assertions; enabled by default in devmode and by the test command, including release
        Assume      = 0x2000     // Invariants asserted by 'assume', including casts and fallible operations
        ValueBorrow = 0x4000     // Writes or invalidation of storage borrowed by a value argument
        None        = 0x0000     // No check
        All         = 0xFFFF     // Every check
    }

    // Enables or disables runtime safety checks in a declaration, a block, or a file.
    #[AttrUsage(AttributeUsage.All | AttributeUsage.File | AttributeUsage.Scope), AttrMulti]
    attr Safety(what: SafetyWhat, value: bool)

    // Enables or disables optimized code generation in a function, a block, or a file.
    #[AttrUsage(AttributeUsage.Function | AttributeUsage.File | AttributeUsage.Scope), AttrMulti]
    attr Optimize(level: bool)

    // How a warning is reported. See [[Warning]].
    enum WarningLevel: u8
    {
        Disable     // Do not report the warning
        Warning     // Report the warning as a warning
        Error       // Report the warning as an error
    }

    // Sets how one warning, a list of warnings, or every warning is reported in a declaration, a block, or a file.
    //
    // A warning is named by its diagnostic identifier, the string `--diagnostic-id` prints;
    // `"all"` names every warning at once.
    // ```swag
    // #[Swag.Warning("sema_warn_unreachable_code", .Disable)]
    // #[Swag.Warning("sema_warn_unreachable_code|sema_warn_compiler_warning", .Error)]
    // #global #[Swag.Warning("all", .Error)]
    // ```
    // A decision that names a warning outranks a decision that says `"all"`, and this
    // attribute outranks both [[Swag.Build.Warnings]] and the `--warn-*` command-line options.
    #[AttrUsage(AttributeUsage.All | AttributeUsage.File | AttributeUsage.Scope), AttrMulti]
    attr Warning(what: string, level: WarningLevel)

    // Keeps the alias distinct from its target: no implicit conversion goes between them.
    #[AttrUsage(AttributeUsage.Alias)]
    attr Strict()

    // Sets the alignment of a struct or a struct field, in bytes.
    #[AttrUsage(AttributeUsage.Struct | AttributeUsage.StructVariable)]
    attr Align(value: u8)
}
