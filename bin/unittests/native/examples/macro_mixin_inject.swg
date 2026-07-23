#global private

// Real-life example: compile-time helpers shape an invoice pipeline with
// caller-scope mixins and macros that inject line-item processing.

struct InvoiceLine
{
    sku:            string
    quantity:       s32
    unitPriceCents: s32
    taxable:        bool
}

struct InvoiceTotals
{
    lineCount:            s32
    taxableLineCount:     s32
    subtotalCents:        s32
    taxableSubtotalCents: s32
    discountCents:        s32
    shippingCents:        s32
    taxCents:             s32
    totalCents:           s32
}

#[Swag.Mixin]
func declareInvoiceState()
{
    var lineCount:            s32
    var taxableLineCount:     s32
    var subtotalCents:        s32
    var taxableSubtotalCents: s32
}

#[Swag.Mixin]
func accumulateInvoiceLine(lineTotalCents: s32, isTaxable: bool)
{
    lineCount     += 1
    subtotalCents += lineTotalCents
    if isTaxable
    {
        taxableLineCount     += 1
        taxableSubtotalCents += lineTotalCents
    }
}

#[Swag.Mixin]
func declareShippingFees(baseFeeCents: s32)
{
    const standardShippingCents: s32  = baseFeeCents
    const expeditedShippingCents: s32 = baseFeeCents + 900
}

#[Swag.Macro]
func visitInvoiceLines(lines: const [..] InvoiceLine, stmt: #code(line: InvoiceLine, index: s32, lineTotalCents: s32))
{
    for @countof(lines)
    {
        #inject(stmt, line = lines[@index], index = cast(s32) @index, lineTotalCents = lines[@index].quantity * lines[@index].unitPriceCents)
    }
}

#[Swag.Macro]
func tieredDiscount(subtotalExpr: #code->s32)->s32
{
    let subtotal = #inject(subtotalExpr)
    if subtotal >= 40000 do
        return 3500

    if subtotal >= 20000 do
        return 1200

    return 0
}

func buildInvoiceTotals(lines: const [..] InvoiceLine, expeditedShipping: bool)->InvoiceTotals
{
    declareInvoiceState()
    declareShippingFees(600)

    visitInvoiceLines(lines)
    {
        @assert(index >= 0)
        @assert(line.quantity > 0)
        @assert(line.unitPriceCents > 0)
        @assert(lineTotalCents == line.quantity * line.unitPriceCents)
        accumulateInvoiceLine(lineTotalCents, line.taxable)
    }

    var shippingCents = standardShippingCents
    if expeditedShipping do
        shippingCents = expeditedShippingCents

    let discountCents = tieredDiscount(subtotalCents)
    let taxCents = taxableSubtotalCents / 10

    var result: InvoiceTotals
    result.lineCount            = lineCount
    result.taxableLineCount     = taxableLineCount
    result.subtotalCents        = subtotalCents
    result.taxableSubtotalCents = taxableSubtotalCents
    result.discountCents        = discountCents
    result.shippingCents        = shippingCents
    result.taxCents             = taxCents
    result.totalCents           = subtotalCents - discountCents + shippingCents + taxCents
    return result
}

#test
{
    const starterInvoice: [3] InvoiceLine =
        [
        {sku: "seat-license", quantity: 4, unitPriceCents: 2500, taxable: true},
        {sku: "onboarding", quantity: 1, unitPriceCents: 8000, taxable: false},
        {sku: "backup-addon", quantity: 2, unitPriceCents: 1500, taxable: true},
        ]

    let starterTotals = buildInvoiceTotals(starterInvoice, false)

    @assert(starterTotals.lineCount == 3)
    @assert(starterTotals.taxableLineCount == 2)
    @assert(starterTotals.subtotalCents == 21000)
    @assert(starterTotals.taxableSubtotalCents == 13000)
    @assert(starterTotals.discountCents == 1200)
    @assert(starterTotals.shippingCents == 600)
    @assert(starterTotals.taxCents == 1300)
    @assert(starterTotals.totalCents == 21700)

    const enterpriseInvoice: [4] InvoiceLine =
        [
        {sku: "seat-license", quantity: 10, unitPriceCents: 2500, taxable: true},
        {sku: "audit-log", quantity: 4, unitPriceCents: 2200, taxable: true},
        {sku: "migration", quantity: 1, unitPriceCents: 9500, taxable: false},
        {sku: "training", quantity: 2, unitPriceCents: 5000, taxable: false},
        ]

    let enterpriseTotals = buildInvoiceTotals(enterpriseInvoice, true)

    @assert(enterpriseTotals.lineCount == 4)
    @assert(enterpriseTotals.taxableLineCount == 2)
    @assert(enterpriseTotals.subtotalCents == 53300)
    @assert(enterpriseTotals.taxableSubtotalCents == 33800)
    @assert(enterpriseTotals.discountCents == 3500)
    @assert(enterpriseTotals.shippingCents == 1500)
    @assert(enterpriseTotals.taxCents == 3380)
    @assert(enterpriseTotals.totalCents == 54680)
}
