# 006_005_operator_overloading.swg — old->new hunks (document opIndexPtr)

Target: `bin/reference/modules/language/src/006_005_operator_overloading.swg`

## Hunk 1 — header prose (after the paragraph ending "...reported where it occurs.", line ~17)

Insert a new paragraph between the 'where' paragraph and the literal-suffix paragraph:

NEW (inserted):
```
A container hands out element addresses with 'opIndexPtr', the place-forming twin of the
value-returning 'opIndex'. The compiler selects 'opIndexPtr' in place contexts — a member
access or method call on 'v[i]', the address '&v[i]', a nested index, or an assignment when
no dedicated write operator matches — and 'opIndex' for plain value reads. Declare a 'const'
overload returning 'const *T' so read-only receivers get a read-only element address.
'opIndexPtr' is never evaluated at compile time.
```

## Hunk 2 — catalogue, "Element & slice access" section (after the two 'opIndex' overloads, line ~88)

OLD:
```
    func opIndex(me, row: OneType, column: OneType)->WhateverType
    {
        return true
    }

    // Called when @countof is used (typically in a 'for' block) to return the count of elements
```

NEW:
```
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
```

## Hunk 3 — 'opIndexSet' comment (line ~155-156)

OLD:
```
    // Assign to an indexed position via '[?] ='. All index parameters must have the same type.
    // When both opIndexSet and opIndex can write, opIndexSet is selected.
```

NEW:
```
    // Assign to an indexed position via '[?] ='. All index parameters must have the same type.
    // 'opIndexSet' keeps priority over writing through the 'opIndexPtr' element address.
```

## Hunk 4 — 'opIndexAssign' comment (line ~214-215)

OLD:
```
    // Indexed assignment with operator 'op'. All index parameters must have the same type.
    // When both opIndexAssign and opIndex can write, opIndexAssign is selected.
```

NEW:
```
    // Indexed assignment with operator 'op'. All index parameters must have the same type.
    // 'opIndexAssign' keeps priority over writing through the 'opIndexPtr' element address.
```

## Grounding

Signature pair and selection rules mirror `bin/std/modules/core/src/collections/array.swg`
(mtd const opIndexPtr -> const *T / mtd opIndexPtr -> *T) and the behavior pinned by
`bin/unittests/native/specops/operator_index_ptr.swg` (place contexts, write-through when no
opIndexSet/opIndexAssign, const overload selection, escaping `&c[i]`, priority of the
dedicated write operators, value reads preferring opIndex). "Never const-eval" comes from
.campaign/NOTES.md "Décisions arrêtées". In the catalogue file, `me.x` is an `s32` and
`AnotherType` is the file's alias for `s32`, so `&me.x` types as `*AnotherType`.
