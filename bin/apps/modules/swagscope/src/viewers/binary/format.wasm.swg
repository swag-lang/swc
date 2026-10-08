#global internal
#global namespace Viewers.Binary

using Core

// Bytes every WebAssembly module begins with.
private const WasmMagic = "\0asm"

// Returns whether the file is a WebAssembly module.
func isWasmModule(image: *BinaryImage)->bool => image.matches(0, WasmMagic)

// Returns what one section of a module holds.
func wasmSectionName(value: u8)->string
{
    switch value
    {
    case 0:  return "custom"
    case 1:  return "type"
    case 2:  return "import"
    case 3:  return "function"
    case 4:  return "table"
    case 5:  return "memory"
    case 6:  return "global"
    case 7:  return "export"
    case 8:  return "start"
    case 9:  return "element"
    case 10: return "code"
    case 11: return "data"
    case 12: return "data count"
    case 13: return "tag"
    }

    return "?"
}

// Returns what one import or export names.
func wasmKindName(value: u8)->string
{
    let texts = texts()
    switch value
    {
    case 0: return texts.wasm_Function
    case 1: return texts.wasm_Table
    case 2: return texts.wasm_Memory
    case 3: return texts.wasm_Global
    }

    return "?"
}

// Adds the sections of a module, and the names it trades with its host.
//
// A module is a chain of length-prefixed sections and nothing else, so the chain itself is the
// structure. The two sections worth decoding further are the ones that name things: what the module
// asks its host for, and what it offers back.
func reportWasmModule(image: *BinaryImage, report: *Report)
{
    image.bigEndian = false

    let texts   = texts()
    let version = image.u32At(4)

    report.beginGroup(texts.wasm_Module, WasmMagic[1 until 4], "", offset: 0, length: 8, open: true)
    report.numField(4, 4, "version", cast(u64, version))
    report.endGroup()

    var scan     = 8'u64
    var sections = 0'u64
    var imports  = 0'u64
    var exports  = 0'u64
    var complete = true

    report.beginGroup(texts.shr_Sections, "", "", offset: 8, length: image.bytes.count - 8, open: true)

    while scan < image.bytes.count and sections < ListLimit
    {
        let kind   = image.u8At(scan)
        let header = wasmLeb(image, scan + 1)
        let bodyAt = header.next
        let size   = header.value
        if not header.valid or size > image.bytes.count - bodyAt
        {
            complete = false
            break
        }

        let stored = StrConv.toDisplaySize(size)
        report.beginGroup(wasmSectionName(kind), stored, "", offset: bodyAt, length: size)
        report.numField(scan, 1, "id", cast(u64, kind), wasmSectionName(kind))
        report.sizeField(scan + 1, bodyAt - scan - 1, "size", size)

        switch kind
        {
        case 0:
            let name = wasmName(image, bodyAt)
            report.field(name.at, name.length, texts.wasm_Custom, name.text)

        case 2:
            imports = reportWasmImports(image, report, bodyAt)

        case 7:
            exports = reportWasmExports(image, report, bodyAt)
        }

        report.endGroup()
        sections += 1
        scan     = bodyAt + size
    }

    if not complete do
        report.note(texts.wasm_Malformed)
    report.listCut(sections, sections)
    report.endGroup()

    let counted = countText(sections, texts.word_Section, texts.word_Sections)
    let traded  = Format.toString("% / %", imports, exports)
    report.formatName = texts.wasm_Module
    report.summary    = Format.toString("% · % · %", texts.wasm_Module, counted, traded)
}

// Reports the import section at `at` and returns its declared entry count. Stops at the first entry
// without a module name.
private func reportWasmImports(image: *BinaryImage, report: *Report, at: u64)->u64
{
    let texts  = texts()
    let header = wasmLeb(image, at)
    if not header.valid do
        return 0

    let count = header.value
    let shown = Math.min(count, ListLimit)
    let total = countText(count, texts.word_Entry, texts.word_Entries)

    report.beginGroup(texts.shr_Imports, total, "", offset: at, length: 0, open: true)

    var scan = header.next
    for shown
    {
        let module = wasmName(image, scan)
        if not module.length do
            break
        let field = wasmName(image, module.at + module.length)
        let kind  = image.u8At(field.at + field.length)
        let label = Format.toString("%.%", module.text, field.text)
        report.field(scan, field.at + field.length - scan + 1, label, "", wasmKindName(kind))
        scan = wasmSkipDescriptor(image, field.at + field.length + 1, kind)
    }

    report.listCut(shown, count)
    report.endGroup()
    return count
}

// Reports the export section at `at`, each name with its kind and index, and returns its declared
// entry count.
private func reportWasmExports(image: *BinaryImage, report: *Report, at: u64)->u64
{
    let texts  = texts()
    let header = wasmLeb(image, at)
    if not header.valid do
        return 0

    let count = header.value
    let shown = Math.min(count, ListLimit)
    let total = countText(count, texts.word_Entry, texts.word_Entries)

    report.beginGroup(texts.shr_Exports, total, "", offset: at, length: 0, open: true)

    var scan = header.next
    for shown
    {
        let name = wasmName(image, scan)
        if not name.length do
            break
        let kind  = image.u8At(name.at + name.length)
        let index = wasmLeb(image, name.at + name.length + 1)
        let value = Format.toString("%", index.value)
        report.field(scan, index.next - scan, name.text, value, wasmKindName(kind))
        scan = index.next
    }

    report.listCut(shown, count)
    report.endGroup()
    return count
}

// Skips the description that follows an import, which differs with what is being imported.
private func wasmSkipDescriptor(image: *BinaryImage, at: u64, kind: u8)->u64
{
    switch kind
    {
    case 0: return wasmLeb(image, at).next
    case 1: return wasmSkipLimits(image, at + 1)
    case 2: return wasmSkipLimits(image, at)
    case 3: return at + 2
    }

    return at
}

// Skips a limits pair, whose upper bound is only present when its flag says so.
private func wasmSkipLimits(image: *BinaryImage, at: u64)->u64
{
    let flags   = image.u8At(at)
    let minimum = wasmLeb(image, at + 1)
    if not (flags & 1) do
        return minimum.next
    return wasmLeb(image, minimum.next).next
}

// One length-prefixed name, and where the bytes after it begin.
private struct WasmName
{
    text:   String
    at:     u64
    length: u64
}

// Reads the length-prefixed name at `at`.
private func wasmName(image: *BinaryImage, at: u64)->WasmName
{
    var result: retval
    let header = wasmLeb(image, at)
    if not header.valid or header.value > 4096
    {
        result.at = at
        return result
    }

    result.at     = header.next
    result.length = header.value
    result.text   = image.fixedTextAt(header.next, header.value)
    return result
}

// One unsigned little-endian base-128 number, and where the bytes after it begin.
private struct WasmNumber
{
    value: u64
    next:  u64
    valid: bool
}

// Reads the variable-length number at `at`, the only way a module writes a count or a size.
private func wasmLeb(image: *BinaryImage, at: u64)->WasmNumber
{
    var result: retval
    result.next = at

    var shift = 0'u64
    for 10
    {
        if not image.has(result.next, 1) do
            return result

        let value = image.u8At(result.next)
        result.next  += 1
        result.value |= cast(u64, value & 0x7F) << shift
        if not (value & 0x80)
        {
            result.valid = true
            return result
        }

        shift += 7
    }

    return result
}
