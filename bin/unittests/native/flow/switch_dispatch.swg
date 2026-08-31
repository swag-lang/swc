#global private

// A switch whose case values the compiler knows is answered by one search over those values,
// emitted before the first case, instead of testing every case in turn. The search ignores the
// order the cases were written in, so what follows covers the shapes where that must not change
// which body a value selects.

// Copies a literal into a buffer and hands back a string over it, so a switch sees a value it
// cannot fold away.
func runtimeString(buffer: [*] u8, text: string)->string
{
    for index in text.count do
        buffer[index] = text[index]
    return Swag.makeString(buffer, text.count)
}

// Twelve names of one length, all different in their first eight bytes: the group is large enough
// to be searched on that first chunk rather than scanned.
func searchedGroup(value: string)->s32
{
    switch value
    {
    case "alpha-name01": return 1
    case "bravo-name02": return 2
    case "charlie-nm03": return 3
    case "delta-name04": return 4
    case "echo--name05": return 5
    case "foxtrot-nm06": return 6
    case "golf--name07": return 7
    case "hotel-name08": return 8
    case "india-name09": return 9
    case "juliet-nam10": return 10
    case "kilo--name11": return 11
    case "lima--name12": return 12
    }

    return 0
}

#test
{
    var buffer: [32] u8

    let names: [12] string = [
        "alpha-name01", "bravo-name02", "charlie-nm03", "delta-name04",
        "echo--name05", "foxtrot-nm06", "golf--name07", "hotel-name08",
        "india-name09", "juliet-nam10", "kilo--name11", "lima--name12"]

    for text, index in names do Swag.assert(searchedGroup(runtimeString(&buffer[0], text)) == cast(s32) index + 1)

    let others: [4] string = ["alpha-name0", "alpha-name010", "alpha-name02", "zulu--name99"]
    for text in others do Swag.assert(!searchedGroup(runtimeString(&buffer[0], text)))
}

// Ten names of one length that share their first eight bytes. Nothing tells them apart there, so
// the split has to come from the chunk after them.
func sharedPrefixGroup(value: string)->s32
{
    switch value
    {
    case "shared--a01": return 1
    case "shared--a02": return 2
    case "shared--a03": return 3
    case "shared--a04": return 4
    case "shared--a05": return 5
    case "shared--a06": return 6
    case "shared--a07": return 7
    case "shared--a08": return 8
    case "shared--a09": return 9
    case "shared--a10": return 10
    }

    return 0
}

#test
{
    var buffer: [32] u8

    let names: [10] string = [
        "shared--a01", "shared--a02", "shared--a03", "shared--a04", "shared--a05",
        "shared--a06", "shared--a07", "shared--a08", "shared--a09", "shared--a10"]

    for text, index in names do Swag.assert(sharedPrefixGroup(runtimeString(&buffer[0], text)) == cast(s32) index + 1)

    let others: [3] string = ["shared--a11", "shared--a0", "shared--b01"]
    for text in others do Swag.assert(!sharedPrefixGroup(runtimeString(&buffer[0], text)))
}

// Twenty names of one single length, so the length separates nothing at all and the whole answer
// comes from the chunks. Neither chunk tells them all apart on its own: the four bytes at the front
// leave the numbered families together, the four at the back put `beta01`, `zeta01` and `iota01` on
// the same value, and only both of them together name a case.
func sameLengthNames(value: string)->s32
{
    switch value
    {
    case "alpha1": return 1
    case "alpha2": return 2
    case "alpha3": return 3
    case "alpha4": return 4
    case "alpha5": return 5
    case "beta01": return 6
    case "beta02": return 7
    case "beta03": return 8
    case "gamma1": return 9
    case "gamma2": return 10
    case "delta1": return 11
    case "delta2": return 12
    case "eps001": return 13
    case "eps002": return 14
    case "zeta01": return 15
    case "zeta02": return 16
    case "eta001": return 17
    case "eta002": return 18
    case "iota01": return 19
    case "kappa1": return 20
    }

    return 0
}

#test
{
    var buffer: [32] u8

    let names: [20] string = [
        "alpha1", "alpha2", "alpha3", "alpha4", "alpha5",
        "beta01", "beta02", "beta03", "gamma1", "gamma2",
        "delta1", "delta2", "eps001", "eps002", "zeta01",
        "zeta02", "eta001", "eta002", "iota01", "kappa1"]

    for text, index in names do Swag.assert(sameLengthNames(runtimeString(&buffer[0], text)) == cast(s32) index + 1)

    // Every one of these shares a chunk with a case it must not be mistaken for.
    let others: [8] string = ["alpha6", "beta04", "zeta03", "iota02", "eta003", "kappa2", "alpha", "alpha11"]
    for text in others do Swag.assert(!sameLengthNames(runtimeString(&buffer[0], text)))
}

// One case listing strings of two different lengths belongs to both length groups.
func twoLengthsOneBody(value: string)->s32
{
    switch value
    {
    case "":              return 1
    case "a", "abcdefgh": return 2
    case "bb":            return 3
    default:              return 9
    }
}

