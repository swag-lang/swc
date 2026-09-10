#global private

struct Value
{
    value: s32 = 7
}

impl Value
{
    mtd opDrop() { .value = 0 }
}

var observed: s32

struct Reader
{
    pointer: *s32?
    value:   s32
}

impl Reader
{
    mtd opDrop()
    {
        if .pointer do
            observed = .pointer[]
    }

    #[Swag.NoInline]
    mtd set(pointer: *s32) { .pointer = pointer }
}

// Leaving a block destroys later declarations first. The task's implicit wait comes
// after Value.opDrop, so it cannot keep the captured value alive.
func taskBeforeCapture()
{
    var task:  Swag.Task
    var value: Value
    task.submit(func|&value|() { observed = value.value })     // swc-expected-error {{sanity_err_borrow_escape}}
}

// A group holds its first children itself, so reserveChild's summary relates a child's storage
// to the group and a spawn is seen as storing into it. The rule is the same as for a task: the
// group's join runs after the captured value's destructor.
func groupBeforeCapture()
{
    var group: Swag.TaskGroup
    var value: Value
    group.spawn(func|&value|() { observed = value.value })     // swc-expected-error {{sanity_err_borrow_escape}}
}

// The rule also applies to ordinary destructors and direct field assignments.
func readerBeforeValue()
{
    var reader: Reader
    var value:  Value
    reader.set(&value.value)     // swc-expected-error {{sanity_err_borrow_escape}}
}

func readerFieldBeforeValue()
{
    var reader: Reader
    var value:  Value
    reader.pointer = &value.value     // swc-expected-error {{sanity_err_borrow_scope_escape}}
}

func readerArrayBeforeValue()
{
    var readers: [2] Reader
    var value:   Value
    readers[0].pointer = &value.value     // swc-expected-error {{sanity_err_borrow_scope_escape}}
}

// Merging borrows must keep the shortest lifetime, regardless of capture or branch order.
func taskBetweenCaptures()
{
    var first:  Value
    var task:   Swag.Task
    var second: Value
    task.submit(func|&first, &second|() { observed = first.value + second.value })     // swc-expected-error {{sanity_err_borrow_escape}}
}

func readerAfterBranch(condition: bool)
{
    var first:  Value
    var reader: Reader
    var second: Value
    var pointer = &first.value
    if condition do
        pointer = &second.value
    reader.set(pointer)     // swc-expected-error {{sanity_err_borrow_escape}}
}

func readerAfterReverseBranch(condition: bool)
{
    var first:  Value
    var reader: Reader
    var second: Value
    var pointer = &second.value
    if condition do
        pointer = &first.value
    reader.set(pointer)     // swc-expected-error {{sanity_err_borrow_escape}}
}

func taskWithNestedCapture()
{
    var first: Value
    var task:  Swag.Task
    {
        var second: Value
        task.submit(func|&first, &second|() { observed = first.value + second.value })     // swc-expected-error {{sanity_err_borrow_escape}}
    }
}

struct Pointers
{
    first:  *s32
    second: *s32
}

func taskWithAggregateCapture()
{
    var first:  Value
    var task:   Swag.Task
    var second: Value
    task.submit(func|pointers = Pointers{&first.value, &second.value}|() { observed = pointers.first[] + pointers.second[] })     // swc-expected-error {{sanity_err_borrow_escape}}
}

func taskWithProjectedCapture()
{
    var first:  Value
    var task:   Swag.Task
    var second: Value
    var pointers = Pointers{&first.value, &second.value}
    task.submit(func|pointers|() { observed = pointers.first[] + pointers.second[] })     // swc-expected-error {{sanity_err_borrow_escape}}
}

// Declaring the source first makes it survive the reader's entire cleanup.
func taskAfterCapture()
{
    var value: Value
    var task:  Swag.Task
    task.submit(func|&value|() { observed = value.value })
}

func readerAfterValue()
{
    var value:  Value
    var reader: Reader
    reader.set(&value.value)
}

func readerFieldAfterValue()
{
    var value:  Value
    var reader: Reader
    reader.pointer = &value.value
}

// A trivial pointer has no cleanup that can observe a later declaration's death.
func trivialCarrierBeforeValue()->s32
{
    var pointer: *s32?
    var value:   Value
    pointer = &value.value
    return pointer[]
}

func readerBorrowsSelf()
{
    var reader: Reader
    reader.set(&reader.value)
}

func readerBorrowsParameter(value: *Value)
{
    var reader: Reader
    reader.set(&value.value)
}
