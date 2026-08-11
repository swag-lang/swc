#global private

// A struct without an 'opEquals' compares member by member as soon as one member answers
// something other than a byte comparison. Every holder below owns such a member, so the two
// values it compares view equal content over two different buffers: a byte comparison of the
// storage would answer 'false' where the member answers 'true'.

struct StringHolder
{
    text: string
    tag:  s64
}

struct NestedHolder
{
    holder: StringHolder
    extra:  s32
}

struct SliceHolder
{
    data: const [..] u8
    tag:  s64
}

struct AlwaysEqual
{
    value: s32
}

impl AlwaysEqual
{
    mtd const opEquals(other: const &AlwaysEqual)->bool
    {
        return true
    }
}

struct OverloadHolder
{
    inner: AlwaysEqual
    tag:   s64
}

struct(T) GenericHolder
{
    value: T
    tag:   s64
}

struct IgnoredStringHolder
{
    #[Swag.OperatorIgnore]
    text: string
    tag:  s64
}

#[Swag.Operators(opEquals)]
struct ExplicitStringHolder
{
    text: string
    tag:  s64
}

struct EmbeddedBase
{
    tag: s32
}

impl EmbeddedBase
{
    mtd const opEquals(other: const &EmbeddedBase)->bool
    {
        return true
    }
}

struct Embedder
{
    using base: EmbeddedBase
    extra:      s32
}

impl Embedder
{
    mtd const opEquals(other: const &Embedder)->bool
    {
        return .extra == other.extra
    }
}

struct PlainEmbedder
{
    using base: EmbeddedBase
    extra:      s32
}

struct Counted
{
    length: u64
}

