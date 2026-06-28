#include "pch.h"
#include "Support/Report/Assert.h"
#include "Backend/Linker/Win32OsPatcher.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_RT_ICON           = 3;
    constexpr uint32_t K_RT_GROUP_ICON     = 14;
    constexpr uint32_t K_RT_VERSION        = 16;
    constexpr uint32_t K_RT_MANIFEST       = 24;
    constexpr uint16_t K_RESOURCE_LANG     = 0x0409;
    constexpr uint16_t K_RESOURCE_CODEPAGE = 0x04B0;
    constexpr uint32_t K_SUBDIR_FLAG       = 0x80000000u;

    struct ResourcePayload
    {
        uint32_t               typeId = 0;
        uint32_t               nameId = 0;
        uint32_t               langId = K_RESOURCE_LANG;
        ByteArray bytes;
    };

    struct ResourceTreeNode
    {
        uint32_t                      id      = 0;
        const ResourcePayload*        payload = nullptr;
        std::vector<ResourceTreeNode> children;
    };

    struct ResourceLeafRef
    {
        const ResourcePayload* payload          = nullptr;
        uint32_t               entryValueOffset = 0;
        uint32_t               dataEntryOffset  = 0;
    };

    struct IconDirEntry
    {
        uint8_t  width       = 0;
        uint8_t  height      = 0;
        uint8_t  colorCount  = 0;
        uint8_t  reserved    = 0;
        uint16_t planes      = 0;
        uint16_t bitCount    = 0;
        uint32_t bytesInRes  = 0;
        uint32_t imageOffset = 0;
        uint16_t resourceId  = 0;
    };

    struct VersionString
    {
        std::u16string key;
        std::u16string value;
    };

    bool hasRange(const ByteArray& bytes, const size_t offset, const size_t size)
    {
        return bytes.containsRange(offset, size);
    }

    bool resourceTreeNodeLess(const ResourceTreeNode& lhs, const ResourceTreeNode& rhs)
    {
        return lhs.id < rhs.id;
    }

    bool tryReadU16(uint16_t& outValue, const ByteArray& bytes, const size_t offset)
    {
        if (!hasRange(bytes, offset, sizeof(uint16_t)))
            return false;
        outValue = bytes.readLe16(offset);
        return true;
    }

    bool tryReadU32(uint32_t& outValue, const ByteArray& bytes, const size_t offset)
    {
        if (!hasRange(bytes, offset, sizeof(uint32_t)))
            return false;
        outValue = bytes.readLe32(offset);
        return true;
    }

    void writeU16(ByteArray& bytes, const size_t offset, const uint16_t value)
    {
        bytes.writeLe16(offset, value);
    }

    void appendUtf16CodePoint(std::u16string& out, uint32_t cp)
    {
        if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF))
            cp = 0xFFFD;
        if (cp <= 0xFFFF)
        {
            out.push_back(static_cast<char16_t>(cp));
            return;
        }

        cp -= 0x10000;
        out.push_back(static_cast<char16_t>(0xD800 + (cp >> 10)));
        out.push_back(static_cast<char16_t>(0xDC00 + (cp & 0x3FF)));
    }

    std::u16string utf8ToUtf16(std::string_view text)
    {
        std::u16string out;
        out.reserve(text.size());

        for (size_t i = 0; i < text.size();)
        {
            const auto b0 = static_cast<uint8_t>(text[i]);
            if (b0 < 0x80)
            {
                appendUtf16CodePoint(out, b0);
                ++i;
                continue;
            }

            uint32_t cp    = 0xFFFD;
            size_t   count = 0;
            if ((b0 & 0xE0) == 0xC0)
            {
                cp    = b0 & 0x1F;
                count = 2;
            }
            else if ((b0 & 0xF0) == 0xE0)
            {
                cp    = b0 & 0x0F;
                count = 3;
            }
            else if ((b0 & 0xF8) == 0xF0)
            {
                cp    = b0 & 0x07;
                count = 4;
            }

            bool valid = count != 0 && i + count <= text.size();
            for (size_t j = 1; valid && j < count; ++j)
            {
                const auto bx = static_cast<uint8_t>(text[i + j]);
                if ((bx & 0xC0) != 0x80)
                {
                    valid = false;
                    break;
                }
                cp = (cp << 6) | (bx & 0x3F);
            }

            if (!valid || (count == 2 && cp < 0x80) || (count == 3 && cp < 0x800) || (count == 4 && cp < 0x10000))
            {
                appendUtf16CodePoint(out, 0xFFFD);
                ++i;
                continue;
            }

            appendUtf16CodePoint(out, cp);
            i += count;
        }

        return out;
    }

    Utf8 versionString(const LinkWin32ApplicationConfig& config)
    {
        const uint32_t major = std::min(config.version, 0xFFFFu);
        const uint32_t minor = std::min(config.revision, 0xFFFFu);
        const uint32_t build = std::min(config.buildNum, 0xFFFFu);
        return std::format("{}.{}.{}.0", major, minor, build);
    }

    uint32_t versionMs(const LinkWin32ApplicationConfig& config)
    {
        const uint32_t major = std::min(config.version, 0xFFFFu);
        const uint32_t minor = std::min(config.revision, 0xFFFFu);
        return (major << 16) | minor;
    }

    uint32_t versionLs(const LinkWin32ApplicationConfig& config)
    {
        const uint32_t build = std::min(config.buildNum, 0xFFFFu);
        return build << 16;
    }

    uint32_t beginVersionBlock(ByteArray& bytes, std::u16string_view key, const uint16_t valueLength, const uint16_t type)
    {
        const uint32_t offset = static_cast<uint32_t>(bytes.size());
        bytes.appendLe16(0);
        bytes.appendLe16(valueLength);
        bytes.appendLe16(type);
        bytes.appendUtf16LeZ(key);
        bytes.align(4);
        return offset;
    }

    void finishVersionBlock(ByteArray& bytes, const uint32_t offset)
    {
        const uint32_t length = static_cast<uint32_t>(bytes.size()) - offset;
        SWC_ASSERT(length <= 0xFFFF);
        writeU16(bytes, offset, static_cast<uint16_t>(length));
    }

    void appendVersionStringBlock(ByteArray& bytes, const VersionString& value)
    {
        const uint16_t valueLength = static_cast<uint16_t>(std::min<size_t>(value.value.size() + 1, 0xFFFF));
        const uint32_t offset      = beginVersionBlock(bytes, value.key, valueLength, 1);
        bytes.appendUtf16LeZ(value.value);
        bytes.align(4);
        finishVersionBlock(bytes, offset);
    }

    void appendVersionString(std::vector<VersionString>& strings, std::string_view key, const Utf8& value)
    {
        if (value.empty())
            return;
        strings.push_back({.key = utf8ToUtf16(key), .value = utf8ToUtf16(value.view())});
    }

    void appendVersionStringFileInfo(ByteArray& bytes, const LinkImage& image)
    {
        std::vector<VersionString> strings;
        const Utf8                 appName     = image.win32.appName.empty() ? image.moduleName : image.win32.appName;
        const Utf8                 description = image.win32.appDescription.empty() ? appName : image.win32.appDescription;
        const Utf8                 ver         = versionString(image.win32);

        appendVersionString(strings, "CompanyName", image.win32.appCompany);
        appendVersionString(strings, "FileDescription", description);
        appendVersionString(strings, "FileVersion", ver);
        appendVersionString(strings, "InternalName", appName);
        appendVersionString(strings, "LegalCopyright", image.win32.appCopyright);
        appendVersionString(strings, "OriginalFilename", image.moduleName);
        appendVersionString(strings, "ProductName", appName);
        appendVersionString(strings, "ProductVersion", ver);

        const uint32_t fileInfoOffset = beginVersionBlock(bytes, u"StringFileInfo", 0, 1);
        const uint32_t tableOffset    = beginVersionBlock(bytes, u"040904b0", 0, 1);
        for (const VersionString& str : strings)
            appendVersionStringBlock(bytes, str);
        finishVersionBlock(bytes, tableOffset);
        finishVersionBlock(bytes, fileInfoOffset);
    }

    void appendVersionVarFileInfo(ByteArray& bytes)
    {
        const uint32_t varInfoOffset = beginVersionBlock(bytes, u"VarFileInfo", 0, 1);
        const uint32_t varOffset     = beginVersionBlock(bytes, u"Translation", 4, 0);
        bytes.appendLe16(K_RESOURCE_LANG);
        bytes.appendLe16(K_RESOURCE_CODEPAGE);
        bytes.align(4);
        finishVersionBlock(bytes, varOffset);
        finishVersionBlock(bytes, varInfoOffset);
    }

    ByteArray buildVersionInfo(const LinkImage& image)
    {
        ByteArray bytes;
        const uint32_t         rootOffset = beginVersionBlock(bytes, u"VS_VERSION_INFO", 52, 0);

        bytes.appendLe32(0xFEEF04BDu);
        bytes.appendLe32(0x00010000u);
        bytes.appendLe32(versionMs(image.win32));
        bytes.appendLe32(versionLs(image.win32));
        bytes.appendLe32(versionMs(image.win32));
        bytes.appendLe32(versionLs(image.win32));
        bytes.appendLe32(0x0000003Fu);
        bytes.appendLe32(0);
        bytes.appendLe32(0x00040004u);
        bytes.appendLe32(image.kind == LinkImageKind::SharedLibrary ? 2u : 1u);
        bytes.appendLe32(0);
        bytes.appendLe32(0);
        bytes.appendLe32(0);
        bytes.align(4);

        appendVersionStringFileInfo(bytes, image);
        appendVersionVarFileInfo(bytes);
        finishVersionBlock(bytes, rootOffset);
        return bytes;
    }

    void addPayload(std::vector<ResourcePayload>& payloads, const uint32_t typeId, const uint32_t nameId, ByteArray bytes)
    {
        payloads.push_back({.typeId = typeId, .nameId = nameId, .langId = K_RESOURCE_LANG, .bytes = std::move(bytes)});
    }

    ByteArray buildManifest()
    {
        static constexpr char MANIFEST[] =
            "<?xml version='1.0' encoding='UTF-8' standalone='yes'?>\r\n"
            "<assembly xmlns='urn:schemas-microsoft-com:asm.v1' manifestVersion='1.0'>\r\n"
            "  <trustInfo xmlns=\"urn:schemas-microsoft-com:asm.v3\">\r\n"
            "    <security>\r\n"
            "      <requestedPrivileges>\r\n"
            "        <requestedExecutionLevel level='asInvoker' uiAccess='false' />\r\n"
            "      </requestedPrivileges>\r\n"
            "    </security>\r\n"
            "  </trustInfo>\r\n"
            "</assembly>\r\n";

        const auto* begin = reinterpret_cast<const std::byte*>(MANIFEST);
        return {begin, begin + sizeof(MANIFEST) - 1};
    }

    bool failInvalidIcon(Diagnostic& outDiag, const LinkWin32ApplicationConfig& config, std::string_view because)
    {
        outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_resource_invalid);
        outDiag.addArgument(Diagnostic::ARG_PATH, config.iconPath.empty() ? Utf8{"icon"} : config.iconPath);
        outDiag.addArgument(Diagnostic::ARG_BECAUSE, Utf8{because});
        return false;
    }

    bool readIconEntries(std::vector<IconDirEntry>& outEntries, Diagnostic& outDiag, const LinkWin32ApplicationConfig& config)
    {
        outEntries.clear();
        const ByteArray& bytes = config.iconBytes;

        uint16_t reserved = 0;
        uint16_t type     = 0;
        uint16_t count    = 0;
        if (!tryReadU16(reserved, bytes, 0) || !tryReadU16(type, bytes, 2) || !tryReadU16(count, bytes, 4))
            return failInvalidIcon(outDiag, config, "ICO header is truncated");
        if (reserved != 0 || type != 1)
            return failInvalidIcon(outDiag, config, "file is not a Windows icon");
        if (count == 0)
            return failInvalidIcon(outDiag, config, "icon contains no images");
        if (!hasRange(bytes, 6, static_cast<size_t>(count) * 16))
            return failInvalidIcon(outDiag, config, "ICO directory is truncated");

        outEntries.reserve(count);
        for (uint16_t index = 0; index < count; ++index)
        {
            const size_t entryOffset = 6 + static_cast<size_t>(index) * 16;
            IconDirEntry entry;
            entry.width      = std::to_integer<uint8_t>(bytes[entryOffset + 0]);
            entry.height     = std::to_integer<uint8_t>(bytes[entryOffset + 1]);
            entry.colorCount = std::to_integer<uint8_t>(bytes[entryOffset + 2]);
            entry.reserved   = std::to_integer<uint8_t>(bytes[entryOffset + 3]);
            if (!tryReadU16(entry.planes, bytes, entryOffset + 4) || !tryReadU16(entry.bitCount, bytes, entryOffset + 6) || !tryReadU32(entry.bytesInRes, bytes, entryOffset + 8) || !tryReadU32(entry.imageOffset, bytes, entryOffset + 12))
                return failInvalidIcon(outDiag, config, "ICO directory entry is truncated");
            if (entry.reserved != 0)
                return failInvalidIcon(outDiag, config, "ICO directory entry is invalid");
            if (!hasRange(bytes, entry.imageOffset, entry.bytesInRes))
                return failInvalidIcon(outDiag, config, "ICO image data is out of bounds");

            entry.resourceId = static_cast<uint16_t>(index + 1);
            outEntries.push_back(entry);
        }

        return true;
    }

    ByteArray buildGroupIcon(const std::vector<IconDirEntry>& entries)
    {
        ByteArray group;
        group.appendLe16(0);
        group.appendLe16(1);
        group.appendLe16(static_cast<uint16_t>(entries.size()));
        for (const IconDirEntry& entry : entries)
        {
            group.push_back(static_cast<std::byte>(entry.width));
            group.push_back(static_cast<std::byte>(entry.height));
            group.push_back(static_cast<std::byte>(entry.colorCount));
            group.push_back(std::byte{0});
            group.appendLe16(entry.planes);
            group.appendLe16(entry.bitCount);
            group.appendLe32(entry.bytesInRes);
            group.appendLe16(entry.resourceId);
        }

        return group;
    }

    bool appendIconPayloads(std::vector<ResourcePayload>& payloads, Diagnostic& outDiag, const LinkWin32ApplicationConfig& config)
    {
        std::vector<IconDirEntry> entries;
        if (!readIconEntries(entries, outDiag, config))
            return false;

        for (const IconDirEntry& entry : entries)
        {
            const auto* imageBegin = config.iconBytes.data() + entry.imageOffset;
            ByteArray image(imageBegin, imageBegin + entry.bytesInRes);
            addPayload(payloads, K_RT_ICON, entry.resourceId, std::move(image));
        }

        addPayload(payloads, K_RT_GROUP_ICON, 1, buildGroupIcon(entries));
        return true;
    }

    ResourceTreeNode& findOrCreateChild(std::vector<ResourceTreeNode>& children, const uint32_t id)
    {
        for (ResourceTreeNode& child : children)
            if (child.id == id)
                return child;

        ResourceTreeNode child;
        child.id = id;
        children.push_back(std::move(child));
        return children.back();
    }

    void insertPayload(ResourceTreeNode& root, const ResourcePayload& payload)
    {
        ResourceTreeNode& typeNode = findOrCreateChild(root.children, payload.typeId);
        ResourceTreeNode& nameNode = findOrCreateChild(typeNode.children, payload.nameId);
        ResourceTreeNode& langNode = findOrCreateChild(nameNode.children, payload.langId);
        langNode.payload           = &payload;
    }

    void sortTree(ResourceTreeNode& node)
    {
        std::ranges::sort(node.children, resourceTreeNodeLess);
        for (ResourceTreeNode& child : node.children)
            sortTree(child);
    }

    uint32_t appendDirectory(ByteArray& bytes, const ResourceTreeNode& node, std::vector<ResourceLeafRef>& leaves)
    {
        const uint32_t offset = static_cast<uint32_t>(bytes.size());
        bytes.appendLe32(0);
        bytes.appendLe32(0);
        bytes.appendLe16(0);
        bytes.appendLe16(0);
        bytes.appendLe16(0);
        bytes.appendLe16(static_cast<uint16_t>(node.children.size()));

        const uint32_t entriesOffset = static_cast<uint32_t>(bytes.size());
        bytes.resize(bytes.size() + node.children.size() * 8, std::byte{0});

        for (uint32_t i = 0; i < node.children.size(); ++i)
        {
            const ResourceTreeNode& child       = node.children[i];
            const uint32_t          entryOffset = entriesOffset + i * 8;
            bytes.writeLe32(entryOffset + 0, child.id);
            if (child.payload)
            {
                leaves.push_back({.payload = child.payload, .entryValueOffset = entryOffset + 4});
                continue;
            }

            const uint32_t childOffset = appendDirectory(bytes, child, leaves);
            bytes.writeLe32(entryOffset + 4, K_SUBDIR_FLAG | childOffset);
        }

        return offset;
    }

    void appendResourceDataEntries(Win32ResourceSection& outSection, std::vector<ResourceLeafRef>& leaves)
    {
        for (ResourceLeafRef& leaf : leaves)
        {
            leaf.dataEntryOffset = static_cast<uint32_t>(outSection.bytes.size());
            outSection.bytes.writeLe32(leaf.entryValueOffset, leaf.dataEntryOffset);
            outSection.bytes.appendLe32(0);
            outSection.bytes.appendLe32(static_cast<uint32_t>(leaf.payload->bytes.size()));
            outSection.bytes.appendLe32(0);
            outSection.bytes.appendLe32(0);
        }
    }

    void appendResourcePayloads(Win32ResourceSection& outSection, const std::vector<ResourceLeafRef>& leaves)
    {
        for (const ResourceLeafRef& leaf : leaves)
        {
            outSection.bytes.align(4);
            const uint32_t payloadOffset = static_cast<uint32_t>(outSection.bytes.size());
            outSection.bytes.writeLe32(leaf.dataEntryOffset, payloadOffset);
            outSection.bytes.append(leaf.payload->bytes);
            outSection.rvaPatches.push_back({.dataEntryOffset = leaf.dataEntryOffset, .payloadOffset = payloadOffset});
        }
    }

    void buildResourceTree(Win32ResourceSection& outSection, const std::vector<ResourcePayload>& payloads)
    {
        ResourceTreeNode root;
        for (const ResourcePayload& payload : payloads)
            insertPayload(root, payload);
        sortTree(root);

        std::vector<ResourceLeafRef> leaves;
        appendDirectory(outSection.bytes, root, leaves);
        appendResourceDataEntries(outSection, leaves);
        appendResourcePayloads(outSection, leaves);
    }
}

bool Win32OsPatcher::buildResourceSection(Win32ResourceSection& outSection, Diagnostic& outDiag, const LinkImage& image)
{
    outSection = {};

    std::vector<ResourcePayload> payloads;
    if (image.win32.hasIcon() && !appendIconPayloads(payloads, outDiag, image.win32))
        return false;
    if (image.win32.hasVersionInfo())
        addPayload(payloads, K_RT_VERSION, 1, buildVersionInfo(image));
    addPayload(payloads, K_RT_MANIFEST, 1, buildManifest());

    buildResourceTree(outSection, payloads);
    return true;
}

void Win32OsPatcher::patchResourceSectionRvas(ByteArray& bytes, std::span<const Win32ResourceRvaPatch> patches, const uint32_t sectionRva)
{
    for (const Win32ResourceRvaPatch& patch : patches)
        bytes.writeLe32(patch.dataEntryOffset, sectionRva + patch.payloadOffset);
}

SWC_END_NAMESPACE();
