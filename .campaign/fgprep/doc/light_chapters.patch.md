# Light chapters — old->new hunks (one section per file)

All paths relative to `bin/reference/modules/language/src/`.

---

## 002_007_keywords.swg / 002_008_sigils.swg — VERIFIED, NO CHANGE

Both catalogues were swept: no `&T` type spelling, no reference-world prose. `dref`
is already listed in "Values, Errors, and Conversion" (002_007) and `cast #bit
#unconst (*s32) p` (002_008) is already pointer-world. Nothing to do.

## 007_006_ufcs.swg — one prose amendment

The chapter's code is already pointer-world. Amend the "Static Functions as Methods"
prose so the automatic address-taking is stated.

OLD (lines ~18-21):
```
# Static Functions as Methods
All functions in Swag are static, but UFCS enables them to be invoked with instance-style syntax.
This improves clarity when working with structs or objects.
```

NEW:
```
# Static Functions as Methods
All functions in Swag are static, but UFCS enables them to be invoked with instance-style syntax.
When the first parameter is a pointer to the value's type, the UFCS call takes the value's
address automatically: 'pt.set(10)' below passes '&pt'. This improves clarity when working
with structs or objects.
```

---

## 013_004_borrowing.swg — drop "reference" from the views list

OLD (lines ~6-7):
```
A **view** is a value that reads storage it does not own: a pointer, a reference, a
slice, a 'string', an 'any', an interface, a closure capturing by address. Swag has one
```

NEW:
```
A **view** is a value that reads storage it does not own: a pointer, a slice, a
'string', an 'any', an interface, a closure capturing by address. Swag has one
```

(The two later "back-reference" occurrences are ordinary English and stay.)

---

## 004_000_data_structures.swg — drop the deleted chapter from the list

OLD (lines ~3-6):
```
Swag provides fixed arrays, slices, tuples, enums, unions, pointers,
references, and the type-erased 'any' value. Choose the representation that
matches ownership and lifetime: arrays own inline storage, slices borrow a
contiguous range, and pointers make indirection and nullability explicit.
```

NEW:
```
Swag provides fixed arrays, slices, tuples, enums, unions, pointers, and the
type-erased 'any' value. Choose the representation that matches ownership and
lifetime: arrays own inline storage, slices borrow a contiguous range, and
pointers make indirection and nullability explicit.
```

---

## 004_009_any.swg — pointer vocabulary + drop the 'const &' cast

### Hunk 1 (lines ~6-12)

OLD:
```
'any' is a dynamically typed reference that can point to a value of any concrete type.

> WARNING:
> 'any' is **not** a variant. It holds a reference to an existing value plus its runtime type
> info. Assigning to an 'any' never copies the value, so an 'any' is a view for the purposes
> of the borrow rules, and must not outlive the storage it refers to. See the 'Borrowing'
> section.
```

NEW:
```
'any' is a dynamically typed view that can point to a value of any concrete type.

> WARNING:
> 'any' is **not** a variant. It holds the address of an existing value plus its runtime type
> info. Assigning to an 'any' never copies the value, so an 'any' is a view for the purposes
> of the borrow rules, and must not outlive the storage it refers to. See the 'Borrowing'
> section.
```

### Hunk 2 (lines ~48-49)

OLD:
```
'#typeof' on an 'any' yields 'any' (the reference type).
Use '@kindof' to get the concrete runtime type of the referenced value.
```

NEW:
```
'#typeof' on an 'any' yields 'any' (the type of the view itself).
Use '@kindof' to get the concrete runtime type of the viewed value.
```

### Hunk 3 (lines ~63-81)

OLD:
```
# Retrieving Values from 'any'

You can retrieve the stored value directly or as a constant reference.
*/

#test
{
    let a: any = 42
    #assert(#typeof(a) == any)
    @assert(@kindof(a) == s32)

    let b = cast(s32) a     // Get the value itself
    @assert(b == 42)

    let c = cast(const &s32) a     // Get a constant reference to the value
    let d = cast(const *s32) a     // Get a constant pointer to the value
    @assert(c == 42)
    @assert(dref d == 42)
}
```

