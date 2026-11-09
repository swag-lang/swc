#global if #command == Swag.CompilerCommand.Test
#global internal

using Swag, Core, Core.Errors

#test
{
    // 8,001 bits/s over a 1,000-tick clock credits exactly one fractional bit
    // over 1,000 pictures. The input packets spend exactly 8,000 bits.
    var control = expect H264.RateControl.create(8_001, 10_000, 1_000, 20, 40)
    var picture = 0'u32
    while picture < 1_000
    {
        let qp = control.chooseQp(false, false)
        Swag.require(qp == 30)
        Swag.require(qp == control.chooseQp(false, false))
        expect control.observe(1, 1, qp)
        picture += 1
    }
    Swag.require(control.fullnessBits == 5_001)
    Swag.require(control.fractionalBits == 0)
}

#test
{
    var control = expect H264.RateControl.create(8_000, 16_000, 1_000, 20, 24)
    Swag.require(control.chooseQp(false, false) == 22)
    Swag.require(control.chooseQp(true, false) == 23)
    Swag.require(control.chooseQp(true, true) == 24)
    Swag.require(control.fullnessBits == 8_000)

    // An oversized IDR drains the reservoir but remains valid feedback.
    expect control.observe(3_000, 1_000, control.chooseQp(true, true))
    Swag.require(control.fullnessBits == 0)
    Swag.require(control.chooseQp(false, false) == 24)
    Swag.require(control.chooseQp(true, true) == 24)
    expect control.observe(1, 1_000, control.chooseQp(false, false))
    Swag.require(control.fullnessBits == 7_992)
    expect control.observe(1, 1_000, control.chooseQp(false, false))
    Swag.require(control.fullnessBits == 15_984)
    Swag.require(control.chooseQp(false, false) == 22)
    Swag.require(control.chooseQp(true, true) == 24)
    expect control.observe(1, 1_000, control.chooseQp(false, false))
    Swag.require(control.chooseQp(false, false) == 20)
    Swag.require(control.chooseQp(true, true) == 22)
}

#test
{
    // Key/scene-cut bias cannot jump beyond the two-QP step from the last used QP.
    var control = expect H264.RateControl.create(8_000, 16_000, 1_000, 0, 51)
    let first = control.chooseQp(false, false)
    Swag.require(first == 25)
    expect control.observe(3_000, 1_000, first)
    Swag.require(control.chooseQp(false, false) == 27)
    Swag.require(control.chooseQp(true, true) == 27)
    Swag.require(control.chooseQp(true, true) == control.chooseQp(true, true))
}

#test
{
    var rejected: Swag.Error
    discard catch H264.RateControl.create(0, 100, 1_000, 0, 51) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch H264.RateControl.create(1, 0, 1_000, 0, 51) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch H264.RateControl.create(1, 100, 0, 0, 51) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch H264.RateControl.create(1, 100, 1_000, 30, 29) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch H264.RateControl.create(1, 100, 1_000, 0, 52) as rejected
    Swag.require(rejected.value() is BadParameterError)

    var control = expect H264.RateControl.create(8_000, 16_000, 1_000, 20, 24)
    discard catch control.observe(1, 0, 22) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch control.observe(1, 1_000, 25) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch control.observe(Swag.U64.Max / 8 + 1, 1_000, 22) as rejected
    Swag.require(rejected.value() is OverflowError)
    Swag.require(control.fullnessBits == 8_000 and control.fractionalBits == 0)
    Swag.require(control.chooseQp(false, false) == 22)
    expect control.observe(1, 1_000, 22)
    // A two-step change is legal; the next assertion checks a larger jump.
    expect control.observe(1, 1_000, 20)
    discard catch control.observe(1, 1_000, 24) as rejected
    Swag.require(rejected.value() is BadParameterError)
}

#test
{
    // Overflow in budget multiplication and in the final whole+fractional sum
    // must leave the state untouched, including the carried remainder.
    var rejected: Swag.Error
    var control = expect H264.RateControl.create(Swag.U64.Max, 100, 1, 0, 51)
    discard catch control.observe(0, 2, 25) as rejected
    Swag.require(rejected.value() is OverflowError)
    Swag.require(control.fullnessBits == 50 and control.fractionalBits == 0)
    Swag.require(control.chooseQp(false, false) == 25)

    let rate = 2 * (Swag.U64.Max / 3) + 1
    var fractional = expect H264.RateControl.create(rate, 100, 2, 0, 51)
    expect fractional.observe(0, 1, 25)
    Swag.require(fractional.fullnessBits == 100 and fractional.fractionalBits == 1)
    discard catch fractional.observe(0, 3, 25) as rejected
    Swag.require(rejected.value() is OverflowError)
    Swag.require(fractional.fullnessBits == 100 and fractional.fractionalBits == 1)
}