#test
{
    var buffer: [32] u8
    Swag.assert(twoLengthsOneBody(runtimeString(&buffer[0], "")) == 1)
    Swag.assert(twoLengthsOneBody(runtimeString(&buffer[0], "a")) == 2)
    Swag.assert(twoLengthsOneBody(runtimeString(&buffer[0], "abcdefgh")) == 2)
    Swag.assert(twoLengthsOneBody(runtimeString(&buffer[0], "bb")) == 3)
    Swag.assert(twoLengthsOneBody(runtimeString(&buffer[0], "b")) == 9)
    Swag.assert(twoLengthsOneBody(runtimeString(&buffer[0], "abcdefghi")) == 9)
}

// A string too long to compare in place keeps the whole switch on the runtime comparison, which
// has to answer exactly the same way.
func longStringCase(value: string)->s32
{
    switch value
    {
    case "short": return 1
    case "0123456789012345678901234567890123456789012345678901234567890123456789": return 2
    }

    return 0
}

#test
{
    var buffer: [128] u8
    Swag.assert(longStringCase(runtimeString(&buffer[0], "short")) == 1)
    Swag.assert(longStringCase(runtimeString(&buffer[0], "0123456789012345678901234567890123456789012345678901234567890123456789")) == 2)
    Swag.assert(!longStringCase(runtimeString(&buffer[0], "012345678901234567890123456789012345678901234567890123456789012345678")))
}

// Values written out of order, and enough of them to be searched rather than scanned. A search
// that ordered the negative keys as if they were unsigned would answer the low half wrong.
func searchedValue(value: s32)->s32
{
    switch value
    {
    case 700:     return 1
    case 3:       return 2
    case 42:      return 3
    case -8:      return 4
    case 0:       return 5
    case 19:      return 6
    case -100000: return 7
    case 5:       return 8
    case 6:       return 9
    case 1000000: return 10
    case -1:      return 11
    case 128:     return 12
    default:      return 0
    }
}

#test
{
    let values: [12] s32 = [700, 3, 42, -8, 0, 19, -100000, 5, 6, 1000000, -1, 128]
    for value, index in values do Swag.assert(searchedValue(value) == cast(s32) index + 1)

    let others: [6] s32 = [1, 2, 4, -2, -99999, 1000001]
    for value in others do Swag.assert(!searchedValue(value))
}

// The upper half of an unsigned type sorts above its lower half, never below it.
func unsignedValue(value: u8)->s32
{
    switch value
    {
    case 0:   return 1
    case 1:   return 2
    case 2:   return 3
    case 64:  return 4
    case 127: return 5
    case 128: return 6
    case 129: return 7
    case 200: return 8
    case 254: return 9
    case 255: return 10
    default:  return 0
    }
}

#test
{
    let values: [10] u8 = [0, 1, 2, 64, 127, 128, 129, 200, 254, 255]
    for value, index in values do Swag.assert(unsignedValue(value) == cast(s32) index + 1)

    let others: [4] u8 = [3, 63, 130, 253]
    for value in others do Swag.assert(!unsignedValue(value))
}

// A sixty-four bit key does not fit an instruction immediate and has to be materialized first.
func wideValue(value: u64)->s32
{
    switch value
    {
    case 0:                  return 1
    case 0xFFFFFFFF:         return 2
    case 0x123456789ABCDEF0: return 3
    case 0xFFFFFFFFFFFFFFFF: return 4
    default:                 return 0
    }
}

#test
{
    Swag.assert(wideValue(0) == 1)
    Swag.assert(wideValue(0xFFFFFFFF) == 2)
    Swag.assert(wideValue(0x123456789ABCDEF0) == 3)
    Swag.assert(wideValue(0xFFFFFFFFFFFFFFFF) == 4)
    Swag.assert(!wideValue(1))
    Swag.assert(!wideValue(0x100000000))
    Swag.assert(!wideValue(0xFFFFFFFFFFFFFFFE))
}

// Ranges, single values and an empty range, all in one search.
func rangedValue(value: s32)->s32
{
    switch value
    {
    case -50 to -40:   return 1
    case 0 until 10:   return 2
    case 10:           return 3
    case 11:           return 4
    case 20 until 20:  return 5
    case 100 to 200:   return 6
    case 1000:         return 7
    case 2000 to 2001: return 8
    case 3000:         return 9
    case 4000:         return 10
    default:           return 0
    }
}

#test
{
    Swag.assert(rangedValue(-50) == 1)
    Swag.assert(rangedValue(-45) == 1)
    Swag.assert(rangedValue(-40) == 1)
    Swag.assert(rangedValue(0) == 2)
    Swag.assert(rangedValue(9) == 2)
    Swag.assert(rangedValue(10) == 3)
    Swag.assert(rangedValue(11) == 4)
    Swag.assert(rangedValue(200) == 6)
    Swag.assert(rangedValue(2001) == 8)
    Swag.assert(rangedValue(4000) == 10)

    // Nothing matches an empty range, and nothing falls just outside a bound.
    let others: [7] s32 = [20, -51, -39, 12, 99, 201, 2002]
    for value in others do Swag.assert(!rangedValue(value))
}