NEW:
```
# Retrieving Values from 'any'

You can retrieve the stored value directly or through a constant pointer.
*/

#test
{
    let a: any = 42
    #assert(#typeof(a) == any)
    @assert(@kindof(a) == s32)

    let b = cast(s32) a     // Get the value itself
    @assert(b == 42)

    let d = cast(const *s32) a     // Get a constant pointer to the value
    @assert(dref d == 42)
}
```

---

## 006_001_declaration.swg — struct arguments are by-value (const-address ABI)

OLD (lines ~166-171):
```
# Structs as Function Arguments

Functions can take a struct as an argument. This is done by reference,
with no copy made — equivalent to passing a const reference in C++.
```

NEW:
```
# Structs as Function Arguments

Functions take a struct argument as an immutable **value**. Under the hood the
compiler passes the struct's address rather than copying it, but the callee
cannot write through the parameter, so the code behaves as if a private copy had
been made — at zero copy cost. To let a function modify the caller's struct,
pass its address explicitly through a pointer parameter ('*Struct3').
```

---

## 006_002_impl.swg — 'me' is a pointer; reflected method type; loop binding

### Hunk 1 (line ~43)

OLD:
```
    // 'me' is implicitly 'var me: MyStruct'
```

NEW:
```
    // 'me' is the receiver's address: an implicit non-null '*MyStruct'
```

### Hunk 2 (line ~84)

OLD:
```
alias ReflectedMyStructMethod = func(&MyStruct)->s32
```

NEW:
```
alias ReflectedMyStructMethod = func(*MyStruct)->s32
```

### Hunk 3 (lines ~92-99)

OLD:
```
    for &method in methods
    {
        if method.name == "returnX"
        {
            returnX = &method
            break
        }
    }
```

NEW:
```
    for &method in methods
    {
        if method.name == "returnX"
        {
            returnX = method
            break
        }
    }
```

('for &method' over the const 'methods' slice binds 'const *Swag.TypeValue', so the
binding itself is the address to keep; the slice lives in the constant segment, so it
may escape the loop.)

---

## 003_006_operators.swg — opEquals takes its operand by value

OLD (lines ~144-151):
```
impl Tolerance
{
    // Two readings one unit apart count as the same reading.
    mtd const opEquals(other: const &Tolerance)->bool
    {
        return .value == other.value or .value + 1 == other.value or .value == other.value + 1
    }
}
```

NEW:
```
impl Tolerance
{
    // Two readings one unit apart count as the same reading.
    mtd const opEquals(other: Tolerance)->bool
    {
        return .value == other.value or .value + 1 == other.value or .value == other.value + 1
    }
}
```

---

## 007_003_closure.swg — "by reference" becomes "by address" (code unchanged)

### Hunk 1 (lines ~9-13)

OLD:
```
A by-value capture is a plain byte copy into the closure: the closure never runs
'opPostCopy' on the way in and never drops the captured value. Only simple types
(without 'opDrop', 'opPostCopy', or 'opPostMove', and not marked '#[Swag.NoCopy]')
can therefore be captured by value; other types must be captured by reference
with '&'.
```

NEW:
```
A by-value capture is a plain byte copy into the closure: the closure never runs
'opPostCopy' on the way in and never drops the captured value. Only simple types
(without 'opDrop', 'opPostCopy', or 'opPostMove', and not marked '#[Swag.NoCopy]')
can therefore be captured by value; other types must be captured by address
with '&'.
```

### Hunk 2 (lines ~62-65)

OLD:
```
# Capturing Variables by Reference

Use '&' to capture by reference; otherwise, capture is by value.
```

NEW:
```
# Capturing Variables by Address

Use '&' to capture the variable's address; otherwise, capture is by value. An
'&' capture aliases the outer variable: reads and writes in the closure body
reach the original storage.
```

### Hunk 3 (line ~81)

OLD:
```
# Aliased Reference Capture
```

NEW:
```
# Aliased Address Capture
```

---

## 015_002_macros.swg — drop the stale clause

OLD (lines ~179-181):
```
# Mutable Block Parameters
A 'var' parameter gives the injected code a mutable binding. A typed parameter
also types (and checks) the binding, which is required for references.
```

NEW:
```
# Mutable Block Parameters
A 'var' parameter gives the injected code a mutable binding. A typed parameter
also types (and checks) the binding.
```
