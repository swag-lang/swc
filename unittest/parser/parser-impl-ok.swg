impl A for B { }
impl A.B for B { }
impl A.B for B.X { }
impl A.B { }
impl A { }

impl I for A
{
    mtd impl toto() {}
}
