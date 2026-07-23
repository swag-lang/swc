#global private

func semaTest001()
{
    var a: #null *s32
    var b: #null *s8
    let c = a == b
    let d = a <= b
}

func semaTest002()
{
    var a: #null *s32 = null
    let b = a == null
    let c = a != null
    #assert(#typeof(b) == bool)
    #assert(#typeof(c) == bool)
}

func semaTest003()
{
    var a: #null *s32
    var b: #null *s8
    let c = a < b
    let d = a > b
    let e = a >= b
}

func semaTest004()
{
    var value:    s32 = 42
    let valueRef: const &s32 = &value
    let eq0 = valueRef == 42
    let eq1 = 42 == valueRef
    let ne0 = valueRef != 0
    let lt0 = valueRef < 100
    let lt1 = 0 < valueRef
    let le0 = valueRef <= 42
    let ge0 = valueRef >= 42
    let cmp0 = valueRef <=> 42

    #assert(#typeof(eq0) == bool)
    #assert(#typeof(eq1) == bool)
    #assert(#typeof(ne0) == bool)
    #assert(#typeof(lt0) == bool)
    #assert(#typeof(lt1) == bool)
    #assert(#typeof(le0) == bool)
    #assert(#typeof(ge0) == bool)
    #assert(#typeof(cmp0) == s32)
}

func semaTest005()
{
    var value:    s32 = 2
    var refValue: &s32 = &value
    let ok = refValue == 2
    #assert(#typeof(ok) == bool)
}

func semaTest006()
{
    var value:    f32 = 1.5
    let valueRef: const &f32 = &value
    let ok0 = valueRef == 1.5
    let ok1 = valueRef < 2.0
    let cmp = valueRef <=> 1.5

    #assert(#typeof(ok0) == bool)
    #assert(#typeof(ok1) == bool)
    #assert(#typeof(cmp) == s32)
}

struct RefCompareStruct
{
    value: s32
}

interface ICompareAllocator
{
    mtd reserve()->u32;
}

struct CompareAllocator
{
    id: u32
}

impl ICompareAllocator for CompareAllocator
{
    mtd impl reserve()->u32 => .id
}

struct CompareAllocatorHolder
{
    allocator: #null ICompareAllocator
}

impl CompareAllocatorHolder
{
    mtd needsAllocator()->bool
    {
        return .allocator == null
    }

    mtd needsAllocatorLeft()->bool
    {
        return null == .allocator
    }

    mtd hasAllocator()->bool
    {
        return .allocator != null
    }
}

func semaTest007()
{
    var holder = CompareAllocatorHolder{}
    let a = holder.needsAllocator()
    let b = holder.needsAllocatorLeft()
    let c = holder.hasAllocator()
    #assert(#typeof(a) == bool)
    #assert(#typeof(b) == bool)
    #assert(#typeof(c) == bool)
}

func semaTest008()
{
    var holder = CompareAllocatorHolder{}
    var alloc = CompareAllocator{id: 77}
    holder.allocator = alloc

    let a = holder.needsAllocator()
    let b = holder.needsAllocatorLeft()
    let c = holder.hasAllocator()
    #assert(#typeof(a) == bool)
    #assert(#typeof(b) == bool)
    #assert(#typeof(c) == bool)
}
