#global private

/**
A struct in Swag can define operator overloads within the 'impl' block. These hooks are
predefined and recognized by the compiler, which lets a struct customize operators and
core interactions.

'opBinary', 'opBinaryRight', 'opUnary', 'opAssign' and 'opIndexAssign' take the operator as
a compile-time 'Swag.Operator' value, so one hook covers a whole family and a misspelled
member is reported instead of being a comparison that silently never matches. Each spelling
has its own member: unary '-' arrives as 'Neg', binary '-' as 'Sub'. 'op.symbol()' returns
the source spelling when generated code or a diagnostic needs it.

Use a 'where' clause on 'op' to state which operators a hook handles. A failing constraint
removes that specialization from overload resolution; a '#error' reached in the body remains
a compile-time error and is reported where it occurs.

A container hands out element addresses with 'opIndexPtr', the place-forming twin of the
value-returning 'opIndex'. The compiler selects 'opIndexPtr' in place contexts â€” a member
access or method call on 'v[i]', the address '&v[i]', a nested index, or an assignment when
no dedicated write operator matches â€” and 'opIndex' for plain value reads. Declare a 'const'
overload returning 'const *T' so read-only receivers get a read-only element address.
'opIndexPtr' is never evaluated at compile time.

A literal suffix stays a string ('opSetLiteral'), because the set of suffixes is open-ended
and chosen by the user rather than by the language.

'#[Swag.Operators]' asks the compiler to write 'opEquals' and 'opCompare' from the members,
and '#[Swag.OperatorIgnore]' keeps one member out of them. A struct that asks for neither
still receives a member-wise 'opEquals' when one of its members compares its content rather
than its bytes, so a struct and its members never disagree about equality.
*/

struct Struct
{
    x, y: s32     // Two properties, x and y, of type s32 (signed 32-bit integer)
}

// Type aliases used in the examples below
alias OneType      = bool     // Alias for boolean type
alias AnotherType  = s32      // Alias for signed 32-bit integer type
alias WhateverType = bool     // Another alias for boolean type

#[Swag.Operators(opEquals, opCompare)]
struct AutoComparable
{
    x, y: s32
    #[Swag.OperatorIgnore]
    cachedHash: u64
}

#[Swag.Operators(opEquals, opCompare)]
struct(T) AutoComparableBox
{
    value: T
}

// Implementation: lifecycle, accessors, conversions, comparisons, assignments,
// indexing, binary/unary operators, and iteration hooks
impl Struct
{
    // -------------------------------------------------------------------------
    // Lifecycle hooks
    // -------------------------------------------------------------------------

    // Called whenever a variable of this struct is about to be destroyed (C++ destructor-like)
    func opDrop(me) {}

    // Invoked after a raw copy operation has been performed from one value to another
    func opPostCopy(me) {}

    // Called after a move semantic operation has been executed from one value to another
    func opPostMove(me) {}

    // -------------------------------------------------------------------------
    // Element & slice access
    // -------------------------------------------------------------------------

    // Access a value by slicing with the [low..up] notation. Returns a string or a slice.
    func opSlice(me, low, up: u64)->string
    {
        return "true"
    }

    // Access a value by one or more indices. All index parameters must have the same type.
    func opIndex(me, index: OneType)->WhateverType
    {
        return true
    }

    func opIndex(me, row: OneType, column: OneType)->WhateverType
    {
        return true
    }

    // Return the address of an element instead of its value. Selected in place contexts:
    // a member access or method call on 'v[i]', the address '&v[i]', a nested index, or
    // an assignment when no dedicated write operator matches.
    func opIndexPtr(me, index: OneType)->*AnotherType
    {
        return &me.x
    }

    // The 'const' overload serves read-only receivers with a read-only element address.
    func opIndexPtr(const me, index: OneType)->const *AnotherType
    {
        return &me.x
    }

    // Called when @countof is used (typically in a 'for' block) to return the count of elements
    func opCount(me)->u64
    {
        return 0
    }

    // Called when @dataof is used; returns a pointer to the underlying data of type WhateverType
    func opData(me)->#null *WhateverType
    {
        return null
    }

    // -------------------------------------------------------------------------
    // Conversions (cast)
    // -------------------------------------------------------------------------

    // Custom casting between the struct and another type; can be overloaded with different return types
    // Example: var x = cast(OneType) v
    func opCast(me)->OneType
    {
        return true
    }

