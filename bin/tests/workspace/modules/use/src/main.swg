using Dep

#main
{
    @assert(DEP_VALUE == 7)
    @assert(DEP_PUBLIC_DEFAULT == 11)
    @assert(DEP_MULTI_A == 13)
    @assert(DEP_MULTI_B == 17)
    @assert(DepTools.DEP_NAMESPACE_A == 31)
    @assert(DepTools.DEP_NAMESPACE_B == 37)
    @assert(DepTools.DEP_NAMESPACE_C == 41)
    @assert(DepTools.Deep.DEP_NAMESPACE_DEEP == 43)
    @assert(depLegacyValue() == 5)

    var count: DepCount = 19
    @assert(count == 19)

    var pair: DepPair
    pair.left  = 2
    pair.right = 5
    @assert(pair.left + pair.right == 7)

    var value = DepValue{asInt: 0x1234}
    @assert(value.asInt == 0x1234)

    #assert(#sizeof(DepOpaque) == 16)
    #assert(#alignof(DepOpaque) == 8)
    var opaque: DepOpaque
    @assert(#sizeof(opaque) == 16)

    var namespaced: DepTools.DepNamespaced
    namespaced.value = 12
    @assert(namespaced.value == 12)
}
