#include "pch.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Backend/Runtime.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    ConstantValue makeMaterializedConstantValue(Sema& sema, TypeRef typeRef, ByteSpan storedBytes)
    {
        TaskContext&    ctx            = sema.ctx();
        const TypeInfo& originalType   = ctx.typeMgr().get(typeRef);
        TypeRef         storageTypeRef = originalType.unwrap(ctx, typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        if (storageTypeRef.isInvalid())
            storageTypeRef = typeRef;

        const TypeInfo& storageType = ctx.typeMgr().get(storageTypeRef);
        ConstantValue   result;

        if (storageType.isStruct() || storageType.isAny() || storageType.isInterface())
            result = ConstantValue::makeStructBorrowed(ctx, storageTypeRef, storedBytes);
        else if (storageType.isArray())
            result = ConstantValue::makeArrayBorrowed(ctx, storageTypeRef, storedBytes);
        else
            result = ConstantValue::make(ctx, storedBytes.data(), storageTypeRef, ConstantValue::PayloadOwnership::Borrowed);

        if (!result.isValid())
            return result;

        if (originalType.isEnum())
        {
            const ConstantRef storageRef = sema.cstMgr().addConstant(ctx, result);
            return ConstantValue::makeEnumValue(ctx, storageRef, typeRef);
        }

        result.setTypeRef(typeRef);
        return result;
    }

    bool mergeRequiredShardIndex(uint32_t& outShardIndex, bool& hasRequiredShard, uint32_t candidateShardIndex)
    {
        if (!hasRequiredShard)
        {
            outShardIndex    = candidateShardIndex;
            hasRequiredShard = true;
            return true;
        }

        return outShardIndex == candidateShardIndex;
    }

    bool requirePointerShardIndex(uint32_t& outShardIndex, bool& hasRequiredShard, Sema& sema, const void* ptr)
    {
        if (!ptr)
            return true;

        uint32_t  shardIndex = 0;
        const Ref targetRef  = sema.cstMgr().findDataSegmentRef(shardIndex, ptr);
        if (targetRef == INVALID_REF)
            return false;

        return mergeRequiredShardIndex(outShardIndex, hasRequiredShard, shardIndex);
    }

    bool resolveStaticPayloadRequiredShardIndex(uint32_t& outShardIndex, bool& hasRequiredShard, Sema& sema, TypeRef typeRef, ByteSpan payload)
    {
        if (typeRef.isInvalid())
            return false;

        TaskContext&    ctx      = sema.ctx();
        const TypeInfo& typeInfo = ctx.typeMgr().get(typeRef);
        if (typeInfo.isAlias())
        {
            const TypeRef unwrappedTypeRef = typeInfo.unwrap(ctx, typeRef, TypeExpandE::Alias);
            return unwrappedTypeRef.isValid() && resolveStaticPayloadRequiredShardIndex(outShardIndex, hasRequiredShard, sema, unwrappedTypeRef, payload);
        }

        const uint64_t sizeOf = typeInfo.sizeOf(ctx);
        if (sizeOf != payload.size())
            return false;

        if (typeInfo.isEnum())
            return resolveStaticPayloadRequiredShardIndex(outShardIndex, hasRequiredShard, sema, typeInfo.payloadSymEnum().underlyingTypeRef(), payload);

        if (typeInfo.isBool() || typeInfo.isChar() || typeInfo.isRune() || typeInfo.isInt() || typeInfo.isFloat() || typeInfo.isString() || typeInfo.isSlice())
            return true;

        if (typeInfo.isAny())
        {
            if (payload.size() != sizeof(Runtime::Any))
                return false;

            const auto* runtimeAny = reinterpret_cast<const Runtime::Any*>(payload.data());
            if (!runtimeAny->type)
                return runtimeAny->value == nullptr;

            return requirePointerShardIndex(outShardIndex, hasRequiredShard, sema, runtimeAny->type);
        }

        if (typeInfo.isInterface())
        {
            if (payload.size() != sizeof(Runtime::Interface))
                return false;

            const auto* runtimeInterface = reinterpret_cast<const Runtime::Interface*>(payload.data());
            return requirePointerShardIndex(outShardIndex, hasRequiredShard, sema, runtimeInterface->obj) &&
                   requirePointerShardIndex(outShardIndex, hasRequiredShard, sema, runtimeInterface->itable);
        }

        if (typeInfo.isArray())
        {
            const TypeRef   elementTypeRef = typeInfo.payloadArrayElemTypeRef();
            const TypeInfo& elementType    = ctx.typeMgr().get(elementTypeRef);
            const uint64_t  elementSize    = elementType.sizeOf(ctx);
            if (!elementSize)
                return payload.empty();

            uint64_t totalCount = 1;
            for (const uint64_t dim : typeInfo.payloadArrayDims())
                totalCount *= dim;

            for (uint64_t idx = 0; idx < totalCount; ++idx)
            {
                const uint64_t elementOffset = idx * elementSize;
                const auto     elementBytes  = ByteSpan{payload.data() + elementOffset, static_cast<size_t>(elementSize)};
                if (!resolveStaticPayloadRequiredShardIndex(outShardIndex, hasRequiredShard, sema, elementTypeRef, elementBytes))
                    return false;
            }

            return true;
        }

        if (typeInfo.isStruct())
        {
            for (const SymbolVariable* field : typeInfo.payloadSymStruct().fields())
            {
                if (!field)
                    continue;

                const TypeRef   fieldTypeRef = field->typeRef();
                const TypeInfo& fieldType    = ctx.typeMgr().get(fieldTypeRef);
                const uint64_t  fieldSize    = fieldType.sizeOf(ctx);
                const uint64_t  fieldOffset  = field->offset();
                if (fieldOffset + fieldSize > payload.size())
                    return false;

                const auto fieldBytes = ByteSpan{payload.data() + fieldOffset, static_cast<size_t>(fieldSize)};
                if (!resolveStaticPayloadRequiredShardIndex(outShardIndex, hasRequiredShard, sema, fieldTypeRef, fieldBytes))
                    return false;
            }

            return true;
        }

        if (typeInfo.isPointerLike() || typeInfo.isReference() || typeInfo.isTypeInfo() || typeInfo.isCString() || typeInfo.isFunction())
        {
            if (payload.size() != sizeof(uint64_t))
                return false;

            const uint64_t rawPtr = *reinterpret_cast<const uint64_t*>(payload.data());
            return requirePointerShardIndex(outShardIndex, hasRequiredShard, sema, reinterpret_cast<const void*>(rawPtr));
        }

        return false;
    }
}

