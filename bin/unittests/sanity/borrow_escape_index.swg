#global public
// Reading a single element out of a container by value must not make the CONTAINER
// escape: 'container[i]' yields the element value (a copy), which aliases neither the
// container storage nor the slice the struct decays to when indexed through 'opIndex'.
#global #[Swag.Sanity(.Lifecycle, true)]
using Swag

struct BorrowIndexVec
{
    buffer: [8] *s32
    count:  u64
}

impl BorrowIndexVec
{
    #[Swag.Inline]
    mtd const opIndex(index: u64)->const &*s32
    {
        return &.buffer[index]
    }

    mtd add(value: *s32)
    {
        me.buffer[me.count] = value
        me.count += 1
    }
}

struct BorrowIndexHolder
{
    picked: *s32
}

// Copying a pointer element out of a local container into caller-owned storage is fine:
// the pointer value points at 'src' (caller-owned), not into the local 'vec'.
func borrowIndexPointerElementCopy(h: *BorrowIndexHolder, src: *s32)
{
    var vec: BorrowIndexVec = undefined
    vec.count = 0
    vec.add(src)
    h.picked = vec[0]
}

// Same through a builtin array of pointers.
func borrowIndexBuiltinArrayElement(h: *BorrowIndexHolder, src: *s32)
{
    var arr: [4] *s32 = undefined
    arr[0] = src
    h.picked = arr[0]
}
