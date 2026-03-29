#global fileprivate

impl A for B { }
impl A.B for B { }
impl A.B for B.X { }
impl A.B { }
impl A { }

impl I for A
{
    mtd impl toto() {}
}

impl GenericSample
{
    func(var U) pairWith(me, other: U)->U => other
    func(var U, var V) makeTriple(me, other: U, tail: V)->V => tail
    func(const Left: s32, const Right: s32) pickPair(me)->s32 => Left + Right
    func(var U, var V, const Left: s32, const Right: s32) makeIndexedTriple(me, other: U, tail: V)->s32 => Left + Right
    mtd(var U, const N: s32) tagged(other: U)->s32 => N
}

impl enum A.B. { } // swc-expected-error {{parser_err_expected_token_fam}}
