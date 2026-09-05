namespace InlineCrossFile
{
    #[Swag.Inline]
    func(T) forEachMutable(values: [..] T, action: func||(*T))
    {
        for i in values.count do
            action(&values[i])
    }

    struct Text
    {
        data:  const [*] u8?
        count: u64
    }

    impl Text
    {
        #[Swag.Implicit, Swag.Inline]
        mtd const opCast()->string => Swag.makeString(.data, .count)
    }

    struct TextTarget { count: u64 }

    impl TextTarget
    {
        #[Swag.Inline]
        mtd opSet(value: string) => .set(value)

        #[Swag.NoInline]
        mtd set(value: string?) { .count = value.count }
    }

    struct Factory {}
    struct Position { x: s32 }

    impl Factory
    {
        #[Swag.Inline]
        func(T) create(value: s32 = 0, id: s32 = 0, hook: s32 = 0)->s32
        {
            return create'T(value, "", {}, id, hook)
        }

        #[Swag.Inline]
        func(T) create(value: s32, position: Position, id: s32 = 0, hook: s32 = 0)->s32
        {
            return create'T(value, "", position, id, hook)
        }

        func(T) create(value: s32, name: string?, position: Position, id: s32 = 0, hook: s32 = 0)->s32
        {
            return value + 3
        }
    }

    struct(T) Buffer
    {
        data: [*] T
    }

    impl Buffer
    {
        #[Swag.Inline]
        mtd(op: Swag.Operator) opIndexAssign(index: u64, value: T)
        {
            let buffer = .data!
            #ast "buffer[index] " ++ op.symbol() ++ " value"
        }

        #[Swag.Inline]
        mtd opIndexPtr(index: u64)->*T
        {
            let buffer = .data!
            return buffer + index
        }
    }

    struct Pair { x, y: s32 }

    impl Pair
    {
        // An element type whose compound operator is itself an inlined operator: the generated
        // 'buffer[index] += value' of 'Buffer.opIndexAssign' becomes a nested expansion, and the
        // clone of its receiver pins the symbols the generated identifiers resolved to.
        #[Swag.Inline]
        mtd(op: Swag.Operator) opAssign(other: Pair)
            where op == .AddAssign
        {
            .x += other.x
            .y += other.y
        }
    }

    #[Swag.NoInline]
    private func increment(value: s32)->s32 => value + 1

    #[Swag.Inline]
    func nested(value: s32)->s32 => increment(value) * 2

    #[Swag.Inline]
    func(T) identity(value: T)->T => value

    private func apply(value: s32, callback: func(s32)->s32)->s32 => callback(value)

    #[Swag.Inline]
    func withCallback(value: s32)->s32 => apply(value, func(x) => x * 3)

    struct(T) Vector
    {
        x, y: T
    }

    impl Vector
    {
        #[Swag.Inline]
        mtd(op: Swag.Operator) const opBinary(other: Vector'T)->Vector'T
            where op == .Add or op == .Sub
        {
            #static if op == .Add
            {
                return {.x + other.x, .y + other.y}
            }
            else
            {
                return {.x - other.x, .y - other.y}
            }
        }
    }
}
