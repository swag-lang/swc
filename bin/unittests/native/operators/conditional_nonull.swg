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
    mtd opIndexPtr(index: u64)->*T
    {
        return &.values[index]
    }
}

func nativeConditionalMaybe(p: *NativeConditionalNonNullItem)->*NativeConditionalNonNullItem? => p

func nativeConditionalNonNullBranches(flag: bool)->bool
{
    var first   = NativeConditionalNonNullItem{value: 11}
    var second  = NativeConditionalNonNullItem{value: 22}
    var indexed = NativeConditionalIndex'(*NativeConditionalNonNullItem){values: [&first]}

    let legacy:   *NativeConditionalNonNullItem  = &first
    let nullable: *NativeConditionalNonNullItem? = nativeConditionalMaybe(&first)
    let required: *NativeConditionalNonNullItem  = &second

    let indexedNullLast       = flag ? indexed[0] : null
    let indexedNullFirst      = flag ? null : indexed[0]
    let requiredNullLast      = flag ? required : null
    let requiredNullFirst     = flag ? null : required
    let legacyRequiredFirst   = flag ? legacy : required
    let legacyRequiredLast    = flag ? required : legacy
    let nullableRequiredFirst = flag ? nullable : required
    let nullableRequiredLast  = flag ? required : nullable
    let requiredOnly          = flag ? required : required

    #assert(#typeof(indexedNullLast) == *NativeConditionalNonNullItem?)
    #assert(#typeof(indexedNullFirst) == *NativeConditionalNonNullItem?)
    #assert(#typeof(requiredNullLast) == *NativeConditionalNonNullItem?)
    #assert(#typeof(requiredNullFirst) == *NativeConditionalNonNullItem?)
    #assert(#typeof(legacyRequiredFirst) == *NativeConditionalNonNullItem)
    #assert(#typeof(legacyRequiredLast) == *NativeConditionalNonNullItem)
    #assert(#typeof(nullableRequiredFirst) == *NativeConditionalNonNullItem?)
    #assert(#typeof(nullableRequiredLast) == *NativeConditionalNonNullItem?)
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
    Swag.assert(nativeConditionalNonNullBranches(true))
    Swag.assert(nativeConditionalNonNullBranches(false))
}
