#global namespace Clipboard
using Core, Pixel

// In-memory fake clipboard, enabled by the headless test host (see Testing.HeadlessHost).
// The OS clipboard is a machine-global shared resource: another process can hold or
// rewrite it at any time, which makes tests flaky and clobbers the user's own clipboard.
// When enabled, every Clipboard function reads and writes this process-local store
// instead, with the same replacement semantics as the OS paths (adding an image empties
// the clipboard first; a string or a typed payload only replaces its own format).

struct FakeTypedData
{
    fmt:     ValueFormat
    crc:     u32
    data:    Array'u8
}

struct FakeStore
{
    enabled:     bool
    hasStr:      bool
    str:         String
    hasImg:      bool
    img:         Image
    typed:       Array'FakeTypedData
}

var g_Fake: FakeStore

// Redirect the whole Clipboard API to a process-local store (true) or back to the OS
// clipboard (false). The store starts empty on each switch.
public func setFake(enable: bool)
{
    g_Fake.enabled = enable
    fakeClear()
}

func fakeClear()
{
    g_Fake.hasStr = false
    g_Fake.str.clear()
    g_Fake.hasImg = false
    g_Fake.img = Image{}
    g_Fake.typed.clear()
}

func fakeFind(fmt: ValueFormat)->#null *FakeTypedData
{
    for i in g_Fake.typed.count
    {
        if g_Fake.typed[i].fmt == fmt do
            return g_Fake.typed.buffer + i
    }

    return null
}

func fakeAddTypedData(fmt: ValueFormat, type: #null typeinfo, data: #nonull const [..] u8)
{
    var entry = fakeFind(fmt)
    if !entry
    {
        g_Fake.typed.add({fmt: fmt})
        entry = g_Fake.typed.backPtr()
    }

    entry.crc = type ? type.crc : 0
    entry.data.clear()
    entry.data.add(data)
}

func fakeGetTypedData(fmt: ValueFormat, type: #null typeinfo)->Array'u8
{
    var result: retval
    let entry = fakeFind(fmt)
    if !entry or (type and entry.crc != type.crc) do
        return result

    result.add(entry.data.toSlice())
    return result
}
