#include "pch.h"
#include "Backend/Linker/ELFImageWriter.h"
#include "Backend/Linker/Archive.h"
#include "Backend/Linker/ObjectWriter.elf.h"
#include "Backend/Linker/ELFReader.h"
#include "Backend/Linker/LinkJob.h"
#include "Backend/RuntimeName.h"
#include "Main/FileSystem.h"
#include "Support/Os/Os.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint64_t K_PAGE = 4096;
    constexpr size_t K_NO_TARGET = SIZE_MAX;

    struct OutputSection
    {
        std::string name;
        uint32_t type = ELF::SHT_PROGBITS;
        uint32_t link = 0;
        uint32_t info = 0;
        uint64_t flags = 0;
        uint64_t align = 1;
        uint64_t entrySize = 0;
        uint64_t size = 0;
        uint64_t offset = 0;
        uint64_t address = 0;
        ByteArray bytes;
        uint32_t nameOffset = 0;
    };

    struct SymbolReference
    {
        ELF::File* file = nullptr;
        size_t index = 0;
        const ELF::Symbol& symbol() const { return file->symbols[index]; }
    };

    struct Target
    {
        std::string name;
        SymbolReference reference;
        size_t section = 0;
        uint64_t offset = 0;
        uint64_t size = 0;
        uint32_t dynamicIndex = 0;
        uint32_t nameOffset = 0;
        uint32_t staticNameOffset = 0;
        uint16_t version = 1;
        uint8_t info = 0x10, visibility = 0;
        bool absolute = false;
        bool imported = false;
        bool weak = false;
        bool copy = false;
        bool used = false;
        bool exported = false;
        size_t got = K_NO_TARGET;
        size_t plt = K_NO_TARGET;
    };

    struct InputArchive
    {
        Archive archive;
        std::set<uint32_t> extracted;
    };

    struct DynamicRelocation
    {
        uint64_t address = 0;
        uint32_t symbol = 0;
        uint32_t type = 0;
        int64_t addend = 0;
    };

    class ElfImageLink
    {
    public:
        ElfImageLink(Utf8& error, const LinkJob& job) : error_(&error), job_(&job), shared_(job.output == LinkJob::Output::SharedLibrary) {}
        bool run(ByteArray& bytes);

    private:
        bool fail(std::string_view reason)
        {
            *error_ = reason;
            return false;
        }
        bool readObject(std::span<const std::byte> bytes, const Utf8& name);
        bool loadLibrary(const fs::path& name, const fs::path& relative = {}, bool direct = true);
        bool loadScript(const fs::path& path, std::span<const std::byte> bytes, bool direct);
        fs::path findLibrary(const fs::path& name, const fs::path& relative) const;
        bool extractArchives();
        bool mergeObjects();
        bool mergeSection(ELF::File& file, ELF::Section& input);
        bool resolveTargets();
        bool prepareDynamic();
        bool layout();
        bool relocate();
        bool emit(ByteArray& bytes);
        bool buildUnwindHeader();
        bool finishDynamic();
        size_t section(std::string_view name, uint32_t type, uint64_t flags, uint64_t align = 1);
        size_t addTarget(const std::string& name, const SymbolReference& reference, bool imported);
        uint64_t address(const Target& target) const;
        uint32_t dynamicString(std::string_view name);
        void dynamicEntry(uint64_t tag, uint64_t value);
        void appendDynamicRelocation(uint64_t address, uint32_t type, const Target& target, int64_t addend = 0);
        bool addBootstrap();

        Utf8* error_;
        const LinkJob* job_;
        bool shared_;
        uint64_t base_ = 0, page_ = K_PAGE, fileEnd_ = 0;
        std::vector<fs::path> search_;
        std::set<fs::path> loaded_;
        std::vector<std::unique_ptr<ELF::File>> objects_, libraries_;
        std::vector<std::unique_ptr<InputArchive>> archives_;
        std::map<std::string, SymbolReference> definitions_, imports_;
        std::map<std::string, size_t> globals_;
        std::vector<Target> targets_;
        std::vector<OutputSection> sections_{1};
        std::vector<std::string> needed_;
        std::vector<uint32_t> neededOffsets_;
        std::map<std::pair<std::string, std::string>, uint16_t> versions_;
        std::vector<DynamicRelocation> dynamicRelocations_;
        ByteArray bootstrap_;
        size_t dynstr_ = 0, dynsym_ = 0, hash_ = 0, versym_ = 0, verneed_ = 0, rela_ = 0, got_ = 0, plt_ = 0, dynamic_ = 0, unwind_ = 0, interp_ = 0;
        size_t symtab_ = 0, strtab_ = 0, shstrtab_ = 0;
        size_t dynamicCount_ = 0, relocationCount_ = 0;
        uint32_t sonameOffset_ = 0, runpathOffset_ = 0;
        struct Segment { uint64_t begin = 0, end = 0, memoryEnd = 0; } segments_[4];
    };

    uint64_t alignTo(const uint64_t value, const uint64_t alignment)
    {
        return (value + alignment - 1) & ~(alignment - 1);
    }

    uint32_t appendString(ByteArray& bytes, const std::string_view name)
    {
        const auto offset = static_cast<uint32_t>(bytes.size());
        bytes.append(name);
        bytes.pushBack(std::byte{0});
        return offset;
    }

    size_t ElfImageLink::section(const std::string_view name, const uint32_t type, const uint64_t flags, const uint64_t align)
    {
        for (size_t index = 1; index < sections_.size(); ++index)
        {
            OutputSection& existing = sections_[index];
            if (existing.name == name && existing.type == type && existing.flags == flags)
            {
                existing.align = std::max(existing.align, align);
                return index;
            }
        }
        OutputSection out;
        out.name = name;
        out.type = type;
        out.flags = flags;
        out.align = align;
        sections_.push_back(std::move(out));
        return sections_.size() - 1;
    }

    bool ElfImageLink::readObject(const std::span<const std::byte> bytes, const Utf8& name)
    {
        auto file = std::make_unique<ELF::File>();
        file->name = name;
        if (!file->read(*error_, bytes))
            return false;
        if (file->shared)
            return fail(std::format("{}: an archive member needs a relocatable ELF object", name));
        for (size_t index = 1; index < file->symbols.size(); ++index)
        {
            const ELF::Symbol& symbol = file->symbols[index];
            if (symbol.section && symbol.type() == 10)
                return fail(std::format("{}: relocatable ELF inputs do not yet support IFUNC resolver '{}'", name, symbol.name));
            if (!symbol.binding() || !symbol.section || symbol.name.empty())
                continue;
            const SymbolReference reference{file.get(), index};
            const auto found = definitions_.find(symbol.name);
            if (found == definitions_.end())
                definitions_.emplace(symbol.name, reference);
            else
            {
                const ELF::Symbol& previous = found->second.symbol();
                const uint8_t previousStrength = previous.binding() == 2 ? 0 : previous.section == ELF::SHN_COMMON ? 1 : 2;
                const uint8_t strength = symbol.binding() == 2 ? 0 : symbol.section == ELF::SHN_COMMON ? 1 : 2;
                if (strength > previousStrength)
                    found->second = reference;
                else if (strength == previousStrength && strength == 1)
                {
                    ELF::Symbol& common = found->second.file->symbols[found->second.index];
                    common.size = std::max(common.size, symbol.size);
                    common.value = std::max(common.value, symbol.value);
                }
                else if (strength == previousStrength && strength == 2 && (symbol.binding() != 10 || previous.binding() != 10))
                    return fail(std::format("symbol '{}' is defined by both '{}' and '{}'", symbol.name, found->second.file->name, name));
            }
        }
        objects_.push_back(std::move(file));
        return true;
    }

    fs::path ElfImageLink::findLibrary(const fs::path& name, const fs::path& relative) const
    {
        std::error_code error;
        if (name.is_absolute())
            return fs::is_regular_file(name, error) ? name : fs::path{};
        std::vector<std::string> candidates;
        const std::string text = name.string();
        if (name.has_extension() || name.has_parent_path())
            candidates.push_back(text);
        else
        {
            // The runtime sonames also work on installations without development packages.
            if (text == "c" || text == "m")
                candidates.push_back("lib" + text + ".so.6");
            else if (text == "dl" || text == "pthread" || text == "rt")
                candidates.push_back("lib" + text + ".so." + (text == "dl" ? "2" : text == "rt" ? "1" : "0"));
            else if (text == "gcc_s")
                candidates.push_back("libgcc_s.so.1");
            candidates.push_back("lib" + text + ".so");
            candidates.push_back("lib" + text + ".a");
        }
        if (!relative.empty())
            for (const std::string& candidate : candidates)
                if (fs::is_regular_file(relative / candidate, error))
                    return relative / candidate;
        for (const fs::path& directory : search_)
            for (const std::string& candidate : candidates)
                if (fs::is_regular_file(directory / candidate, error))
                    return directory / candidate;
        return {};
    }

    bool ElfImageLink::loadScript(const fs::path& path, const std::span<const std::byte> bytes, const bool direct)
    {
        std::string_view text(reinterpret_cast<const char*>(bytes.data()), bytes.size());
        std::vector<std::string> tokens;
        for (size_t cursor = 0; cursor < text.size();)
        {
            if (std::isspace(static_cast<unsigned char>(text[cursor])) || text[cursor] == ',')
            {
                ++cursor;
                continue;
            }
            if (text.substr(cursor, 2) == "/*")
            {
                const size_t end = text.find("*/", cursor + 2);
                if (end == std::string_view::npos)
                    return fail(std::format("{}: linker script comment has no terminator", Utf8(path)));
                cursor = end + 2;
                continue;
            }
            if (text[cursor] == '(' || text[cursor] == ')')
            {
                tokens.emplace_back(1, text[cursor++]);
                continue;
            }
            const char quote = text[cursor] == '\'' || text[cursor] == '"' ? text[cursor++] : 0;
            const size_t start = cursor;
            while (cursor < text.size() && (quote ? text[cursor] != quote : !std::isspace(static_cast<unsigned char>(text[cursor])) && text[cursor] != '(' && text[cursor] != ')' && text[cursor] != ','))
                ++cursor;
            tokens.emplace_back(text.substr(start, cursor - start));
            if (quote && cursor < text.size())
                ++cursor;
        }
        size_t depth = 0;
        bool inputs = false, sawInput = false;
        for (const std::string& token : tokens)
        {
            if (!depth && (token == "GROUP" || token == "INPUT"))
            {
                inputs = true;
                sawInput = true;
            }
            else if (token == "(")
                ++depth;
            else if (token == ")")
            {
                if (!depth)
                    return fail(std::format("{}: linker script has an unmatched closing parenthesis", Utf8(path)));
                if (!--depth)
                    inputs = false;
            }
            else if (inputs && depth && token != "AS_NEEDED")
            {
                const std::string_view name = token.starts_with("-l:") ? std::string_view(token).substr(3) : token.starts_with("-l") ? std::string_view(token).substr(2) : std::string_view(token);
                if (!loadLibrary(fs::path(name), path.parent_path(), direct))
                    return false;
            }
        }
        return sawInput && !depth ? true : fail(std::format("{}: link input needs ELF, an indexed archive, or an INPUT/GROUP linker script", Utf8(path)));
    }

    bool ElfImageLink::loadLibrary(const fs::path& name, const fs::path& relative, const bool direct)
    {
        const fs::path found = findLibrary(name, relative);
        if (found.empty())
            return fail(std::format("cannot find Linux link library '{}'", Utf8(name)));
        std::error_code ec;
        const fs::path path = fs::weakly_canonical(found, ec);
        if (ec)
            return fail(std::format("cannot resolve Linux link library '{}': {}", Utf8(found), ec.message()));
        if (!loaded_.insert(path).second)
            return true;
        // Published archives can be large while only a few members are reachable.
        // Reuse the shared mapped reader instead of copying every member into memory.
        if (path.extension() == ".a")
        {
            auto archive = std::make_unique<InputArchive>();
            Diagnostic diagnostic;
            if (!archive->archive.loadFile(diagnostic, path))
                return fail(std::format("cannot read indexed archive '{}'", Utf8(path)));
            archive->archive.setSourcePath(path);
            archives_.push_back(std::move(archive));
            return true;
        }
        ByteArray bytes;
        FileSystem::IoErrorInfo io;
        if (FileSystem::readBinaryFile(path, bytes, io) != Result::Continue)
            return fail(std::format("cannot read '{}': {}", Utf8(path), FileSystem::describeIoFailure(io)));
        if (bytes.size() >= 8 && std::memcmp(bytes.data(), "!<arch>\n", 8) == 0)
        {
            auto archive = std::make_unique<InputArchive>();
            Diagnostic diagnostic;
            if (!archive->archive.load(diagnostic, std::move(bytes)))
                return fail(std::format("{}: cannot decode the archive symbol directory", Utf8(path)));
            archive->archive.setSourcePath(path);
            archives_.push_back(std::move(archive));
            return true;
        }
        if (bytes.size() < 4 || bytes.readLe32(0) != 0x464c457f)
            return loadScript(path, bytes.span(), direct);
        auto file = std::make_unique<ELF::File>();
        file->name = Utf8(path);
        file->owned = std::move(bytes);
        if (!file->read(*error_, file->owned.span()))
            return false;
        if (!file->shared)
            return fail(std::format("{}: a library input needs a shared object or indexed archive", Utf8(path)));
        if (file->soname.empty())
            file->soname = found.filename().string();
        const bool defaultRuntime = name == "c" || name == "m" || name == "dl";
        if (direct && !defaultRuntime && std::ranges::find(needed_, file->soname) == needed_.end())
            needed_.push_back(file->soname);
        for (size_t index = 1; index < file->symbols.size(); ++index)
        {
            const ELF::Symbol& symbol = file->symbols[index];
            if (symbol.section && symbol.binding() && !symbol.hiddenVersion && symbol.visibility != 1 && symbol.visibility != 2)
                imports_.try_emplace(symbol.name, SymbolReference{file.get(), index});
        }
        const std::vector<std::string> dependencies = file->needed;
        libraries_.push_back(std::move(file));
        for (const std::string& dependency : dependencies)
            if (!loadLibrary(fs::path(dependency), found.parent_path(), false))
                return false;
        return true;
    }

    bool ElfImageLink::addBootstrap()
    {
        LinkImage image;
        LinkSection text;
        text.name = ".text";
        text.align = 16;
        text.flags = LinkSectionFlagsE::Code | LinkSectionFlagsE::Read | LinkSectionFlagsE::Execute;
        // System V process entry: preserve the loader finalizer, recover argc/argv and
        // align the stack before entering glibc. SWC's ordinary 'main' owns its runtime.
        constexpr unsigned char code[] = {0x31,0xed,0x49,0x89,0xd1,0x5e,0x48,0x89,0xe2,0x48,0x83,0xe4,0xf0,0x50,0x54,0x45,0x31,0xc0,0x31,0xc9,0x48,0x8d,0x3d,0,0,0,0,0xff,0x15,0,0,0,0,0xf4};
        text.bytes.append(std::as_bytes(std::span(code)));
        text.relocs.push_back({.offset = 23, .kind = LinkRelocKind::Rel32, .symbolName = "main"});
        text.relocs.push_back({.offset = 29, .kind = LinkRelocKind::GotRel32, .symbolName = "__libc_start_main"});
        image.sections.push_back(std::move(text));
        image.symbols.push_back({.name = "_start"});
        Diagnostic diagnostic;
        if (!buildElfObject(bootstrap_, diagnostic, image))
            return fail("cannot build the ELF process entry object");
        return readObject(bootstrap_.span(), "<SWC process entry>");
    }

    bool ElfImageLink::extractArchives()
    {
        std::set<std::string> pending;
        size_t scanned = 0;
        // Scan each loaded member once. COMMON declarations also search archives for
        // stronger definitions, including a later entry behind a weak indexed definition.
        while (scanned < objects_.size() || !pending.empty())
        {
            while (scanned < objects_.size())
            {
                const ELF::File& file = *objects_[scanned++];
                for (const ELF::Symbol& symbol : file.symbols)
                    if (symbol.section == ELF::SHN_COMMON && symbol.binding() != 2)
                        pending.insert(symbol.name);
                for (const ELF::Relocation& relocation : file.relocations)
                {
                    const ELF::Symbol& symbol = file.symbols[relocation.symbol];
                    if (!relocation.type || !symbol.binding() || symbol.binding() == 2)
                        continue;
                    const auto definition = definitions_.find(symbol.name);
                    if (definition == definitions_.end() || definition->second.symbol().section == ELF::SHN_COMMON)
                        pending.insert(symbol.name);
                }
            }
            if (pending.empty())
                break;
            const std::string name = *pending.begin();
            pending.erase(pending.begin());
            const auto definition = definitions_.find(name);
            const bool common = definition != definitions_.end() && definition->second.symbol().section == ELF::SHN_COMMON;
            if (definition != definitions_.end() && !common)
                continue;
            bool loaded = false;
            for (const auto& archive : archives_)
            {
                const Utf8 symbolName(name);
                const std::array<uint32_t, 1> first = {archive->archive.memberOffsetForSymbol(symbolName)};
                std::vector<uint32_t> alternatives;
                std::span<const uint32_t> candidates(first);
                if (common)
                {
                    alternatives = archive->archive.memberOffsetsForSymbol(symbolName);
                    candidates = alternatives;
                }
                for (const uint32_t offset : candidates)
                {
                    if (!offset || archive->extracted.contains(offset))
                        continue;
                    Diagnostic diagnostic;
                    const auto bytes = archive->archive.memberData(diagnostic, offset);
                    if (bytes.empty())
                        return fail(std::format("cannot load archive member defining '{}' from '{}'", name, Utf8(archive->archive.sourcePath())));
                    const Utf8 memberName = std::format("{}({})", Utf8(archive->archive.sourcePath()), offset);
                    if (common)
                    {
                        ELF::File probe;
                        probe.name = memberName;
                        if (!probe.read(*error_, bytes))
                            return false;
                        const bool stronger = std::ranges::any_of(probe.symbols, [&](const ELF::Symbol& symbol) { return symbol.name == name && symbol.section && symbol.section != ELF::SHN_COMMON && symbol.binding() && symbol.binding() != 2; });
                        if (!stronger)
                            continue;
                    }
                    archive->extracted.insert(offset);
                    if (!readObject(bytes, memberName))
                        return false;
                    loaded = true;
                    break;
                }
                if (loaded)
                    break;
            }
        }
        return true;
    }

    bool ElfImageLink::mergeSection(ELF::File& file, ELF::Section& input)
    {
        const bool array = input.type >= ELF::SHT_INIT_ARRAY && input.type <= ELF::SHT_PREINIT_ARRAY;
        if (!array && input.type != ELF::SHT_PROGBITS && input.type != ELF::SHT_NOBITS && input.type != 7)
            return true;
        if (input.name == ".note.GNU-stack" || input.name == ".comment")
            return true;
        if ((input.flags & (ELF::SHF_WRITE | ELF::SHF_EXEC)) == (ELF::SHF_WRITE | ELF::SHF_EXEC))
            return fail(std::format("{}: ELF input section '{}' requests both write and execute access", file.name, input.name));
        if (input.flags & ELF::SHF_TLS)
            return fail(std::format("{}: ELF link inputs do not yet support static TLS sections", file.name));
        if (input.size > UINT32_MAX || input.align > UINT32_MAX)
            return fail(std::format("{}: ELF section exceeds the image size limit", file.name));
        const char* arrayName = input.type == ELF::SHT_INIT_ARRAY ? ".init_array" : input.type == ELF::SHT_FINI_ARRAY ? ".fini_array" : ".preinit_array";
        const uint64_t flags = array ? ELF::SHF_ALLOC | ELF::SHF_WRITE : input.flags & (ELF::SHF_ALLOC | ELF::SHF_WRITE | ELF::SHF_EXEC);
        const uint64_t alignment = array ? std::max<uint64_t>(8, input.align) : input.align;
        input.output = section(array ? std::string_view(arrayName) : std::string_view(input.name), input.type, flags, alignment);
        OutputSection& output = sections_[input.output];
        if (array)
        {
            if (input.entrySize != 8 || input.size % 8 || !(input.flags & ELF::SHF_ALLOC))
                return fail(std::format("{}: ELF constructor arrays need allocated eight-byte entries", file.name));
            if (shared_ && input.type == ELF::SHT_PREINIT_ARRAY)
                return fail(std::format("{}: shared ELF inputs do not accept preinitialization arrays", file.name));
            output.entrySize = 8;
        }
        input.contribution = alignTo(output.size, alignment);
        output.size = input.contribution + input.size;
        if (output.size > UINT32_MAX)
            return fail("ELF output section exceeds the image size limit");
        if (input.type != ELF::SHT_NOBITS)
        {
            output.bytes.resize(input.contribution);
            output.bytes.append(file.bytes.span().subspan(input.offset, input.size));
        }
        return true;
    }

    bool ElfImageLink::mergeObjects()
    {
        struct ArrayContribution
        {
            ELF::File* file;
            ELF::Section* input;
            uint32_t priority = 65535;
        };
        std::vector<ArrayContribution> arrays;
        for (const auto& file : objects_)
        {
            for (size_t index = 1; index < file->sections.size(); ++index)
            {
                ELF::Section& input = file->sections[index];
                if (input.type < ELF::SHT_INIT_ARRAY || input.type > ELF::SHT_PREINIT_ARRAY)
                {
                    if (!mergeSection(*file, input))
                        return false;
                    continue;
                }
                ArrayContribution contribution{file.get(), &input};
                const size_t suffix = input.name.rfind('.');
                if (suffix != std::string::npos && suffix > 0)
                {
                    const char* begin = input.name.data() + suffix + 1;
                    const char* end = input.name.data() + input.name.size();
                    const auto parsed = std::from_chars(begin, end, contribution.priority);
                    if (parsed.ec != std::errc{} || parsed.ptr != end || contribution.priority > 65535)
                        return fail(std::format("{}: ELF constructor priority needs an integer from 0 to 65535", file->name));
                }
                arrays.push_back(contribution);
            }
        }
        // One dynamic tag describes each array, so priority subsections must be merged
        // globally. Equal priorities retain input order; fini arrays run in reverse at exit.
        std::stable_sort(arrays.begin(), arrays.end(), [](const ArrayContribution& left, const ArrayContribution& right) { return std::tie(left.input->type, left.priority) < std::tie(right.input->type, right.priority); });
        for (const ArrayContribution& contribution : arrays)
            if (!mergeSection(*contribution.file, *contribution.input))
                return false;
        return true;
    }

    size_t ElfImageLink::addTarget(const std::string& name, const SymbolReference& reference, const bool imported)
    {
        const ELF::Symbol& symbol = reference.symbol();
        Target target;
        target.name = name;
        target.reference = reference;
        target.info = imported ? static_cast<uint8_t>((symbol.binding() == 2 ? 0x20 : 0x10) | (symbol.type() == 10 ? 2 : symbol.type())) : symbol.info;
        target.visibility = imported ? 0 : symbol.visibility;
        target.size = symbol.size;
        target.weak = symbol.binding() == 2;
        target.imported = imported;
        if (!imported && symbol.section == ELF::SHN_ABS)
        {
            target.absolute = true;
            target.offset = symbol.value;
        }
        else if (!imported && symbol.section == ELF::SHN_COMMON)
        {
            SWC_ASSERT(std::has_single_bit(std::max<uint64_t>(1, symbol.value)));
            target.section = section(".bss", ELF::SHT_NOBITS, ELF::SHF_ALLOC | ELF::SHF_WRITE, std::max<uint64_t>(1, symbol.value));
            OutputSection& bss = sections_[target.section];
            target.offset = alignTo(bss.size, std::max<uint64_t>(1, symbol.value));
            bss.size = target.offset + symbol.size;
        }
        else if (!imported && symbol.section)
        {
            const ELF::Section& contribution = reference.file->sections[symbol.section];
            target.section = contribution.output;
            target.offset = contribution.contribution + symbol.value;
        }
        targets_.push_back(std::move(target));
        return targets_.size() - 1;
    }

    bool ElfImageLink::resolveTargets()
    {
        if (!job_->elfRuntimeHook.empty())
        {
            const auto hook = definitions_.find(std::string(job_->elfRuntimeHook.view()));
            if (hook == definitions_.end())
                return fail("shared module has no runtime initialization hook");
            definitions_.emplace(std::string(K_SHARED_RUNTIME_HOOK_SYMBOL), hook->second);
        }
        for (const auto& [name, reference] : definitions_)
            globals_.emplace(name, addTarget(name, reference, false));
        for (const auto& library : libraries_)
            for (const ELF::Symbol& symbol : library->symbols)
            {
                if (symbol.section || !symbol.binding())
                    continue;
                const auto found = globals_.find(symbol.name);
                if (found != globals_.end())
                    targets_[found->second].exported = true;
            }
        for (const auto& file : objects_)
        {
            for (size_t index = 0; index < file->symbols.size(); ++index)
            {
                ELF::Symbol& symbol = file->symbols[index];
                if (symbol.binding())
                {
                    auto found = globals_.find(symbol.name);
                    if (found == globals_.end())
                    {
                        const auto imported = imports_.find(symbol.name);
                        if (imported != imports_.end())
                            found = globals_.emplace(symbol.name, addTarget(symbol.name, imported->second, true)).first;
                        else
                            found = globals_.emplace(symbol.name, addTarget(symbol.name, {file.get(), index}, true)).first;
                    }
                    symbol.target = found->second;
                }
                else
                    symbol.target = addTarget(symbol.name, {file.get(), index}, false);
            }
        }
        for (const auto& file : objects_)
            for (const ELF::Relocation& relocation : file->relocations)
            {
                if (!relocation.type)
                    continue;
                Target& target = targets_[file->symbols[relocation.symbol].target];
                target.used = true;
                if (target.imported && target.reference.symbol().type() == 6)
                    return fail(std::format("{}: imported TLS symbol '{}' needs a supported TLS relocation model", file->name, target.name));
                if (!target.imported && !target.absolute && !target.section && target.reference.symbol().section)
                    return fail(std::format("{}: symbol '{}' references a discarded metadata section", file->name, target.name));
                if (target.imported && !target.reference.file->shared && !target.weak)
                    return fail(std::format("cannot resolve ELF symbol '{}' referenced by '{}'", target.name, file->name));
                if ((relocation.type == ELF::R_PC32 || relocation.type == ELF::R_PLT32) && target.imported && target.reference.symbol().type() == 1)
                {
                    if (shared_ || target.reference.symbol().visibility == 3)
                        return fail(std::format("shared or protected imported ELF data '{}' needs a GOT-relative access", target.name));
                    if (!target.copy)
                    {
                        const ELF::Symbol& imported = target.reference.symbol();
                        uint64_t alignment = 16;
                        if (imported.section < target.reference.file->sections.size())
                        {
                            const uint64_t sectionAlign = target.reference.file->sections[imported.section].align;
                            const uint64_t valueAlign = imported.value ? imported.value & (~imported.value + 1) : sectionAlign;
                            alignment = std::max(alignment, std::min(sectionAlign, valueAlign));
                        }
                        if (alignment > UINT32_MAX || target.size > UINT32_MAX)
                            return fail(std::format("imported ELF data '{}' exceeds the image size or alignment range", target.name));
                        target.section = section(".bss", ELF::SHT_NOBITS, ELF::SHF_ALLOC | ELF::SHF_WRITE, alignment);
                        OutputSection& bss = sections_[target.section];
                        target.offset = alignTo(bss.size, alignment);
                        bss.size = target.offset + target.size;
                        if (bss.size > UINT32_MAX)
                            return fail("ELF copy relocations exceed the image size limit");
                        target.copy = true;
                    }
                }
                if (relocation.type == ELF::R_GOTPCREL || relocation.type == ELF::R_GOTPCRELX || relocation.type == ELF::R_REX_GOTPCRELX ||
                    ((relocation.type == ELF::R_PC32 || relocation.type == ELF::R_PLT32) && target.imported && !target.copy))
                {
                    if (target.got == K_NO_TARGET)
                    {
                        target.got = sections_[got_].bytes.size();
                        sections_[got_].bytes.appendLe64(0);
                    }
                    if ((relocation.type == ELF::R_PC32 || relocation.type == ELF::R_PLT32) && target.plt == K_NO_TARGET)
                    {
                        target.plt = sections_[plt_].bytes.size();
                        sections_[plt_].bytes.resize(target.plt + 16, std::byte{0x90});
                    }
                }
            }
        return true;
    }

    uint32_t ElfImageLink::dynamicString(const std::string_view name)
    {
        return appendString(sections_[dynstr_].bytes, name);
    }

    uint64_t ElfImageLink::address(const Target& target) const
    {
        return target.absolute ? target.offset : target.section ? sections_[target.section].address + target.offset : 0;
    }

    bool ElfImageLink::prepareDynamic()
    {
        dynstr_ = section(".dynstr", ELF::SHT_STRTAB, ELF::SHF_ALLOC);
        dynsym_ = section(".dynsym", ELF::SHT_DYNSYM, ELF::SHF_ALLOC, 8);
        hash_ = section(".hash", 5, ELF::SHF_ALLOC, 8);
        versym_ = section(".gnu.version", 0x6fffffff, ELF::SHF_ALLOC, 2);
        verneed_ = section(".gnu.version_r", 0x6ffffffe, ELF::SHF_ALLOC, 8);
        rela_ = section(".rela.dyn", ELF::SHT_RELA, ELF::SHF_ALLOC, 8);
        dynamic_ = section(".dynamic", ELF::SHT_DYNAMIC, ELF::SHF_ALLOC | ELF::SHF_WRITE, 8);
        unwind_ = section(".eh_frame_hdr", ELF::SHT_PROGBITS, ELF::SHF_ALLOC, 4);
        sections_[dynstr_].bytes.pushBack(std::byte{0});
        dynamicCount_ = 1;
        for (Target& target : targets_)
        {
            if ((target.info >> 4) == 0 || target.name.empty() || target.visibility == 1 || target.visibility == 2)
                continue;
            if (!target.imported && ((!target.section && !target.absolute) || (!shared_ && !target.exported)))
                continue;
            // Shared objects export their definitions. Executables only export definitions
            // needed by a DSO; private functions remain in .symtab and runtime debug metadata.
            if (target.imported)
            {
                if (!target.used)
                    continue;
                if (target.reference.file->shared)
                {
                    const std::string& provider = target.reference.file->soname;
                    if (std::ranges::find(needed_, provider) == needed_.end())
                        needed_.push_back(provider);
                    const std::string& version = target.reference.symbol().version;
                    if (!version.empty())
                    {
                        const auto [entry, inserted] = versions_.try_emplace({provider, version}, static_cast<uint16_t>(versions_.size() + 2));
                        SWC_UNUSED(inserted);
                        target.version = entry->second;
                    }
                }
            }
            target.dynamicIndex = static_cast<uint32_t>(dynamicCount_++);
            target.nameOffset = dynamicString(target.name);
        }
        if (dynamicCount_ > UINT32_MAX || versions_.size() >= 0x7ffe)
            return fail("ELF dynamic symbols exceed the supported index range");
        for (const std::string& needed : needed_)
            neededOffsets_.push_back(dynamicString(needed));
        // One Verneed record per provider, followed by its Vernaux records.
        std::map<std::string, std::vector<std::pair<std::string, uint16_t>>> providers;
        for (const auto& [key, index] : versions_)
            providers[key.first].push_back({key.second, index});
        for (auto provider = providers.begin(); provider != providers.end(); ++provider)
        {
            ByteArray& bytes = sections_[verneed_].bytes;
            bytes.appendLe16(1);
            bytes.appendLe16(static_cast<uint16_t>(provider->second.size()));
            const uint32_t fileName = dynamicString(provider->first);
            bytes.appendLe32(fileName);
            bytes.appendLe32(16);
            bytes.appendLe32(std::next(provider) == providers.end() ? 0 : static_cast<uint32_t>(16 + provider->second.size() * 16));
            for (size_t index = 0; index < provider->second.size(); ++index)
            {
                const auto& [name, version] = provider->second[index];
                bytes.appendLe32(ELF::hash(name));
                bytes.appendLe16(0);
                bytes.appendLe16(version);
                const uint32_t nameOffset = dynamicString(name);
                bytes.appendLe32(nameOffset);
                bytes.appendLe32(index + 1 == provider->second.size() ? 0 : 16);
            }
        }
        sections_[verneed_].info = static_cast<uint32_t>(providers.size());
        sections_[verneed_].link = static_cast<uint32_t>(dynstr_);
        sections_[versym_].link = static_cast<uint32_t>(dynsym_);
        sections_[versym_].entrySize = 2;
        sections_[dynsym_].link = static_cast<uint32_t>(dynstr_);
        sections_[dynsym_].info = 1;
        sections_[dynsym_].entrySize = 24;
        sections_[hash_].link = static_cast<uint32_t>(dynsym_);
        sections_[hash_].entrySize = 4;
        sections_[rela_].link = static_cast<uint32_t>(dynsym_);
        sections_[rela_].entrySize = 24;
        sections_[dynamic_].link = static_cast<uint32_t>(dynstr_);
        sections_[dynamic_].entrySize = 16;
        sections_[dynsym_].bytes.resize(dynamicCount_ * 24);
        sections_[versym_].bytes.resize(dynamicCount_ * 2);
        const uint32_t bucketCount = std::max<uint32_t>(1, static_cast<uint32_t>(dynamicCount_ / 4));
        ByteArray& hashes = sections_[hash_].bytes;
        hashes.resize(8 + (bucketCount + dynamicCount_) * 4);
        hashes.writeLe32(0, bucketCount);
        hashes.writeLe32(4, static_cast<uint32_t>(dynamicCount_));
        for (const Target& target : targets_)
        {
            if (!target.dynamicIndex)
                continue;
            const uint32_t bucket = ELF::hash(target.name) % bucketCount;
            const uint32_t previous = hashes.readLe32(8 + bucket * 4);
            hashes.writeLe32(8 + (bucketCount + target.dynamicIndex) * 4, previous);
            hashes.writeLe32(8 + bucket * 4, target.dynamicIndex);
        }
        relocationCount_ = 0;
        for (const Target& target : targets_)
        {
            if (target.got != K_NO_TARGET && ((target.imported && !target.copy) || (shared_ && !target.absolute)))
                ++relocationCount_;
            if (target.copy)
                ++relocationCount_;
        }
        size_t frameCount = 0;
        for (const auto& file : objects_)
        {
            for (const ELF::Relocation& relocation : file->relocations)
            {
                const ELF::Section& source = file->sections[relocation.section];
                if (relocation.type == ELF::R_ABS64 && source.output && (source.flags & ELF::SHF_ALLOC))
                {
                    const Target& target = targets_[file->symbols[relocation.symbol].target];
                    if (!target.absolute && (shared_ || (target.imported && !target.copy)))
                        ++relocationCount_;
                }
            }
            for (const ELF::Section& source : file->sections)
            {
                if (source.name != ".eh_frame")
                    continue;
                for (uint64_t offset = 0; offset + 4 <= source.size;)
                {
                    const uint32_t length = file->bytes.readLe32(source.offset + offset);
                    if (!length)
                        break;
                    if (length < 4 || length > source.size - offset - 4)
                        return fail(std::format("{}: unwind record extends beyond its section", file->name));
                    if (file->bytes.readLe32(source.offset + offset + 4))
                        ++frameCount;
                    offset += 4 + length;
                }
            }
        }
        sections_[rela_].bytes.resize(relocationCount_ * 24);
        sections_[unwind_].bytes.resize(12 + frameCount * 8);
        // Reserve exactly the entries emitted by finishDynamic, before assigning addresses.
        size_t entries = 15 + needed_.size();
        runpathOffset_ = dynamicString("$ORIGIN");
        if (shared_)
            sonameOffset_ = dynamicString(job_->outputPath.filename().string());
        if (!versions_.empty())
            entries += 3;
        if (shared_)
            ++entries;
        for (const auto& output : sections_)
            if (output.type == ELF::SHT_INIT_ARRAY || output.type == ELF::SHT_FINI_ARRAY || output.type == ELF::SHT_PREINIT_ARRAY)
                entries += 2;
        sections_[dynamic_].bytes.resize(entries * 16);
        return true;
    }

    bool ElfImageLink::layout()
    {
        symtab_ = section(".symtab", ELF::SHT_SYMTAB, 0, 8);
        strtab_ = section(".strtab", ELF::SHT_STRTAB, 0);
        shstrtab_ = section(".shstrtab", ELF::SHT_STRTAB, 0);
        sections_[strtab_].bytes.pushBack(std::byte{0});
        size_t staticCount = 1;
        uint32_t localCount = 1;
        for (Target& target : targets_)
        {
            if (target.name.empty() && !target.section && !target.absolute)
                continue;
            target.staticNameOffset = appendString(sections_[strtab_].bytes, target.name);
            ++staticCount;
            if (!(target.info >> 4))
                ++localCount;
        }
        sections_[symtab_].bytes.resize(staticCount * 24);
        sections_[symtab_].entrySize = 24;
        sections_[symtab_].link = static_cast<uint32_t>(strtab_);
        sections_[symtab_].info = localCount;
        sections_[shstrtab_].bytes.pushBack(std::byte{0});
        for (size_t index = 1; index < sections_.size(); ++index)
            sections_[index].nameOffset = appendString(sections_[shstrtab_].bytes, sections_[index].name);
        for (OutputSection& output : sections_)
        {
            if (output.type != ELF::SHT_NOBITS)
                output.size = output.bytes.size();
            if (output.flags & ELF::SHF_ALLOC)
                page_ = std::max(page_, output.align);
        }
        base_ = shared_ ? 0 : alignTo(0x400000, page_);
        uint64_t cursor = 64 + (shared_ ? 9 : 10) * 56;
        for (size_t group = 0; group < 4; ++group)
        {
            if (group)
                cursor = alignTo(cursor, page_);
            segments_[group].begin = group ? cursor : 0;
            for (const bool uninitialized : {false, true})
            {
                for (size_t index = 1; index < sections_.size(); ++index)
                {
                    OutputSection& output = sections_[index];
                    if (!(output.flags & ELF::SHF_ALLOC) || (output.type == ELF::SHT_NOBITS) != uninitialized)
                        continue;
                    const bool writable = (output.flags & ELF::SHF_WRITE) != 0;
                    const bool relro = output.name == ".dynamic" || output.name == ".got" || output.name.starts_with(".data.rel.ro") || output.type == ELF::SHT_INIT_ARRAY || output.type == ELF::SHT_FINI_ARRAY || output.type == ELF::SHT_PREINIT_ARRAY;
                    const size_t selected = output.flags & ELF::SHF_EXEC ? 1 : writable ? (relro ? 2 : 3) : 0;
                    if (selected != group)
                        continue;
                    cursor = alignTo(cursor, output.align);
                    output.offset = cursor;
                    output.address = base_ + cursor;
                    cursor += output.size;
                    if (!uninitialized)
                        segments_[group].end = cursor;
                }
            }
            if (group == 2)
                cursor = alignTo(cursor, page_);
            segments_[group].memoryEnd = cursor;
            segments_[group].end = std::max(segments_[group].end, segments_[group].begin);
            if (group != 3)
                segments_[group].end = cursor;
        }
        cursor = std::max(segments_[3].end, segments_[3].begin);
        for (size_t index = 1; index < sections_.size(); ++index)
        {
            OutputSection& output = sections_[index];
            if (output.flags & ELF::SHF_ALLOC)
                continue;
            cursor = alignTo(cursor, output.align);
            output.offset = cursor;
            output.address = 0;
            cursor += output.size;
        }
        fileEnd_ = alignTo(cursor, 8);
        if (fileEnd_ > UINT32_MAX || segments_[3].memoryEnd > UINT32_MAX || sections_.size() >= 0xff00)
            return fail("ELF image exceeds the supported size or section index range");
        return true;
    }

    void ElfImageLink::appendDynamicRelocation(const uint64_t location, const uint32_t type, const Target& target, const int64_t addend)
    {
        dynamicRelocations_.push_back({location, type == ELF::R_RELATIVE ? 0 : target.dynamicIndex, type, addend});
    }

    bool ElfImageLink::relocate()
    {
        for (const Target& target : targets_)
        {
            if (target.got != K_NO_TARGET)
            {
                const uint64_t location = sections_[got_].address + target.got;
                if (target.imported && !target.copy)
                    appendDynamicRelocation(location, ELF::R_GLOB_DAT, target);
                else if (shared_ && !target.absolute)
                    appendDynamicRelocation(location, ELF::R_RELATIVE, target, static_cast<int64_t>(address(target)));
                else
                    sections_[got_].bytes.writeLe64(target.got, address(target));
            }
            if (target.plt != K_NO_TARGET)
            {
                ByteArray& code = sections_[plt_].bytes;
                code[target.plt] = std::byte{0xff};
                code[target.plt + 1] = std::byte{0x25};
                const int64_t displacement = static_cast<int64_t>(sections_[got_].address + target.got) - static_cast<int64_t>(sections_[plt_].address + target.plt + 6);
                if (displacement < INT32_MIN || displacement > INT32_MAX)
                    return fail("ELF import trampoline exceeds its signed 32-bit displacement range");
                code.writeLe32(target.plt + 2, static_cast<uint32_t>(displacement));
            }
            if (target.copy)
                appendDynamicRelocation(address(target), ELF::R_COPY, target);
        }
        for (const auto& file : objects_)
        {
            for (const ELF::Relocation& relocation : file->relocations)
            {
                const ELF::Section& source = file->sections[relocation.section];
                if (!source.output || !relocation.type)
                    continue;
                OutputSection& output = sections_[source.output];
                const Target& target = targets_[file->symbols[relocation.symbol].target];
                const uint64_t offset = source.contribution + relocation.offset;
                const uint64_t location = output.address + offset;
                uint64_t value = address(target);
                const bool got = relocation.type == ELF::R_GOTPCREL || relocation.type == ELF::R_GOTPCRELX || relocation.type == ELF::R_REX_GOTPCRELX;
                const bool relative = relocation.type == ELF::R_PC32 || relocation.type == ELF::R_PLT32 || relocation.type == ELF::R_PC64 || got;
                const bool full = relocation.type == ELF::R_ABS64 || relocation.type == ELF::R_PC64;
                if (relative && !got && target.imported && !target.copy && target.plt == K_NO_TARGET)
                    return fail(std::format("{}: imported symbol '{}' needs a PLT-compatible relocation", file->name, target.name));
                if (!relative && relocation.type != ELF::R_ABS64 && relocation.type != ELF::R_32 && relocation.type != ELF::R_32S)
                    return fail(std::format("{}: ELF relocation type {} is not supported for '{}'", file->name, relocation.type, target.name));
                if (relocation.offset > source.size || (full ? 8u : 4u) > source.size - relocation.offset || output.type == ELF::SHT_NOBITS)
                    return fail(std::format("{}: relocation for '{}' extends beyond its section", file->name, target.name));
                if (got)
                    value = sections_[got_].address + target.got;
                else if (relative && target.imported && !target.copy)
                    value = sections_[plt_].address + target.plt;
                const bool allocated = (output.flags & ELF::SHF_ALLOC) != 0;
                if (shared_ && allocated && !target.absolute && (relocation.type == ELF::R_32 || relocation.type == ELF::R_32S))
                    return fail(std::format("{}: absolute 32-bit relocation for '{}' needs position-independent code", file->name, target.name));
                if (relocation.type == ELF::R_ABS64 && allocated && shared_ && !target.absolute)
                {
                    if (!(output.flags & ELF::SHF_WRITE))
                        return fail(std::format("{}: absolute relocation for '{}' needs writable relocation storage, found '{}'", file->name, target.name, output.name));
                    if (target.imported)
                        appendDynamicRelocation(location, ELF::R_ABS64, target, relocation.addend);
                    else
                        appendDynamicRelocation(location, ELF::R_RELATIVE, target, static_cast<int64_t>(value + static_cast<uint64_t>(relocation.addend)));
                    output.bytes.writeLe64(offset, 0);
                    continue;
                }
                if (target.imported && !target.copy && !relative)
                {
                    if (allocated)
                    {
                        // Executables normally reach imports through GOT loads. Absolute
                        // imported pointers in writable data are resolved by the loader too.
                        if (relocation.type != ELF::R_ABS64 || !(output.flags & ELF::SHF_WRITE))
                            return fail(std::format("{}: imported symbol '{}' needs a GOT-relative access", file->name, target.name));
                        appendDynamicRelocation(location, ELF::R_ABS64, target, relocation.addend);
                        output.bytes.writeLe64(offset, 0);
                        continue;
                    }
                    value = 0;
                }
                value += static_cast<uint64_t>(relocation.addend);
                if (relative)
                    value -= location;
                const int64_t signedValue = std::bit_cast<int64_t>(value);
                if (!full && (relative || relocation.type == ELF::R_32S) && (signedValue < INT32_MIN || signedValue > INT32_MAX))
                    return fail(std::format("{}: relocation for '{}' exceeds its signed 32-bit range", file->name, target.name));
                if (relocation.type == ELF::R_32 && value > UINT32_MAX)
                    return fail(std::format("{}: relocation for '{}' exceeds its unsigned 32-bit range", file->name, target.name));
                if (full)
                    output.bytes.writeLe64(offset, value);
                else
                    output.bytes.writeLe32(offset, static_cast<uint32_t>(value));
            }
        }
        return true;
    }

    bool ElfImageLink::buildUnwindHeader()
    {
        std::vector<std::pair<uint64_t, uint64_t>> frames;
        uint64_t frameSection = 0;
        for (const auto& file : objects_)
        {
            for (const ELF::Section& input : file->sections)
            {
                if (input.name != ".eh_frame" || !input.output)
                    continue;
                const OutputSection& output = sections_[input.output];
                frameSection = output.address;
                for (uint64_t offset = 0; offset + 4 <= input.size;)
                {
                    const uint32_t length = file->bytes.readLe32(input.offset + offset);
                    if (!length)
                        break;
                    if (file->bytes.readLe32(input.offset + offset + 4))
                    {
                        if (length < 12)
                            return fail("ELF unwind FDE has no complete code address");
                        const uint64_t start = input.contribution + offset;
                        const int32_t displacement = std::bit_cast<int32_t>(output.bytes.readLe32(start + 8));
                        const uint64_t pc = output.address + start + 8 + static_cast<uint64_t>(displacement);
                        frames.emplace_back(pc, output.address + start);
                    }
                    offset += 4 + length;
                }
            }
        }
        std::ranges::sort(frames);
        ByteArray bytes;
        bytes.pushBack(std::byte{1});
        bytes.pushBack(std::byte{0x1b}); // PC-relative signed 32-bit .eh_frame pointer.
        bytes.pushBack(std::byte{3}); // Unsigned 32-bit FDE count.
        bytes.pushBack(std::byte{0x3b}); // Header-relative signed 32-bit table entries.
        const uint64_t base = sections_[unwind_].address;
        bytes.appendLe32(static_cast<uint32_t>(frameSection ? frameSection - (base + 4) : 0));
        bytes.appendLe32(static_cast<uint32_t>(frames.size()));
        for (const auto& [pc, frame] : frames)
        {
            bytes.appendLe32(static_cast<uint32_t>(pc - base));
            bytes.appendLe32(static_cast<uint32_t>(frame - base));
        }
        SWC_ASSERT(bytes.size() == sections_[unwind_].size);
        sections_[unwind_].bytes = std::move(bytes);
        return true;
    }

    void ElfImageLink::dynamicEntry(const uint64_t tag, const uint64_t value)
    {
        sections_[dynamic_].bytes.appendLe64(tag);
        sections_[dynamic_].bytes.appendLe64(value);
    }

    bool ElfImageLink::finishDynamic()
    {
        for (const Target& target : targets_)
        {
            if (!target.dynamicIndex)
                continue;
            ByteArray& symbols = sections_[dynsym_].bytes;
            const uint64_t entry = uint64_t{target.dynamicIndex} * 24;
            symbols.writeLe32(entry, target.nameOffset);
            symbols[entry + 4] = static_cast<std::byte>(target.info);
            symbols[entry + 5] = static_cast<std::byte>(target.visibility);
            symbols.writeLe16(entry + 6, target.absolute ? ELF::SHN_ABS : static_cast<uint16_t>(target.section));
            symbols.writeLe64(entry + 8, address(target));
            symbols.writeLe64(entry + 16, target.size);
            sections_[versym_].bytes.writeLe16(uint64_t{target.dynamicIndex} * 2, target.version);
        }
        ByteArray& relocations = sections_[rela_].bytes;
        relocations.clear();
        // RELATIVE entries precede symbol lookups; stable ordering keeps emitted bytes deterministic.
        std::stable_sort(dynamicRelocations_.begin(), dynamicRelocations_.end(), [](const DynamicRelocation& left, const DynamicRelocation& right) { return (left.type == ELF::R_RELATIVE) > (right.type == ELF::R_RELATIVE); });
        for (const DynamicRelocation& relocation : dynamicRelocations_)
        {
            relocations.appendLe64(relocation.address);
            relocations.appendLe64((uint64_t{relocation.symbol} << 32) | relocation.type);
            relocations.appendLe64(std::bit_cast<uint64_t>(relocation.addend));
        }
        if (relocations.size() != sections_[rela_].size)
            return fail("ELF relocation planning disagrees with the final relocation count");
        ByteArray& dynamic = sections_[dynamic_].bytes;
        dynamic.clear();
        for (const uint32_t offset : neededOffsets_)
            dynamicEntry(1, offset); // DT_NEEDED
        if (shared_)
            dynamicEntry(14, sonameOffset_);
        dynamicEntry(5, sections_[dynstr_].address);
        dynamicEntry(10, sections_[dynstr_].size);
        dynamicEntry(6, sections_[dynsym_].address);
        dynamicEntry(11, 24);
        dynamicEntry(4, sections_[hash_].address);
        dynamicEntry(7, sections_[rela_].address);
        dynamicEntry(8, sections_[rela_].size);
        dynamicEntry(9, 24);
        dynamicEntry(3, sections_[got_].address);
        dynamicEntry(24, 0); // DT_BIND_NOW: Swag also carries arguments in R10/R11.
        dynamicEntry(30, shared_ ? 0x0a : 0x08); // DF_SYMBOLIC | DF_BIND_NOW.
        dynamicEntry(0x6ffffffb, 1); // DF_1_NOW
        dynamicEntry(shared_ ? 16 : 21, 0); // DT_SYMBOLIC or the loader's DT_DEBUG slot.
        dynamicEntry(29, runpathOffset_);
        if (!versions_.empty())
        {
            dynamicEntry(0x6ffffff0, sections_[versym_].address);
            dynamicEntry(0x6ffffffe, sections_[verneed_].address);
            dynamicEntry(0x6fffffff, sections_[verneed_].info);
        }
        for (const OutputSection& output : sections_)
        {
            const uint64_t tag = output.type == ELF::SHT_INIT_ARRAY ? 25 : output.type == ELF::SHT_FINI_ARRAY ? 26 : output.type == ELF::SHT_PREINIT_ARRAY ? 32 : 0;
            if (tag)
            {
                dynamicEntry(tag, output.address);
                dynamicEntry(tag == 25 ? 27 : tag == 26 ? 28 : 33, output.size);
            }
        }
        dynamicEntry(0, 0);
        if (dynamic.size() != sections_[dynamic_].size)
            return fail("ELF dynamic table planning disagrees with the final entry count");
        ByteArray& symbols = sections_[symtab_].bytes;
        size_t index = 1;
        for (const bool local : {true, false})
        {
            for (const Target& target : targets_)
            {
                if (((target.info >> 4) == 0) != local || (target.name.empty() && !target.section && !target.absolute))
                    continue;
                const uint64_t entry = index++ * 24;
                symbols.writeLe32(entry, target.staticNameOffset);
                symbols[entry + 4] = static_cast<std::byte>(target.info);
                symbols[entry + 5] = static_cast<std::byte>(target.visibility);
                symbols.writeLe16(entry + 6, target.absolute ? ELF::SHN_ABS : static_cast<uint16_t>(target.section));
                symbols.writeLe64(entry + 8, address(target));
                symbols.writeLe64(entry + 16, target.size);
            }
        }
        return buildUnwindHeader();
    }

    void appendProgram(ByteArray& bytes, const uint32_t type, const uint32_t flags, const uint64_t offset, const uint64_t address, const uint64_t fileSize, const uint64_t memorySize, const uint64_t align)
    {
        bytes.appendLe32(type);
        bytes.appendLe32(flags);
        bytes.appendLe64(offset);
        bytes.appendLe64(address);
        bytes.appendLe64(address);
        bytes.appendLe64(fileSize);
        bytes.appendLe64(memorySize);
        bytes.appendLe64(align);
    }

    bool ElfImageLink::emit(ByteArray& bytes)
    {
        ByteArray image(64);
        const uint16_t programCount = shared_ ? 9 : 10;
        image.writeLe32(0, 0x464c457f);
        image[4] = std::byte{2};
        image[5] = std::byte{1};
        image[6] = std::byte{1};
        image.writeLe16(16, shared_ ? 3 : 2);
        image.writeLe16(18, 62);
        image.writeLe32(20, 1);
        if (!shared_)
        {
            const auto entry = globals_.find("_start");
            if (entry == globals_.end())
                return fail("ELF executable has no process entry symbol");
            image.writeLe64(24, address(targets_[entry->second]));
        }
        image.writeLe64(32, 64);
        image.writeLe64(40, fileEnd_);
        image.writeLe16(52, 64);
        image.writeLe16(54, 56);
        image.writeLe16(56, programCount);
        image.writeLe16(58, 64);
        image.writeLe16(60, static_cast<uint16_t>(sections_.size()));
        image.writeLe16(62, static_cast<uint16_t>(shstrtab_));
        appendProgram(image, 6, 4, 64, base_ + 64, programCount * 56, programCount * 56, 8);
        if (!shared_)
            appendProgram(image, 3, 4, sections_[interp_].offset, sections_[interp_].address, sections_[interp_].size, sections_[interp_].size, 1);
        for (size_t index = 0; index < 4; ++index)
        {
            const Segment& segment = segments_[index];
            appendProgram(image, 1, index == 1 ? 5 : index ? 6 : 4, segment.begin, base_ + segment.begin, segment.end - segment.begin, segment.memoryEnd - segment.begin, page_);
        }
        const OutputSection& dynamic = sections_[dynamic_];
        appendProgram(image, 2, 6, dynamic.offset, dynamic.address, dynamic.size, dynamic.size, 8);
        const OutputSection& unwind = sections_[unwind_];
        appendProgram(image, 0x6474e550, 4, unwind.offset, unwind.address, unwind.size, unwind.size, 4);
        appendProgram(image, 0x6474e551, 6, 0, 0, 0, 0, 16);
        const Segment& relro = segments_[2];
        appendProgram(image, 0x6474e552, 4, relro.begin, base_ + relro.begin, relro.end - relro.begin, relro.memoryEnd - relro.begin, 1);
        SWC_ASSERT(image.size() == 64 + size_t{programCount} * 56);
        image.resize(fileEnd_);
        for (size_t index = 1; index < sections_.size(); ++index)
        {
            const OutputSection& output = sections_[index];
            if (output.type != ELF::SHT_NOBITS && !output.bytes.empty())
                std::memcpy(image.data() + output.offset, output.bytes.data(), output.bytes.size());
        }
        image.resize(image.size() + 64); // Mandatory null section.
        for (size_t index = 1; index < sections_.size(); ++index)
        {
            const OutputSection& output = sections_[index];
            image.appendLe32(output.nameOffset);
            image.appendLe32(output.type);
            image.appendLe64(output.flags);
            image.appendLe64(output.address);
            image.appendLe64(output.offset);
            image.appendLe64(output.size);
            image.appendLe32(output.link);
            image.appendLe32(output.info);
            image.appendLe64(output.align);
            image.appendLe64(output.entrySize);
        }
        bytes = std::move(image);
        return true;
    }

    bool ElfImageLink::run(ByteArray& bytes)
    {
        search_ = job_->elfSearchDirs;
        for (const std::string_view variable : {"LIBRARY_PATH", "LD_LIBRARY_PATH"})
        {
            const auto value = Os::readEnvironmentVariable(variable);
            if (!value)
                continue;
            std::string_view paths = value->view();
            while (!paths.empty())
            {
                const size_t separator = paths.find(':');
                const std::string_view path = paths.substr(0, separator);
                if (!path.empty())
                    search_.emplace_back(path);
                if (separator == std::string_view::npos)
                    break;
                paths.remove_prefix(separator + 1);
            }
        }
        for (const char* directory : {"/usr/local/lib", "/lib/x86_64-linux-gnu", "/usr/lib/x86_64-linux-gnu", "/lib64", "/usr/lib64", "/lib", "/usr/lib"})
            search_.emplace_back(directory);
        got_ = section(".got", ELF::SHT_PROGBITS, ELF::SHF_ALLOC | ELF::SHF_WRITE, 8);
        plt_ = section(".plt", ELF::SHT_PROGBITS, ELF::SHF_ALLOC | ELF::SHF_EXEC, 16);
        if (!shared_)
        {
            interp_ = section(".interp", ELF::SHT_PROGBITS, ELF::SHF_ALLOC);
            // The Linux x86-64 ABI uses this runtime interpreter independently of GCC.
            appendString(sections_[interp_].bytes, "/lib64/ld-linux-x86-64.so.2");
            if (!addBootstrap())
                return false;
        }
        for (const LinkArchiveMember& object : job_->archiveMembers)
            if (!readObject(object.bytes.span(), object.name))
                return false;
        for (const fs::path& library : job_->elfLibraries)
            if (!loadLibrary(library))
                return false;
        if (!extractArchives() || !mergeObjects() || !resolveTargets() || !prepareDynamic() || !layout() || !relocate() || !finishDynamic())
            return false;
        return emit(bytes);
    }
}

bool buildElfImage(ByteArray& outBytes, Utf8& outError, const LinkJob& job)
{
    outBytes.clear();
    outError.clear();
    return ElfImageLink(outError, job).run(outBytes);
}

SWC_END_NAMESPACE();
