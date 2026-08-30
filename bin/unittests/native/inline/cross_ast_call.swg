#global private

#test
{
    let angle = InlineCrossAstCall.Angle{rad: -3.14159265'f32}
    let deg   = angle.toDegrees()
    Swag.assert(deg > -180.001'f32 and deg < -179.999'f32)

    let implicitAngle: InlineCrossAstCall.Angle = -3.14159265'f32
    Swag.assert(implicitAngle.rad < -3.141'f32 and implicitAngle.rad > -3.142'f32)
    let implicitDeg = implicitAngle.toDegrees()
    Swag.assert(implicitDeg > -180.001'f32 and implicitDeg < -179.999'f32)
    Swag.assert(InlineCrossAstCall.isEqualEpsilon(implicitAngle.toDegrees(), -180.0, 0.001))
    Swag.assert(InlineCrossAstCall.isEqualEpsilonF64Only(InlineCrossAstCall.inlineF32Degrees(-3.14159265'f32), -180.0, 0.001))
    Swag.assert(InlineCrossAstCall.nestedIfParamCaller(0) == 7)
    Swag.assert(InlineCrossAstCall.nestedIfParamCaller(4) == 5)
    Swag.assert(InlineCrossAstCall.inlineArgFromLocal(-6) == 6)
    Swag.assert(InlineCrossAstCall.inlineArgFromLocal(8) == 9)
    Swag.assert(InlineCrossAstCall.inlineMethodParamFromCallerExpr(8))
    Swag.assert(InlineCrossAstCall.inlineMacroStmtCapture(5) == 9)
    Swag.assert(InlineCrossAstCall.inlineForwardedMacroCapture(5) == 7)
    Swag.assert(InlineCrossAstCall.inlineMacroBlockCapture(5) == 10)
    Swag.assert(InlineCrossAstCall.inlineMacroExprCapture(4) == 10)
    Swag.assert(InlineCrossAstCall.inlineForwardedGenericMacroCapture(4) == 5)
    Swag.assert(InlineCrossAstCall.inlineForwardedGenericMacroReturn(4) == 6)
    Swag.assert(InlineCrossAstCall.inlineDirectReceiverCheck(4, 0))
    Swag.assert(InlineCrossAstCall.inlineForwardedCountIsFour(4))
    Swag.assert(InlineCrossAstCall.inlineForwardedValueReceiverCheckReversed(4, 0))
    Swag.assert(InlineCrossAstCall.inlineForwardedValueReceiverCheck(4, 0))
    Swag.assert(InlineCrossAstCall.inlineSafetyLikeReceiverCheck(4, 0))
    var data: [16] u8
    let pix = InlineCrossAstCall.inlinePointerOffset(data.buffer, 1, 1, 2, 4)
    pix[0] = 77
    Swag.assert(data[6] == 77)
    InlineCrossAstCall.inlineInjectedPointerOffset(data.buffer)
    Swag.assert(data[6] == 91)
    var pixelProbe = InlineCrossAstCall.InlinePixelProbe{buffer: data.buffer, bpp8: 2, width: 4}
    InlineCrossAstCall.inlineInjectedPointerOffsetShadow(&pixelProbe)
    Swag.assert(data[6] == 103)
    InlineCrossAstCall.inlineInjectedContextDataShadow(&pixelProbe)
    Swag.assert(data[6] == 117)
    InlineCrossAstCall.inlineInjectedLocalContextDataShadow(&pixelProbe)
    Swag.assert(data[6] == 119)
    Swag.assert(InlineCrossAstCall.inlineMixinCapture(6) == 9)
}
