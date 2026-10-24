#include "pch.h"
#include "Backend/Micro/MachineCodeCache.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerCache.h"
#include "Main/CompilerCacheStore.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/WorkspaceLayout.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Math/Sha256.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint64_t K_MAGIC           = 0x3345444f434d5753; // SWMCODE3
    constexpr uint32_t K_CHECKSUM_OFFSET = 40;
    constexpr uint32_t K_HEADER_SIZE     = K_CHECKSUM_OFFSET + 32;
    constexpr uint32_t K_RELOCATION_SIZE = 28;
    constexpr uint32_t K_SOURCE_SIZE     = 12;
    constexpr uint32_t K_MAX_IMAGE_SIZE  = 64 * 1024 * 1024;

    void appendString(ByteArray& out, const std::string_view text)
    {
        out.appendLe32(static_cast<uint32_t>(text.size()));
        out.append(text);
    }

    void appendTypeQualifiers(ByteArray& out, TaskContext& ctx, const TypeRef typeRef, const ABITypeNormalize::Usage usage)
    {
        out.appendLe32(typeRef.isValid());
        if (typeRef.isInvalid())
            return;
        out.appendLe32(ctx.typeMgr().get(typeRef).flags().get());
        out.appendLe32(ctx.typeMgr().unwrapAliasEnumTypeOrSelf(ctx, typeRef).flags().get());
        const auto shape = ABITypeNormalize::normalize(ctx, CallConv::get(CallConvKind::Swag), ctx.typeMgr().get(typeRef), usage);
        out.pushBack(static_cast<std::byte>(shape.isVoid));
        out.pushBack(static_cast<std::byte>(shape.isFloat));
        out.pushBack(static_cast<std::byte>(shape.isSigned));
        out.pushBack(static_cast<std::byte>(shape.isIndirect));
        out.pushBack(static_cast<std::byte>(shape.needsIndirectCopy));
        out.pushBack(static_cast<std::byte>(shape.numBits));
        out.appendLe32(shape.indirectSize);
        out.appendLe32(shape.indirectAlign);
    }

    // The static sanitizer follows storage fields when proving a loaded pointer
    // non-null. Named runtime type hashes intentionally omit those layouts.
    bool appendStorageType(ByteArray& out, TaskContext& ctx, const TypeRef typeRef, const uint32_t depth = 0)
    {
        if (typeRef.isInvalid() || depth >= 128)
            return false;
        const TypeInfo& type = ctx.typeMgr().unwrapAliasEnumTypeOrSelf(ctx, typeRef);
        out.appendLe32(static_cast<uint32_t>(type.kind()));
        out.appendLe32(type.flags().get());
        out.appendLe64(type.sizeOf(ctx));
        out.appendLe32(type.alignOf(ctx));
        if (type.isStruct())
        {
            const SymbolStruct& structure = type.payloadSymStruct();
            out.appendLe32(structure.isUnion());
            out.appendLe32(static_cast<uint32_t>(structure.fields().size()));
            for (const SymbolVariable* field : structure.fields())
            {
                out.appendLe32(field->offset());
                out.appendLe32(field->hasExtraFlag(SymbolVariableFlagsE::LateInit));
                if (!appendStorageType(out, ctx, field->typeRef(), depth + 1))
                    return false;
            }
        }
        else if (type.isArray())
        {
            out.appendLe32(static_cast<uint32_t>(type.payloadArrayDims().size()));
            for (const uint64_t dimension : type.payloadArrayDims())
                out.appendLe64(dimension);
            return appendStorageType(out, ctx, type.payloadArrayElemTypeRef(), depth + 1);
        }
        return true;
    }

    bool appendFunction(ByteArray& out, TaskContext& ctx, const SymbolFunction& function)
    {
        // Expression evaluators created for '#run' have a result type but no
        // ordinary callable signature. They are not module interface functions.
        if (function.typeRef().isInvalid() || !function.isSemaCompleted() || (function.isGenericRoot() && !function.isGenericInstance()))
            return false;
        appendString(out, function.getFullScopedName(ctx).view());
        out.appendLe32(ctx.typeMgr().get(function.typeRef()).runtimeHash(ctx));
        out.appendLe32(static_cast<uint32_t>(function.callConvKind()));
        out.appendLe32(function.attributes().hasRtFlag(RtAttributeFlagsE::ReadOnly));
        // Runtime type identity deliberately ignores nullability. The static
        // sanitizer consumes it, so the emitted-code identity keeps it here.
        appendTypeQualifiers(out, ctx, function.returnTypeRef(), ABITypeNormalize::Usage::Return);
        out.appendLe32(static_cast<uint32_t>(function.parameters().size()));
        for (const SymbolVariable* parameter : function.parameters())
            appendTypeQualifiers(out, ctx, parameter->typeRef(), ABITypeNormalize::Usage::Argument);
        if (function.isForeign())
        {
            appendString(out, function.resolveForeignModuleName(ctx).view());
            appendString(out, function.resolveForeignFunctionName(ctx).view());
        }
        return true;
    }

    bool constantSource(TaskContext& ctx, DataSegmentRef& out, const MicroRelocation& target)
    {
        if (target.hasConstantSource())
        {
            out = {.shardIndex = target.constantShard, .offset = target.constantOffset};
            return out.shardIndex < ConstantStorageLayout::SHARD_COUNT;
        }
        return ctx.cstMgr().resolveConstantDataSegmentRef(out, target.constantRef, reinterpret_cast<const void*>(target.targetAddress));
    }

    // Data pointers in constants are edges, not bytes. Number allocations in traversal
    // order to preserve sharing and cycles without persisting shard offsets or addresses.
    struct InputIdentity
    {
        TaskContext*                                        ctx = nullptr;
        std::unordered_map<uint64_t, uint32_t>              allocations;
        std::unordered_map<const SymbolFunction*, uint32_t> functions;
        std::unordered_map<uint64_t, uint32_t>              sources;
        std::optional<uint64_t>                             globalBases[2];

        void appendSource(ByteArray& out, const DebugSourceInfo& source)
        {
            out.appendLe32(source.debugNoStep);
            out.appendLe32(source.isValid());
            if (!source.isValid())
                return;
            // Cached ranges are rebound by input index. Preserve source-sharing
            // topology, including the declaration fallback, rather than paths
            // or token offsets that change when an API is republished.
            const uint64_t binding = (static_cast<uint64_t>(source.sourceCodeRef.srcViewRef.get()) << 32) | source.sourceCodeRef.tokRef.get();
            const auto     entry   = sources.emplace(binding, static_cast<uint32_t>(sources.size())).first;
            out.appendLe32(entry->second);
        }

        bool appendFunctionTarget(ByteArray& out, const SymbolFunction& function)
        {
            const auto [entry, inserted] = functions.emplace(&function, static_cast<uint32_t>(functions.size()));
            out.appendLe32(entry->second);
            out.appendLe32(inserted);
            return !inserted || appendFunction(out, *ctx, function);
        }

        bool appendConstant(ByteArray& out, const DataSegmentRef source, const uint32_t depth = 0)
        {
            if (depth >= 128 || allocations.size() >= 4096 || out.size() >= K_MAX_IMAGE_SIZE)
                return false;
            const DataSegment&    segment = ctx->cstMgr().shardDataSegment(source.shardIndex);
            DataSegmentAllocation allocation;
            if (!segment.findAllocation(allocation, source.offset))
                return false;
            const uint64_t key           = (static_cast<uint64_t>(source.shardIndex) << 32) | allocation.offset;
            const auto [entry, inserted] = allocations.emplace(key, static_cast<uint32_t>(allocations.size()));
            out.appendLe32(entry->second);
            out.appendLe32(source.offset - allocation.offset);
            out.appendLe32(inserted);
            if (!inserted)
                return true;
            if (allocation.size > K_MAX_IMAGE_SIZE - std::min<size_t>(out.size(), K_MAX_IMAGE_SIZE))
                return false;

            std::vector<DataSegmentRelocation> relocations;
            segment.copyRelocations(relocations, allocation.offset, allocation.size);
            std::ranges::sort(relocations, {}, &DataSegmentRelocation::offset);
            ByteArray bytes(allocation.size);
            std::memcpy(bytes.data(), segment.ptr<std::byte>(allocation.offset), allocation.size);
            for (const auto& relocation : relocations)
            {
                if (relocation.offset - allocation.offset > allocation.size || allocation.size - (relocation.offset - allocation.offset) < sizeof(uint64_t))
                    return false;
                bytes.writeLe64(relocation.offset - allocation.offset, 0);
            }
            out.appendLe32(allocation.align);
            out.appendLe32(allocation.size);
            out.append(bytes);
            out.appendLe32(static_cast<uint32_t>(relocations.size()));
            for (const auto& relocation : relocations)
            {
                out.appendLe32(relocation.offset - allocation.offset);
                out.appendLe32(static_cast<uint32_t>(relocation.kind));
                if (relocation.kind == DataSegmentRelocationKind::FunctionSymbol)
                {
                    if (!relocation.targetSymbol)
                        return false;
                    if (!appendFunctionTarget(out, *relocation.targetSymbol))
                        return false;
                    out.appendLe32(relocation.allowUnresolvedFunction);
                }
                else
                {
                    const uint32_t shard = relocation.targetShardIndex == INVALID_REF ? source.shardIndex : relocation.targetShardIndex;
                    if (shard >= ConstantStorageLayout::SHARD_COUNT || !appendConstant(out, {.shardIndex = shard, .offset = relocation.targetOffset}, depth + 1))
                        return false;
                }
            }
            return true;
        }
    };

    void appendRegisterSets(ByteArray& out, const MicroBuilder& builder)
    {
        std::vector<std::pair<uint32_t, uint32_t>> forbidden;
        for (const auto& [reg, physical] : builder.virtualRegForbiddenPhysRegs())
            for (const MicroReg value : physical)
                forbidden.emplace_back(reg.packed, value.packed);
        std::ranges::sort(forbidden);
        out.appendLe32(static_cast<uint32_t>(forbidden.size()));
        for (const auto [reg, value] : forbidden)
        {
            out.appendLe32(reg);
            out.appendLe32(value);
        }
        for (const auto* set : {&builder.preservedVirtualCopyRegs(), &builder.immutableStorageBases(), &builder.forwardableStorageBases()})
        {
            std::vector<uint32_t> values;
            for (const MicroReg reg : *set)
                values.push_back(reg.packed);
            std::ranges::sort(values);
            out.appendLe32(static_cast<uint32_t>(values.size()));
            for (const uint32_t value : values)
                out.appendLe32(value);
        }
    }

    bool appendTarget(ByteArray& out, InputIdentity& constants, const MicroRelocation& target, const SymbolFunction& function)
    {
        out.appendLe32(static_cast<uint32_t>(target.kind));
        out.appendLe32(static_cast<uint32_t>(target.form));
        out.appendLe32(target.constantCopySize);
        out.appendLe32(target.privateGlobal);
        switch (target.kind)
        {
            case MicroRelocation::Kind::LocalFunctionAddress:
            case MicroRelocation::Kind::ForeignFunctionAddress:
                if (!target.targetSymbol || !target.targetSymbol->isFunction())
                    return false;
                if (!constants.appendFunctionTarget(out, target.targetSymbol->cast<SymbolFunction>()))
                    return false;
                out.appendLe32(target.targetSymbol == &function);
                return true;
            case MicroRelocation::Kind::ConstantAddress:
            {
                DataSegmentRef source;
                return constantSource(*constants.ctx, source, target) && constants.appendConstant(out, source);
            }
            case MicroRelocation::Kind::GlobalZeroAddress:
            case MicroRelocation::Kind::GlobalInitAddress:
            {
                // Translation within one segment preserves every alias/distance relation.
                // Publication remaps the group's base through a current input relocation.
                auto& base = constants.globalBases[target.kind == MicroRelocation::Kind::GlobalInitAddress];
                if (!base)
                    base = target.targetAddress;
                out.appendLe64(target.targetAddress - *base);
                return true;
            }
            case MicroRelocation::Kind::CompilerAddress:
                return false;
        }
        return false;
    }

    // Emission may fold an address into a memory operand. Its displacement is still
    // relative to an allocation already materialized by the current lowering.
    bool targetDelta(TaskContext& ctx, int64_t& outDelta, const MicroRelocation& input, const MicroRelocation& output)
    {
        outDelta = 0;
        if (input.kind != output.kind)
            return false;
        if (input.hasSameTarget(output))
            return true;
        if (input.kind == MicroRelocation::Kind::LocalFunctionAddress || input.kind == MicroRelocation::Kind::ForeignFunctionAddress)
            return input.targetSymbol == output.targetSymbol;
        if (input.kind == MicroRelocation::Kind::GlobalInitAddress || input.kind == MicroRelocation::Kind::GlobalZeroAddress)
        {
            outDelta = static_cast<int64_t>(output.targetAddress) - static_cast<int64_t>(input.targetAddress);
            return true;
        }
        if (input.kind != MicroRelocation::Kind::ConstantAddress)
            return false;
        DataSegmentRef left, right;
        if (!constantSource(ctx, left, input) || !constantSource(ctx, right, output) || left.shardIndex != right.shardIndex)
            return false;
        const DataSegment&    segment = ctx.cstMgr().shardDataSegment(left.shardIndex);
        DataSegmentAllocation allocation;
        if (!segment.findAllocation(allocation, left.offset) || right.offset < allocation.offset || right.offset - allocation.offset >= allocation.size)
            return false;
        outDelta = static_cast<int64_t>(right.offset) - left.offset;
        return true;
    }
}

