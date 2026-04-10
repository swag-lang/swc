#global fileprivate

#test
{
    var a: *s32
    var b: *s8
    let c = a == b
    let d = a <= b
}

#test
{
    var a: *s32 = null
    let b = a == null
    let c = a != null
    #assert(#typeof(b) == bool)
    #assert(#typeof(c) == bool)
}

#test
{
    var a: *s32
    var b: *s8
    let c = a < b
    let d = a > b
    let e = a >= b
}

#test
{
    var a: *s32
    let b = a == 1 // swc-expected-error {{sema_err_compare_operand_type}}
}

#test
{
    var a: *s32
    let b = a < true // swc-expected-error {{sema_err_compare_operand_type}}
}

#test
{
    var value: s32 = 42
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

#test
{
    var value: s32 = 2
    var refValue: &s32 = &value
    let ok = refValue == 2
    #assert(#typeof(ok) == bool)
}

#test
{
    var value: f32 = 1.5
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

#test
{
    var value: RefCompareStruct
    let valueRef: const &RefCompareStruct = &value
    let bad = valueRef == 0 // swc-expected-error {{sema_err_compare_operand_type}}
}
