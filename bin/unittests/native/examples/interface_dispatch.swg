#global private

// Strategy pattern: a pipeline of pricing rules implemented as interfaces.
// Demonstrates dynamic dispatch, interface arrays, state mutation, and
// interface switch for classification.

enum ProductKind: u8
{
    Book
    Electronics
    Food
    Clothing
}

struct OrderLine
{
    kind:     ProductKind
    quantity: s32
    unitCent: s32
}

impl OrderLine
{
    mtd totalCent()->s32 => .quantity * .unitCent
}

// Discount rule interface.
interface IDiscountRule
{
    mtd apply(line: *OrderLine)->s32
    mtd tag()->string
}

// Bulk discount: >5 items gets 10% off.
struct BulkDiscount {}

impl IDiscountRule for BulkDiscount
{
    mtd impl apply(line: *OrderLine)->s32
    {
        if line.quantity > 5 do
            return (line.quantity * line.unitCent) / 10
        return 0
    }
    mtd impl tag()->string => "bulk"
}

// Category discount: books are 15% off.
struct BookDiscount {}

impl IDiscountRule for BookDiscount
{
    mtd impl apply(line: *OrderLine)->s32
    {
        if line.kind == ProductKind.Book do
            return (line.quantity * line.unitCent) * 15 / 100
        return 0
    }
    mtd impl tag()->string => "book"
}

// Flat discount: fixed amount off any item.
struct FlatDiscount { amountCent: s32 }

impl IDiscountRule for FlatDiscount
{
    mtd impl apply(line: *OrderLine)->s32 => me.amountCent
    mtd impl tag()->string                => "flat"
}

// Apply all rules to a single line, return best discount.
func bestDiscount(rules: [..] IDiscountRule, line: *OrderLine)->s32
{
    var best: s32 = 0
    for i in rules.count
    {
        let d = rules[i].apply(line)
        if d > best do
            best = d
    }
    return best
}

// Basic: single rule, single line.
#test
{
    var bulk:  BulkDiscount
    var rules: [1] IDiscountRule = [cast(IDiscountRule) bulk]

    var line: OrderLine = {kind: ProductKind.Electronics, quantity: 10, unitCent: 200}
    let disc            = rules[0].apply(&line)
    Swag.assert(disc == 200)
}

// Book discount activates only for books.
#test
{
    var bd:        BookDiscount
    var bookLine:  OrderLine = {kind: ProductKind.Book, quantity: 1, unitCent: 1000}
    var otherLine: OrderLine = {kind: ProductKind.Food, quantity: 1, unitCent: 1000}

    let itf = cast(IDiscountRule) bd
    Swag.assert(itf.apply(&bookLine) == 150)
    Swag.assert(itf.apply(&otherLine) == 0)
}

// Multiple rules: best discount wins.
#test
{
    var bulk: BulkDiscount
    var book: BookDiscount
    var flat: FlatDiscount = {amountCent: 50}

    var rules: [3] IDiscountRule = [cast(IDiscountRule) bulk, cast(IDiscountRule) book, cast(IDiscountRule) flat]

    // 8 books at 1000c each: bulk=800, book=1200, flat=50 -> best=1200
    var line: OrderLine = {kind: ProductKind.Book, quantity: 8, unitCent: 1000}
    Swag.assert(bestDiscount(Swag.makeSlice(&rules[0], 3), &line) == 1200)
}

// Swag.kindOf to classify which rule type was applied.
#test
{
    var bulk: BulkDiscount
    var book: BookDiscount
    var flat: FlatDiscount = {amountCent: 25}

    var rules: [3] IDiscountRule = [cast(IDiscountRule) bulk, cast(IDiscountRule) book, cast(IDiscountRule) flat]

    Swag.assert(Swag.kindOf(rules[0]) == BulkDiscount)
    Swag.assert(Swag.kindOf(rules[1]) == BookDiscount)
    Swag.assert(Swag.kindOf(rules[2]) == FlatDiscount)

    Swag.assert(rules[0].tag() == "bulk")
    Swag.assert(rules[1].tag() == "book")
    Swag.assert(rules[2].tag() == "flat")
}

// Interface switch to dispatch by concrete type.
func classifyRule(rule: IDiscountRule)->s32
{
    switch rule
    {
    case BulkDiscount: return 1
    case BookDiscount: return 2
    case FlatDiscount: return 3
    default:           return 0
    }
}

#test
{
    var bulk: BulkDiscount
    var book: BookDiscount
    var flat: FlatDiscount = {amountCent: 10}
    Swag.assert(classifyRule(cast(IDiscountRule) bulk) == 1)
    Swag.assert(classifyRule(cast(IDiscountRule) book) == 2)
    Swag.assert(classifyRule(cast(IDiscountRule) flat) == 3)
}