impl Counted
{
    // An 'opEquals' declared against another type adds a comparison beside the built-in one
    // instead of replacing it, so two 'Counted' values still compare as the storage they are.
    mtd const opEquals(other: #null string)->bool
    {
        return .length == @countof(other)
    }
}

struct CountedHolder
{
    counted: Counted
    text:    string
}

// A union has no member-wise answer to give: its members share one storage.
union OverlappedHolder
{
    text: string
    raw:  [16] u8
}

struct PlainPair
{
    x, y: s32
}

// A layout with a hole in it: 7 bytes of padding between the members, and the same again in
// every element of an array of them.
struct Padded
{
    small: u8
    wide:  u64
}

struct PaddedHolder
{
    first:  Padded
    second: Padded
}

#[Swag.Optimize(false)]
func viewText(buffer: const [*] u8)->string
{
    return cast(string) @mkslice(buffer, 3'u64)
}

#[Swag.Optimize(false)]
func viewBytes(buffer: const [*] u8)->const [..] u8
{
    return @mkslice(buffer, 3'u64)
}

#test
{
    var left:  [3] u8 = ['a', 'b', 'c']
    var right: [3] u8 = ['a', 'b', 'c']

    let leftText  = viewText(cast(const [*] u8) &left[0])
    let rightText = viewText(cast(const [*] u8) &right[0])
    @assert(leftText == rightText)

    let a = StringHolder{text: leftText, tag: 7}
    let b = StringHolder{text: rightText, tag: 7}
    let c = StringHolder{text: rightText, tag: 8}
    @assert(a == b)
    @assert(!(a != b))
    @assert(a != c)
}

#test
{
    var left:  [3] u8 = ['a', 'b', 'c']
    var right: [3] u8 = ['a', 'b', 'c']

    let a = NestedHolder{holder: {text: viewText(cast(const [*] u8) &left[0]), tag: 7}, extra: 3}
    let b = NestedHolder{holder: {text: viewText(cast(const [*] u8) &right[0]), tag: 7}, extra: 3}
    let c = NestedHolder{holder: {text: viewText(cast(const [*] u8) &right[0]), tag: 7}, extra: 4}
    @assert(a == b)
    @assert(a != c)
}

#test
{
    var left:  [3] u8 = ['a', 'b', 'c']
    var right: [3] u8 = ['a', 'b', 'c']

    let a = SliceHolder{data: viewBytes(cast(const [*] u8) &left[0]), tag: 1}
    let b = SliceHolder{data: viewBytes(cast(const [*] u8) &right[0]), tag: 1}
    let c = SliceHolder{data: viewBytes(cast(const [*] u8) &right[0]), tag: 2}
    @assert(a == b)
    @assert(a != c)
}

#test
{
    // The member's 'opEquals' decides, so two different values compare equal.
    let a = OverloadHolder{inner: {value: 1}, tag: 7}
    let b = OverloadHolder{inner: {value: 2}, tag: 7}
    let c = OverloadHolder{inner: {value: 2}, tag: 8}
    @assert(a == b)
    @assert(a != c)
}

#test
{
    var left:  [3] u8 = ['a', 'b', 'c']
    var right: [3] u8 = ['a', 'b', 'c']

    // A struct declared in a function body has no name reachable from where its generic instance
    // is completed, and the generated comparison names its type through the block it lives in.
    struct(T) LocalHolder
    {
        value: T
        tag:   s64
    }

    let a = LocalHolder'string{value: viewText(cast(const [*] u8) &left[0]), tag: 1}
    let b = LocalHolder'string{value: viewText(cast(const [*] u8) &right[0]), tag: 1}
    let c = LocalHolder'string{value: viewText(cast(const [*] u8) &right[0]), tag: 2}
    @assert(a == b)
    @assert(a != c)

    struct LocalPlainHolder
    {
        text: string
        tag:  s64
    }

    let d = LocalPlainHolder{text: viewText(cast(const [*] u8) &left[0]), tag: 1}
    let e = LocalPlainHolder{text: viewText(cast(const [*] u8) &right[0]), tag: 1}
    @assert(d == e)
}

#test
{
    var left:  [3] u8 = ['a', 'b', 'c']
    var right: [3] u8 = ['a', 'b', 'c']

    // Each generic instance decides on its own members.
    let a = GenericHolder'string{value: viewText(cast(const [*] u8) &left[0]), tag: 4}
    let b = GenericHolder'string{value: viewText(cast(const [*] u8) &right[0]), tag: 4}
    let c = GenericHolder'string{value: viewText(cast(const [*] u8) &right[0]), tag: 5}
    @assert(a == b)
    @assert(a != c)

    let d = GenericHolder's32{value: 5, tag: 4}
    let e = GenericHolder's32{value: 5, tag: 4}
    let f = GenericHolder's32{value: 6, tag: 4}
    @assert(d == e)
    @assert(d != f)
}

#test
{
    // An ignored member stays out of the generated comparison.
    let a = IgnoredStringHolder{text: "one", tag: 2}
    let b = IgnoredStringHolder{text: "two", tag: 2}
    let c = IgnoredStringHolder{text: "one", tag: 3}
    @assert(a == b)
    @assert(a != c)
}

#test
{
    var left:  [3] u8 = ['a', 'b', 'c']
    var right: [3] u8 = ['a', 'b', 'c']

    // An explicit '#[Swag.Operators]' still owns the comparison.
    let a = ExplicitStringHolder{text: viewText(cast(const [*] u8) &left[0]), tag: 9}
    let b = ExplicitStringHolder{text: viewText(cast(const [*] u8) &right[0]), tag: 9}
    @assert(a == b)
}

#test
{
    // A comparison declared by the embedder wins over the one its 'using' member promotes,
    // instead of tying with it.
    let a = Embedder{base: {tag: 1}, extra: 5}
    let b = Embedder{base: {tag: 2}, extra: 5}
    let c = Embedder{base: {tag: 1}, extra: 6}
    @assert(a == b)
    @assert(a != c)
}

#test
{
    // Without one of its own, the embedder gets a member-wise comparison because a member owns
    // an 'opEquals': that member answers for itself, and 'extra' still compares as a number.
    let a = PlainEmbedder{base: {tag: 1}, extra: 5}
    let b = PlainEmbedder{base: {tag: 2}, extra: 5}
    let c = PlainEmbedder{base: {tag: 1}, extra: 6}
    @assert(a == b)
    @assert(a != c)
}

#test
{
    var left:  [3] u8 = ['a', 'b', 'c']
    var right: [3] u8 = ['a', 'b', 'c']

    // The overload against another type is additive: two 'Counted' values still compare, and
    // the holder still gets its member-wise comparison.
    let a = CountedHolder{counted: {length: 3}, text: viewText(cast(const [*] u8) &left[0])}
    let b = CountedHolder{counted: {length: 3}, text: viewText(cast(const [*] u8) &right[0])}
    let c = CountedHolder{counted: {length: 4}, text: viewText(cast(const [*] u8) &right[0])}
    @assert(a == b)
    @assert(a != c)

    @assert(a.counted == b.counted)
    @assert(a.counted != c.counted)

    // The foreign overload keeps answering what it was written for.
    @assert(a.counted == "abc")
    @assert(a.counted != "ab")
}

#test
{
    // Assigning the widest member leaves no undefined byte behind, so the storage comparison
    // a union keeps is well defined.
    var a: OverlappedHolder = undefined
    var b: OverlappedHolder = undefined
    a.text = "same"
    b.text = "same"
    @assert(a == b)

    b.text = "other"
    @assert(a != b)
}

#[Swag.Optimize(false)]
func eqPadded(a, b: Padded)->bool => a == b

#[Swag.Optimize(false)]
func eqPaddedHolder(a, b: PaddedHolder)->bool => a == b

#[Swag.Optimize(false)]
func eqPaddedArray(a, b: [3] Padded)->bool => a == b

#test
{
    // Padding is not a member: two values whose every member is equal compare equal whatever
    // the bytes between them hold. 'undefined' plus a fill is the only way to observe it, since
    // a defaulted value zeroes its storage.
    var a: Padded = undefined
    var b: Padded = undefined
    @memset(&a, 0xAA, #sizeof(Padded))
    @memset(&b, 0x55, #sizeof(Padded))
    a.small = 1
    a.wide  = 2
    b.small = 1
    b.wide  = 2
    @assert(eqPadded(a, b))

    b.wide = 3
    @assert(!eqPadded(a, b))
}

#test
{
    // The same holds through a nested member and through an array element.
    var a: PaddedHolder = undefined
    var b: PaddedHolder = undefined
    @memset(&a, 0xAA, #sizeof(PaddedHolder))
    @memset(&b, 0x55, #sizeof(PaddedHolder))
    a.first.small  = 1
    a.first.wide   = 2
    a.second.small = 3
    a.second.wide  = 4
    b.first.small  = 1
    b.first.wide   = 2
    b.second.small = 3
    b.second.wide  = 4
    @assert(eqPaddedHolder(a, b))

    b.second.wide = 5
    @assert(!eqPaddedHolder(a, b))

    var c: [3] Padded = undefined
    var d: [3] Padded = undefined
    @memset(&c, 0xAA, #sizeof([3] Padded))
    @memset(&d, 0x55, #sizeof([3] Padded))
    for i in 3
    {
        c[i].small = 1
        c[i].wide  = 2
        d[i].small = 1
        d[i].wide  = 2
    }

    @assert(eqPaddedArray(c, d))

    d[2].wide = 3
    @assert(!eqPaddedArray(c, d))
}

#test
{
    // A struct whose members all compare as bytes keeps comparing its storage, and its
    // comparison still folds at compile time.
    const A = PlainPair{x: 1, y: 2}
    const B = PlainPair{x: 1, y: 2}
    #assert(A == B)

    let c = PlainPair{x: 1, y: 3}
    @assert(A == B)
    @assert(A != c)
}
