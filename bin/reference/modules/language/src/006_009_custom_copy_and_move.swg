#global private
/**
Swag supports both copy and move semantics for structures. In this example, we demonstrate these concepts using a 'Vector3' struct. Although a 'Vector3' typically wouldn't require move semantics (no heap allocation), this illustrates how these features can be implemented and used in Swag.
*/

struct Vector3
{
    x, y, z: s32 = 666
}

impl Vector3
{
    // Called after a copy; customize post-copy behavior here.
    mtd opPostCopy()
    {
        .x, .y, .z += 1
    }

    // Called after a move; customize post-move behavior here.
    mtd opPostMove()
    {
        .x, .y, .z += 2
    }

    // Called before destruction; place cleanup here if needed.
    mtd opDrop() {}
}

#test
{
    var a = Vector3{}                  // Default init.
    var b = Vector3{100, 200, 300}     // Custom init.

    // Copy semantics: drop 'a' (if needed), copy 'b' to 'a', then call 'opPostCopy' on 'a'.
    a = b
    @assert(a.x == 101)
    @assert(a.y == 201)
    @assert(a.z == 301)

    // Move semantics with '#move': drop 'a' (if needed), move 'b' to 'a', then call 'opPostMove' on 'a'.
    // With 'opDrop' present, 'b' is reinitialized to defaults (666).
    a = #move b
    @assert(a.x == 102)
    @assert(a.y == 202)
    @assert(a.z == 302)
    @assert(b.x == 666)

    // '#nodrop' skips the initial drop of 'a'.
    a = #nodrop b           // Copy without dropping 'a' first.
    a = #nodrop #move b     // Move without dropping 'a' first.

    // '#relocate' is the raw relocation used by container internals: the target is treated
    // as uninitialized (no drop) and the source is abandoned (no reinitialization). Use with care.
    a = #relocate b
}

/**
# Drop Elision

When the source of a '#move' is a plain local that is provably never used again — no
read or write after the move, no taken address, no capture, and a move that always
executes when its scope exits — the compiler elides both the reset of the source and
its scope-exit drop: 'opDrop' is then NOT called on the reset value. A program can
therefore not rely on counting the drops of fully consumed locals. Any use after the
move (or any use the compiler cannot prove harmless) keeps the documented
reset-then-drop behavior.
*/

/**
# Lifecycle Safety

Reading a value abandoned by '#relocate' — or by '#move' when the type has no 'opDrop',
which leaves the source unreset — reads stale bits. Under the 'Swag.SafetyWhat.Lifecycle'
safety guard (part of 'All', so enabled by default in debug configurations), the compiler
reports proven reads of moved-from locals at compile time, and poisons abandoned or
dropped storage with '0xDD' bytes at runtime so hidden violations fail deterministically
instead of silently reading stale data. A '#move' of a type with 'opDrop' is not
concerned: the source is reset to its defaults, which is defined behavior.
*/

/**
# Move Semantics in Functions

Move semantics can be expressed in function parameters by prefixing the parameter type with '#move'.
At the call site, prefix the argument with '#move' to pass it as a move reference.

A '#move' parameter also accepts a plain (copyable) value: the compiler then materializes a
temporary copy at the call site and passes it as the move reference. A single '#move' function
therefore serves both call styles — including through lambdas, function pointers and interface
methods — at the price of one extra copy on the copy path. This works for structs, for plain
scalar values (integers, floats, bool, rune, enums), and for untyped literals alike.

Conversely, an explicit '#move' argument is always honored. Passed to a '#move' parameter, it
is the zero-cost transfer above. Passed to a BY-VALUE parameter, the source is moved into a
call-site temporary that the callee borrows: the caller drops the temporary right after the
call, and the source is consumed. Passed to a reference or pointer parameter, it is a
compile-time error — the transfer would be silently ignored. On by-value scalars, '#move' is
accepted and equivalent to a plain pass.

A named function can avoid that extra copy by declaring the parameter with '#fwd' instead: the
compiler emits two overloads, a copy variant (the parameter behaves like a plain value) and a
move variant (the parameter behaves like '#move'). Inside the body, '#fwd' forwards the
parameter with the mode of the selected variant. Calls without '#move' then pick the dedicated
copy variant, with no temporary. With several '#fwd' parameters, a mixed call picks whichever
variant matches best; the '#move' arguments are honored either way — through the move
variant's parameter, or through a by-value move into the copy variant's parameter.

If the type is not copyable (marked with '#[Swag.NoCopy]'), the copy paths are
automatically discarded at overload resolution: only a '#move' call is accepted.
*/

#test
{
    // One declaration, two variants: 'assign(&v, x)' copies, 'assign(&v, #move x)' moves.
    func assign(assignTo: &Vector3, from: #fwd Vector3)
    {
        assignTo = #fwd from
    }

    var a  = Vector3{1, 2, 3}
    var b: Vector3

    // Copy path.
    assign(&b, a)
    @assert(b.x == 2 and b.y == 3 and b.z == 4)     // +1 via 'opPostCopy'.
    @assert(a.x == 1 and a.y == 2 and a.z == 3)     // 'a' unchanged.

    // Move path: '#move' passes 'a' as a move reference.
    assign(&b, #move a)
    @assert(b.x == 3 and b.y == 4 and b.z == 5)           // +2 via 'opPostMove'.
    @assert(a.x == 666 and a.y == 666 and a.z == 666)     // 'a' reset to defaults after move.
}

#test
{
    // A single '#move' function also accepts both call styles: a plain argument is
    // copied into a call-site temporary, then moved from it.
    func assign(assignTo: &Vector3, from: #move Vector3)
    {
        assignTo = #move from
    }

    var a  = Vector3{1, 2, 3}
    var b: Vector3

    // Copy call style: 'a' is copied into a temporary (+1), the temporary is moved (+2).
    assign(&b, a)
    @assert(b.x == 4 and b.y == 5 and b.z == 6)
    @assert(a.x == 1 and a.y == 2 and a.z == 3)     // 'a' unchanged.

    // Move call style: zero extra cost.
    assign(&b, #move a)
    @assert(b.x == 3 and b.y == 4 and b.z == 5)
    @assert(a.x == 666 and a.y == 666 and a.z == 666)
}
