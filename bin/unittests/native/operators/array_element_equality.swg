#global private

// Regression: an array compared with '==' must give the answer its ELEMENTS give.
//
// The aggregate compare path reinterpreted the whole array as storage, so an array of
// 'string', of slices, or of structs owning an 'opEquals' answered a different question
// than a single element did: two 'string' elements viewing equal bytes at different
// addresses compared 'true' one by one and 'false' as an array. A struct holding such an
// array inherited the same disagreement.
//
// Every case forces RUNTIME, memory-backed operands through 'Swag.Optimize(false)' helpers,
// so neither Sema folding nor the optimizer can answer before code generation does.

struct Point
{
    x, y: s32
}

impl Point
{
    // Answers on 'x' only, so its answer and its storage deliberately disagree.
    mtd const opEquals(other: Point)->bool => x == other.x
}

// Two of these fit in one machine register, so the array is narrow enough to reach the scalar
// compare path unless a member with an answer of its own forces the aggregate one.
struct Tolerance
{
    value: s32
}

impl Tolerance
{
    // Two readings one unit apart count as the same reading.
    mtd const opEquals(other: Tolerance)->bool => value == other.value or value + 1 == other.value or value == other.value + 1
}

struct Holder
{
    names: [2] string
    tag:   s32
}

#[Swag.Optimize(false)]
func viewText(buffer: const [*] u8, count: u64)->string => cast(string) @mkslice(buffer, count)

#[Swag.Optimize(false)]
func viewBytes(buffer: const [*] u8, count: u64)->const [..] u8 => @mkslice(buffer, count)

#[Swag.Optimize(false)]
func eqNames(a, b: [2] string)->bool => a == b
#[Swag.Optimize(false)]
func neNames(a, b: [2] string)->bool => a != b
#[Swag.Optimize(false)]
func eqGrid(a, b: [2, 2] string)->bool => a == b
#[Swag.Optimize(false)]
func eqViews(a, b: [2] const [..] u8)->bool => a == b
#[Swag.Optimize(false)]
func eqPoints(a, b: [2] Point)->bool => a == b
#[Swag.Optimize(false)]
func eqTolerances(a, b: [2] Tolerance)->bool => a == b
#[Swag.Optimize(false)]
func eqHolder(a, b: Holder)->bool => a == b
#[Swag.Optimize(false)]
func eqPlain(a, b: [4] s32)->bool => a == b

// Two distinct buffers holding the same bytes, so a view comparison and a storage
// comparison cannot agree by accident.
var g_left:  [3] u8 = ['a', 'b', 'c']
var g_right: [3] u8 = ['a', 'b', 'c']
var g_other: [3] u8 = ['a', 'b', 'z']

// A 'string' element compares the content it views, like a bare 'string' does.
#test
{
    let left  = viewText(cast(const [*] u8) &g_left[0], 3)
    let right = viewText(cast(const [*] u8) &g_right[0], 3)
    let other = viewText(cast(const [*] u8) &g_other[0], 3)
    let short = viewText(cast(const [*] u8) &g_left[0], 2)

    @assert(left == right)
    @assert(eqNames([left, left], [right, right]))
    @assert(!eqNames([left, left], [right, other]))
    @assert(!eqNames([left, left], [short, right]))
    @assert(!neNames([left, left], [right, right]))
    @assert(neNames([left, left], [right, other]))
}

// A second dimension keeps the element comparison.
#test
{
    let left  = viewText(cast(const [*] u8) &g_left[0], 3)
    let right = viewText(cast(const [*] u8) &g_right[0], 3)
    let other = viewText(cast(const [*] u8) &g_other[0], 3)

    var same:      [2, 2] string = [[left, left], [left, left]]
    var equal:     [2, 2] string = [[right, right], [right, right]]
    var different: [2, 2] string = [[right, right], [right, other]]

    @assert(eqGrid(same, equal))
    @assert(!eqGrid(same, different))
}

// A slice element compares its content, like a bare slice does.
#test
{
    let left  = viewBytes(cast(const [*] u8) &g_left[0], 3)
    let right = viewBytes(cast(const [*] u8) &g_right[0], 3)
    let other = viewBytes(cast(const [*] u8) &g_other[0], 3)

    @assert(left == right)
    @assert(eqViews([left, left], [right, right]))
    @assert(!eqViews([left, left], [right, other]))
}

// A struct element answers through the 'opEquals' it owns.
#test
{
    @assert(Point{1, 2} == Point{1, 9})
    @assert(eqPoints([{1, 2}, {3, 4}], [{1, 9}, {3, 9}]))
    @assert(!eqPoints([{1, 2}, {3, 4}], [{1, 9}, {4, 9}]))
}

// An array no wider than a machine register still asks its elements.
#test
{
    @assert(eqTolerances([{10}, {20}], [{11}, {21}]))
    @assert(!eqTolerances([{10}, {20}], [{11}, {30}]))
}

// A struct holding such an array asks the array, which asks its elements.
#test
{
    let left  = viewText(cast(const [*] u8) &g_left[0], 3)
    let right = viewText(cast(const [*] u8) &g_right[0], 3)
    let other = viewText(cast(const [*] u8) &g_other[0], 3)

    @assert(eqHolder(Holder{[left, left], 7}, Holder{[right, right], 7}))
    @assert(!eqHolder(Holder{[left, left], 7}, Holder{[right, right], 8}))
    @assert(!eqHolder(Holder{[left, left], 7}, Holder{[right, other], 7}))
}

// An element with nothing of its own to say still compares as one contiguous run.
#test
{
    @assert(eqPlain([1, 2, 3, 4], [1, 2, 3, 4]))
    @assert(!eqPlain([1, 2, 3, 4], [1, 2, 3, 5]))
}
