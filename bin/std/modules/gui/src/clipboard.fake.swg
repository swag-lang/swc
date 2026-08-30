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

// The store is armed by the sandbox, not by a caller: the OS clipboard belongs to the person
// running the process, and a test or a smoke run must not be able to read or overwrite it.
#init
{
    if Env.isSandboxed() do
        g_Fake.enabled = true
}

// Reports whether clipboard calls go to the process-local store rather than to the system.
public func isFake()->bool => g_Fake.enabled

// Empties the process-local store.
//
// Fails outside a sandbox: there is no process-local store to reset there, and silently
// clearing the system clipboard instead would destroy the user's own content.
public func resetFake() fail
{
    if !g_Fake.enabled do
        fail Core.Errors.BadParameterError{"the clipboard is not faked outside a sandbox"}
    fakeClear()
}

func fakeClear()
{
    let enabled = g_Fake.enabled
    Swag.drop(&g_Fake, 1)
    Swag.init(&g_Fake, 1)
    g_Fake.enabled = enabled
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

func fakeAddTypedData(fmt: ValueFormat, type: #null typeinfo, data: const [..] u8)
{
    var entry = fakeFind(fmt)
    if !entry
    {
        g_Fake.typed.add({fmt: fmt})
        entry = g_Fake.typed.backPtr()
    }

    let e = entry!
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
