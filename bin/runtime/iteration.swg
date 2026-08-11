// Reverse iteration is represented by ordinary borrowed views. The compiler only knows
// `opVisit`; these types keep traversal policy in user-visible, composable values.

#[Swag.Opaque]
struct(T) ReversedCount
{
    count: T
}

impl ReversedCount
{
    #[Swag.Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(item: T))
        where !ptr
    {
        var item = .count
        for .count
        {
            item -= cast(T) 1
            #inject(stmt, item = item)
        }
    }
}

// Returns a zero-allocation view that visits the indices of `count` in descending order.
#[Swag.Inline]
func(T) reversed(count: T)->ReversedCount'T
    where #typeof(#type T).kind == .Native and
          (cast(const *Swag.TypeInfoNative) #typeof(#type T)).nativeKind >= .S8 and
          (cast(const *Swag.TypeInfoNative) #typeof(#type T)).nativeKind <= .U64
{
    return {count: count}
}

#[Swag.Opaque]
struct(T) IterationRange
{
    lower:     T
    upper:     T
    inclusive: bool
}

// Returns a zero-allocation half-open interval `[lower, upper)`.
#[Swag.Inline]
func(T) range(lower, upper: T)->IterationRange'T
{
    return {lower: lower, upper: upper}
}

// Returns a zero-allocation closed interval `[lower, upper]`.
#[Swag.Inline]
func(T) rangeTo(lower, upper: T)->IterationRange'T
{
    return {lower: lower, upper: upper, inclusive: true}
}

#[Swag.Opaque]
struct(T) ReversedRange
{
    lower:     T
    upper:     T
    inclusive: bool
}

impl IterationRange
{
    #[Swag.Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(item: T))
        where !ptr
    {
        if .lower <= .upper
        {
            var item = .lower
            #scope(Up)
                while item < .upper or (.inclusive and item == .upper)
            {
                #scope(Down)
                    #inject(stmt, item = item, break = break to Up, continue = break to Down)
                if item == .upper do
                    break
                item += cast(T) 1
            }
        }
    }

}

// Returns the same interval with descending traversal.
#[Swag.Inline]
func(T) reversed(value: IterationRange'T)->ReversedRange'T
    => {lower: value.lower, upper: value.upper, inclusive: value.inclusive}

impl ReversedRange
{
    #[Swag.Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(item: T))
        where !ptr
    {
        if .lower <= .upper and (.inclusive or .upper != .lower)
        {
            var item = .upper
            if !.inclusive do
                item -= cast(T) 1

            #scope(Up)
                while true
            {
                #scope(Down)
                    #inject(stmt, item = item, break = break to Up, continue = break to Down)
                if item == .lower do
                    break
                item -= cast(T) 1
            }
        }
    }
}

#[Swag.Opaque]
struct(T) ReversedSlice
{
    values: [..] T
}

impl ReversedSlice
{
    #[Swag.Macro]
    mtd(ptr: bool) opVisit(stmt: #code(item, index: u64))
    {
        var scan = @dataof(.values) + @countof(.values)
        for offset in @countof(.values)
        {
            scan -= 1
            let index = @countof(.values) - offset - 1
            #static if ptr do
                #inject(stmt, item = cast(&T) scan, index = index)
            elif #typeof(#type T).kind == .Struct do
                #inject(stmt, item = cast(const &T) scan, index = index)
            else do
                #inject(stmt, item = scan[0], index = index)
        }
    }
}

#[Swag.Opaque]
struct(T) ConstReversedSlice
{
    values: const [..] T
}

impl ConstReversedSlice
{
    #[Swag.Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(item, index: u64))
        where !ptr
    {
        var scan = @dataof(.values) + @countof(.values)
        for offset in @countof(.values)
        {
            scan -= 1
            let index = @countof(.values) - offset - 1
            #static if #typeof(#type T).kind == .Struct do
                #inject(stmt, item = cast(const &T) scan, index = index)
            else do
                #inject(stmt, item = scan[0], index = index)
        }
    }
}

// Returns a mutable zero-allocation view that traverses `values` in reverse order.
#[Swag.Inline]
func(T) reversed(values: [..] T)->ReversedSlice'T
    => reverseSlice(values)

// Returns an immutable zero-allocation view that traverses `values` in reverse order.
#[Swag.Inline]
func(T) reversed(values: const [..] T)->ConstReversedSlice'T
    => reverseSlice(values)

#[Swag.NoDoc, Swag.Inline]
func(T) reverseSlice(values: [..] T)->ReversedSlice'T => {values: values}

#[Swag.NoDoc, Swag.Inline]
func(T) reverseSlice(values: const [..] T)->ConstReversedSlice'T => {values: values}

// Iterates adjacent elements of an immutable slice without allocating pairs.
#[Swag.Opaque]
struct(T) Pairs
{
    values: const [..] T
}

impl Pairs
{
    #[Swag.Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(left, right))
        where !ptr
    {
        let count = @countof(.values)
        if count < 2 do
            return

        let data = @dataof(.values)
        for index in count - 1
        {
            #static if #typeof(#type T).kind == .Struct do
                #inject(stmt, left = cast(const &T) (data + index), right = cast(const &T) (data + index + 1))
            else do
                #inject(stmt, left = data[index], right = data[index + 1])
        }
    }
}

#[Swag.NoDoc, Swag.Inline]
func(T) pairsView(values: const [..] T)->Pairs'T => {values: values}

// Returns a zero-allocation view over adjacent elements of `values`.
#[Swag.Inline]
func(T) pairs(values: const [..] T)->Pairs'T
    => pairsView(values)

#[Swag.Opaque]
struct ReversedCString
{
    value: const cstring
}

impl ReversedCString
{
    #[Swag.Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(item: u8, index: u64))
        where !ptr
    {
        let count = @countof(.value)
        for offset in count
        {
            let index = count - offset - 1
            #inject(stmt, item = .value[index], index = index)
        }
    }
}

// Returns an immutable zero-allocation view over a null-terminated byte string.
func reversed(value: const cstring)->ReversedCString
    => {value: value}
