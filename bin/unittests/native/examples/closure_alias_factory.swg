#global private

// Real-life example: build a SaaS team subscription quote with a discount closure
// and a plain lambda for optional priority support pricing.

struct SubscriptionPlan
{
    code:               string
    baseSeatPriceCents: s32
    includedSeats:      s32
}

struct TeamOrder
{
    requestedSeats:       s32
    analyticsAddOnCents:  s32
    needsPrioritySupport: bool
}

struct QuoteSummary
{
    billableSeats:     s32
    seatSubtotalCents: s32
    addOnCents:        s32
    discountCents:     s32
    supportCents:      s32
    totalCents:        s32
}

alias SeatDiscountRule = func||(s32)->s32
alias SupportFeeRule   = func||(bool)->s32

func makeSeatDiscountRule(requestedSeats: s32)->SeatDiscountRule
{
    var discountPerSeatCents: s32
    if requestedSeats >= 20 do
        discountPerSeatCents = 350
    else
    {
        if requestedSeats >= 10 do
            discountPerSeatCents = 150
    }

    return func|requestedSeats, discountPerSeatCents|(seatSubtotalCents: s32)->s32
    {
        if requestedSeats <= 4 do
            return 0

        if (requestedSeats - 4) * discountPerSeatCents > seatSubtotalCents do
            return seatSubtotalCents

        return (requestedSeats - 4) * discountPerSeatCents
    }
}

func buildQuote(plan: SubscriptionPlan, order: TeamOrder, supportFeeRule: SupportFeeRule)->QuoteSummary
{
    let discountRule = makeSeatDiscountRule(order.requestedSeats)

    var result: QuoteSummary
    result.billableSeats = order.requestedSeats - plan.includedSeats
    if result.billableSeats < 0 do
        result.billableSeats = 0

    result.seatSubtotalCents = result.billableSeats * plan.baseSeatPriceCents
    result.addOnCents        = order.analyticsAddOnCents
    result.discountCents     = discountRule(result.seatSubtotalCents)
    result.supportCents      = supportFeeRule(order.needsPrioritySupport)
    result.totalCents        = result.seatSubtotalCents + result.addOnCents + result.supportCents - result.discountCents
    return result
}

// SaaS subscription quote with closure discounts
#test
{
    const growthPlan: SubscriptionPlan = {code: "growth", baseSeatPriceCents: 2400, includedSeats: 3}

    let supportFeeRule: SupportFeeRule = func(needsPrioritySupport: bool)->s32
    {
        if needsPrioritySupport do
            return 2500
        return 0
    }

    let startupOrder = TeamOrder{requestedSeats: 8, analyticsAddOnCents: 1200, needsPrioritySupport: false}
    let startupQuote = buildQuote(growthPlan, startupOrder, supportFeeRule)

    Swag.assert(startupQuote.billableSeats == 5)
    Swag.assert(startupQuote.seatSubtotalCents == 12000)
    Swag.assert(startupQuote.discountCents == 0)
    Swag.assert(startupQuote.supportCents == 0)
    Swag.assert(startupQuote.totalCents == 13200)

    let scaleUpOrder = TeamOrder{requestedSeats: 12, analyticsAddOnCents: 5000, needsPrioritySupport: true}
    let scaleUpQuote = buildQuote(growthPlan, scaleUpOrder, supportFeeRule)

    Swag.assert(scaleUpQuote.billableSeats == 9)
    Swag.assert(scaleUpQuote.seatSubtotalCents == 21600)
    Swag.assert(scaleUpQuote.discountCents == 1200)
    Swag.assert(scaleUpQuote.supportCents == 2500)
    Swag.assert(scaleUpQuote.totalCents == 27900)

    let enterpriseOrder = TeamOrder{requestedSeats: 22, analyticsAddOnCents: 9000, needsPrioritySupport: true}
    let enterpriseQuote = buildQuote(growthPlan, enterpriseOrder, supportFeeRule)

    Swag.assert(enterpriseQuote.billableSeats == 19)
    Swag.assert(enterpriseQuote.seatSubtotalCents == 45600)
    Swag.assert(enterpriseQuote.discountCents == 6300)
    Swag.assert(enterpriseQuote.supportCents == 2500)
    Swag.assert(enterpriseQuote.totalCents == 50800)
}
