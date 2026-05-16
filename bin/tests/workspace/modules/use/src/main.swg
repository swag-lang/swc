using Dep, DepLib

func keepDepScore(score: IDepScore)->IDepScore => score

#main
{
    @assert(DEP_VALUE == 7)
    @assert(DEP_PUBLIC_DEFAULT == 11)
    @assert(DEP_MULTI_A == 13)
    @assert(DEP_MULTI_B == 17)
    @assert(depFutureExport() == 7)
    @assert(depGenericIdentity(42) == 42)
    @assert(DepTools.DEP_NAMESPACE_A == 31)
    @assert(DepTools.DEP_NAMESPACE_B == 37)
    @assert(DepTools.DEP_NAMESPACE_C == 41)
    @assert(DepTools.Deep.DEP_NAMESPACE_DEEP == 43)
    @assert(depLegacyValue() == 5)

    var count: DepCount = 19
    @assert(count == 19)
    var mode: DepMode = .Big
    @assert(mode == .Big)

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
    var ignoredContainer: DepIgnoredContainer
    ignoredContainer.run()

    @assert(depDouble(21) == 42)
    @assert(depMirror(42) == 42)
    @assert(depTriple(14) == 42)
    @assert(depMacroTwicePlus(20, 2) == 42)
    @assert(depScale(cast(s32) 10) == 40)
    @assert(depScale(cast(f32) 2) == cast(f32) 8)

    var total = 0
    depMixinAccumulateTwice(21)
    @assert(total == 42)

    var calc = DepCalculator.make(5)
    @assert(DepCalculator.resolve(6) == 106)
    @assert(calc.resolve(6) == 1011)
    @assert(calc.add(cast(s32) 7) == 12)
    @assert(calc.add(cast(f32) 2) == cast(f32) 7)
    @assert(calc.addTwice(7) == 19)
    @assert(calc.sub(2) == 3)
}
