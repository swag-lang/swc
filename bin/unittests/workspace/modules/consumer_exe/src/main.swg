using ExportApi, StaticApi, RuntimeCtxDll, RuntimeCtxBase, RuntimeCtxDirect

#assert(#sizeof(CtxAbiPair) == 8)
#assert(#alignof(CtxAbiPair) == 4)
#assert(#sizeof(CtxAbiPayload) == 32)
#assert(#alignof(CtxAbiPayload) == 8)
#assert(#sizeof(CtxAbiOffsets) == 16)
#assert(#alignof(CtxAbiOffsets) == 8)
#assert(#sizeof(CtxAbiFloatPack) == 24)
#assert(#alignof(CtxAbiFloatPack) == 8)
#assert(#sizeof(CtxAbiFloatPair) == 8)
#assert(#alignof(CtxAbiFloatPair) == 4)
#assert(depInlineConstexpr(20) == 42)
#assert(depInlineIncrement(41) == 42)
const WORKSPACE_DOC_PROBE = #run ctxSharedPassStringAt("workspace", 0)
#assert(WORKSPACE_DOC_PROBE == 'w')

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
var gStaticInlineStorage = [7'u8]
var gStaticInlineBuffer:   StaticInlineBuffer
const IMPORTED_DEFAULT_OUTER: DepImportedDefaultOuter

func verifyImportedImplicitStructDefaults()
{
    #assert(IMPORTED_DEFAULT_OUTER.required == 0)
    #assert(IMPORTED_DEFAULT_OUTER.timing.seed == 17)
    #assert(IMPORTED_DEFAULT_OUTER.marker == 42)
    Swag.assert(IMPORTED_DEFAULT_OUTER.timing.minStep > 0.0)
    Swag.assert(IMPORTED_DEFAULT_OUTER.timing.maxStep == 1.0)

    gImportedDefaultOuter.required = 11
    Swag.assert(gImportedDefaultOuter.required == 11)
    Swag.assert(gImportedDefaultOuter.timing.minStep > 0.0)
    Swag.assert(gImportedDefaultOuter.timing.maxStep == 1.0)
    Swag.assert(gImportedDefaultOuter.timing.seed == 17)
    Swag.assert(gImportedDefaultOuter.marker == 42)

    var localDefault: DepImportedDefaultOuter
    localDefault.required = 13
    Swag.assert(localDefault.required == 13)
    Swag.assert(localDefault.timing.minStep > 0.0)
    Swag.assert(localDefault.timing.maxStep == 1.0)
    Swag.assert(localDefault.timing.seed == 17)
    Swag.assert(localDefault.marker == 42)
}

func verifyImportedInterfaceTablePreparation()
{
    let objectType    = #typeof(DepTableScore{})
    let objectInfo    = cast(const *Swag.TypeInfoStruct) objectType
    let interfaceInfo = cast(const *Swag.TypeInfoStruct) #typeof(IDepTableScore)
    let table         = Swag.tableOf(objectInfo, interfaceInfo)
    Swag.assert(table != null)

    var dynamicScore = Swag.makeInterface(null, objectType, IDepTableScore)
    let runtimeScore = cast(*Swag.Interface) &dynamicScore
    Swag.assert(runtimeScore != null)
    Swag.assert(runtimeScore.itable == table)
    Swag.assert(cast(#null const *Swag.TypeInfoStruct) runtimeScore.itable![] == objectInfo)

    var concreteScore             = DepTableScore{value: 32}
    var castScore: IDepTableScore = concreteScore
    Swag.assert(castScore.score() == 32)
}

func verifyImportedGenericRootMethodSema()
{
    var scratchRng      = DepSharedRng.Rng.makeScratch'DepSharedRng.MWC()
    let scratchRngValue = scratchRng.nextU32()
    var rng: DepSharedRng.Rng'DepSharedRng.MWC
    let sharedRngValue  = DepSharedRng.shared(&rng).nextU32()

    #assert(#typeof(scratchRngValue) == u32)
    #assert(#typeof(sharedRngValue) == u32)
}

func verifyImportedClosureCallbacks()
{
    var unarySet: DepByteSet = {values: ['C'u8, 'A'u8, 'B'u8, 0], count: 3}
    Swag.assert(depInvokeUnary('C'u8, func|&unarySet|(x: u8)->bool { return unarySet.contains(x) }))
    Swag.assert(!depInvokeUnary('Z'u8, func|&unarySet|(x: u8)->bool { return unarySet.contains(x) }))
    Swag.assert(depInvokeUnary('A'u8, func|&unarySet|(x: u8)->bool { return unarySet.containsViaGeneric(x) }))

    var genericSet: DepByteSet = {values: ['C'u8, 'A'u8, 'B'u8, 0], count: 3}
    Swag.assert(depInvokeGeneric('A'u8, func|&genericSet|(x: u8)->bool { return genericSet.contains(x) }))
    Swag.assert(!depInvokeGeneric('Z'u8, func|&genericSet|(x: u8)->bool { return genericSet.contains(x) }))
    Swag.assert(depInvokeGeneric('B'u8, func|&genericSet|(x: u8)->bool { return genericSet.containsViaGeneric(x) }))

    var prev:     [3] u8     = ['C', 'A', 'B']
    var allOfSet: DepByteSet = {values: ['A'u8, 'B'u8, 'C'u8, 'D'u8], count: 4}
    Swag.assert(depAllOf(prev[to], func|&allOfSet|(x: u8)->bool { return allOfSet.contains(x) }))
    Swag.assert(depAllOf(prev[to], func|&allOfSet|(x: u8)->bool { return allOfSet.containsViaGeneric(x) }))

    var selfBufferSet     = depMakeSelfBufferSet('A'u8, 'B'u8, 'C'u8, 'D'u8, 4)
    var prevSelfBufferSet = depMakeSelfBufferSet('C'u8, 'A'u8, 'B'u8, 0, 3)
    Swag.assert(depInvokeUnary('A'u8, func|&selfBufferSet|(x: u8)->bool { return selfBufferSet.contains(x) }))
    Swag.assert(depInvokeGeneric('B'u8, func|&selfBufferSet|(x: u8)->bool { return selfBufferSet.containsViaGeneric(x) }))
    Swag.assert(depAllOf(prev[to], func|&selfBufferSet|(x: u8)->bool { return selfBufferSet.contains(x) }))
    Swag.assert(depAllOf(prev[to], func|&selfBufferSet|(x: u8)->bool { return selfBufferSet.containsViaGeneric(x) }))
    Swag.assert(depAllOf(prevSelfBufferSet.toSlice(), func|&selfBufferSet|(x: u8)->bool { return selfBufferSet.contains(x) }))
    Swag.assert(depAllOf(prevSelfBufferSet.toSlice(), func|&selfBufferSet|(x: u8)->bool { return selfBufferSet.containsViaGeneric(x) }))
    let depWrappers = [DepSelfBufferWrapper{prev: prevSelfBufferSet}]
    for wrapper in depWrappers
    {
        Swag.assert(depAllOf(wrapper.prev.toSlice(), func|&selfBufferSet|(x: u8)->bool { return selfBufferSet.contains(x) }))
        Swag.assert(depAllOf(wrapper.prev.toSlice(), func|&selfBufferSet|(x: u8)->bool { return selfBufferSet.containsViaGeneric(x) }))
    }

    var sharedUnarySet: CtxClosureByteSet = {values: ['C'u8, 'A'u8, 'B'u8, 0], count: 3}
    Swag.assert(ctxSharedInvokeUnary('C'u8, func|&sharedUnarySet|(x: u8)->bool { return sharedUnarySet.contains(x) }))
    Swag.assert(!ctxSharedInvokeUnary('Z'u8, func|&sharedUnarySet|(x: u8)->bool { return sharedUnarySet.contains(x) }))
    Swag.assert(ctxSharedInvokeUnary('A'u8, func|&sharedUnarySet|(x: u8)->bool { return sharedUnarySet.containsViaGeneric(x) }))

    var sharedGenericSet: CtxClosureByteSet = {values: ['C'u8, 'A'u8, 'B'u8, 0], count: 3}
    Swag.assert(ctxSharedInvokeGeneric('A'u8, func|&sharedGenericSet|(x: u8)->bool { return sharedGenericSet.contains(x) }))
    Swag.assert(!ctxSharedInvokeGeneric('Z'u8, func|&sharedGenericSet|(x: u8)->bool { return sharedGenericSet.contains(x) }))
    Swag.assert(ctxSharedInvokeGeneric('B'u8, func|&sharedGenericSet|(x: u8)->bool { return sharedGenericSet.containsViaGeneric(x) }))

    var sharedPrev:     [3] u8            = ['C', 'A', 'B']
    var sharedAllOfSet: CtxClosureByteSet = {values: ['A'u8, 'B'u8, 'C'u8, 'D'u8], count: 4}
    Swag.assert(ctxSharedAllOf(sharedPrev[to], func|&sharedAllOfSet|(x: u8)->bool { return sharedAllOfSet.contains(x) }))
    Swag.assert(ctxSharedAllOf(sharedPrev[to], func|&sharedAllOfSet|(x: u8)->bool { return sharedAllOfSet.containsViaGeneric(x) }))

    var sharedSelfBufferSet     = ctxSharedMakeSelfBufferSet('A'u8, 'B'u8, 'C'u8, 'D'u8, 4)
    var sharedPrevSelfBufferSet = ctxSharedMakeSelfBufferSet('C'u8, 'A'u8, 'B'u8, 0, 3)
    Swag.assert(ctxSharedInvokeUnary('A'u8, func|&sharedSelfBufferSet|(x: u8)->bool { return sharedSelfBufferSet.contains(x) }))
    Swag.assert(ctxSharedInvokeGeneric('B'u8, func|&sharedSelfBufferSet|(x: u8)->bool { return sharedSelfBufferSet.containsViaGeneric(x) }))
    Swag.assert(ctxSharedAllOf(sharedPrev[to], func|&sharedSelfBufferSet|(x: u8)->bool { return sharedSelfBufferSet.contains(x) }))
    Swag.assert(ctxSharedAllOf(sharedPrev[to], func|&sharedSelfBufferSet|(x: u8)->bool { return sharedSelfBufferSet.containsViaGeneric(x) }))
    Swag.assert(ctxSharedAllOf(sharedPrevSelfBufferSet.toSlice(), func|&sharedSelfBufferSet|(x: u8)->bool { return sharedSelfBufferSet.contains(x) }))
    Swag.assert(ctxSharedAllOf(sharedPrevSelfBufferSet.toSlice(), func|&sharedSelfBufferSet|(x: u8)->bool { return sharedSelfBufferSet.containsViaGeneric(x) }))
    let sharedWrappers = [CtxSelfBufferWrapper{prev: sharedPrevSelfBufferSet}]
    for wrapper in sharedWrappers
    {
        Swag.assert(ctxSharedAllOf(wrapper.prev.toSlice(), func|&sharedSelfBufferSet|(x: u8)->bool { return sharedSelfBufferSet.contains(x) }))
        Swag.assert(ctxSharedAllOf(wrapper.prev.toSlice(), func|&sharedSelfBufferSet|(x: u8)->bool { return sharedSelfBufferSet.containsViaGeneric(x) }))
    }
}

func verifyExportAndStaticModules()
{
    Swag.assert(DEP_VALUE == 7)
    Swag.assert(DEP_PUBLIC_DEFAULT == 11)
    Swag.assert(DEP_MULTI_A == 13)
    Swag.assert(DEP_MULTI_B == 17)
    Swag.assert(depFutureExport() == 7)
    Swag.assert(depGeneratedExport() == 42)
    Swag.assert(depPlaceholderExport(35) == 42)
    Swag.assert(depGenericIdentity(42) == 42)
    Swag.assert(DepTools.DEP_NAMESPACE_A == 31)
    Swag.assert(DepTools.DEP_NAMESPACE_B == 37)
    Swag.assert(DepTools.DEP_NAMESPACE_C == 41)
    Swag.assert(DepTools.Deep.DEP_NAMESPACE_DEEP == 43)
    Swag.assert(depLegacyValue() == 5)

    var count: DepCount = 19
    Swag.assert(count == 19)
    var mode: DepMode = .Big
    Swag.assert(mode == .Big)

    var pair: DepPair
    pair.left  = 2
    pair.right = 5
    Swag.assert(pair.left + pair.right == 7)
    var shortCallOwner: DepShortCallOwner
    Swag.assert(shortCallOwner.ready())
    Swag.assert(#sizeof(DepPublicWithPrivateField) == 8)
    let publicWithPrivate = makeDepPublicWithPrivateField(41)
    Swag.assert(publicWithPrivate.publicValue == 41)
    Swag.assert(#sizeof(DepPublicWithPrivateInlineUnion) == 12)

    var genericLayout: DepGenericLayout's32
    genericLayout.value = 42
    Swag.assert(genericLayout.value == 42)

    var value = DepValue{asInt: 0x1234}
    Swag.assert(value.asInt == 0x1234)

    #assert(#sizeof(DepOpaque) == 16)
    #assert(#alignof(DepOpaque) == 8)
    var opaque: DepOpaque
    Swag.assert(#sizeof(opaque) == 16)

    var opaqueGenericBox: DepOpaqueGenericBox
    opaqueGenericBox.init(7)
    Swag.assert(opaqueGenericBox.addSeed(35) == 42)

    var namespaced: DepTools.DepNamespaced
    namespaced.value = 12
    Swag.assert(namespaced.value == 12)
    Swag.assert(DepTools.hash32WithGeneratedFullName(namespaced) == 0x10C'u32)
    Swag.assert(DepTools.DepGeneratedCommandOwner.GeneratedAccept == "DepTools.DepGeneratedCommandOwner.GeneratedAccept")

    var staticInferredDepOwner: StaticInferredDepOwner
    staticInferredDepOwner.namespaced.value = 15
    Swag.assert(staticInferredDepOwner.getNamespaced().value == 15)

    gStaticInlineStorage[0]    = 7
    gStaticInlineBuffer.buffer = &gStaticInlineStorage[0]
    gStaticInlineBuffer.clearFirst()
    Swag.assert(gStaticInlineStorage[0] == 0)

    var staticOpaqueInline: StaticOpaqueInline
    staticOpaqueInline.init(42)
    Swag.assert(staticOpaqueInline.getValue() == 42)

    var ignoredContainer: DepIgnoredContainer
    ignoredContainer.run()

    Swag.assert(depDouble(21) == 42)
    Swag.assert(depMirror(42) == 42)
    Swag.assert(depTriple(14) == 42)
    Swag.assert(depStringLength("workspace") == 9)
    Swag.assert(depMacroTwicePlus(20, 2) == 42)
    Swag.assert(depScale(cast(s32) 10) == 40)
    Swag.assert(depScale(cast(f32) 2) == cast(f32) 8)

    var total = 0
    depMixinAccumulateTwice(21)
    Swag.assert(total == 42)

    var calc = DepCalculator.make(5)
    Swag.assert(DepCalculator.resolve(6) == 106)
    Swag.assert(calc.resolve(6) == 1011)
    Swag.assert(calc.add(cast(s32) 7) == 12)
    Swag.assert(calc.add(cast(f32) 2) == cast(f32) 7)
    Swag.assert(calc.addTwice(7) == 19)
    Swag.assert(calc.sub(2) == 3)
}

func verifyDllAbiCalls()
{
    Swag.assert(ctxSharedPassString("abi-string") == "abi-string")
    Swag.assert(ctxSharedPassString("abi-string-2") == "abi-string-2")
    Swag.assert(ctxSharedPassStringAt("abi-string", 1) == 98'u8)
    Swag.assert(ctxSharedPassStringAt("abi-string", 2) == 'i'u8)
    Swag.assert(ctxSharedPassStringAt("abi-string", 9) == 'g'u8)

    let array0 = ctxSharedPassArray([11, 22, 33, 44])
    let array1 = ctxSharedPassArray([101, 202, 303, 404])
    let array2 = ctxSharedPassArray([-1, -2, -3, -4])
    Swag.assert(array0[0] == 11)
    Swag.assert(array0[3] == 44)
    Swag.assert(array1[0] == 101)
    Swag.assert(array1[3] == 404)
    Swag.assert(array2[0] == -1)
    Swag.assert(array2[3] == -4)

    let pair0    = ctxSharedPassPair({a: 9, b: 13})
    let pair1    = ctxSharedMakePair(-9, -13)
    let payload0 = ctxSharedPassPayload(ctxSharedMakePayload(10))
    let payload1 = ctxSharedClonePayload(ctxSharedMakePayload(1))
    Swag.assert(pair0.a == 9)
    Swag.assert(pair0.b == 13)
    Swag.assert(pair1.a == -9)
    Swag.assert(pair1.b == -13)
    Swag.assert(ctxSharedPassPairSum({a: 9, b: 13}) == 22)
    Swag.assert(ctxSharedPassPairSum({a: 90, b: 130}) == 220)
    Swag.assert(ctxSharedPassPairSum({a: -90, b: 130}) == 40)
    Swag.assert(payload0.a0 == 11'u64)
    Swag.assert(payload0.a3 == 14'u64)
    Swag.assert(payload1.a0 == 2'u64)
    Swag.assert(payload1.a3 == 5'u64)

    let offsets0 = ctxSharedMakeOffsets(1'u8, 2'u16, 3'u32, 4'u64)
    Swag.assert(offsets0.a == 1'u8)
    Swag.assert(offsets0.b == 2'u16)
    Swag.assert(offsets0.c == 3'u32)
    Swag.assert(offsets0.d == 4'u64)
    Swag.assert(ctxSharedPassOffsets(offsets0) == 10'u64)

    let p0 = ctxSharedPassPointer(null)
    let p1 = ctxSharedPassPointer(cast(#null *void) 0x1234'u64)
    Swag.assert(p0 == null)
    Swag.assert(p1 == cast(#null *void) 0x1234'u64)
    Swag.assert(ctxSharedPassMixed(3, "mix", {a: 10, b: 11}, [8, 9], null) == 131)
    Swag.assert(ctxSharedPassMixed(30, "mix2", {a: 100, b: 110}, [80, 90], cast(#null *void) 0x4567'u64) == 330)

    const pairRef: CtxAbiPair = {a: 6, b: 7}
    Swag.assert(ctxSharedPassConstRef(pairRef) == 13)
    Swag.assert(ctxSharedPassConstRef({a: 8, b: 9}) == 17)
    Swag.assert(ctxSharedPassScalars(-5's8, -123's16, 77's32, 5000's64, 9'u8, 10'u16, 11'u32, 12'u64, 1.25'f32, 2.5'f64, true, 'R') == 5077)
    Swag.assert(ctxSharedPassBoolRunePositions(true, 3, 'Q', 4, true, 'W') == 177)
    Swag.assert(ctxSharedPassBoolRunePositions(false, 30, 'Q', 40, false, 'W') == 238)
    Swag.assert(ctxSharedPassBoolRunePositions(true, -3, 'Q', 7, false, 'W') == 173)
    Swag.assert(ctxSharedPassAliasEnum(1, cast(CtxAbiAlias) 2, CtxAbiEnum.A, 3) == 23)
    Swag.assert(ctxSharedPassAliasEnum(10, cast(CtxAbiAlias) 20, CtxAbiEnum.B, 30) == 183)
    Swag.assert(ctxSharedPassAliasEnum(-10, cast(CtxAbiAlias) 20, CtxAbiEnum.A, -30) == -3)
    Swag.assert(CtxAbiEnum.A.score() == 7)
    Swag.assert(CtxAbiEnum.B.score() == 11)

    const values0: [4] s32 = [11, 22, 33, 44]
    const values1: [4] s32 = [101, 202, 303, 404]
    const values2: [4] s32 = [-1, -2, -3, -4]
    Swag.assert(ctxSharedPassSlice(values0, 2) == 33)
    Swag.assert(ctxSharedPassSlice(values1, 3) == 404)
    Swag.assert(ctxSharedPassSlice(values2, 0) == -1)
    Swag.assert(ctxSharedPassAggregatePositions(cast(#null *void) 0x10'u64, [5, 6], "abc", {a: 7, b: 8}, {a0: 1'u64, a1: 2'u64, a2: 3'u64, a3: 4'u64}) == 115'u64)
    Swag.assert(ctxSharedPassAggregatePositions(null, [50, 60], "Abc", {a: 70, b: 80}, {a0: 10'u64, a1: 20'u64, a2: 30'u64, a3: 40'u64}) == 235'u64)
    Swag.assert(ctxSharedPassNested({p: {a: 3, b: 4}, q: {a0: 10'u64, a1: 20'u64, a2: 30'u64, a3: 40'u64}}, 5) == 62'u64)
    Swag.assert(ctxSharedPassKindof({a: 1, b: 2}, {a0: 3'u64, a1: 4'u64, a2: 5'u64, a3: 6'u64}, "ok", null, [7, 8], CtxAbiEnum.A))
    Swag.assert(ctxSharedPassNestedArray({p: {a: 10, b: 11}, q: {a0: 1'u64, a1: 2'u64, a2: 3'u64, a3: 4'u64}}, [{a: 20, b: 21}, {a: 30, b: 31}]) == 61)

    var nested0 = ctxSharedMakeNested(7)
    Swag.assert(nested0.p.a == 7)
    Swag.assert(nested0.p.b == 8)
    Swag.assert(nested0.q.a0 == 17'u64)
    Swag.assert(nested0.q.a3 == 47'u64)

    let floatPair0 = ctxSharedMakeFloatPair(733, 366)
    let floatPair1 = ctxSharedPassFloatPair({x: -1.5, y: 2.25})
    Swag.assert(floatPair0.x == cast(f32) 733)
    Swag.assert(floatPair0.y == cast(f32) 366)
    Swag.assert(floatPair1.x == cast(f32) -1.5)
    Swag.assert(floatPair1.y == cast(f32) 2.25)
    Swag.assert(ctxSharedFloatPairSum({x: 1.5, y: 2.5}) == cast(f32) 4)

    let floatPair2 = ctxSharedMakeFloatPairViaLocal(733, 366)
    Swag.assert(floatPair2.x == cast(f32) 733)
    Swag.assert(floatPair2.y == cast(f32) 366)

    // A method and a free function whose flattened names would collide must stay two
    // distinct exports: calling one has to run its own body, not the other's.
    let cursor = CtxAbiCursor{pos: {x: 12, y: 34}}
    let viaMtd = cursor.position()
    let viaFn  = ctxAbiCursorPosition()
    Swag.assert(viaMtd.x == cast(f32) 12)
    Swag.assert(viaMtd.y == cast(f32) 34)
    Swag.assert(viaFn.x == cast(f32) 91)
    Swag.assert(viaFn.y == cast(f32) 82)

    let float0 = ctxSharedMakeFloatPack(0.5)
    let float1 = ctxSharedCloneFloatPack(ctxSharedMakeFloatPack(1.5))
    Swag.assert(float0.r == 0.5)
    Swag.assert(float0.g == 0.75)
    Swag.assert(float0.b == 1.0)
    Swag.assert(float1.r == 1.5)
    Swag.assert(float1.g == 1.75)
    Swag.assert(float1.b == 2.0)

    var writtenPair: CtxAbiPair = {a: 0, b: 0}
    ctxSharedWritePair(&writtenPair, 77, -33)
    Swag.assert(writtenPair.a == 77)
    Swag.assert(writtenPair.b == -33)

    var writtenPayload = CtxAbiPayload{a0: 0'u64, a1: 0'u64, a2: 0'u64, a3: 0'u64}
    ctxSharedWritePayload(&writtenPayload, 30'u64)
    Swag.assert(writtenPayload.a0 == 31'u64)
    Swag.assert(writtenPayload.a1 == 32'u64)
    Swag.assert(writtenPayload.a2 == 33'u64)
    Swag.assert(writtenPayload.a3 == 34'u64)

    Swag.assert(ctxSharedScale(cast(s32) 10) == 40)
    Swag.assert(ctxSharedScale(cast(f32) 2) == cast(f32) 8)

    var calc = CtxAbiCalculator.make(5)
    Swag.assert(CtxAbiCalculator.resolve(6) == 106)
    Swag.assert(calc.resolve(6) == 1011)
    Swag.assert(calc.add(cast(s32) 7) == 12)
    Swag.assert(calc.add(cast(f32) 2) == cast(f32) 7)
    Swag.assert(calc.sub(2) == 3)

    let calcPair = calc.makePair(2)
    Swag.assert(calcPair.a == 7)
    Swag.assert(calcPair.b == 3)

    let calcPayload = calc.makePayload(20'u64)
    Swag.assert(calcPayload.a0 == 26'u64)
    Swag.assert(calcPayload.a1 == 27'u64)
    Swag.assert(calcPayload.a2 == 28'u64)
    Swag.assert(calcPayload.a3 == 29'u64)
}

// `Swag.setContext` installs a POINTER to its argument, so the patched copy must outlive the frame
// that builds it: a stack local would leave every later `Swag.getContext` — including the error
// machinery behind `fail`/`catch` — reading a dead frame.
var gPatchedContext: Swag.Context

func verifyRuntimeContext()
{
    gPatchedContext       = Swag.getContext()[]
    gPatchedContext.user0 = 42
    gPatchedContext.user2 = cast(u64) Swag.getContext()
    Swag.setContext(gPatchedContext)

    let expectedContext = Swag.getContext().user2
    Swag.assert(ctxBaseReadContext() == 42)
    Swag.assert(ctxSharedReadContext() == 42)
    Swag.assert(ctxDirectReadContext() == 42)
    Swag.assert(ctxBaseContextMarker() == expectedContext)
    Swag.assert(ctxSharedContextMarker() == expectedContext)
    Swag.assert(ctxDirectContextMarker() == expectedContext)
    Swag.assert(ctxBaseInitCount() == 2)
    Swag.assert(ctxBasePreMainCount() == 2)
}

#init
{
    Swag.assert((Swag.getContext().user1 & CTX_SHARED_INIT_FLAG) != 0)
    Swag.assert((Swag.getContext().user1 & CTX_DIRECT_INIT_FLAG) != 0)
}

#premain
{
    Swag.assert((Swag.getContext().user1 & CTX_SHARED_PREMAIN_FLAG) != 0)
    Swag.assert((Swag.getContext().user1 & CTX_DIRECT_PREMAIN_FLAG) != 0)
}

#drop
{
    // Same lifetime rule as `verifyRuntimeContext`: the DLL's `#drop` runs after this one and
    // reads `user0` through the installed pointer, so the patched copy must not be a local.
    gPatchedContext       = Swag.getContext()[]
    gPatchedContext.user0 = 43
    Swag.setContext(gPatchedContext)
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
    Swag.assert(gEvtClassified == 1)

    gEvtClassified = 0
    depDispatchEvt(&onDepEvt, 3)
    Swag.assert(gEvtClassified == 3)
}

// An imported function keeps the discardability its declaration gave it, so a call made only
// for its effect compiles here exactly as it does inside the provider.
func verifyImportedDiscardable()
{
    depDiscardableCount()
    depDiscardableInlineCount()
    Swag.assert(depDiscardableCount() == 61)
    Swag.assert(depDiscardableInlineCount() == 67)
}

func verifyCrossDllTypeIdentity()
{
    // The DLL-produced typeinfo for an imported type must compare equal to the
    // consumer's view (stable cross-module `crc`/runtimeHash), and distinct types
    // must stay distinct.
    Swag.assert(depTypeOfResizeEvt() == #typeof(DepResizeEvt))
    Swag.assert(depTypeOfDestroyEvt() == #typeof(DepDestroyEvt))
    Swag.assert(depTypeOfResizeEvt() != #typeof(DepDestroyEvt))
    Swag.assert(depTypeOfResizeEvt() != depTypeOfDestroyEvt())
}

func verifyRuntimeTypeCrossDllIdentity()
{
    // Runtime `Swag.*` types are compiled into every module; the DLL's descriptors and this
    // executable's must still describe one type on both sides of the boundary (F-084).
    Swag.assert(ctxSharedTypeOfBaseError() == Swag.BaseError)
    Swag.assert(ctxSharedTypeOfSystemError() == Swag.SystemError)
    Swag.assert(ctxSharedTypeOfSystemError() != Swag.BaseError)
    Swag.assert(ctxSharedClassifyRuntimeError(#typeof(Swag.SystemError)) == 1)
    Swag.assert(ctxSharedClassifyRuntimeError(#typeof(Swag.BaseError)) == 2)
    Swag.assert(ctxSharedClassifyRuntimeError(#typeof(CtxAbiPair)) == 0)

    var hit = 0
    switch ctxSharedTypeOfSystemError()
    {
    case Swag.SystemError:
        hit = 1
    default:
        hit = -1
    }
    Swag.assert(hit == 1)

    // A fallible import that succeeds must leave the capture null.
    catch ctxSharedMayFailNothing() as none
    Swag.assert(none == null)

    // An error raised in the DLL carries the DLL's descriptor; classifying, walking and casting
    // it here uses this executable's.
    catch ctxSharedRaiseSystemError() as raised
    Swag.assert(raised != null)
    Swag.assert(raised is Swag.SystemError)
    Swag.assert(raised is Swag.BaseError)

    switch raised
    {
    case Swag.SystemError:
        hit = 2
    default:
        hit = -2
    }
    Swag.assert(hit == 2)

    let sysErr = raised as Swag.SystemError
    Swag.assert(sysErr != null)
    Swag.assert(sysErr.message == "raised across the boundary")
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
    verifyImportedDiscardable()
    verifyCrossDllTypeIdentity()
    verifyRuntimeTypeCrossDllIdentity()
    verifyImportedBorrowSummaries()

    // The workspace suite checks this marker after a test build to prove that run restored
    // the normal executable instead of reusing the test artifact.
    Swag.print("SWAG_WORKSPACE_MAIN_RAN\n")
}

#test
{
    Swag.print("SWAG_WORKSPACE_TEST_RAN\n")
}