MachineCodeCache::MachineCodeCache(TaskContext& ctx, const SymbolFunction& function, const MicroBuilder& builder)
{
    const CommandLine& command = ctx.cmdLine();
    if (!function.decl() || command.optimizerStats || command.command == CommandKind::Syntax || builder.hasPrintPassOptions() || builder.backendBuildCfg().debugInfo || ctx.compiler().buildCfg().backend.debugInfo || isEditorServiceCommand(command.command))
        return;
#if SWC_DEV_MODE
    if (command.devFull || command.validateMicro)
        return;
#endif
    const SourceFile* file = ctx.compiler().ownerSourceFile(function.srcViewRef());
    if (!file || file->hasFlag(FileFlagsE::CustomSrc) || compilerCacheIdentity().empty())
        return;

    key_ = inputKey(ctx, sources_, function, builder, compilerCacheIdentity().view());
    if (key_.empty())
        return;
    ctx_     = &ctx;
    targets_ = builder.codeRelocations();
}

Utf8 MachineCodeCache::inputKey(TaskContext& ctx, std::vector<DebugSourceInfo>& outSources, const SymbolFunction& function, const MicroBuilder& builder, const std::string_view compilerIdentity)
{
    outSources.clear();
    const CommandLine& command = ctx.cmdLine();
    ByteArray          identity;
    appendString(identity, compilerIdentity);
    builder.backendBuildCfg().appendCacheIdentity(identity);
    identity.appendLe32(ctx.compiler().buildCfg().backend.enableExceptions);
    identity.appendLe32(static_cast<uint32_t>(command.targetOs));
    identity.appendLe32(static_cast<uint32_t>(command.targetArch));
    identity.appendLe32(!command.scriptMode && Runtime::backendKindProducesNativeArtifact(ctx.compiler().buildCfg().backendKind));
    identity.appendLe32(builder.usesIntReturnRegOnRet());
    identity.appendLe32(builder.usesFloatReturnRegOnRet());
    identity.appendLe32(function.debugStackBaseReg().packed);
    identity.appendLe32(function.debugStackFrameSize());
    identity.appendLe32(function.attributes().effectiveSanityMask(ctx.compiler().buildCfg().sanityGuards));
    if (!appendFunction(identity, ctx, function))
        return {};
    MicroPassContext frameContext;
    frameContext.taskContext       = &ctx;
    frameContext.sanitizerFunction = &function;
    const auto objects             = MicroPassHelpers::frameObjects(frameContext);
    identity.appendLe32(static_cast<uint32_t>(objects.size()));
    for (const auto& object : objects)
    {
        identity.appendLe64(object.offset);
        identity.appendLe64(object.size);
        identity.appendLe32(object.alignment);
    }
    for (const SymbolVariable* parameter : function.parameters())
    {
        identity.appendLe32(parameter->debugStackSlotOffset());
        identity.appendLe32(parameter->debugStackSlotSize());
    }
    for (const auto* variables : {&function.localVariables(), &function.parameters()})
    {
        for (const SymbolVariable* variable : *variables)
        {
            if (!variable || (!variable->hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) && !variable->debugStackSlotSize()))
                continue;
            identity.appendLe32(variable->offset());
            identity.appendLe32(variable->hasExtraFlag(SymbolVariableFlagsE::LateInit));
            if (!appendStorageType(identity, ctx, variable->typeRef()))
                return {};
        }
        identity.appendLe32(INVALID_REF);
    }
    appendRegisterSets(identity, builder);

    InputIdentity                          constants{.ctx = &ctx};
    const auto&                            relocations = builder.codeRelocations();
    std::unordered_map<uint32_t, uint32_t> targetByInstruction;
    for (uint32_t index = 0; index < relocations.size(); ++index)
    {
        if (!targetByInstruction.emplace(relocations[index].instructionRef.get(), index).second)
            return {};
    }
    identity.appendLe32(static_cast<uint32_t>(relocations.size()));
    identity.appendLe32(builder.instructions().count());
    for (auto it = builder.instructions().view().begin(); it != builder.instructions().view().end(); ++it)
    {
        const MicroInstr& instruction = *it;
        if (instruction.op == MicroInstrOpcode::LoadRegPtrImm)
            return {};
        const auto target = targetByInstruction.find(it.current.get());
        identity.appendLe32(target != targetByInstruction.end() ? target->second : INVALID_REF);
        if (target != targetByInstruction.end() && !appendTarget(identity, constants, relocations[target->second], function))
            return {};
        identity.pushBack(static_cast<std::byte>(instruction.op));
        identity.pushBack(static_cast<std::byte>(instruction.numOperands));
        identity.pushBack(static_cast<std::byte>(instruction.compilerSafetyCall));
        identity.pushBack(static_cast<std::byte>(instruction.frameWriteGuard));
        const auto* operands = instruction.ops(builder.operands());
        for (uint32_t index = 0; index < instruction.numOperands; ++index)
        {
            // Relocatable pointer loads carry their process address in operand 2.
            if (instruction.op == MicroInstrOpcode::LoadRegPtrReloc && index == 2)
            {
                if (target == targetByInstruction.end())
                    return {};
                continue;
            }
            identity.appendLe64(operands[index].valueU64);
            identity.appendLe32(operands[index].valueInt.bitWidth());
            if (operands[index].valueInt.bitWidth() > 64)
                appendString(identity, operands[index].valueInt.toString().view());
        }
        const auto& source = instruction.debugSourceInfo;
        outSources.push_back(source);
        constants.appendSource(identity, source);
    }
    identity.appendLe32(function.decl() != nullptr);
    if (function.decl())
    {
        outSources.push_back({.sourceCodeRef = function.codeRef()});
        constants.appendSource(identity, outSources.back());
    }
    return Utf8Helper::toLowerHex(sha256(identity.span()));
}

