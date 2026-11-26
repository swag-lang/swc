#global if #os == Swag.TargetOs.Linux

namespace __LinuxRT
{
    struct ImageInfo
    {
        path:          const [*] u8?
        base:          *void?
        symbol:        const [*] u8?
        symbolAddress: *void?
    }

    struct CpuFeature
    {
        present: [4] u32
        active:  [4] u32
    }

    #[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
    {
        func dladdr(address: const *void, info: *ImageInfo)->s32
        func malloc(size: u64)->*void?
        func free(address: *void?)
        func __x86_get_cpuid_feature_leaf(index: u32)->const *CpuFeature
    }
}

// glibc's active mask includes the operating system's enabled XSAVE/YMM state.
func __hostHasAvx2()->bool => (__LinuxRT.__x86_get_cpuid_feature_leaf(1).active[1] & (1'u32 << 5)) != 0

func __hostImageBaseForAddress(address: *void)->*void?
{
    var image: __LinuxRT.ImageInfo
    return __LinuxRT.dladdr(address, &image) != 0 ? image.base : null
}

private struct LinuxElfHeader
{
    identity:         [16] u8
    kind:             u16
    machine:          u16
    version:          u32
    entry:            u64
    programOffset:    u64
    sectionOffset:    u64
    flags:            u32
    headerSize:       u16
    programEntrySize: u16
    programCount:     u16
    sectionEntrySize: u16
    sectionCount:     u16
    sectionNames:     u16
}

private struct LinuxElfSection
{
    name:      u32
    kind:      u32
    flags:     u64
    address:   u64
    offset:    u64
    size:      u64
    link:      u32
    info:      u32
    alignment: u64
    entrySize: u64
}

private struct LinuxDebugImage
{
    next:    *LinuxDebugImage?
    base:    *void
    section: [*] u8
    size:    u64
}

private var linuxDebugImages: *LinuxDebugImage?
private var linuxDebugMutex:  MutexRW

func __hostAllocateDebugImage()->*SwagDebugImage? => cast(*SwagDebugImage?, __LinuxRT.malloc(#sizeof(SwagDebugImage)))

#[Swag.Safety(.ValueBorrow, false)]
private func __linuxFindDebugSection(mapping: *void, length: u64, size: *u64)->[*] u8?
{
    if length < #sizeof(LinuxElfHeader) do
        return null
    let header = cast(const *LinuxElfHeader, mapping)
    if header.identity[0] != 0x7F or
       header.identity[1] != 'E' or
       header.identity[2] != 'L' or
       header.identity[3] != 'F' or
       header.identity[4] != 2 or
       header.identity[5] != 1 or
       header.machine != 62 do
        return null
    if header.sectionEntrySize != #sizeof(LinuxElfSection) or
       header.sectionCount == 0 or
       header.sectionNames >= header.sectionCount do
        return null
    let tableSize = cast(u64, header.sectionCount) * #sizeof(LinuxElfSection)
    if tableSize > length or header.sectionOffset > length - tableSize do
        return null
    let bytes    = cast([*] u8, mapping)
    let sections = cast(const [*] LinuxElfSection, &bytes[header.sectionOffset])
    let names    = &sections[header.sectionNames]
    if names.size > length or names.offset > length - names.size or names.size < 9 do
        return null
    for index in header.sectionCount
    {
        let section = &sections[index]
        if section.name > names.size - 9 do
            continue
        if Swag.memcmp(&bytes[names.offset + section.name], ".swagdbg".buffer, 9) != 0 do
            continue
        if section.kind != 1 or
           section.size < 16 or
           section.size > length or
           section.offset > length - section.size do
            return null
        size[] = section.size
        return &bytes[section.offset]
    }

    return null
}

// The ELF section table need not be loaded by the dynamic linker. Read it from the actual
// owning image, and retain successful mappings so names returned by symbolization stay valid.
#[Swag.Safety(.ValueBorrow, false)]
func __hostDebugSection(base: *void, size: *u64)->[*] u8?
{
    size[] = 0
    linuxDebugMutex.lock()
    defer linuxDebugMutex.unlock()
    var known = linuxDebugImages
    while known
    {
        if known.base == base
        {
            size[] = known.size
            return known.section
        }

        known = known.next
    }

    var image: __LinuxRT.ImageInfo
    if __LinuxRT.dladdr(base, &image) == 0 or not image.path do
        return null
    let descriptor = __LinuxRT.open(image.path, __LinuxRT.CloseOnExec)
    if descriptor < 0 do
        return null
    defer discard __LinuxRT.close(descriptor)
    let fileSize = __LinuxRT.lseek(descriptor, 0, 2)
    if fileSize <= 0 do
        return null
    let length  = cast(u64, fileSize)
    let mapping = __LinuxRT.mmap(null, length, 1, 2, descriptor, 0)
    if not mapping or cast(s64, mapping) == -1 do
        return null
    var sectionSize: u64
    let section = __linuxFindDebugSection(mapping, length, &sectionSize)
    if not section
    {
        discard __LinuxRT.munmap(mapping, length)
        return null
    }

    let memory = __LinuxRT.malloc(#sizeof(LinuxDebugImage))
    if not memory
    {
        discard __LinuxRT.munmap(mapping, length)
        return null
    }

    let record = cast(*LinuxDebugImage, memory)
    record[]         = LinuxDebugImage{next: linuxDebugImages, base: base, section: section, size: sectionSize}
    linuxDebugImages = record
    size[]           = sectionSize
    return section
}

// Expand the packed table on first use. Version 1 remains a view of the image.
func __hostDecodeDebugSection(section: [*] u8, sectionSize: u64, decodedSize: *u64)->[*] u8?
{
    decodedSize[] = 0
    if sectionSize < 16 or sectionSize > 0xFFFF_FFFF or Swag.__dbgU32(section, 0) != 0x4244_5753 do
        return null

    let version = Swag.__dbgU32(section, 4)
    if version == 1
    {
        decodedSize[] = sectionSize
        return section
    }

    let packed = Swag.readCompressedDebugTable(section, sectionSize)
    if not packed.decodedSize or packed.format == 2 do
        return null
    let decoded = cast([*] u8?, __LinuxRT.malloc(packed.decodedSize))
    if not decoded do
        return null
    if not packed.decode(section, decoded)
    {
        __LinuxRT.free(decoded)
        return null
    }

    decodedSize[] = packed.decodedSize
    return decoded
}

func __hostReleaseDecodedDebugSection(section: [*] u8?)
{
    __LinuxRT.free(section)
}
