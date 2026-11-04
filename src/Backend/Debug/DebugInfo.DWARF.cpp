#include "pch.h"
#include "Backend/Debug/DebugInfo.DWARF.h"
#include "Backend/Debug/DebugPath.h"
#include "Backend/Encoder/Frame.DWARF.X64.h"
#include "Backend/Linker/Format.COFF.h"
#include "Backend/Micro/MachineCode.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Compiler/SourceFile.h"
#include "Main/CompilerInstance.h"
#include "Main/Version.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // DWARF 4 with 64-bit section offsets. Address relocations can then use the
    // same Abs64 representation as data, including cross-object debug contributions.
    enum class Tag : uint32_t
    {
        Array           = 0x01,
        Parameter       = 0x05,
        Member          = 0x0d,
        Pointer         = 0x0f,
        CompileUnit     = 0x11,
        Structure       = 0x13,
        Typedef         = 0x16,
        Subrange        = 0x21,
        BaseType        = 0x24,
        Subprogram      = 0x2e,
        Variable        = 0x34,
        UnspecifiedType = 0x3b,
    };
    enum class Attribute : uint32_t
    {
        Location             = 0x02,
        Name                 = 0x03,
        ByteSize             = 0x0b,
        StatementList        = 0x10,
        LowPc                = 0x11,
        HighPc               = 0x12,
        CompilationDirectory = 0x1b,
        LowerBound           = 0x22,
        Producer             = 0x25,
        Count                = 0x37,
        MemberLocation       = 0x38,
        DeclarationFile      = 0x3a,
        DeclarationLine      = 0x3b,
        Declaration          = 0x3c,
        Encoding             = 0x3e,
        Type                 = 0x49,
        Ranges               = 0x55,
        LinkageName          = 0x6e,
    };
    enum class Form : uint32_t
    {
        Address       = 0x01,
        Data8         = 0x07,
        String        = 0x08,
        Data1         = 0x0b,
        Unsigned      = 0x0f,
        Reference8    = 0x14,
        SectionOffset = 0x17,
        Expression    = 0x18,
        FlagPresent   = 0x19,
    };
    enum class Abbreviation : uint32_t
    {
        CompileUnit = 1,
        Function,
        Parameter,
        Variable,
        BaseType,
        Pointer,
        Structure,
        Member,
        Typedef,
        Array,
        Subrange,
        Opaque,
        Void,
    };

    void appendUnsigned(ByteArray& bytes, uint64_t value)
    {
        do
        {
            const uint8_t part = value & 0x7f;
            value >>= 7;
            bytes.pushBack(std::byte{static_cast<uint8_t>(part | (value ? 0x80 : 0))});
        } while (value);
    }

    void appendSigned(ByteArray& bytes, int64_t value)
    {
        bool more;
        do
        {
            const uint8_t part = value & 0x7f;
            value >>= 7;
            more = !((value == 0 && !(part & 0x40)) || (value == -1 && (part & 0x40)));
            bytes.pushBack(std::byte{static_cast<uint8_t>(part | (more ? 0x80 : 0))});
        } while (more);
    }

    void beginUnit(ByteArray& bytes)
    {
        bytes.appendLe32(UINT32_MAX);
        bytes.appendLe64(0);
        bytes.appendLe16(4);
    }

    void finishUnit(ByteArray& bytes)
    {
        bytes.writeLe64(4, bytes.size() - 12);
    }

    struct SourceLine
    {
        uint32_t offset = 0;
        uint32_t file   = 0;
        uint32_t line   = 0;
        uint32_t column = 0;
    };

    struct FunctionSource
    {
        const DebugInfoFunctionRecord* function = nullptr;
        std::vector<SourceLine>        lines;
        uint32_t                       bodyEnd = 0;
    };

    class DwarfObject
    {
    public:
        explicit DwarfObject(const DebugInfoObjectRequest& request) :
            request_(&request)
        {
            info_.name          = ".debug_info";
            abbreviations_.name = ".debug_abbrev";
            lines_.name         = ".debug_line";
            ranges_.name        = ".debug_ranges";
            locations_.name     = ".debug_loc";
        }

        void build(DebugInfoObjectResult& result)
        {
            collectSources();
            if (functions_.empty())
                return;
            buildAbbreviations();
            buildLines();
            buildInfo();
            for (NativeSectionData* section : {&info_, &abbreviations_, &lines_, &ranges_, &locations_})
            {
                if (section->bytes.empty())
                    continue;
                section->characteristics = PE::SCN_CNT_INITIALIZED_DATA | PE::SCN_ALIGN_1BYTES;
                result.symbols.push_back({.name = sectionSymbol(*section), .sectionName = section->name});
                result.sections.push_back(std::move(*section));
            }
        }

    private:
        Utf8 sectionSymbol(const NativeSectionData& section) const
        {
            return std::format("__swc_dwarf_{:08x}_{}{}", request_->symbolScopeHash, request_->objectIndex, section.name);
        }

        void relocate(NativeSectionData& section, const Utf8& symbol, const uint64_t addend = 0)
        {
            section.relocations.push_back({.offset = static_cast<uint32_t>(section.bytes.size()), .symbolName = symbol, .addend = addend});
            section.bytes.appendLe64(0);
        }

        void collectSources()
        {
            for (const auto& function : request_->functions)
            {
                if (!function.machineCode || function.machineCode->bytes.empty() || function.debugName.empty())
                    continue;
                FunctionSource source{.function = &function};
                for (const auto& range : function.machineCode->debugSourceRanges)
                {
                    if (!range.debugSourceInfo.isStepVisible())
                        continue;
                    MachineCode::ResolvedDebugSourceRange resolved;
                    if (!MachineCode::tryResolveDebugSourceRange(*request_->ctx, resolved, range) || !resolved.source.sourceFile || !resolved.source.codeRange.line)
                        continue;
                    const Utf8 path     = DebugPath::normalizedString(resolved.source.sourceFile->path());
                    auto [entry, added] = fileIndices_.try_emplace(path, static_cast<uint32_t>(files_.size() + 1));
                    if (added)
                        files_.push_back(path);
                    source.lines.push_back({range.codeStartOffset, entry->second, resolved.source.codeRange.line, resolved.source.codeRange.column});
                    source.bodyEnd = range.codeEndOffset;
                }
                // Compiler-only thunks have no source location and should not claim the
                // user's file or expose generated variable homes as source variables.
                if (!source.lines.empty())
                    functions_.push_back(std::move(source));
            }
        }

        void abbreviation(const Abbreviation code, const Tag tag, const bool children, const std::initializer_list<std::pair<Attribute, Form>> attributes)
        {
            auto& bytes = abbreviations_.bytes;
            appendUnsigned(bytes, static_cast<uint32_t>(code));
            appendUnsigned(bytes, static_cast<uint32_t>(tag));
            bytes.pushBack(std::byte{static_cast<uint8_t>(children)});
            for (const auto [attribute, form] : attributes)
            {
                appendUnsigned(bytes, static_cast<uint32_t>(attribute));
                appendUnsigned(bytes, static_cast<uint32_t>(form));
            }
            bytes.appendLe16(0);
        }

        void buildAbbreviations()
        {
            abbreviation(Abbreviation::CompileUnit, Tag::CompileUnit, true, {{Attribute::Producer, Form::String}, {Attribute::Name, Form::String}, {Attribute::CompilationDirectory, Form::String}, {Attribute::StatementList, Form::SectionOffset}, {Attribute::Ranges, Form::SectionOffset}});
            abbreviation(Abbreviation::Function, Tag::Subprogram, true, {{Attribute::Name, Form::String}, {Attribute::LinkageName, Form::String}, {Attribute::LowPc, Form::Address}, {Attribute::HighPc, Form::Data8}, {Attribute::DeclarationFile, Form::Unsigned}, {Attribute::DeclarationLine, Form::Unsigned}, {Attribute::Type, Form::Reference8}});
            for (const auto [code, tag] : {std::pair{Abbreviation::Parameter, Tag::Parameter}, std::pair{Abbreviation::Variable, Tag::Variable}})
                abbreviation(code, tag, false, {{Attribute::Name, Form::String}, {Attribute::Type, Form::Reference8}, {Attribute::Location, Form::SectionOffset}});
            abbreviation(Abbreviation::BaseType, Tag::BaseType, false, {{Attribute::Name, Form::String}, {Attribute::ByteSize, Form::Data8}, {Attribute::Encoding, Form::Data1}});
            abbreviation(Abbreviation::Pointer, Tag::Pointer, false, {{Attribute::ByteSize, Form::Data8}, {Attribute::Type, Form::Reference8}});
            abbreviation(Abbreviation::Structure, Tag::Structure, true, {{Attribute::Name, Form::String}, {Attribute::ByteSize, Form::Data8}});
            abbreviation(Abbreviation::Member, Tag::Member, false, {{Attribute::Name, Form::String}, {Attribute::Type, Form::Reference8}, {Attribute::MemberLocation, Form::Unsigned}});
            abbreviation(Abbreviation::Typedef, Tag::Typedef, false, {{Attribute::Name, Form::String}, {Attribute::Type, Form::Reference8}});
            abbreviation(Abbreviation::Array, Tag::Array, true, {{Attribute::Type, Form::Reference8}});
            abbreviation(Abbreviation::Subrange, Tag::Subrange, false, {{Attribute::LowerBound, Form::Unsigned}, {Attribute::Count, Form::Unsigned}});
            abbreviation(Abbreviation::Opaque, Tag::Structure, false, {{Attribute::Name, Form::String}, {Attribute::ByteSize, Form::Data8}, {Attribute::Declaration, Form::FlagPresent}});
            abbreviation(Abbreviation::Void, Tag::UnspecifiedType, false, {{Attribute::Name, Form::String}});
            abbreviations_.bytes.pushBack(std::byte{0});
        }

        void buildLines()
        {
            auto& bytes = lines_.bytes;
            beginUnit(bytes);
            bytes.appendLe64(0); // Header length, excluding this field.
            const size_t headerStart = bytes.size();
            for (const uint8_t value : {1, 1, 1, 251, 14, 13})
                bytes.pushBack(std::byte{value}); // min instruction, max ops, statement, line base/range, opcode base
            for (const uint8_t value : {0, 1, 1, 1, 1, 0, 0, 0, 1, 0, 0, 1})
                bytes.pushBack(std::byte{value});
            bytes.pushBack(std::byte{0}); // Full source paths need no directory table.
            for (const Utf8& file : files_)
            {
                bytes.appendCString(file.view());
                bytes.pushBack(std::byte{0}); // Directory index.
                bytes.pushBack(std::byte{0}); // Unknown modification time.
                bytes.pushBack(std::byte{0}); // Unknown source size.
            }
            bytes.pushBack(std::byte{0});
            bytes.writeLe64(14, bytes.size() - headerStart);
            for (const auto& source : functions_)
            {
                const auto& function = *source.function;
                bytes.pushBack(std::byte{0});
                appendUnsigned(bytes, 9);
                bytes.pushBack(std::byte{2}); // DW_LNE_set_address
                relocate(lines_, function.symbolName);
                uint32_t offset = 0;
                int64_t  line   = 1;
                uint32_t file   = 1;
                bool     first  = true;
                // Give an entry address a source location without making the prologue
                // a statement breakpoint. The first real row marks prologue completion.
                if (source.lines.front().offset)
                {
                    file = source.lines.front().file;
                    line = source.lines.front().line;
                    bytes.pushBack(std::byte{4});
                    appendUnsigned(bytes, file);
                    bytes.pushBack(std::byte{3});
                    appendSigned(bytes, line - 1);
                    bytes.pushBack(std::byte{6}); // DW_LNS_negate_stmt
                    bytes.pushBack(std::byte{1});
                    bytes.pushBack(std::byte{6});
                }
                for (const auto& row : source.lines)
                {
                    SWC_ASSERT(row.offset >= offset);
                    if (row.offset != offset)
                    {
                        bytes.pushBack(std::byte{2}); // DW_LNS_advance_pc
                        appendUnsigned(bytes, row.offset - offset);
                    }
                    if (row.file != file)
                    {
                        bytes.pushBack(std::byte{4}); // DW_LNS_set_file
                        appendUnsigned(bytes, row.file);
                    }
                    bytes.pushBack(std::byte{3}); // DW_LNS_advance_line
                    appendSigned(bytes, static_cast<int64_t>(row.line) - line);
                    bytes.pushBack(std::byte{5}); // DW_LNS_set_column
                    appendUnsigned(bytes, row.column);
                    if (first)
                        bytes.pushBack(std::byte{10}); // DW_LNS_set_prologue_end
                    bytes.pushBack(std::byte{1});      // DW_LNS_copy
                    offset = row.offset;
                    line   = row.line;
                    file   = row.file;
                    first  = false;
                }
                bytes.pushBack(std::byte{2});
                appendUnsigned(bytes, function.machineCode->bytes.size() - offset);
                bytes.pushBack(std::byte{0});
                appendUnsigned(bytes, 1);
                bytes.pushBack(std::byte{1}); // DW_LNE_end_sequence
            }
            finishUnit(bytes);
        }

        void code(const Abbreviation abbreviation)
        {
            appendUnsigned(info_.bytes, static_cast<uint32_t>(abbreviation));
        }

        void typeReference(const TypeRef type)
        {
            typePatches_.push_back({static_cast<uint32_t>(info_.bytes.size()), type});
            info_.bytes.appendLe64(0);
            if (queuedTypes_.insert(type.get()).second)
                types_.push_back(type);
        }

        void variable(const FunctionSource& source, const DebugInfoLocalRecord& variable, const Abbreviation abbreviation)
        {
            MicroReg base = variable.baseReg;
            if (base.isVirtual())
                base = source.function->machineCode->debugStackBasePhysReg;
            if (!base.isInt() || variable.typeRef.isInvalid())
                return;
            code(abbreviation);
            info_.bytes.appendCString(variable.name.view());
            typeReference(variable.typeRef);
            relocate(info_, sectionSymbol(locations_), locations_.bytes.size());
            // Homes exist only after the prologue. Exclude it from each location list
            // instead of reporting stack bytes as initialized parameter values.
            relocate(locations_, source.function->symbolName, source.lines.front().offset);
            relocate(locations_, source.function->symbolName, source.bodyEnd);
            ByteArray expression;
            expression.pushBack(std::byte{0x92}); // DW_OP_bregx
            appendUnsigned(expression, X64DwarfFrame::registerNumber(base));
            appendSigned(expression, static_cast<int32_t>(variable.offset));
            locations_.bytes.appendLe16(static_cast<uint16_t>(expression.size()));
            locations_.bytes.append(expression);
            locations_.bytes.appendLe64(0);
            locations_.bytes.appendLe64(0);
        }

        void buildInfo()
        {
            auto& bytes = info_.bytes;
            beginUnit(bytes);
            relocate(info_, sectionSymbol(abbreviations_));
            bytes.pushBack(std::byte{8});
            code(Abbreviation::CompileUnit);
            bytes.appendCString(std::format("swc {}.{}.{}", SWC_VERSION, SWC_REVISION, SWC_BUILD_NUM));
            bytes.appendCString(files_.front().view());
            bytes.appendCString(Utf8(fs::path(files_.front().c_str()).parent_path()).view());
            relocate(info_, sectionSymbol(lines_));
            relocate(info_, sectionSymbol(ranges_));
            for (const auto& source : functions_)
            {
                const auto& function = *source.function;
                relocate(ranges_, function.symbolName);
                relocate(ranges_, function.symbolName, function.machineCode->bytes.size());
                code(Abbreviation::Function);
                bytes.appendCString(function.debugName.view());
                bytes.appendCString(function.symbolName.view());
                relocate(info_, function.symbolName);
                bytes.appendLe64(function.machineCode->bytes.size());
                appendUnsigned(bytes, source.lines.front().file);
                appendUnsigned(bytes, source.lines.front().line);
                typeReference(function.returnTypeRef);
                for (const auto& parameter : function.parameters)
                    variable(source, parameter, Abbreviation::Parameter);
                for (const auto& local : function.locals)
                    variable(source, local, Abbreviation::Variable);
                bytes.pushBack(std::byte{0});
            }
            ranges_.bytes.appendLe64(0);
            ranges_.bytes.appendLe64(0);
            for (size_t index = 0; index < types_.size(); ++index)
                type(types_[index]);
            for (const auto& [offset, type] : typePatches_)
                bytes.writeLe64(offset, typeOffsets_.at(type.get()));
            bytes.pushBack(std::byte{0});
            finishUnit(bytes);
        }

        void type(const TypeRef typeRef)
        {
            auto& bytes = info_.bytes;
            typeOffsets_.emplace(typeRef.get(), bytes.size());
            if (typeRef.isInvalid())
            {
                code(Abbreviation::Void);
                bytes.appendCString("void");
                return;
            }
            TaskContext&    ctx  = *request_->ctx;
            const TypeInfo& type = ctx.typeMgr().get(typeRef);
            const Utf8      name = type.toName(ctx);
            if (type.isVoid())
            {
                code(Abbreviation::Void);
                bytes.appendCString(name.view());
            }
            else if (type.isBool() || type.isScalarNumeric())
            {
                code(Abbreviation::BaseType);
                bytes.appendCString(name.view());
                bytes.appendLe64(type.sizeOf(ctx));
                bytes.pushBack(std::byte{static_cast<uint8_t>(type.isBool() ? 2 : type.isFloat()   ? 4
                                                                              : type.isIntSigned() ? 5
                                                                                                   : 7)});
            }
            else if (type.isAlias() || type.isEnum())
            {
                code(Abbreviation::Typedef);
                bytes.appendCString(name.view());
                typeReference(type.isEnum() ? type.payloadSymEnum().underlyingTypeRef() : type.unwrap(ctx, typeRef, TypeExpandE::Alias));
            }
            else if (type.isPointerOrReference())
            {
                code(Abbreviation::Pointer);
                bytes.appendLe64(type.sizeOf(ctx));
                typeReference(type.payloadTypeRef());
            }
            else if (type.isArray())
            {
                code(Abbreviation::Array);
                typeReference(type.payloadArrayElemTypeRef());
                for (const uint64_t count : type.payloadArrayDims())
                {
                    code(Abbreviation::Subrange);
                    appendUnsigned(bytes, 0);
                    appendUnsigned(bytes, count);
                }
                bytes.pushBack(std::byte{0});
            }
            else if (type.isStruct())
            {
                code(Abbreviation::Structure);
                bytes.appendCString(name.view());
                bytes.appendLe64(type.sizeOf(ctx));
                for (const SymbolVariable* member : type.payloadSymStruct().fields())
                {
                    if (!member || member->typeRef().isInvalid() || !member->idRef().isValid())
                        continue;
                    code(Abbreviation::Member);
                    bytes.appendCString(member->name(ctx));
                    typeReference(member->typeRef());
                    appendUnsigned(bytes, member->offset());
                }
                bytes.pushBack(std::byte{0});
            }
            else
            {
                // Preserve an unsupported type's actual name and size, without inventing
                // fields or pretending an aggregate is a machine pointer.
                code(Abbreviation::Opaque);
                bytes.appendCString(name.view());
                bytes.appendLe64(type.sizeOf(ctx));
            }
        }

        const DebugInfoObjectRequest*             request_ = nullptr;
        NativeSectionData                         info_, abbreviations_, lines_, ranges_, locations_;
        std::vector<Utf8>                         files_;
        std::unordered_map<Utf8, uint32_t>        fileIndices_;
        std::vector<FunctionSource>               functions_;
        std::vector<TypeRef>                      types_;
        std::unordered_set<uint32_t>              queuedTypes_;
        std::vector<std::pair<uint32_t, TypeRef>> typePatches_;
        std::unordered_map<uint32_t, uint64_t>    typeOffsets_;
    };
}

