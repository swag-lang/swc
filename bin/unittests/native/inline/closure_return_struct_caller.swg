#global private

// An inlined closure factory used by a caller that returns a struct indirectly. The closure
// value must be built in the inline result slot, never in the caller's own return slot: the
// caller returns a Quote, and writing a ClosureValue there overwrites the result being built.

struct Quote
{
    billableSeats:     s32
    seatSubtotalCents: s32
    discountCents:     s32
}

#[Swag.Inline]
func makeDiscountRule(seats: s32)->func||(s32)->s32
{
    var perSeatCents = 0's32
    if seats >= 10 do
        perSeatCents = 150

    return func|seats, perSeatCents|(subtotalCents: s32)->s32
    {
        if seats <= 4 do
            return 0
        return (seats - 4) * perSeatCents
    }
}

func buildQuote(seats: s32)->Quote
{
    let discountRule = makeDiscountRule(seats)

    var result: Quote
    result.billableSeats     = seats
    result.seatSubtotalCents = result.billableSeats * 2400
    result.discountCents     = discountRule(result.seatSubtotalCents)
    return result
}

#test
{
    let small = buildQuote(3)
    @assert(small.billableSeats == 3)
    @assert(small.seatSubtotalCents == 7200)
    @assert(small.discountCents == 0)

    let large = buildQuote(12)
    @assert(large.billableSeats == 12)
    @assert(large.seatSubtotalCents == 28800)
    @assert(large.discountCents == 1200)
}