    func opCast(me)->AnotherType
    {
        return 0
    }

    // -------------------------------------------------------------------------
    // Equality & ordering
    // -------------------------------------------------------------------------

    // Compare the struct value with another; used in '==' and '!=' operations
    func opEquals(me, other: OneType)->bool
    {
        return false
    }

    func opEquals(me, other: AnotherType)->bool
    {
        return false
    }

    // Three-way comparison; returns -1, 0, or 1 (used for '<', '>', '<=', '>=', '<=>')
    func opCompare(me, other: OneType)->s32
    {
        return 0
    }

    func opCompare(me, other: AnotherType)->s32
    {
        return 0
    }

    // -------------------------------------------------------------------------
    // Assignment
    // -------------------------------------------------------------------------

    // Direct assignment via '='
    func opSet(me, other: OneType) {}
    func opSet(me, other: AnotherType) {}

    // Assign a literal value with a specific suffix to the struct (generic)
    func(suffix: string) opSetLiteral(me, value: OneType) {}
    func(suffix: string) opSetLiteral(me, value: AnotherType) {}

    // Assign to an indexed position via '[?] ='. All index parameters must have the same type.
    // 'opIndexSet' keeps priority over writing through the 'opIndexPtr' element address.
    func opIndexSet(me, index: OneType, value: OneType) {}
    func opIndexSet(me, row: OneType, column: OneType, value: OneType) {}
    func opIndexSet(me, index: OneType, value: AnotherType) {}

    // -------------------------------------------------------------------------
    // Operators (binary, unary, compound assignment)
    // -------------------------------------------------------------------------

    // Binary operation. 'op' is the 'Swag.Operator' member the compiler asks for:
    // Add, Sub, Mul, Div, Mod, BitOr, BitAnd, BitXor, Shl, Shr
    func(op: Swag.Operator) opBinary(me, other: OneType)->Struct
        where op == .Add or op == .Sub
    {
        #static switch op
        {
        case .Add: return {1, 2}
        case .Sub: return {2, 1}
        }
    }

    func(op: Swag.Operator) opBinary(me, other: AnotherType)->Struct
    {
        return {1, 2}
    }

    // Binary operation when this struct is the right operand
    // Examples: OneType + myStruct, AnotherType * myStruct
    func(op: Swag.Operator) opBinaryRight(me, other: OneType)->Struct
    {
        return {1, 2}
    }

    func(op: Swag.Operator) opBinaryRight(me, other: AnotherType)->Struct
    {
        return {1, 2}
    }

    // A commutative opBinary can also be used when the struct is the right operand.
    // Restrict the operators when a generic opBinary also handles non-commutative ones.
    #[Swag.Commutative(.Add, .Mul)]
    func(op: Swag.Operator) opBinary(me, other: u32)->Struct
    {
        return {1, 2}
    }

    // Unary operation. 'op' is one of Not, Pos, Neg, BitNot.
    // Unary '-' arrives as 'Neg', so it never collides with the binary 'Sub'.
    func(op: Swag.Operator) opUnary(me)->Struct
    {
        return {1, 2}
    }

    // Compound assignment. 'op' is one of AddAssign, SubAssign, MulAssign, DivAssign,
    // ModAssign, BitOrAssign, BitAndAssign, BitXorAssign, ShlAssign, ShrAssign.
    func(op: Swag.Operator) opAssign(me, other: OneType) {}
    func(op: Swag.Operator) opAssign(me, other: AnotherType) {}

    // Indexed assignment with operator 'op'. All index parameters must have the same type.
    // 'opIndexAssign' keeps priority over writing through the 'opIndexPtr' element address.
    func(op: Swag.Operator) opIndexAssign(me, index: OneType, value: OneType) {}
    func(op: Swag.Operator) opIndexAssign(me, row: OneType, column: OneType, value: OneType) {}
    func(op: Swag.Operator) opIndexAssign(me, index: OneType, value: AnotherType) {}

    // -------------------------------------------------------------------------
    // Iteration ('for' support)
    // -------------------------------------------------------------------------

    // Called in a 'for' iteration block to iterate over the struct's elements.
    // Alternative traversals are ordinary view types that define their own opVisit.
    #[Swag.Macro]
    {
        func(ptr: bool) opVisit(me, stmt: #code) {}
    }
}
