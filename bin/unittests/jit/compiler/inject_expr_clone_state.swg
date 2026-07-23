#global private
using Swag

namespace InjectExprCloneSupport
{
    struct VisitProbe
    {
        value: s32
    }

    struct VisitBuffer
    {
        values: [4] VisitProbe
        count:  u64
    }

    impl VisitBuffer
    {
        mtd add(value: VisitProbe)
        {
            .values[.count] = value
            .count          += 1
        }

        #[Macro]
        mtd(ptr: bool, back: bool) opVisit(stmt: #code(item: &InjectExprCloneSupport.VisitProbe, index: u64))
        {
            #if back do
                var cursor = .count
                #else do
                var cursor: u64 = 0

            #scope(Up)
                while true
            {
                #if back
                {
                    if !cursor do
                        break
                    cursor -= 1
                }
                    #else
                {
                    if cursor >= .count do
                        break
                }

                #scope(Down)
                {
                    #inject(stmt, item = cast(&InjectExprCloneSupport.VisitProbe) &.values[cursor], index = cursor, break = break to Up, continue = break to Down)
                }

                #if !back do
                    cursor += 1
            }
        }
    }

    #[Inline]
    func visitStructBuffer(values: &VisitBuffer)->s32
    {
        var code = 0
        for value, index in values
        {
            if value.value == 12 do
                continue

            code = code * 10 + value.value
            if value.value == 13 do
                return code
        }

        return code
    }

    #[Macro]
    func assignInjectedS32(out: *s32, expr: #code->s32)
    {
        dref out = #inject(expr)
    }
}

#test
{
    var values: InjectExprCloneSupport.VisitBuffer
    values.add(InjectExprCloneSupport.VisitProbe{value: 1})
    values.add(InjectExprCloneSupport.VisitProbe{value: 2})
    values.add(InjectExprCloneSupport.VisitProbe{value: 3})

    for &value in values do
        value.value += 10

    var direct = 0
    InjectExprCloneSupport.assignInjectedS32(&direct, InjectExprCloneSupport.visitStructBuffer(&values))
    @assert(direct == 123)
    @assert(InjectExprCloneSupport.visitStructBuffer(&values) == 123)
}
