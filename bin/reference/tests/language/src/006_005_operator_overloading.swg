#global fileprivate
/**
A struct in Swag can define operator overloads within the 'impl' block. These hooks are
predefined and recognized by the compiler, which lets a struct customize operators and
core interactions.
*/

struct Struct
{
    x, y: s32 // Two properties, x and y, of type s32 (signed 32-bit integer)
}

// Type aliases used in the examples below
alias OneType      = bool // Alias for boolean type
alias AnotherType  = s32 // Alias for signed 32-bit integer type
alias WhateverType = bool // Another alias for boolean type

#[Swag.Operators(opEquals, opCompare)]
struct AutoComparable
{
    x, y: s32
    #[Swag.OperatorIgnore]
    cachedHash: u64
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
    func opSlice(me, low, up: u64)->string { return "true"; }

    // Access a value by one or more indices. All index parameters must have the same type.
    func opIndex(me, index: OneType)->WhateverType { return true; }
    func opIndex(me, row: OneType, column: OneType)->WhateverType { return true; }

    // Called when @countof is used (typically in a 'for' block) to return the count of elements
    func opCount(me)->u64 { return 0; }

    // Called when @dataof is used; returns a pointer to the underlying data of type WhateverType
    func opData(me)->#null *WhateverType { return null; }

    // -------------------------------------------------------------------------
    // Conversions (cast)
    // -------------------------------------------------------------------------

    // Custom casting between the struct and another type; can be overloaded with different return types
    // Example: var x = cast(OneType) v
    func opCast(me)->OneType { return true; }
    func opCast(me)->AnotherType { return 0; }

    // -------------------------------------------------------------------------
    // Equality & ordering
    // -------------------------------------------------------------------------

    // Compare the struct value with another; used in '==' and '!=' operations
    func opEquals(me, other: OneType)->bool { return false; }
    func opEquals(me, other: AnotherType)->bool { return false; }

    // Three-way comparison; returns -1, 0, or 1 (used for '<', '>', '<=', '>=', '<=>')
    func opCompare(me, other: OneType)->s32 { return 0; }
    func opCompare(me, other: AnotherType)->s32 { return 0; }

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
    // When both opIndexSet and opIndex can write, opIndexSet is selected.
    func opIndexSet(me, index: OneType, value: OneType) {}
    func opIndexSet(me, row: OneType, column: OneType, value: OneType) {}
    func opIndexSet(me, index: OneType, value: AnotherType) {}

    // -------------------------------------------------------------------------
    // Operators (binary, unary, compound assignment)
    // -------------------------------------------------------------------------

    // Binary operation with 'op' representing the operator as a string
    // Examples: '+', '-', '*', '/', '%', '|', '&', '^', '<<', '>>'
    func(op: string) opBinary(me, other: OneType)->Struct { return {1, 2}; }
    func(op: string) opBinary(me, other: AnotherType)->Struct { return {1, 2}; }

    // Binary operation when this struct is the right operand
    // Examples: OneType + myStruct, AnotherType * myStruct
    func(op: string) opBinaryRight(me, other: OneType)->Struct { return {1, 2}; }
    func(op: string) opBinaryRight(me, other: AnotherType)->Struct { return {1, 2}; }

    // A commutative opBinary can also be used when the struct is the right operand.
    // Restrict the operators when a generic opBinary also handles non-commutative ones.
    #[Swag.Commutative("+", "*")]
    func(op: string) opBinary(me, other: u32)->Struct { return {1, 2}; }

    // Unary operation with 'op' representing the operator as a string
    // Examples: '!', '-', '~'
    func(op: string) opUnary(me)->Struct { return {1, 2}; }

    // Assignment with operator 'op' (compound assignments)
    // Examples: '+=', '-=', '*=', '/=', '%=', '|=', '&=', '^=', '<<=', '>>='
    func(op: string) opAssign(me, other: OneType) {}
    func(op: string) opAssign(me, other: AnotherType) {}

    // Indexed assignment with operator 'op'. All index parameters must have the same type.
    // When both opIndexAssign and opIndex can write, opIndexAssign is selected.
    func(op: string) opIndexAssign(me, index: OneType, value: OneType) {}
    func(op: string) opIndexAssign(me, row: OneType, column: OneType, value: OneType) {}
    func(op: string) opIndexAssign(me, index: OneType, value: AnotherType) {}

    // -------------------------------------------------------------------------
    // Iteration (foreach support)
    // -------------------------------------------------------------------------

    // Called in a 'foreach' block to iterate over the struct's elements.
    // Multiple versions can be defined by adding a name after 'opVisit'.
    #[Swag.Macro]
    {
        func(ptr: bool, back: bool) opVisit(me, stmt: #code void) {}
        func(ptr: bool, back: bool) opVisitWhatever(me, stmt: #code void) {}
        func(ptr: bool, back: bool) opVisitAnother(me, stmt: #code void) {}
    }
}
