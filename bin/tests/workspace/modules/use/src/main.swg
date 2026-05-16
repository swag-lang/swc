using Dep, DepLib

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

    @assert(depDouble(21) == 42)
    @assert(depTriple(14) == 42)
    @assert(depScale(cast(s32) 10) == 40)
    @assert(depScale(cast(f32) 2) == cast(f32) 8)

    var calc = DepCalculator.make(5)
    @assert(calc.add(cast(s32) 7) == 12)
    @assert(calc.add(cast(f32) 2) == cast(f32) 7)
    @assert(calc.addTwice(7) == 19)
    @assert(calc.sub(2) == 3)
}
