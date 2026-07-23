#global namespace InlineCrossAstCall
#global public

func toDegrees(value: f32)->f32 => value * 57.295779513082320876798154814105'f32
func toDegrees(value: f64)->f64 => value * 57.295779513082320876798154814105'f64
#[Swag.Inline]
func abs(value: f32)->f32 => @abs(value)
#[Swag.Inline]
func abs(value: f64)->f64 => @abs(value)
#[Swag.Inline]
func isEqualEpsilon(value, expected: f32, eps: f32)->bool => abs(value - expected) < eps
#[Swag.Inline]
func isEqualEpsilon(value, expected: f64, eps: f64)->bool => abs(value - expected) < eps
#[Swag.Inline]
func isEqualEpsilonF64Only(value: f64, expected: f64, eps: f64)->bool => abs(value - expected) < eps

struct Angle
{
    rad: f32
}

impl Angle
{
    #[Swag.Implicit, Swag.Inline]
    mtd opSet(value: f32)
    {
        .rad = value
    }

    #[Swag.Inline]
    mtd const toDegrees()->f32 => toDegrees(.rad)
}

struct InlineSelection
{
    selected: u32
}

impl InlineSelection
{
    #[Swag.Inline]
    mtd const isSelected(idx: u32)->bool => idx == .selected
}

#[Swag.Inline]
func inlineF32Degrees(value: f32)->f32 => toDegrees(value)

#[Swag.Inline]
func nestedIfParam(num: u64)->u64
{
    if !num do
        return 7
    return num + 1
}

#[Swag.Inline]
func nestedIfParamCaller(num: u64)->u64 => nestedIfParam(num)

#[Swag.Inline]
func useSignedArg(value: s32)->s32
{
    if value < 0 do
        return -value
    return value + 1
}

#[Swag.Inline]
func inlineArgFromLocal(seed: s32)->s32
{
    var local = seed
    return useSignedArg(local)
}

#[Swag.Inline]
func inlineMethodParamFromCallerExpr(seed: u32)->bool
{
    let selection = InlineSelection{selected: seed + 1}
    return selection.isSelected(seed + 1)
}