bool MachineCodeCache::read(MachineCode& out) const
{
    if (key_.empty() || ctx_->cmdLine().rebuild)
        return false;
    const auto record = CompilerCacheStore::get(false).read(key_);
    if (!record || record.bytes.size() < K_HEADER_SIZE || record.bytes.readLe64(0) != K_MAGIC)
        return false;
    const ByteView& bytes    = record.bytes;
    const uint32_t  codeSize = bytes.readLe32(8), unwindSize = bytes.readLe32(12);
    const uint32_t  relocations = bytes.readLe32(24), sources = bytes.readLe32(28);
    if (K_HEADER_SIZE + static_cast<uint64_t>(codeSize) + unwindSize + static_cast<uint64_t>(relocations) * K_RELOCATION_SIZE + static_cast<uint64_t>(sources) * K_SOURCE_SIZE != bytes.size() || !codeSize)
        return false;
    std::array<uint8_t, 32> checksum;
    std::memcpy(checksum.data(), bytes.data() + K_CHECKSUM_OFFSET, checksum.size());
    // The checksum field is logically zero; the shared record stays immutable.
    const std::array<std::byte, 32> zero{};
    const auto                      keyBytes = std::as_bytes(std::span{key_.data(), key_.size()});
    if (sha256Parts({bytes.span().first(K_CHECKSUM_OFFSET), zero, bytes.span().subspan(K_HEADER_SIZE), keyBytes}) != checksum)
        return false;

    MachineCode code;
    code.debugStackBasePhysReg = MicroReg::fromPacked(bytes.readLe32(16));
    code.codeAlignment         = bytes.readLe32(20);
    code.callClobbers          = bytes.readLe64(32);
    if (!std::has_single_bit(code.codeAlignment) || code.codeAlignment > 4096)
        return false;
    size_t cursor = K_HEADER_SIZE;
    code.bytes.append(bytes.span().subspan(cursor, codeSize));
    cursor += codeSize;
    code.unwindInfo.append(bytes.span().subspan(cursor, unwindSize));
    cursor += unwindSize;
    for (uint32_t index = 0; index < relocations; ++index, cursor += K_RELOCATION_SIZE)
    {
        const uint32_t target = bytes.readLe32(cursor);
        const uint32_t form   = bytes.readLe32(cursor + 4);
        if (target >= targets_.size() || form > static_cast<uint32_t>(MicroRelocation::Form::Relative32))
            return false;
        MicroRelocation relocation   = targets_[target];
        relocation.form              = static_cast<MicroRelocation::Form>(form);
        relocation.codeOffset        = bytes.readLe32(cursor + 8);
        relocation.relativeEndOffset = bytes.readLe32(cursor + 12);
        relocation.constantCopySize  = bytes.readLe32(cursor + 16);
        const auto     delta         = static_cast<int64_t>(bytes.readLe64(cursor + 20));
        const uint32_t width         = relocation.form == MicroRelocation::Form::Relative32 ? 4 : 8;
        if (relocation.codeOffset > codeSize || codeSize - relocation.codeOffset < width || relocation.relativeEndOffset > codeSize)
            return false;
        if (delta)
        {
            if (relocation.kind == MicroRelocation::Kind::GlobalInitAddress || relocation.kind == MicroRelocation::Kind::GlobalZeroAddress)
            {
                const auto offset = static_cast<int64_t>(relocation.targetAddress) + delta;
                if (offset < 0 || offset > std::numeric_limits<uint32_t>::max())
                    return false;
                relocation.targetAddress = static_cast<uint64_t>(offset);
            }
            else
            {
                if (relocation.kind != MicroRelocation::Kind::ConstantAddress)
                    return false;
                DataSegmentRef source;
                if (!constantSource(*ctx_, source, relocation))
                    return false;
                const auto            offset  = static_cast<int64_t>(source.offset) + delta;
                const DataSegment&    segment = ctx_->cstMgr().shardDataSegment(source.shardIndex);
                DataSegmentAllocation allocation;
                if (!segment.findAllocation(allocation, source.offset) || offset < allocation.offset || offset - allocation.offset >= allocation.size)
                    return false;
                relocation.targetAddress  = reinterpret_cast<uint64_t>(segment.ptr<std::byte>(static_cast<uint32_t>(offset)));
                relocation.constantShard  = source.shardIndex;
                relocation.constantOffset = static_cast<uint32_t>(offset);
            }
        }
        relocation.instructionRef = MicroInstrRef::invalid();
        code.codeRelocations.push_back(relocation);
    }
    for (uint32_t index = 0; index < sources; ++index, cursor += K_SOURCE_SIZE)
    {
        const uint32_t start = bytes.readLe32(cursor), end = bytes.readLe32(cursor + 4), sourceFlags = bytes.readLe32(cursor + 8);
        const uint32_t source = sourceFlags & 0x7fffffff;
        if (source >= sources_.size() || start >= end || end > codeSize)
            return false;
        auto debugSourceInfo        = sources_[source];
        debugSourceInfo.debugNoStep = (sourceFlags >> 31) != 0;
        code.debugSourceRanges.push_back({.codeStartOffset = start, .codeEndOffset = end, .debugSourceInfo = debugSourceInfo});
    }
    out = std::move(code);
    return true;
}

