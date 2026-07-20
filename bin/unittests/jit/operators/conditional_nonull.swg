#global private

struct JitConditionalNonNullItem
{
    value: u32
}

struct(T) JitConditionalIndex
{
    values: [1] T
}

impl JitConditionalIndex
{
    #[Swag.Inline]
    mtd opIndex(index: u64)->&T
    {
        return &.values[index]
    }
}

func jitConditionalNonNullBranches(flag: bool)->bool
{
    var first  = JitConditionalNonNullItem{value: 11}
    var second = JitConditionalNonNullItem{value: 22}
    var indexed = JitConditionalIndex'(*JitConditionalNonNullItem){values: [&first]}

    let legacy: *JitConditionalNonNullItem          = &first
    let nullable: #null *JitConditionalNonNullItem  = &first
    let required: *JitConditionalNonNullItem = &second

    let indexedNullLast  = flag ? indexed[0] : null
    let indexedNullFirst = flag ? null : indexed[0]
    let requiredNullLast = flag ? required : null
    let requiredNullFirst = flag ? null : required
    let legacyRequiredFirst = flag ? legacy : required
    let legacyRequiredLast  = flag ? required : legacy
    let nullableRequiredFirst = flag ? nullable : required
    let nullableRequiredLast  = flag ? required : nullable
    let requiredOnly = flag ? required : required

    #assert(#typeof(indexedNullLast) == #null *JitConditionalNonNullItem)
    #assert(#typeof(indexedNullFirst) == #null *JitConditionalNonNullItem)
    #assert(#typeof(requiredNullLast) == #null *JitConditionalNonNullItem)
    #assert(#typeof(requiredNullFirst) == #null *JitConditionalNonNullItem)
    #assert(#typeof(legacyRequiredFirst) == *JitConditionalNonNullItem)
    #assert(#typeof(legacyRequiredLast) == *JitConditionalNonNullItem)
    #assert(#typeof(nullableRequiredFirst) == #null *JitConditionalNonNullItem)
    #assert(#typeof(nullableRequiredLast) == #null *JitConditionalNonNullItem)
    #assert(#typeof(requiredOnly) == *JitConditionalNonNullItem)

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
    @assert(jitConditionalNonNullBranches(true))
    @assert(jitConditionalNonNullBranches(false))
}
