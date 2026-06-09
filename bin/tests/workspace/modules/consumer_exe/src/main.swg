using ExportApi, StaticApi, RuntimeCtxDll, RuntimeCtxBase, RuntimeCtxDirect

#assert(#sizeof(CtxAbiPair) == 8)
#assert(#alignof(CtxAbiPair) == 4)
#assert(#sizeof(CtxAbiPayload) == 32)
#assert(#alignof(CtxAbiPayload) == 8)
#assert(#sizeof(CtxAbiOffsets) == 16)
#assert(#alignof(CtxAbiOffsets) == 8)
#assert(#sizeof(CtxAbiFloatPack) == 24)
#assert(#alignof(CtxAbiFloatPack) == 8)

struct DepSelfBufferWrapper
{
    prev: DepSelfBufferSet
}

struct CtxSelfBufferWrapper
{
    prev: CtxSelfBufferSet
}

func keepDepScore(score: IDepScore)->IDepScore => score

var gImportedDefaultOuter: DepImportedDefaultOuter
const IMPORTED_DEFAULT_OUTER: DepImportedDefaultOuter

func verifyImportedImplicitStructDefaults()
{
    #assert(IMPORTED_DEFAULT_OUTER.required == 0)
    #assert(IMPORTED_DEFAULT_OUTER.timing.seed == 17)
    #assert(IMPORTED_DEFAULT_OUTER.marker == 42)
    @assert(IMPORTED_DEFAULT_OUTER.timing.minStep > 0.0)
    @assert(IMPORTED_DEFAULT_OUTER.timing.maxStep == 1.0)

    gImportedDefaultOuter.required = 11
    @assert(gImportedDefaultOuter.required == 11)
    @assert(gImportedDefaultOuter.timing.minStep > 0.0)
    @assert(gImportedDefaultOuter.timing.maxStep == 1.0)
    @assert(gImportedDefaultOuter.timing.seed == 17)
    @assert(gImportedDefaultOuter.marker == 42)

    var localDefault: DepImportedDefaultOuter
    localDefault.required = 13
    @assert(localDefault.required == 13)
    @assert(localDefault.timing.minStep > 0.0)
    @assert(localDefault.timing.maxStep == 1.0)
    @assert(localDefault.timing.seed == 17)
    @assert(localDefault.marker == 42)
}

func verifyImportedInterfaceTablePreparation()
{
    let objectType    = #typeof(DepTableScore{})
    let objectInfo    = cast(const *Swag.TypeInfoStruct) objectType
    let interfaceInfo = cast(const *Swag.TypeInfoStruct) #typeof(IDepTableScore)
    let table         = @tableof(objectInfo, interfaceInfo)
    @assert(table != null)

    var dynamicScore = @mkinterface(null, objectType, IDepTableScore)
    let runtimeScore = cast(*Swag.Interface) &dynamicScore
    @assert(runtimeScore != null)
    @assert(runtimeScore.itable == table)
    @assert(cast(const *Swag.TypeInfoStruct) dref runtimeScore.itable == objectInfo)

    var concreteScore = DepTableScore{value: 32}
    var castScore: IDepTableScore = concreteScore
    @assert(castScore.score() == 32)
}

func verifyImportedGenericRootMethodSema()
{
    var scratchRng = DepSharedRng.Rng.makeScratch'DepSharedRng.MWC()
    let scratchRngValue = scratchRng.nextU32()
    var rng: DepSharedRng.Rng'DepSharedRng.MWC
    let sharedRngValue = DepSharedRng.shared(&rng).nextU32()

    #assert(#typeof(scratchRngValue) == u32)
    #assert(#typeof(sharedRngValue) == u32)
}

