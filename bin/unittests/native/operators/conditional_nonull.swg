#global private

struct NativeConditionalNonNullItem
{
    value: u32
}

struct(T) NativeConditionalIndex
{
    values: [1] T
}

impl NativeConditionalIndex
{
    #[Swag.Inline]
    mtd opIndex(index: u64)->&T
    {
        return &.values[index]
    }
}

func nativeConditionalNonNullBranches(flag: bool)->bool
{
    var first  = NativeConditionalNonNullItem{value: 11}
    var second = NativeConditionalNonNullItem{value: 22}
    var indexed = NativeConditionalIndex'(*NativeConditionalNonNullItem){values: [&first]}

    let legacy: *NativeConditionalNonNullItem          = &first
    let nullable: #null *NativeConditionalNonNullItem  = &first
    let required: *NativeConditionalNonNullItem = &second

    let indexedNullLast  = flag ? indexed[0] : null
    let indexedNullFirst = flag ? null : indexed[0]
    let requiredNullLast = flag ? required : null
    let requiredNullFirst = flag ? null : required
    let legacyRequiredFirst = flag ? legacy : required
    let legacyRequiredLast  = flag ? required : legacy
    let nullableRequiredFirst = flag ? nullable : required
    let nullableRequiredLast  = flag ? required : nullable
    let requiredOnly = flag ? required : required

    #assert(#typeof(indexedNullLast) == #null *NativeConditionalNonNullItem)
    #assert(#typeof(indexedNullFirst) == #null *NativeConditionalNonNullItem)
    #assert(#typeof(requiredNullLast) == #null *NativeConditionalNonNullItem)
    #assert(#typeof(requiredNullFirst) == #null *NativeConditionalNonNullItem)
    #assert(#typeof(legacyRequiredFirst) == *NativeConditionalNonNullItem)
    #assert(#typeof(legacyRequiredLast) == *NativeConditionalNonNullItem)
    #assert(#typeof(nullableRequiredFirst) == #null *NativeConditionalNonNullItem)
    #assert(#typeof(nullableRequiredLast) == #null *NativeConditionalNonNullItem)
    #assert(#typeof(requiredOnly) == *NativeConditionalNonNullItem)

    if flag
    {
        return indexedNullLast == &first and
               indexedNullFirst == null and
               requiredNullLast == &second and
               requiredNullFirst == null and
               legacyRequiredFirst == &first and
               legacyRequiredLast == &second and
               nullableRequiredFirst == &first and
               nullableRequiredLast == &second and
               requiredOnly == &second
    }

    return indexedNullLast == null and
           indexedNullFirst == &first and
           requiredNullLast == null and
           requiredNullFirst == &second and
           legacyRequiredFirst == &second and
           legacyRequiredLast == &first and
           nullableRequiredFirst == &second and
           nullableRequiredLast == &first and
           requiredOnly == &second
}

#test
{
    @assert(nativeConditionalNonNullBranches(true))
    @assert(nativeConditionalNonNullBranches(false))
}
