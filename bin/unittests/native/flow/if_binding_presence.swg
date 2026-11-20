#global private

struct BindingJob
{
    ready: bool
}

#test
{
    var branches = 0
    if let count = 0 where count == 0 do
        branches += 1
    if var enabled = false where not enabled do
        branches += 2
    if const paused = false where not paused do
        branches += 4

    let job = BindingJob{ready: true}
    if not job.ready do
        branches += 100
    elif let candidate = job where candidate.ready do
        branches += 8

    Swag.require(branches == 15)
}

#[Swag.NoInline]
func bindingText(initializations: *s32, present: bool)->string?
{
    initializations[] += 1
    return present ? "" : null
}

#[Swag.NoInline]
func bindingGuard(evaluations: *s32, passed: bool)->bool
{
    evaluations[] += 1
    return passed
}

#test
{
    var initializations = 0
    var guards          = 0
    if let text = bindingText(&initializations, true) where bindingGuard(&guards, true) do
        Swag.require(text.count == 0)
    else do
        Swag.require(false)

    if let text = bindingText(&initializations, false) where bindingGuard(&guards, true) do
        Swag.require(false)
    else do
        Swag.require(text == null)

    if var text = bindingText(&initializations, false) where bindingGuard(&guards, true) do
        Swag.require(false)
    else do
        Swag.require(text == null)

    if var text = bindingText(&initializations, true) where bindingGuard(&guards, false) do
        Swag.require(false)
    else do
        Swag.require(text != null and text.count == 0)

    if const text: string? = null where bindingGuard(&guards, true) do
        Swag.require(false)
    else do
        Swag.require(text == null)

    if const text: string? = "" where bindingGuard(&guards, true) do
        Swag.require(text.count == 0)
    else do
        Swag.require(false)

    if const text: string? = "text" where bindingGuard(&guards, text[0] == 't') do
        Swag.require(text.count == 4)
    else do
        Swag.require(false)

    Swag.require(initializations == 4 and guards == 4)
}

alias MaybeBoundCount = *s32?

func bindingNumber(value: *s32)->MaybeBoundCount => value
func bindingEmptySlice(storage: [*] s32)->[..] s32? => Swag.makeSlice(storage, 0)

#test
{
    var count = 0
    if let pointer = bindingNumber(&count) where pointer[] == 0 do
        pointer[] = 7
    else do
        Swag.require(false)
    Swag.require(count == 7)

    var storage: [1] s32
    if let slice = bindingEmptySlice(&storage[0]) do
        Swag.require(slice.count == 0)
    else do
        Swag.require(false)
}

#test
{
    let number: const any = 0's32
    let other:  const any = "text"
    var guards = 0

    if number is s32 as value where bindingGuard(&guards, value[] == 0) do
        Swag.require(value[] == 0)
    else do
        Swag.require(false)

    if other is s32 as value where bindingGuard(&guards, value[] == 0) do
        Swag.require(false)

    Swag.require(guards == 1)
}
