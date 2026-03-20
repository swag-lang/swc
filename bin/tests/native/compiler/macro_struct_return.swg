#global fileprivate

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
    shippingCents:        s32
    taxCents:             s32
    totalCents:           s32
}

#[Swag.Macro]
func visitInvoiceLines(lines: const [..] InvoiceLine, stmt: #code void)
{
    for @countof(lines)
    {
        let #alias0 = lines[@index]
        let #alias1 = lines[@index].quantity * lines[@index].unitPriceCents
        #inject(stmt)
    }
}

func buildInvoiceTotals(lines: const [..] InvoiceLine, expeditedShipping: bool)->InvoiceTotals
{
    var lineCount: s32
    var taxableLineCount: s32
    var subtotalCents: s32
    var taxableSubtotalCents: s32

    visitInvoiceLines(|line, lineTotalCents| lines)
    {
        @assert(line.quantity > 0)
        @assert(line.unitPriceCents > 0)
        @assert(lineTotalCents == line.quantity * line.unitPriceCents)
        lineCount += 1
        subtotalCents += lineTotalCents
        if line.taxable
        {
            taxableLineCount += 1
            taxableSubtotalCents += lineTotalCents
        }
    }

    var shippingCents = 600
    if expeditedShipping do
        shippingCents = 1500

    let taxCents = taxableSubtotalCents / 10

    var result: InvoiceTotals
    result.lineCount = lineCount
    result.taxableLineCount = taxableLineCount
    result.subtotalCents = subtotalCents
    result.taxableSubtotalCents = taxableSubtotalCents
    result.shippingCents = shippingCents
    result.taxCents = taxCents
    result.totalCents = subtotalCents + shippingCents + taxCents
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
    @assert(starterTotals.shippingCents == 600)
    @assert(starterTotals.taxCents == 1300)
    @assert(starterTotals.totalCents == 22900)
}
