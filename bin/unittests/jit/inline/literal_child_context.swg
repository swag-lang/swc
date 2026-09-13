#global private

enum FirstKind: u8 { A, B }
enum SecondKind: u16 { C, D }

struct Pair
{
    first:  FirstKind
    second: SecondKind
}

#[Swag.Inline]
func contextualRows(index: u32)->u32
{
    let rows: [3] Pair = [
        {second: .C, first: .A},
        {first: .B,  second: .D},
        {second: .D, first: .A}
        ]
    let firsts: [3] FirstKind = [.A, .B, .A]
    let seconds = [SecondKind.C, .D, .D]
    Swag.assert(rows[index].first == firsts[index])
    Swag.assert(rows[index].second == seconds[index])
    return cast(u32) rows[index].first * 10 + cast(u32) rows[index].second
}

#test
{
    #assert(#run contextualRows(0) == 0)
    #assert(#run contextualRows(1) == 11)
    Swag.assert(contextualRows(2) == 1)
}

#test
{
    // Nested array constants retain their narrow target; scalar fields merge after sizing.
    let records = [
        {lanes: [1'u8, 2'u8], tag: 3'u8},
        {lanes: [4, 5],       tag: 6}
        ]
    #assert(#typeof(records[1].lanes[0]) == u8)
    #assert(#typeof(records[1].tag) == s32)
    Swag.assert(records[0].lanes[1] + records[1].lanes[0] + records[1].tag == 12)
}
