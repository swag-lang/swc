#global private

alias Callback = func||()->s32

struct Box
{
    value: s32
}

struct BorrowedBox
{
    pointer: *s32
}

func returnPointerCapture()->Callback
{
    var value = 7
    return func|pointer = &value|()->s32 { return pointer[] }     // swc-expected-error {{sanity_err_borrow_escape}}
}

func returnMemberCapture()->Callback
{
    var box = Box{7}
    return func|&value = box.value|()->s32 { return value }     // swc-expected-error {{sanity_err_borrow_escape}}
}

func returnSliceCapture()->Callback
{
    var values: [2] s32 = [7, 9]
    return func|view = values[0 until 1]|()->s32 { return view[0] }     // swc-expected-error {{sanity_err_borrow_escape}}
}

func returnAggregateCapture()->Callback
{
    var value = 7
    return func|box = BorrowedBox{&value}|()->s32 { return box.pointer[] }     // swc-expected-error {{sanity_err_borrow_escape}}
}

#[Swag.NoInline]
func borrowedPointer(pointer: *s32)->*s32 => pointer

func returnCallCapture()->Callback
{
    var value = 7
    return func|pointer = borrowedPointer(&value)|()->s32 { return pointer[] }     // swc-expected-error {{sanity_err_borrow_escape}}
}

func storeTaskCapture()
{
    var task: Swag.Task
    {
        var value = 7
        task.submit(func|pointer = &value|() { pointer[] = 9 })     // swc-expected-error {{sanity_err_borrow_escape}}
    }
}

func storeTaskMemberCapture()
{
    var task: Swag.Task
    {
        var box = Box{7}
        task.submit(func|&value = box.value|() { value = 9 })     // swc-expected-error {{sanity_err_borrow_escape}}
    }
}

// GAP language.parallelism.005: storing through a caller-owned parameter is exempted by
// intoArgumentOutlivesStored, even with an ordinary named capture. The local origin cannot
// propagate into a caller-parameter summary, so this currently escapes without a diagnostic.
func storeTaskParameterGap(task: *Swag.Task)
{
    var box = Box{7}
    task.submit(func|&box|() { box.value = 9 })
}

// Borrow rejection is a language rule even when optional lifecycle sanity is disabled.
#[Swag.Sanity(.Lifecycle, false)]
func returnUncheckedCapture()->Callback
{
    var value = 7
    return func|pointer = &value|()->s32 { return pointer[] }     // swc-expected-error {{sanity_err_borrow_escape}}
}

func captureParameter(pointer: *s32)->Callback
{
    return func|saved = pointer|()->s32 { return saved[] }
}

func returnParameterCapture()->Callback
{
    var value = 7
    return captureParameter(&value)     // swc-expected-error {{sanity_err_borrow_escape}}
}

// Copies of computed scalars carry no borrow of the inputs used to compute them.
func returnComputedCapture()->Callback
{
    var value = 7
    return func|saved = value + 2|()->s32 { return saved }
}

func returnLoadedCapture()->Callback
{
    var value   = 7
    let pointer = &value
    return func|saved = pointer[]|()->s32 { return saved }
}

var globalValue = 7

func returnGlobalCapture()->Callback
{
    return func|pointer = &globalValue|()->s32 { return pointer[] }
}

// The task's owner is nested inside the captured storage's lifetime, and waits before reading.
func joinLocalCapture()->s32
{
    var value = 7
    var task: Swag.Task
    task.submit(func|pointer = &value|() { pointer[] = 9 })
    task.wait()
    return value
}