func verifyImportedClosureCallbacks()
{
    var unarySet: DepByteSet = {values: ['C''u8, 'A''u8, 'B''u8, 0], count: 3}
    @assert(depInvokeUnary('C''u8, func|&unarySet|(x: u8)->bool { return unarySet.contains(x) }))
    @assert(!depInvokeUnary('Z''u8, func|&unarySet|(x: u8)->bool { return unarySet.contains(x) }))
    @assert(depInvokeUnary('A''u8, func|&unarySet|(x: u8)->bool { return unarySet.containsViaGeneric(x) }))

    var genericSet: DepByteSet = {values: ['C''u8, 'A''u8, 'B''u8, 0], count: 3}
    @assert(depInvokeGeneric('A''u8, func|&genericSet|(x: u8)->bool { return genericSet.contains(x) }))
    @assert(!depInvokeGeneric('Z''u8, func|&genericSet|(x: u8)->bool { return genericSet.contains(x) }))
    @assert(depInvokeGeneric('B''u8, func|&genericSet|(x: u8)->bool { return genericSet.containsViaGeneric(x) }))

    var prev: [3] u8 = ['C', 'A', 'B']
    var allOfSet: DepByteSet = {values: ['A''u8, 'B''u8, 'C''u8, 'D''u8], count: 4}
    @assert(depAllOf(prev[ to ], func|&allOfSet|(x: u8)->bool { return allOfSet.contains(x) }))
    @assert(depAllOf(prev[ to ], func|&allOfSet|(x: u8)->bool { return allOfSet.containsViaGeneric(x) }))

    var selfBufferSet = depMakeSelfBufferSet('A''u8, 'B''u8, 'C''u8, 'D''u8, 4)
    var prevSelfBufferSet = depMakeSelfBufferSet('C''u8, 'A''u8, 'B''u8, 0, 3)
    @assert(depInvokeUnary('A''u8, func|&selfBufferSet|(x: u8)->bool { return selfBufferSet.contains(x) }))
    @assert(depInvokeGeneric('B''u8, func|&selfBufferSet|(x: u8)->bool { return selfBufferSet.containsViaGeneric(x) }))
    @assert(depAllOf(prev[ to ], func|&selfBufferSet|(x: u8)->bool { return selfBufferSet.contains(x) }))
    @assert(depAllOf(prev[ to ], func|&selfBufferSet|(x: u8)->bool { return selfBufferSet.containsViaGeneric(x) }))
    @assert(depAllOf(prevSelfBufferSet.toSlice(), func|&selfBufferSet|(x: u8)->bool { return selfBufferSet.contains(x) }))
    @assert(depAllOf(prevSelfBufferSet.toSlice(), func|&selfBufferSet|(x: u8)->bool { return selfBufferSet.containsViaGeneric(x) }))
    let depWrappers = [DepSelfBufferWrapper{prev: prevSelfBufferSet}]
    foreach wrapper in depWrappers
    {
        @assert(depAllOf(wrapper.prev.toSlice(), func|&selfBufferSet|(x: u8)->bool { return selfBufferSet.contains(x) }))
        @assert(depAllOf(wrapper.prev.toSlice(), func|&selfBufferSet|(x: u8)->bool { return selfBufferSet.containsViaGeneric(x) }))
    }

    var sharedUnarySet: CtxClosureByteSet = {values: ['C''u8, 'A''u8, 'B''u8, 0], count: 3}
    @assert(ctxSharedInvokeUnary('C''u8, func|&sharedUnarySet|(x: u8)->bool { return sharedUnarySet.contains(x) }))
    @assert(!ctxSharedInvokeUnary('Z''u8, func|&sharedUnarySet|(x: u8)->bool { return sharedUnarySet.contains(x) }))
    @assert(ctxSharedInvokeUnary('A''u8, func|&sharedUnarySet|(x: u8)->bool { return sharedUnarySet.containsViaGeneric(x) }))

    var sharedGenericSet: CtxClosureByteSet = {values: ['C''u8, 'A''u8, 'B''u8, 0], count: 3}
    @assert(ctxSharedInvokeGeneric('A''u8, func|&sharedGenericSet|(x: u8)->bool { return sharedGenericSet.contains(x) }))
    @assert(!ctxSharedInvokeGeneric('Z''u8, func|&sharedGenericSet|(x: u8)->bool { return sharedGenericSet.contains(x) }))
    @assert(ctxSharedInvokeGeneric('B''u8, func|&sharedGenericSet|(x: u8)->bool { return sharedGenericSet.containsViaGeneric(x) }))

    var sharedPrev: [3] u8 = ['C', 'A', 'B']
    var sharedAllOfSet: CtxClosureByteSet = {values: ['A''u8, 'B''u8, 'C''u8, 'D''u8], count: 4}
    @assert(ctxSharedAllOf(sharedPrev[ to ], func|&sharedAllOfSet|(x: u8)->bool { return sharedAllOfSet.contains(x) }))
    @assert(ctxSharedAllOf(sharedPrev[ to ], func|&sharedAllOfSet|(x: u8)->bool { return sharedAllOfSet.containsViaGeneric(x) }))

    var sharedSelfBufferSet = ctxSharedMakeSelfBufferSet('A''u8, 'B''u8, 'C''u8, 'D''u8, 4)
    var sharedPrevSelfBufferSet = ctxSharedMakeSelfBufferSet('C''u8, 'A''u8, 'B''u8, 0, 3)
    @assert(ctxSharedInvokeUnary('A''u8, func|&sharedSelfBufferSet|(x: u8)->bool { return sharedSelfBufferSet.contains(x) }))
    @assert(ctxSharedInvokeGeneric('B''u8, func|&sharedSelfBufferSet|(x: u8)->bool { return sharedSelfBufferSet.containsViaGeneric(x) }))
    @assert(ctxSharedAllOf(sharedPrev[ to ], func|&sharedSelfBufferSet|(x: u8)->bool { return sharedSelfBufferSet.contains(x) }))
    @assert(ctxSharedAllOf(sharedPrev[ to ], func|&sharedSelfBufferSet|(x: u8)->bool { return sharedSelfBufferSet.containsViaGeneric(x) }))
    @assert(ctxSharedAllOf(sharedPrevSelfBufferSet.toSlice(), func|&sharedSelfBufferSet|(x: u8)->bool { return sharedSelfBufferSet.contains(x) }))
    @assert(ctxSharedAllOf(sharedPrevSelfBufferSet.toSlice(), func|&sharedSelfBufferSet|(x: u8)->bool { return sharedSelfBufferSet.containsViaGeneric(x) }))
    let sharedWrappers = [CtxSelfBufferWrapper{prev: sharedPrevSelfBufferSet}]
    foreach wrapper in sharedWrappers
    {
        @assert(ctxSharedAllOf(wrapper.prev.toSlice(), func|&sharedSelfBufferSet|(x: u8)->bool { return sharedSelfBufferSet.contains(x) }))
        @assert(ctxSharedAllOf(wrapper.prev.toSlice(), func|&sharedSelfBufferSet|(x: u8)->bool { return sharedSelfBufferSet.containsViaGeneric(x) }))
    }
}

func verifyExportAndStaticModules()
{
    @assert(DEP_VALUE == 7)
    @assert(DEP_PUBLIC_DEFAULT == 11)
    @assert(DEP_MULTI_A == 13)
    @assert(DEP_MULTI_B == 17)
    @assert(depFutureExport() == 7)
    @assert(depGeneratedExport() == 42)
    @assert(depPlaceholderExport(35) == 42)
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
    var shortCallOwner: DepShortCallOwner
    @assert(shortCallOwner.ready())
    @assert(#sizeof(DepPublicWithPrivateField) == 8)
    let publicWithPrivate = makeDepPublicWithPrivateField(41)
    @assert(publicWithPrivate.publicValue == 41)
    @assert(#sizeof(DepPublicWithPrivateInlineUnion) == 12)

    var genericLayout: DepGenericLayout's32
    genericLayout.value = 42
    @assert(genericLayout.value == 42)

    var value = DepValue{asInt: 0x1234}
    @assert(value.asInt == 0x1234)

    #assert(#sizeof(DepOpaque) == 16)
    #assert(#alignof(DepOpaque) == 8)
    var opaque: DepOpaque
    @assert(#sizeof(opaque) == 16)

    var opaqueGenericBox: DepOpaqueGenericBox
    opaqueGenericBox.init(7)
    @assert(opaqueGenericBox.addSeed(35) == 42)

    var namespaced: DepTools.DepNamespaced
    namespaced.value = 12
    @assert(namespaced.value == 12)
    @assert(DepTools.hash32WithGeneratedFullName(namespaced) == 0x10c'u32)
    @assert(DepTools.DepGeneratedCommandOwner.GeneratedAccept == "DepTools.DepGeneratedCommandOwner.GeneratedAccept")

    var staticInferredDepOwner: StaticInferredDepOwner
    staticInferredDepOwner.namespaced.value = 15
    @assert(staticInferredDepOwner.getNamespaced().value == 15)

    var ignoredContainer: DepIgnoredContainer
    ignoredContainer.run()

    @assert(depDouble(21) == 42)
    @assert(depMirror(42) == 42)
    @assert(depTriple(14) == 42)
    @assert(depStringLength("workspace") == 9)
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

func verifyDllAbiCalls()
{
    @assert(ctxSharedPassString("abi-string") == "abi-string")
    @assert(ctxSharedPassString("abi-string-2") == "abi-string-2")
    @assert(ctxSharedPassStringAt("abi-string", 1) == 98'u8)
    @assert(ctxSharedPassStringAt("abi-string", 2) == 'i''u8)
    @assert(ctxSharedPassStringAt("abi-string", 9) == 'g''u8)

    let array0 = ctxSharedPassArray([11, 22, 33, 44])
    let array1 = ctxSharedPassArray([101, 202, 303, 404])
    let array2 = ctxSharedPassArray([-1, -2, -3, -4])
    @assert(array0[0] == 11)
    @assert(array0[3] == 44)
    @assert(array1[0] == 101)
    @assert(array1[3] == 404)
    @assert(array2[0] == -1)
    @assert(array2[3] == -4)

    let pair0 = ctxSharedPassPair({a: 9, b: 13})
    let pair1 = ctxSharedMakePair(-9, -13)
    let payload0 = ctxSharedPassPayload(ctxSharedMakePayload(10))
    let payload1 = ctxSharedClonePayload(ctxSharedMakePayload(1))
    @assert(pair0.a == 9)
    @assert(pair0.b == 13)
    @assert(pair1.a == -9)
    @assert(pair1.b == -13)
    @assert(ctxSharedPassPairSum({a: 9, b: 13}) == 22)
    @assert(ctxSharedPassPairSum({a: 90, b: 130}) == 220)
    @assert(ctxSharedPassPairSum({a: -90, b: 130}) == 40)
    @assert(payload0.a0 == 11'u64)
    @assert(payload0.a3 == 14'u64)
    @assert(payload1.a0 == 2'u64)
    @assert(payload1.a3 == 5'u64)

    let offsets0 = ctxSharedMakeOffsets(1'u8, 2'u16, 3'u32, 4'u64)
    @assert(offsets0.a == 1'u8)
    @assert(offsets0.b == 2'u16)
    @assert(offsets0.c == 3'u32)
    @assert(offsets0.d == 4'u64)
    @assert(ctxSharedPassOffsets(offsets0) == 10'u64)

    let p0 = ctxSharedPassPointer(null)
    let p1 = ctxSharedPassPointer(cast(*void) 0x1234'u64)
    @assert(p0 == null)
    @assert(p1 == cast(*void) 0x1234'u64)
    @assert(ctxSharedPassMixed(3, "mix", {a: 10, b: 11}, [8, 9], null) == 131)
    @assert(ctxSharedPassMixed(30, "mix2", {a: 100, b: 110}, [80, 90], cast(*void) 0x4567'u64) == 330)

    const pairRef: CtxAbiPair = {a: 6, b: 7}
    @assert(ctxSharedPassConstRef(pairRef) == 13)
    @assert(ctxSharedPassConstRef({a: 8, b: 9}) == 17)
    @assert(ctxSharedPassScalars(-5's8, -123's16, 77's32, 5000's64, 9'u8, 10'u16, 11'u32, 12'u64, 1.25'f32, 2.5'f64, true, 'R') == 5077)
    @assert(ctxSharedPassBoolRunePositions(true, 3, 'Q', 4, true, 'W') == 177)
    @assert(ctxSharedPassBoolRunePositions(false, 30, 'Q', 40, false, 'W') == 238)
    @assert(ctxSharedPassBoolRunePositions(true, -3, 'Q', 7, false, 'W') == 173)
    @assert(ctxSharedPassAliasEnum(1, cast(CtxAbiAlias) 2, CtxAbiEnum.A, 3) == 23)
    @assert(ctxSharedPassAliasEnum(10, cast(CtxAbiAlias) 20, CtxAbiEnum.B, 30) == 183)
    @assert(ctxSharedPassAliasEnum(-10, cast(CtxAbiAlias) 20, CtxAbiEnum.A, -30) == -3)

    const values0: [4] s32 = [11, 22, 33, 44]
    const values1: [4] s32 = [101, 202, 303, 404]
    const values2: [4] s32 = [-1, -2, -3, -4]
    @assert(ctxSharedPassSlice(values0, 2) == 33)
    @assert(ctxSharedPassSlice(values1, 3) == 404)
    @assert(ctxSharedPassSlice(values2, 0) == -1)
    @assert(ctxSharedPassAggregatePositions(cast(*void) 0x10'u64, [5, 6], "abc", {a: 7, b: 8}, {a0: 1'u64, a1: 2'u64, a2: 3'u64, a3: 4'u64}) == 115'u64)
    @assert(ctxSharedPassAggregatePositions(null, [50, 60], "Abc", {a: 70, b: 80}, {a0: 10'u64, a1: 20'u64, a2: 30'u64, a3: 40'u64}) == 235'u64)
    @assert(ctxSharedPassNested({p: {a: 3, b: 4}, q: {a0: 10'u64, a1: 20'u64, a2: 30'u64, a3: 40'u64}}, 5) == 62'u64)
    @assert(ctxSharedPassKindof({a: 1, b: 2}, {a0: 3'u64, a1: 4'u64, a2: 5'u64, a3: 6'u64}, "ok", null, [7, 8], CtxAbiEnum.A))
    @assert(ctxSharedPassNestedArray({p: {a: 10, b: 11}, q: {a0: 1'u64, a1: 2'u64, a2: 3'u64, a3: 4'u64}}, [{a: 20, b: 21}, {a: 30, b: 31}]) == 61)

    var nested0 = ctxSharedMakeNested(7)
    @assert(nested0.p.a == 7)
    @assert(nested0.p.b == 8)
    @assert(nested0.q.a0 == 17'u64)
    @assert(nested0.q.a3 == 47'u64)

    let float0 = ctxSharedMakeFloatPack(0.5)
    let float1 = ctxSharedCloneFloatPack(ctxSharedMakeFloatPack(1.5))
    @assert(float0.r == 0.5)
    @assert(float0.g == 0.75)
    @assert(float0.b == 1.0)
    @assert(float1.r == 1.5)
    @assert(float1.g == 1.75)
    @assert(float1.b == 2.0)

    var writtenPair: CtxAbiPair = {a: 0, b: 0}
    ctxSharedWritePair(&writtenPair, 77, -33)
    @assert(writtenPair.a == 77)
    @assert(writtenPair.b == -33)

    var writtenPayload = CtxAbiPayload{a0: 0'u64, a1: 0'u64, a2: 0'u64, a3: 0'u64}
    ctxSharedWritePayload(&writtenPayload, 30'u64)
    @assert(writtenPayload.a0 == 31'u64)
    @assert(writtenPayload.a1 == 32'u64)
    @assert(writtenPayload.a2 == 33'u64)
    @assert(writtenPayload.a3 == 34'u64)

    @assert(ctxSharedScale(cast(s32) 10) == 40)
    @assert(ctxSharedScale(cast(f32) 2) == cast(f32) 8)

    var calc = CtxAbiCalculator.make(5)
    @assert(CtxAbiCalculator.resolve(6) == 106)
    @assert(calc.resolve(6) == 1011)
    @assert(calc.add(cast(s32) 7) == 12)
    @assert(calc.add(cast(f32) 2) == cast(f32) 7)
    @assert(calc.sub(2) == 3)

    let calcPair = calc.makePair(2)
    @assert(calcPair.a == 7)
    @assert(calcPair.b == 3)

    let calcPayload = calc.makePayload(20'u64)
    @assert(calcPayload.a0 == 26'u64)
    @assert(calcPayload.a1 == 27'u64)
    @assert(calcPayload.a2 == 28'u64)
    @assert(calcPayload.a3 == 29'u64)
}

func verifyRuntimeContext()
{
    var cxt = dref @getcontext()
    cxt.user0 = 42
    cxt.user2 = cast(u64) @getcontext()
    @setcontext(cxt)

    let expectedContext = @getcontext().user2
    @assert(ctxBaseReadContext() == 42)
    @assert(ctxSharedReadContext() == 42)
    @assert(ctxDirectReadContext() == 42)
    @assert(ctxBaseContextMarker() == expectedContext)
    @assert(ctxSharedContextMarker() == expectedContext)
    @assert(ctxDirectContextMarker() == expectedContext)
    @assert(ctxBaseInitCount() == 2)
    @assert(ctxBasePreMainCount() == 2)
}

#init
{
    @assert((@getcontext().user1 & CTX_SHARED_INIT_FLAG) != 0)
    @assert((@getcontext().user1 & CTX_DIRECT_INIT_FLAG) != 0)
}

#premain
{
    @assert((@getcontext().user1 & CTX_SHARED_PREMAIN_FLAG) != 0)
    @assert((@getcontext().user1 & CTX_DIRECT_PREMAIN_FLAG) != 0)
}

#drop
{
    var cxt = dref @getcontext()
    cxt.user0 = 43
    @setcontext(cxt)
}

var gEvtClassified: s32

func onDepEvt(evt: IDepEvt)
{
    if evt is DepDestroyEvt do
        gEvtClassified = 1
    elif evt is DepResizeEvt do
        gEvtClassified = 3
    else do
        gEvtClassified = -1
}

func verifyEmptyDerivedInterfaceIs()
{
    gEvtClassified = 0
    depDispatchEvt(&onDepEvt, 1)
    @assert(gEvtClassified == 1)

    gEvtClassified = 0
    depDispatchEvt(&onDepEvt, 3)
    @assert(gEvtClassified == 3)
}

#main
{
    verifyImportedImplicitStructDefaults()
    verifyExportAndStaticModules()
    verifyImportedInterfaceTablePreparation()
    verifyImportedGenericRootMethodSema()
    verifyImportedClosureCallbacks()
    verifyDllAbiCalls()
    verifyRuntimeContext()
    verifyEmptyDerivedInterfaceIs()
}
