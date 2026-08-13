# 006_009_custom_copy_and_move.swg — old->new hunks

Target: `bin/reference/modules/language/src/006_009_custom_copy_and_move.swg`

## Hunk 1 — prose, "Move Semantics in Functions" (lines ~91-105)

OLD:
```
Move semantics can be expressed in function parameters by prefixing the parameter type with '#move'.
At the call site, prefix the argument with '#move' to pass it as a move reference.

A '#move' parameter also accepts a plain (copyable) value: the compiler then materializes a
temporary copy at the call site and passes it as the move reference. A single '#move' function
```

NEW:
```
Move semantics can be expressed in function parameters by prefixing the parameter type with '#move'.
At the call site, prefix the argument with '#move' to hand the value over instead of copying it.

A '#move' parameter also accepts a plain (copyable) value: the compiler then materializes a
temporary copy at the call site and moves from that temporary. A single '#move' function
```

## Hunk 2 — prose, same section (lines ~100-105)

OLD:
```
Conversely, an explicit '#move' argument is always honored. Passed to a '#move' parameter, it
is the zero-cost transfer above. Passed to a BY-VALUE parameter, the source is moved into a
call-site temporary that the callee borrows: the caller drops the temporary right after the
call, and the source is consumed. Passed to a reference or pointer parameter, it is a
compile-time error — the transfer would be silently ignored. On by-value scalars, '#move' is
accepted and equivalent to a plain pass.
```

NEW:
```
Conversely, an explicit '#move' argument is always honored. Passed to a '#move' parameter, it
is the zero-cost transfer above. Passed to a BY-VALUE parameter, the source is moved into a
call-site temporary that the callee borrows: the caller drops the temporary right after the
call, and the source is consumed. Passed to a pointer parameter, it is a
compile-time error — the transfer would be silently ignored. On by-value scalars, '#move' is
accepted and equivalent to a plain pass.
```

## Hunk 3 — first '#fwd' test (lines ~119-125)

OLD:
```
    // One declaration, two variants: 'assign(&v, x)' copies, 'assign(&v, #move x)' moves.
    func assign(assignTo: &Vector3, from: #fwd Vector3)
    {
        assignTo = #fwd from
    }
```

NEW:
```
    // One declaration, two variants: 'assign(&v, x)' copies, 'assign(&v, #move x)' moves.
    func assign(assignTo: *Vector3, from: #fwd Vector3)
    {
        dref assignTo = #fwd from
    }
```

## Hunk 4 — comment in the same test (line ~135)

OLD:
```
    // Move path: '#move' passes 'a' as a move reference.
```

NEW:
```
    // Move path: '#move' transfers 'a' into the parameter.
```

## Hunk 5 — second '#move' test (lines ~143-148)

OLD:
```
    // A single '#move' function also accepts both call styles: a plain argument is
    // copied into a call-site temporary, then moved from it.
    func assign(assignTo: &Vector3, from: #move Vector3)
    {
        assignTo = #move from
    }
```

NEW:
```
    // A single '#move' function also accepts both call styles: a plain argument is
    // copied into a call-site temporary, then moved from it.
    func assign(assignTo: *Vector3, from: #move Vector3)
    {
        dref assignTo = #move from
    }
```

## Note for the apply step

`dref assignTo = #fwd from` / `dref assignTo = #move from` (a move assignment whose
target is a `dref` lvalue) is the form NOTES stage D flags as "to settle on tests"
(Sema.Assign assignmentTargetTypeRef). If the compiler ends up requiring another
spelling for a move-into-place through a pointer, these two bodies are the only
sites in the chapter that depend on the decision. Everything else in the file is
already pointer-world (call sites `assign(&b, ...)` are plain address-of and stay).
