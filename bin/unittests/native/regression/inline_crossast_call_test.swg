#global private

#test
{
    let angle = InlineCrossAstCall.Angle{rad: -3.14159265'f32}
    let deg   = angle.toDegrees()
    @assert(deg > -180.001'f32 and deg < -179.999'f32)

    let implicitAngle: InlineCrossAstCall.Angle = -3.14159265'f32
    @assert(implicitAngle.rad < -3.141'f32 and implicitAngle.rad > -3.142'f32)
    let implicitDeg = implicitAngle.toDegrees()
    @assert(implicitDeg > -180.001'f32 and implicitDeg < -179.999'f32)
    @assert(InlineCrossAstCall.isEqualEpsilon(implicitAngle.toDegrees(), -180.0, 0.001))
    @assert(InlineCrossAstCall.isEqualEpsilonF64Only(InlineCrossAstCall.inlineF32Degrees(-3.14159265'f32), -180.0, 0.001))
    @assert(InlineCrossAstCall.nestedIfParamCaller(0) == 7)
    @assert(InlineCrossAstCall.nestedIfParamCaller(4) == 5)
    @assert(InlineCrossAstCall.inlineArgFromLocal(-6) == 6)
    @assert(InlineCrossAstCall.inlineArgFromLocal(8) == 9)
    @assert(InlineCrossAstCall.inlineMethodParamFromCallerExpr(8))
    @assert(InlineCrossAstCall.inlineMacroStmtCapture(5) == 9)
    @assert(InlineCrossAstCall.inlineForwardedMacroCapture(5) == 7)
    @assert(InlineCrossAstCall.inlineMacroBlockCapture(5) == 10)
    @assert(InlineCrossAstCall.inlineMacroExprCapture(4) == 10)
    @assert(InlineCrossAstCall.inlineForwardedGenericMacroCapture(4) == 5)
    @assert(InlineCrossAstCall.inlineForwardedGenericMacroReturn(4) == 6)
    @assert(InlineCrossAstCall.inlineDirectReceiverCheck(4, 0))
    @assert(InlineCrossAstCall.inlineForwardedCountIsFour(4))
    @assert(InlineCrossAstCall.inlineForwardedValueReceiverCheckReversed(4, 0))
    @assert(InlineCrossAstCall.inlineForwardedValueReceiverCheck(4, 0))
    @assert(InlineCrossAstCall.inlineSafetyLikeReceiverCheck(4, 0))
    var data: [16] u8
    let pix = InlineCrossAstCall.inlinePointerOffset(@dataof(data), 1, 1, 2, 4)
    pix[0] = 77
    @assert(data[6] == 77)
    InlineCrossAstCall.inlineInjectedPointerOffset(@dataof(data))
    @assert(data[6] == 91)
    var pixelProbe = InlineCrossAstCall.InlinePixelProbe{buffer: @dataof(data), bpp8: 2, width: 4}
    InlineCrossAstCall.inlineInjectedPointerOffsetShadow(&pixelProbe)
    @assert(data[6] == 103)
    InlineCrossAstCall.inlineInjectedContextDataShadow(&pixelProbe)
    @assert(data[6] == 117)
    InlineCrossAstCall.inlineInjectedLocalContextDataShadow(&pixelProbe)
    @assert(data[6] == 119)
    @assert(InlineCrossAstCall.inlineMixinCapture(6) == 9)
}