ConstantRef ConstantHelpers::materializeStaticPayloadConstant(Sema& sema, TypeRef typeRef, ByteSpan payload)
{
    if (typeRef.isInvalid())
        return ConstantRef::invalid();

    TaskContext&    ctx      = sema.ctx();
    const TypeInfo& typeInfo = ctx.typeMgr().get(typeRef);
    const uint64_t  sizeOf   = typeInfo.sizeOf(ctx);
    if (sizeOf != payload.size())
        return ConstantRef::invalid();

    uint32_t shardIndex       = 0;
    bool     hasRequiredShard = false;
    if (!resolveStaticPayloadRequiredShardIndex(shardIndex, hasRequiredShard, sema, typeRef, payload))
        return ConstantRef::invalid();

    DataSegment& segment = sema.cstMgr().shardDataSegment(hasRequiredShard ? shardIndex : 0);
    uint32_t     offset  = INVALID_REF;
    if (ConstantLower::materializeStaticPayload(offset, sema, segment, typeRef, payload) != Result::Continue)
        return ConstantRef::invalid();

    const ByteSpan      storedBytes{segment.ptr<std::byte>(offset), sizeOf};
    const ConstantValue result = makeMaterializedConstantValue(sema, typeRef, storedBytes);
    if (!result.isValid())
        return ConstantRef::invalid();

    return sema.cstMgr().addConstant(ctx, result);
}

ConstantRef ConstantHelpers::makeSourceCodeLocation(Sema& sema, const SourceCodeRange& codeRange, const SymbolFunction* function)
{
    const TaskContext& ctx      = sema.ctx();
    const TypeRef      typeRef  = sema.typeMgr().structSourceCodeLocation();
    const SourceView*  srcView  = codeRange.srcView;
    const SourceFile*  file     = srcView ? srcView->file() : nullptr;
    const Utf8         fileName = file ? Utf8(file->path().string()) : Utf8{};
    const Utf8         funcName = function ? function->getFullScopedName(ctx) : Utf8{};

    const std::string_view shardKey   = !fileName.empty() ? fileName.view() : funcName.view();
    const uint32_t         shardIndex = std::hash<std::string_view>{}(shardKey) & (ConstantManager::SHARD_COUNT - 1);
    DataSegment&           segment    = sema.cstMgr().shardDataSegment(shardIndex);

    const auto [offset, storage] = segment.reserveBytes(sizeof(Runtime::SourceCodeLocation), alignof(Runtime::SourceCodeLocation), true);
    auto* const rtLoc            = reinterpret_cast<Runtime::SourceCodeLocation*>(storage);

    rtLoc->fileName.length = segment.addString(offset, offsetof(Runtime::SourceCodeLocation, fileName.ptr), fileName);

    if (funcName.empty())
    {
        rtLoc->funcName.ptr    = nullptr;
        rtLoc->funcName.length = 0;
    }
    else
    {
        rtLoc->funcName.length = segment.addString(offset, offsetof(Runtime::SourceCodeLocation, funcName.ptr), funcName);
    }

    rtLoc->lineStart = codeRange.line;
    rtLoc->colStart  = codeRange.column;
    rtLoc->lineEnd   = codeRange.line;
    rtLoc->colEnd    = codeRange.column + codeRange.len;

    const auto          bytes  = ByteSpan{storage, sizeof(Runtime::SourceCodeLocation)};
    const ConstantValue cstVal = ConstantValue::makeStructBorrowed(ctx, typeRef, bytes);
    return sema.cstMgr().addConstant(ctx, cstVal);
}

ConstantRef ConstantHelpers::makeSourceCodeLocation(Sema& sema, const AstNode& node, const SymbolFunction* function)
{
    const SourceCodeRange codeRange = node.codeRangeWithChildren(sema.ctx(), sema.ast());
    return makeSourceCodeLocation(sema, codeRange, function);
}

SWC_END_NAMESPACE();
