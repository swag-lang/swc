#global internal

struct A {}
interface I {
    mtd A() -> s32;
}

impl I for A {
    mtd A() -> s32 {
        return 0;
    }
}