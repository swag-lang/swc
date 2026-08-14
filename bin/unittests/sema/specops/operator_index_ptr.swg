#global private

struct SemaElem
{
    x: s32
}

struct SemaContainer
{
    values: [4] SemaElem
}

impl SemaContainer
{
    mtd opIndexPtr(index: u64)->*SemaElem
    {
        return &.values[index]
    }

    mtd const opIndexPtr(index: u64)->const *SemaElem
    {
        return &.values[index]
    }

    // The indexed expression types as the element, and its address as the element pointer.
    mtd probe()
    {
        #assert(#typeof(me[0]) == #type SemaElem)
        #assert(#typeof(&me[0]) == #type *SemaElem)
        #assert(#typeof(me[0].x) == s32)
    }

    mtd const constProbe()
    {
        #assert(#typeof(&me[0]) == #type const *SemaElem)
    }
}

#test
{
    var c: SemaContainer
    #assert(#typeof(c[0]) == #type SemaElem)
    #assert(#typeof(&c[1]) == #type *SemaElem)
    #assert(#typeof(c[1].x) == s32)

    // Reading the element out is a copy of the element type.
    let v = c[2]
    #assert(#typeof(v) == #type SemaElem)
}
