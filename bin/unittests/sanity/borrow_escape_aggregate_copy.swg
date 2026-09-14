#global private

struct BorrowPair
{
    first, second: *s32?
}

struct BorrowBox { pair: BorrowPair }
struct BorrowBoxes { left, right: BorrowBox }

func copiedField()->*s32?
{
    var value    = 1
    let original = BorrowPair{first: &value}
    let copied   = original
    return copied.first     // swc-expected-error {{sanity_err_borrow_escape}}
}

func assignedField()->*s32?
{
    var value    = 1
    let original = BorrowPair{first: &value}
    var copied   = BorrowPair{}
    copied = original
    return copied.first     // swc-expected-error {{sanity_err_borrow_escape}}
}

func copiedNestedField()->*s32?
{
    var value    = 1
    let original = BorrowBox{pair: BorrowPair{first: &value}}
    let copied   = original
    return copied.pair.first     // swc-expected-error {{sanity_err_borrow_escape}}
}

func copiedSubobject()->*s32?
{
    var value    = 1
    let original = BorrowBox{pair: BorrowPair{first: &value}}
    let copied   = original.pair
    return copied.first     // swc-expected-error {{sanity_err_borrow_escape}}
}

func assignedSubobject()->*s32?
{
    var value    = 1
    let original = BorrowPair{first: &value}
    var copied   = BorrowBox{}
    copied.pair = original
    return copied.pair.first     // swc-expected-error {{sanity_err_borrow_escape}}
}

func literalReadsPreviousField()->*s32?
{
    var value = 1
    var pair  = BorrowPair{first: &value}
    pair = BorrowPair{second: pair.first}
    return pair.second     // swc-expected-error {{sanity_err_borrow_escape}}
}

func literalCopiesSubobject()->*s32?
{
    var value    = 1
    let original = BorrowPair{first: &value}
    let copied   = BorrowBox{pair: original}
    return copied.pair.first     // swc-expected-error {{sanity_err_borrow_escape}}
}

func opaquePair(pointer: *s32)->BorrowPair => BorrowPair{first: pointer}

func copiedOpaqueSubobject(external: *s32)->BorrowPair
{
    var value    = 1
    var original = BorrowBox{}
    original.pair        = opaquePair(&value)
    original.pair.second = external
    let copied = original.pair
    return copied     // swc-expected-error {{sanity_err_borrow_escape}}
}

func replacingOneSubobjectKeepsOther()->*s32?
{
    var value = 1
    var pair  = BorrowPair{second: &value}
    pair.first = null
    return pair.second     // swc-expected-error {{sanity_err_borrow_escape}}
}

func replacingNestedSubobjectKeepsOther()->*s32?
{
    var value = 1
    var boxes = BorrowBoxes{}
    boxes.right.pair.first = &value
    boxes.left = BorrowBox{}
    return boxes.right.pair.first     // swc-expected-error {{sanity_err_borrow_escape}}
}

func copiedArrayField()->*s32?
{
    var value = 1
    var original: [2] BorrowPair = [BorrowPair{}, BorrowPair{}]
    original[0].first = &value
    let copied = original
    return copied[0].first     // swc-expected-error {{sanity_err_borrow_escape}}
}

func copiedDynamicElement(index: u64, external: *s32)->*s32?
{
    var value = 1
    var original: [2] BorrowPair = [BorrowPair{}, BorrowPair{}]
    original[0].first = &value
    original[1].first = external
    let copied = original[index]
    return copied.first     // swc-expected-error {{sanity_err_borrow_escape}}
}

func copiedDynamicIndependentField(index: u64, external: *s32)->*s32?
{
    var value = 1
    var original: [2] BorrowPair = [BorrowPair{}, BorrowPair{}]
    original[0] = BorrowPair{first: &value, second: external}
    original[1] = BorrowPair{second: external}
    let copied = original[index]
    return copied.second
}

func copiedIndependentField(external: *s32)->*s32?
{
    var value    = 1
    let original = BorrowPair{first: &value, second: external}
    let copied   = original
    return copied.second
}

func reboundCopiedField(external: *s32)->BorrowPair
{
    var value    = 1
    let original = BorrowPair{first: &value}
    var copied   = original
    copied.first = external
    return copied
}

func clearedCopiedSubobject()->BorrowBox
{
    var value    = 1
    let original = BorrowBox{pair: BorrowPair{first: &value}}
    var copied   = original
    copied.pair = BorrowPair{}
    return copied
}

#test
{
    var value = 7
    Swag.assert(copiedIndependentField(&value)![] == 7)
    let rebound = reboundCopiedField(&value)
    Swag.assert(rebound.first![] == 7)
    Swag.assert(clearedCopiedSubobject().pair.first == null)
    Swag.assert(copiedDynamicIndependentField(0, &value)![] == 7)
    Swag.assert(copiedDynamicIndependentField(1, &value)![] == 7)
}