Result DebugInfoDwarf::buildObject(DebugInfoObjectResult& outResult, const DebugInfoObjectRequest& request)
{
    outResult = {};
    NativeSectionData section;
    section.name            = ".eh_frame";
    section.characteristics = PE::SCN_CNT_INITIALIZED_DATA | PE::SCN_MEM_READ | PE::SCN_ALIGN_8BYTES;
    for (const DebugInfoFunctionRecord& function : request.functions)
    {
        if (!function.machineCode || function.machineCode->bytes.empty())
            continue;
        uint32_t addressOffset = 0;
        if (!X64DwarfFrame::appendObjectFrame(section.bytes, addressOffset, function.machineCode->unwindInfo, static_cast<uint32_t>(function.machineCode->bytes.size())))
        {
            Diagnostic diagnostic = Diagnostic::get(DiagnosticId::cmd_err_link_elf_object);
            diagnostic.addArgument(Diagnostic::ARG_BECAUSE, std::format("function '{}' has no matching DWARF frame", function.symbolName));
            diagnostic.report(*request.ctx);
            return Result::Error;
        }
        section.relocations.push_back({.offset = addressOffset, .symbolName = function.symbolName, .addend = 4, .kind = NativeRelocationKind::Rel32});
    }
    if (!section.bytes.empty())
    {
        section.bytes.appendLe32(0);
        outResult.sections.push_back(std::move(section));
    }
    if (request.emitDwarf)
        DwarfObject(request).build(outResult);
    return Result::Continue;
}

void DebugInfoDwarf::buildPdbInfo(DebugInfoPdbResult& outResult, const DebugInfoObjectRequest&)
{
    outResult = {};
}

SWC_END_NAMESPACE();
