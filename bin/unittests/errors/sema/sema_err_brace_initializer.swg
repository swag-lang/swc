#global private

struct Point { x, y: s32 }

func takeAny(_: any) {}
func(var T) identity(value: T)->T  => value
func(var T) makePoint(_: T)->Point => Point{}

#test
{
    var pair: (s32, s32) = {1, 2}     // swc-expected-error {{sema_err_record_needs_field_name}}
}

#test
{
    takeAny({1, 2})     // swc-expected-error {{sema_err_record_needs_field_name}}
}

#test
{
    discard identity({1, 2})     // swc-expected-error {{sema_err_record_needs_field_name}}
}

#test
{
    let (first, second) = {1, 2}     // swc-expected-error {{sema_err_record_needs_field_name}}
}

#test
{
    let points = [{1, 2}]     // swc-expected-error {{sema_err_record_needs_field_name}}
}

#test
{
    let y = 1
    var point: Point = {y, 5}     // swc-expected-error {{sema_err_struct_cast_duplicate_field}}
}

#test
{
    var point: Point = {x: 1, 2}     // swc-expected-error {{sema_err_unnamed_parameter}}
}

#test
{
    var point: Point = {1, 2, 3}     // swc-expected-error {{sema_err_struct_cast_field_count}}
}

// A shorthand matching a field still names that field on every occurrence.
#test
{
    let x = 1
    var point: Point = {x, x}     // swc-expected-error {{sema_err_struct_cast_duplicate_field}}
}

#test
{
    let x     = 1
    let point = {x, x}     // swc-expected-error {{sema_err_record_duplicate_field}}
}

#test
{
    let x = 1
    takeAny({x, x})     // swc-expected-error {{sema_err_record_duplicate_field}}
}

#test
{
    let x = 1
    let point: Point = makePoint({x, x})     // swc-expected-error {{sema_err_record_duplicate_field}}
}