enum Fruit
{
    Apple  = 1,
    Banana = 2,
    Cherry = 7,
    Date   = 9,
    Elder  = 11,
    Fig    = 13,
    Grape  = 17,
    Honey  = 19,
    Ivy    = 23,
    Jack   = 29
}

func fruitValue(value: Fruit)->s32
{
    switch value
    {
    case .Apple:  return 1
    case .Banana: return 2
    case .Cherry: return 3
    case .Date:   return 4
    case .Elder:  return 5
    case .Fig:    return 6
    case .Grape:  return 7
    case .Honey:  return 8
    case .Ivy:    return 9
    case .Jack:   return 10
    }

    return 0
}

#test
{
    let values: [10] Fruit = [.Apple, .Banana, .Cherry, .Date, .Elder, .Fig, .Grape, .Honey, .Ivy, .Jack]
    for value, index in values do Swag.assert(fruitValue(value) == cast(s32) index + 1)

    Swag.assert(!fruitValue(cast(Fruit) 0))
    Swag.assert(!fruitValue(cast(Fruit) 30))
}

#test
{
    var value = Fruit.Grape
    var hit   = 0
    switch #complete (value)
    {
    case .Apple:
        hit = 1
    case .Banana:
        hit = 2
    case .Cherry:
        hit = 3
    case .Date:
        hit = 4
    case .Elder:
        hit = 5
    case .Fig:
        hit = 6
    case .Grape:
        hit = 7
    case .Honey:
        hit = 8
    case .Ivy:
        hit = 9
    case .Jack:
        hit = 10
    }

    Swag.assert(hit == 7)
}

func runeValue(value: rune)->s32
{
    switch value
    {
    case 'a': return 1
    case 'b': return 2
    case 'z': return 3
    case '0': return 4
    case '9': return 5
    default:  return 0
    }
}

func boolValue(value: bool)->s32
{
    switch value
    {
    case true:  return 1
    case false: return 2
    }

    return 0
}

#test
{
    Swag.assert(runeValue('a') == 1)
    Swag.assert(runeValue('b') == 2)
    Swag.assert(runeValue('z') == 3)
    Swag.assert(runeValue('0') == 4)
    Swag.assert(runeValue('9') == 5)
    Swag.assert(!runeValue('c'))

    Swag.assert(boolValue(true) == 1)
    Swag.assert(boolValue(false) == 2)
}

// `fallthrough` hands control to the next case body in source order, which the search never
// reorders.
func fallthroughValue(value: s32)->s32
{
    var result = 0
    switch value
    {
    case 1:
        result += 1
        fallthrough
    case 2:
        result += 2
    case 3:
        result += 4
    case 4:
        result += 8
    case 5:
        result += 16
    case 6:
        result += 32
    case 7:
        result += 64
    case 8:
        result += 128
    case 9:
        result += 256
    default:
        result += 512
    }

    return result
}

#test
{
    Swag.assert(fallthroughValue(1) == 3)
    Swag.assert(fallthroughValue(2) == 2)
    Swag.assert(fallthroughValue(3) == 4)
    Swag.assert(fallthroughValue(9) == 256)
    Swag.assert(fallthroughValue(10) == 512)
}

// A `default` written before other cases makes them unreachable. Searching the values would give
// them back, so a switch shaped like this keeps testing its cases one by one.
func defaultFirst(value: s32)->s32
{
    switch value
    {
    case 1:
        return 1
    default:
        return 2
    case 3:
        return 3
    }
}

#test
{
    Swag.assert(defaultFirst(1) == 1)
    Swag.assert(defaultFirst(3) == 2)
    Swag.assert(defaultFirst(9) == 2)
}

// A `where` runs after a case matched, so its switch keeps its cases in order too.
func guardedValue(value: s32, allow: bool)->s32
{
    switch value
    {
    case 1 where allow: return 1
    case 1:             return 2
    case 2:             return 3
    default:            return 0
    }
}

#test
{
    Swag.assert(guardedValue(1, true) == 1)
    Swag.assert(guardedValue(1, false) == 2)
    Swag.assert(guardedValue(2, true) == 3)
    Swag.assert(!guardedValue(3, true))
}

// A case body still owns its scope: what it defers runs when it leaves.
func deferredValue(value: s32)->s32
{
    var result = 0
    switch value
    {
    case 1:
        defer result += 1
        result += 10
    case 2:
        result += 20
    default:
        result += 30
    }

    return result
}

#test
{
    Swag.assert(deferredValue(1) == 11)
    Swag.assert(deferredValue(2) == 20)
    Swag.assert(deferredValue(9) == 30)
}

#test
{
    // A switch value the compiler cannot know keeps the same answers as the constant folded form.
    var value = 6
    var hit   = 0
    switch value
    {
    case 1, 2, 3:
        hit = 1
        break
    case 4, 5, 6:
        hit = 2
        break
    case 7:
        hit = 3
        break
    }

    Swag.assert(hit == 2)
}
