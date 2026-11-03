#global private

#test
{
    let angle = InlineCrossAstCall.Angle{rad: -3.14159265'f32}
    let deg   = angle.toDegrees()
    Swag.require(deg > -180.001'f32 and deg < -179.999'f32)

    let implicitAngle: InlineCrossAstCall.Angle = -3.14159265'f32
    Swag.require(implicitAngle.rad < -3.141'f32 and implicitAngle.rad > -3.142'f32)
    let implicitDeg = implicitAngle.toDegrees()
    Swag.require(implicitDeg > -180.001'f32 and implicitDeg < -179.999'f32)
    Swag.require(InlineCrossAstCall.isEqualEpsilon(implicitAngle.toDegrees(), -180.0, 0.001))
    Swag.require(InlineCrossAstCall.isEqualEpsilonF64Only(InlineCrossAstCall.inlineF32Degrees(-3.14159265'f32), -180.0, 0.001))
    Swag.require(InlineCrossAstCall.nestedIfParamCaller(0) == 7)
    Swag.require(InlineCrossAstCall.nestedIfParamCaller(4) == 5)
    Swag.require(InlineCrossAstCall.inlineArgFromLocal(-6) == 6)
    Swag.require(InlineCrossAstCall.inlineArgFromLocal(8) == 9)
    Swag.require(InlineCrossAstCall.inlineMethodParamFromCallerExpr(8))
    Swag.require(InlineCrossAstCall.inlineMacroStmtCapture(5) == 9)
    Swag.require(InlineCrossAstCall.inlineForwardedMacroCapture(5) == 7)
    Swag.require(InlineCrossAstCall.inlineMacroBlockCapture(5) == 10)
    Swag.require(InlineCrossAstCall.inlineMacroExprCapture(4) == 10)
    Swag.require(InlineCrossAstCall.inlineForwardedGenericMacroCapture(4) == 5)
    Swag.require(InlineCrossAstCall.inlineForwardedGenericMacroReturn(4) == 6)
    Swag.require(InlineCrossAstCall.inlineDirectReceiverCheck(4, 0))
    Swag.require(InlineCrossAstCall.inlineForwardedCountIsFour(4))
    Swag.require(InlineCrossAstCall.inlineForwardedValueReceiverCheckReversed(4, 0))
    Swag.require(InlineCrossAstCall.inlineForwardedValueReceiverCheck(4, 0))
    Swag.require(InlineCrossAstCall.inlineSafetyLikeReceiverCheck(4, 0))
    var data: [16] u8
    let pix = InlineCrossAstCall.inlinePointerOffset(data.buffer, 1, 1, 2, 4)
    pix[0] = 77
    Swag.require(data[6] == 77)
    InlineCrossAstCall.inlineInjectedPointerOffset(data.buffer)
    Swag.require(data[6] == 91)
    var pixelProbe = InlineCrossAstCall.InlinePixelProbe{buffer: data.buffer, bpp8: 2, width: 4}
    InlineCrossAstCall.inlineInjectedPointerOffsetShadow(&pixelProbe)
    Swag.require(data[6] == 103)
    InlineCrossAstCall.inlineInjectedContextDataShadow(&pixelProbe)
    Swag.require(data[6] == 117)
    InlineCrossAstCall.inlineInjectedLocalContextDataShadow(&pixelProbe)
    Swag.require(data[6] == 119)
    Swag.require(InlineCrossAstCall.inlineMixinCapture(6) == 9)
}