#[Swag.Macro]
func injectStmt(stmt: #code)
{
    #inject(stmt)
}

#[Swag.Macro]
func injectExpr(expr: #code->s32)->s32 => #inject(expr)

#[Swag.Macro]
func(enabled: bool) genericInjectExpr(expr: #code->bool)
{
    if #inject(expr) {}
}

#[Swag.Macro]
func(what: bool) genericSafetyLike(expr: #code->bool)->bool
{
    if what
    {
        if !#inject(expr) do
            return false
    }

    return true
}

#[Swag.Macro]
func safetyLikeBoundCheck(expr50: #code->bool)->bool
{
    return genericSafetyLike'(true)(expr50)
}

#[Swag.Macro]
func(what: bool) genericInjectValue(expr: #code->bool)->bool
{
    return #inject(expr)
}

#[Swag.Macro]
func forwardedInjectValue(expr50: #code->bool)->bool
{
    return genericInjectValue'(true)(expr50)
}

#[Swag.Macro]
func forwardStmt(stmt: #code)
{
    injectStmt(stmt)
}

#[Swag.Macro]
func forwardGenericExpr(expr: #code->bool)
{
    genericInjectExpr'(true)(expr)
}

#[Swag.Macro]
func injectFromMacroBlock(stmt: #code)
{
    #inject(stmt)
}

#[Swag.Inline]
func inlineMacroStmtCapture(seed: s32)->s32
{
    var total = seed
    injectStmt(#code {
        total += 4
    })
    return total
}

#[Swag.Inline]
func inlineForwardedMacroCapture(seed: s32)->s32
{
    var total = seed
    forwardStmt(#code {
        total += 2
    })
    return total
}

#[Swag.Inline]
func inlineMacroBlockCapture(seed: s32)->s32
{
    var total = seed
    injectFromMacroBlock(#code {
        total += 5
    })
    return total
}

#[Swag.Inline]
func inlineMacroExprCapture(seed: s32)->s32
{
    let local = seed + 1
    return injectExpr(#code => local * 2)
}

#[Swag.Inline]
func inlineForwardedGenericMacroCapture(seed: s32)->s32
{
    var index = seed
    forwardGenericExpr(index == seed)
    return index + 1
}

#[Swag.Inline]
func inlineForwardedGenericMacroGuard(seed: s32)
{
    var index = seed
    forwardGenericExpr(index == seed)
}

#[Swag.Inline]
func inlineForwardedGenericMacroReturn(seed: s32)->s32
{
    inlineForwardedGenericMacroGuard(seed)
    return seed + 2
}

struct InlineBoundProbe
{
    count: u64
}

impl InlineBoundProbe
{
    #[Swag.Inline]
    mtd check(index: u64)->bool
    {
        return safetyLikeBoundCheck(index < .count)
    }

    #[Swag.Inline]
    mtd checkDirect(index: u64)->bool
    {
        return index < .count
    }

    #[Swag.Inline]
    mtd checkForwardedValue(index: u64)->bool
    {
        return forwardedInjectValue(index < .count)
    }

    #[Swag.Inline]
    mtd checkForwardedValueReversed(index: u64)->bool
    {
        return forwardedInjectValue(.count > index)
    }

    #[Swag.Inline]
    mtd checkForwardedCountIsFour()->bool
    {
        return forwardedInjectValue(.count == 4)
    }
}

#[Swag.Inline]
func inlineSafetyLikeReceiverCheck(count: u64, index: u64)->bool
{
    var probe = InlineBoundProbe{count: count}
    return probe.check(index)
}

#[Swag.Inline]
func inlineDirectReceiverCheck(count: u64, index: u64)->bool
{
    var probe = InlineBoundProbe{count: count}
    return probe.checkDirect(index)
}

#[Swag.Inline]
func inlineForwardedValueReceiverCheck(count: u64, index: u64)->bool
{
    var probe = InlineBoundProbe{count: count}
    return probe.checkForwardedValue(index)
}

#[Swag.Inline]
func inlineForwardedValueReceiverCheckReversed(count: u64, index: u64)->bool
{
    var probe = InlineBoundProbe{count: count}
    return probe.checkForwardedValueReversed(index)
}

#[Swag.Inline]
func inlineForwardedCountIsFour(count: u64)->bool
{
    var probe = InlineBoundProbe{count: count}
    return probe.checkForwardedCountIsFour()
}

#[Swag.Inline]
func inlinePointerOffset(buffer: [*] u8, x: s32, y: s32, bpp8: u8, width8: s32)->[*] u8
{
    return buffer + x * bpp8 + y * width8
}

struct InlinePixelProbe
{
    buffer: [*] u8
    bpp8:   u8
    width:  s32
}

struct InlineJobProbe
{
    contextData: #null *void
}

#[Swag.Macro]
func(T) genericParallelVisitLike(range: [..] T, offset: u32 = 1, contextData: #null *void = null, stmt: #code(var buffer, data))
{
    func visitSlice(sliceBuffer: const [..] T, sliceOffset: u32, sliceContextData: #null *void)
    {
        var scan = @dataof(sliceBuffer)
        let countof = @countof(sliceBuffer)
        for countof / sliceOffset
        {
            #inject(stmt, buffer = cast #unconst (*T) scan, data = sliceContextData)

            scan += sliceOffset
        }
    }

    visitSlice(range, offset, contextData)

    var j: InlineCrossAstCall.InlineJobProbe
    j.contextData = contextData
}

impl InlinePixelProbe
{
    #[Swag.Macro]
    mtd visit(stmt: #code(x: s32, y: s32))
    {
        #inject(stmt, x = 1, y = 1)
    }

    #[Swag.Macro]
    mtd visitWithUserData(userDataArg: *void, stmt: #code(userData, x: s32, y: s32))
    {
        var p = {userData: userDataArg}
        #inject(stmt, userData = p.userData, x = 1, y = 1)
    }

    #[Swag.Macro]
    mtd visitParallelLike(contextData: *void, stmt: #code(userData, x: s32, y: s32))
    {
        var j: InlineCrossAstCall.InlineJobProbe
        #inject(stmt, userData = contextData, x = 1, y = 1)

        j.contextData = contextData
    }

    #[Swag.Macro]
    mtd visitParallelLocalLike(contextData: *void, stmt: #code(userData, x: s32, y: s32))
    {
        func visitSlice(sliceContextData: *void)
        {
            for 1
            {
                #inject(stmt, userData = sliceContextData, x = 1, y = 1)
            }
        }

        visitSlice(contextData)

        var j: InlineCrossAstCall.InlineJobProbe
        j.contextData = contextData
    }
}

#[Swag.Inline]
func inlineInjectedPointerOffset(buffer: [*] u8)
{
    var image = InlinePixelProbe{buffer: buffer, bpp8: 2, width: 4}
    image.visit()
    {
        let pixDst = image.buffer + x * image.bpp8 + y * image.width
        pixDst[0] = 91
    }
}

#[Swag.Inline]
func inlineInjectedPointerOffsetShadow(dstImage: *InlinePixelProbe)
{
    var image = InlinePixelProbe{buffer: dstImage.buffer, bpp8: 2, width: 4}
    image.visitWithUserData(dstImage)
    {
        let dstImage = cast(*InlineCrossAstCall.InlinePixelProbe) userData
        let pixDst = dstImage.buffer + x * dstImage.bpp8 + y * dstImage.width
        pixDst[0] = 103
    }
}

#[Swag.Inline]
func inlineInjectedContextDataShadow(dstImage: *InlinePixelProbe)
{
    var image = InlinePixelProbe{buffer: dstImage.buffer, bpp8: 2, width: 4}
    image.visitParallelLike(dstImage)
    {
        let dstImage = cast(*InlineCrossAstCall.InlinePixelProbe) userData
        let pixDst = dstImage.buffer + x * dstImage.bpp8 + y * dstImage.width
        pixDst[0] = 117
    }
}

#[Swag.Inline]
func inlineInjectedLocalContextDataShadow(dstImage: *InlinePixelProbe)
{
    var image = InlinePixelProbe{buffer: dstImage.buffer, bpp8: 2, width: 4}
    image.visitParallelLocalLike(dstImage)
    {
        let dstImage = cast(*InlineCrossAstCall.InlinePixelProbe) userData
        let pixDst = dstImage.buffer + x * dstImage.bpp8 + y * dstImage.width
        pixDst[0] = 119
    }
}

#[Swag.Inline]
func inlineGenericParallelContextDataShadow(dstImage: *InlinePixelProbe)
{
    genericParallelVisitLike(@mkslice(dstImage.buffer, 1), 1, dstImage)
    {
        let dstImage = cast(*InlineCrossAstCall.InlinePixelProbe) notnull data
        let x = 1
        let y = 1
        let pixDst = dstImage.buffer + x * dstImage.bpp8 + y * dstImage.width
        pixDst[0] = 121
    }
}

#[Swag.Mixin]
func bumpCallerTotal()
{
    total += 3
}

#[Swag.Inline]
func inlineMixinCapture(seed: s32)->s32
{
    var total = seed
    bumpCallerTotal()
    return total
}
