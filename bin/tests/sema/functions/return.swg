#global fileprivate
func test1()
{
    return;
}

func test2() -> s32
{
    return 10;
}

func emitVoid() {}
func emitValue() -> s32 { return 42 }

func test6()
{
    return emitVoid();
}

func test7() -> void
{
    return emitVoid();
}