void MachineCodeCache::write(const MachineCode& code) const
{
    if (key_.empty() || code.bytes.empty())
        return;
    ByteArray records;
    ByteArray image = code.bytes;
    for (const auto& relocation : code.codeRelocations)
    {
        int64_t  delta  = 0;
        uint32_t target = 0;
        for (; target < targets_.size(); ++target)
        {
            if (targetDelta(*ctx_, delta, targets_[target], relocation))
                break;
        }
        if (target == targets_.size())
            return;
        records.appendLe32(target);
        records.appendLe32(static_cast<uint32_t>(relocation.form));
        records.appendLe32(relocation.codeOffset);
        records.appendLe32(relocation.relativeEndOffset);
        records.appendLe32(relocation.constantCopySize);
        records.appendLe64(static_cast<uint64_t>(delta));
        if (relocation.form == MicroRelocation::Form::Relative32)
            image.writeLe32(relocation.codeOffset, 0);
        else
            image.writeLe64(relocation.codeOffset, 0);
    }
    for (const auto& range : code.debugSourceRanges)
    {
        const auto source = std::ranges::find_if(sources_, [&](const DebugSourceInfo& value) { return value.sourceCodeRef == range.debugSourceInfo.sourceCodeRef; });
        if (source == sources_.end())
            return;
        records.appendLe32(range.codeStartOffset);
        records.appendLe32(range.codeEndOffset);
        records.appendLe32(static_cast<uint32_t>(source - sources_.begin()) | (static_cast<uint32_t>(range.debugSourceInfo.debugNoStep) << 31));
    }
    ByteArray bytes;
    bytes.appendLe64(K_MAGIC);
    bytes.appendLe32(static_cast<uint32_t>(image.size()));
    bytes.appendLe32(static_cast<uint32_t>(code.unwindInfo.size()));
    bytes.appendLe32(code.debugStackBasePhysReg.packed);
    bytes.appendLe32(code.codeAlignment);
    bytes.appendLe32(static_cast<uint32_t>(code.codeRelocations.size()));
    bytes.appendLe32(static_cast<uint32_t>(code.debugSourceRanges.size()));
    bytes.appendLe64(code.callClobbers);
    bytes.resize(K_HEADER_SIZE, std::byte{0});
    bytes.append(image);
    bytes.append(code.unwindInfo);
    bytes.append(records);
    if (bytes.size() > K_MAX_IMAGE_SIZE)
        return;
    const auto checksum = sha256Parts({bytes.span(), std::as_bytes(std::span{key_.data(), key_.size()})});
    std::memcpy(bytes.data() + K_CHECKSUM_OFFSET, checksum.data(), checksum.size());
    CompilerCacheStore::get(ctx_->cmdLine().rebuild).write(key_, std::move(bytes));
}

SWC_END_NAMESPACE();
