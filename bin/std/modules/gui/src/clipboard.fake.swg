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
    fmt:  ValueFormat     // Registered clipboard format.
    crc:  u32             // Type fingerprint stored with the payload.
    data: Array'u8        // Serialized payload bytes.
}

struct FakeStore
{
    enabled: bool                    // Whether clipboard calls use this process-local store.
    hasStr:  bool                    // Whether text is available.
    str:     String                  // Stored UTF-8 text.
    hasImg:  bool                    // Whether an image is available.
    img:     Image                   // Stored image copy.
    typed:   Array'FakeTypedData     // Stored typed payloads by registered format.
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
    let enabled = g_Fake.enabled
    @drop(&g_Fake, 1)
    @init(&g_Fake, 1)
    g_Fake.enabled = enabled
}

func fakeFind(fmt: ValueFormat)->#null *FakeTypedData
{
    for [i] in g_Fake.typed.count
    {
        if g_Fake.typed[i].fmt == fmt do
            return g_Fake.typed.buffer + i
    }

    return null
}

func fakeAddTypedData(fmt: ValueFormat, type: #null typeinfo, data: const [..] u8)
{
    var entry = fakeFind(fmt)
    if !entry
    {
        g_Fake.typed.add({fmt: fmt})
        entry = g_Fake.typed.backPtr()
    }

    let e = notnull entry
    e.crc = type ? type.crc : 0
    e.data.clear()
    e.data.add(data)
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
