#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Support/Report/DiagnosticDef.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    SymbolVariable* getVariableSymbol(Symbol* symbol)
    {
        return symbol ? symbol->safeCast<SymbolVariable>() : nullptr;
    }

    bool isGlobalStorageVariable(const SymbolVariable& symVar)
    {
        const SymbolMap* const owner = symVar.ownerSymMap();
        if (!owner)
            return false;

        return owner->isModule() || owner->isNamespace();
    }

    bool isAllZeroBytes(ByteSpan bytes)
    {
        for (const std::byte value : bytes)
        {
            if (value != std::byte{})
                return false;
        }

        return true;
    }

    DataSegment& globalStorageSegment(CompilerInstance& compiler, DataSegmentKind kind)
    {
        switch (kind)
        {
            case DataSegmentKind::GlobalZero:
                return compiler.globalZeroSegment();
            case DataSegmentKind::GlobalInit:
                return compiler.globalInitSegment();
            case DataSegmentKind::Compiler:
                return compiler.compilerSegment();
            case DataSegmentKind::Zero:
                return compiler.constantSegment();
        }

        SWC_UNREACHABLE();
    }

    Result materializeGlobalInitPayloadInPlace(Sema& sema, DataSegment& segment, TypeRef typeRef, uint32_t baseOffset, ByteSpanRW dstBytes, ByteSpan srcBytes);

    Result materializeGlobalInitPayload(uint32_t& outOffset, Sema& sema, DataSegment& segment, TypeRef typeRef, ByteSpan srcBytes)
    {
        outOffset = INVALID_REF;
        if (typeRef.isInvalid())
            return Result::Error;

        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        const uint64_t  sizeOf   = typeInfo.sizeOf(sema.ctx());
        const uint32_t  alignOf  = typeInfo.alignOf(sema.ctx());
        SWC_ASSERT(sizeOf <= std::numeric_limits<uint32_t>::max());
        SWC_ASSERT(sizeOf == srcBytes.size());

        const auto [offset, storage] = segment.reserveBytes(static_cast<uint32_t>(sizeOf), alignOf, true);
        outOffset                    = offset;
        return materializeGlobalInitPayloadInPlace(sema, segment, typeRef, offset, ByteSpanRW{storage, static_cast<size_t>(sizeOf)}, srcBytes);
    }

    Result materializeGlobalInitPayloadInPlace(Sema& sema, DataSegment& segment, TypeRef typeRef, const uint32_t baseOffset, const ByteSpanRW dstBytes, const ByteSpan srcBytes)
    {
        if (typeRef.isInvalid())
            return Result::Error;

        TaskContext&    ctx      = sema.ctx();
        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        if (typeInfo.isAlias())
        {
            const TypeRef unwrapped = typeInfo.unwrap(ctx, typeRef, TypeExpandE::Alias);
            return unwrapped.isValid() ? materializeGlobalInitPayloadInPlace(sema, segment, unwrapped, baseOffset, dstBytes, srcBytes) : Result::Error;
        }

        const uint64_t sizeOf = typeInfo.sizeOf(ctx);
        if (sizeOf != dstBytes.size() || sizeOf != srcBytes.size())
            return Result::Error;

        if (typeInfo.isEnum())
            return materializeGlobalInitPayloadInPlace(sema, segment, typeInfo.payloadSymEnum().underlyingTypeRef(), baseOffset, dstBytes, srcBytes);

        if (typeInfo.isBool() || typeInfo.isChar() || typeInfo.isRune() || typeInfo.isInt() || typeInfo.isFloat())
        {
            if (!dstBytes.empty())
                std::memcpy(dstBytes.data(), srcBytes.data(), dstBytes.size());
            return Result::Continue;
        }

        if (typeInfo.isString())
        {
            if (srcBytes.size() != sizeof(Runtime::String))
                return Result::Error;

            auto* const       dstString = reinterpret_cast<Runtime::String*>(dstBytes.data());
            const auto* const srcString = reinterpret_cast<const Runtime::String*>(srcBytes.data());
            if (!srcString->ptr)
            {
                if (srcString->length != 0)
                    return Result::Error;
                dstString->ptr    = nullptr;
                dstString->length = 0;
                return Result::Continue;
            }

            dstString->length = segment.addString(baseOffset, offsetof(Runtime::String, ptr), std::string_view(srcString->ptr, srcString->length));
            return Result::Continue;
        }

        if (typeInfo.isAny())
        {
            if (srcBytes.size() != sizeof(Runtime::Any))
                return Result::Error;

            auto* const       dstAny = reinterpret_cast<Runtime::Any*>(dstBytes.data());
            const auto* const srcAny = reinterpret_cast<const Runtime::Any*>(srcBytes.data());
            if (!srcAny->type)
            {
                if (srcAny->value != nullptr)
                    return Result::Error;
                dstAny->value = nullptr;
                dstAny->type  = nullptr;
                return Result::Continue;
            }

            uint32_t  typeShardIndex = 0;
            const Ref typeOffset     = sema.cstMgr().findDataSegmentRef(typeShardIndex, srcAny->type);
            if (typeOffset == INVALID_REF)
                return Result::Error;
            if (&segment != &sema.cstMgr().shardDataSegment(typeShardIndex))
                return Result::Error;

            dstAny->type = segment.ptr<Runtime::TypeInfo>(typeOffset);
            segment.addRelocation(baseOffset + offsetof(Runtime::Any, type), typeOffset);

            if (!srcAny->value)
                return Result::Continue;

            const TypeRef valueTypeRef = sema.typeGen().getBackTypeRef(srcAny->type);
            if (valueTypeRef.isInvalid())
                return Result::Error;

            const uint64_t valueSize = sema.typeMgr().get(valueTypeRef).sizeOf(ctx);
            SWC_ASSERT(valueSize <= std::numeric_limits<uint32_t>::max());
            uint32_t valueOffset = INVALID_REF;
            SWC_RESULT(materializeGlobalInitPayload(valueOffset, sema, segment, valueTypeRef, ByteSpan{reinterpret_cast<const std::byte*>(srcAny->value), static_cast<size_t>(valueSize)}));
            dstAny->value = segment.ptr<std::byte>(valueOffset);
            segment.addRelocation(baseOffset + offsetof(Runtime::Any, value), valueOffset);
            return Result::Continue;
        }

        if (typeInfo.isSlice())
        {
            if (srcBytes.size() != sizeof(Runtime::Slice<std::byte>))
                return Result::Error;

            auto* const       dstSlice       = reinterpret_cast<Runtime::Slice<std::byte>*>(dstBytes.data());
            const auto* const srcSlice       = reinterpret_cast<const Runtime::Slice<std::byte>*>(srcBytes.data());
            const TypeRef     elementTypeRef = typeInfo.payloadTypeRef();
            const TypeInfo&   elementType    = sema.typeMgr().get(elementTypeRef);
            const uint64_t    elementSize    = elementType.sizeOf(ctx);
            if (!srcSlice->ptr)
            {
                if (srcSlice->count != 0)
                    return Result::Error;
                dstSlice->ptr   = nullptr;
                dstSlice->count = 0;
                return Result::Continue;
            }

            if (!elementSize)
                return Result::Error;

            const uint64_t byteCount = srcSlice->count * elementSize;
            SWC_ASSERT(byteCount <= std::numeric_limits<uint32_t>::max());
            const auto [dataOffset, dataStorage] = segment.reserveBytes(static_cast<uint32_t>(byteCount), elementType.alignOf(ctx), true);
            for (uint64_t idx = 0; idx < srcSlice->count; ++idx)
            {
                const uint64_t elementOffset = idx * elementSize;
                SWC_RESULT(materializeGlobalInitPayloadInPlace(sema,
                                                                      segment,
                                                                      elementTypeRef,
                                                                      dataOffset + static_cast<uint32_t>(elementOffset),
                                                                      ByteSpanRW{dataStorage + elementOffset, static_cast<size_t>(elementSize)},
                                                                      ByteSpan{srcSlice->ptr + elementOffset, static_cast<size_t>(elementSize)}));
            }

            dstSlice->ptr   = dataStorage;
            dstSlice->count = srcSlice->count;
            segment.addRelocation(baseOffset + offsetof(Runtime::Slice<std::byte>, ptr), dataOffset);
            return Result::Continue;
        }

        if (typeInfo.isArray())
        {
            const TypeRef   elementTypeRef = typeInfo.payloadArrayElemTypeRef();
            const TypeInfo& elementType    = sema.typeMgr().get(elementTypeRef);
            const uint64_t  elementSize    = elementType.sizeOf(ctx);
            if (!elementSize)
                return Result::Error;

            uint64_t totalCount = 1;
            for (const uint64_t dim : typeInfo.payloadArrayDims())
                totalCount *= dim;

            for (uint64_t idx = 0; idx < totalCount; ++idx)
            {
                const uint64_t elementOffset = idx * elementSize;
                SWC_RESULT(materializeGlobalInitPayloadInPlace(sema,
                                                                      segment,
                                                                      elementTypeRef,
                                                                      baseOffset + static_cast<uint32_t>(elementOffset),
                                                                      ByteSpanRW{dstBytes.data() + elementOffset, static_cast<size_t>(elementSize)},
                                                                      ByteSpan{srcBytes.data() + elementOffset, static_cast<size_t>(elementSize)}));
            }

            return Result::Continue;
        }

        if (typeInfo.isStruct())
        {
            for (const SymbolVariable* field : typeInfo.payloadSymStruct().fields())
            {
                if (!field)
                    continue;

                const TypeRef   fieldTypeRef = field->typeRef();
                const TypeInfo& fieldType    = sema.typeMgr().get(fieldTypeRef);
                const uint64_t  fieldSize    = fieldType.sizeOf(ctx);
                const uint64_t  fieldOffset  = field->offset();
                if (fieldOffset + fieldSize > srcBytes.size())
                    return Result::Error;

                SWC_RESULT(materializeGlobalInitPayloadInPlace(sema,
                                                                      segment,
                                                                      fieldTypeRef,
                                                                      baseOffset + static_cast<uint32_t>(fieldOffset),
                                                                      ByteSpanRW{dstBytes.data() + fieldOffset, static_cast<size_t>(fieldSize)},
                                                                      ByteSpan{srcBytes.data() + fieldOffset, static_cast<size_t>(fieldSize)}));
            }

            return Result::Continue;
        }

        if (typeInfo.isInterface())
        {
            if (srcBytes.size() != sizeof(Runtime::Interface))
                return Result::Error;

            auto* const       dstInterface = reinterpret_cast<Runtime::Interface*>(dstBytes.data());
            const auto* const srcInterface = reinterpret_cast<const Runtime::Interface*>(srcBytes.data());

            if (srcInterface->obj)
            {
                uint32_t  objShardIndex = 0;
                const Ref objOffset     = sema.cstMgr().findDataSegmentRef(objShardIndex, srcInterface->obj);
                if (objOffset == INVALID_REF)
                    return Result::Error;
                if (&segment != &sema.cstMgr().shardDataSegment(objShardIndex))
                    return Result::Error;
                dstInterface->obj = segment.ptr<std::byte>(objOffset);
                segment.addRelocation(baseOffset + offsetof(Runtime::Interface, obj), objOffset);
            }

            if (srcInterface->itable)
            {
                uint32_t  itableShardIndex = 0;
                const Ref itableOffset     = sema.cstMgr().findDataSegmentRef(itableShardIndex, srcInterface->itable);
                if (itableOffset == INVALID_REF)
                    return Result::Error;
                if (&segment != &sema.cstMgr().shardDataSegment(itableShardIndex))
                    return Result::Error;
                dstInterface->itable = segment.ptr<void*>(itableOffset);
                segment.addRelocation(baseOffset + offsetof(Runtime::Interface, itable), itableOffset);
            }

            return Result::Continue;
        }

        if (typeInfo.isPointerLike() || typeInfo.isReference() || typeInfo.isTypeInfo() || typeInfo.isCString() || typeInfo.isFunction())
        {
            if (srcBytes.size() != sizeof(uint64_t))
                return Result::Error;

            const uint64_t ptrValue = *reinterpret_cast<const uint64_t*>(srcBytes.data());
            if (!ptrValue)
                return Result::Continue;

            uint32_t  targetShardIndex = 0;
            const Ref targetOffset     = sema.cstMgr().findDataSegmentRef(targetShardIndex, reinterpret_cast<const void*>(ptrValue));
            if (targetOffset == INVALID_REF)
                return Result::Error;
            if (&segment != &sema.cstMgr().shardDataSegment(targetShardIndex))
                return Result::Error;

            *reinterpret_cast<uint64_t*>(dstBytes.data()) = reinterpret_cast<uint64_t>(segment.ptr<std::byte>(targetOffset));
            segment.addRelocation(baseOffset, targetOffset);
            return Result::Continue;
        }

        return Result::Error;
    }

    Result allocateGlobalStorage(Sema& sema, SymbolVariable& symVar)
    {
        if (symVar.hasGlobalStorage())
            return Result::Continue;
        if (!isGlobalStorageVariable(symVar))
            return Result::Continue;

        TaskContext&    ctx      = sema.ctx();
        const TypeInfo& typeInfo = ctx.typeMgr().get(symVar.typeRef());
        SWC_RESULT(sema.waitSemaCompleted(&typeInfo, sema.curNodeRef()));
        TypeRef storageTypeRef = symVar.typeRef();
        if (typeInfo.isAlias())
        {
            const TypeRef unwrappedTypeRef = typeInfo.unwrap(ctx, storageTypeRef, TypeExpandE::Alias);
            if (unwrappedTypeRef.isValid())
                storageTypeRef = unwrappedTypeRef;
        }

        const TypeInfo& storageTypeInfo = ctx.typeMgr().get(storageTypeRef);

        const uint64_t sizeU64 = storageTypeInfo.sizeOf(ctx);
        if (!sizeU64)
            return Result::Continue;
        SWC_ASSERT(sizeU64 <= std::numeric_limits<uint32_t>::max());
        const uint32_t size      = static_cast<uint32_t>(sizeU64);
        uint32_t       alignment = storageTypeInfo.alignOf(ctx);
        if (!alignment)
            alignment = 1;

        const bool      isCompilerGlobal   = symVar.attributes().hasRtFlag(RtAttributeFlagsE::Compiler);
        const bool      explicitUndefined  = symVar.hasExtraFlag(SymbolVariableFlagsE::ExplicitUndefined);
        const bool      hasInitializerData = symVar.cstRef().isValid() && !explicitUndefined;
        DataSegmentKind storageKind        = isCompilerGlobal ? DataSegmentKind::Compiler : DataSegmentKind::GlobalZero;
        if (!isCompilerGlobal && explicitUndefined)
            storageKind = DataSegmentKind::GlobalInit;

        std::vector<std::byte> loweredBytes;
        if (hasInitializerData)
        {
            loweredBytes.resize(size);
            std::memset(loweredBytes.data(), 0, loweredBytes.size());
            ConstantLower::lowerToBytes(sema, ByteSpanRW{loweredBytes.data(), loweredBytes.size()}, symVar.cstRef(), storageTypeRef);

            if (!isCompilerGlobal && !isAllZeroBytes(loweredBytes))
                storageKind = DataSegmentKind::GlobalInit;
            else if (!isCompilerGlobal)
                storageKind = DataSegmentKind::GlobalZero;
        }

        DataSegment& segment = globalStorageSegment(ctx.compiler(), storageKind);
        uint32_t     offset  = 0;
        if (hasInitializerData)
        {
            if (storageKind == DataSegmentKind::GlobalInit)
            {
                const auto [reservedOffset, storage] = segment.reserveBytes(size, alignment, true);
                offset                               = reservedOffset;
                SWC_RESULT(materializeGlobalInitPayloadInPlace(sema, segment, storageTypeRef, offset, ByteSpanRW{storage, loweredBytes.size()}, ByteSpan{loweredBytes.data(), loweredBytes.size()}));
            }
            else
            {
                const std::pair<ByteSpan, Ref> addRes = segment.addSpan(ByteSpan{loweredBytes.data(), loweredBytes.size()}, alignment);
                offset                                = addRes.second;
            }
        }
        else
        {
            const bool                            zeroInit = !explicitUndefined;
            const std::pair<uint32_t, std::byte*> res      = segment.reserveBytes(size, alignment, zeroInit);
            offset                                         = res.first;
        }

        symVar.setGlobalStorage(storageKind, offset);
        return Result::Continue;
    }

    void completeConst(Sema& sema, const std::span<Symbol*>& symbols, ConstantRef cstRef, TypeRef typeRef)
    {
        for (Symbol* s : symbols)
        {
            auto& symCst = s->cast<SymbolConstant>();
            symCst.setCstRef(cstRef);
            if (symCst.typeRef().isInvalid())
                symCst.setTypeRef(typeRef);
            symCst.setTyped(sema.ctx());
            symCst.setSemaCompleted(sema.ctx());
        }
    }

    Result completeVar(Sema& sema, const std::span<Symbol*>& symbols, TypeRef typeRef)
    {
        TaskContext& ctx = sema.ctx();
        for (Symbol* s : symbols)
        {
            auto& symVar = s->cast<SymbolVariable>();
            if (symVar.typeRef().isInvalid())
                symVar.setTypeRef(typeRef);

            if (!symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
            {
                if (SymbolFunction* currentFunc = sema.frame().currentFunction())
                {
                    const TypeInfo* symType = symVar.typeRef().isValid() ? &ctx.typeMgr().get(symVar.typeRef()) : nullptr;
                    SWC_RESULT(sema.waitSemaCompleted(symType, sema.curNodeRef()));
                    currentFunc->addLocalVariable(ctx, &symVar);
                }
                else
                {
                    SWC_RESULT(allocateGlobalStorage(sema, symVar));
                }
            }

            symVar.setTyped(sema.ctx());
            symVar.setSemaCompleted(sema.ctx());
        }

        return Result::Continue;
    }

    bool deduceArrayDimsFromType(Sema& sema, TypeRef typeRef, SmallVector4<uint64_t>& outDims)
    {
        const TypeInfo& type = sema.typeMgr().get(typeRef);
        if (type.isArray())
        {
            const auto& dims = type.payloadArrayDims();
            outDims.insert(outDims.end(), dims.begin(), dims.end());

            const TypeRef   elemTypeRef = type.payloadArrayElemTypeRef();
            const TypeInfo& elemType    = sema.typeMgr().get(elemTypeRef);
            if (elemType.isArray() || elemType.isAggregateArray())
                return deduceArrayDimsFromType(sema, elemTypeRef, outDims);
            return true;
        }

        if (type.isAggregateArray())
        {
            const auto& elemTypes = type.payloadAggregate().types;
            if (elemTypes.empty())
                return false;

            outDims.push_back(elemTypes.size());

            SmallVector4<uint64_t> innerDims;
            bool                   hasInner = false;
            for (const auto elemTypeRef : elemTypes)
            {
                const TypeInfo& elemType = sema.typeMgr().get(elemTypeRef);
                if (!elemType.isArray() && !elemType.isAggregateArray())
                {
                    if (hasInner)
                        return false;
                    continue;
                }

                SmallVector4<uint64_t> nextInner;
                if (!deduceArrayDimsFromType(sema, elemTypeRef, nextInner))
                    return false;

                if (!hasInner)
                {
                    innerDims = std::move(nextInner);
                    hasInner  = true;
                }
                else if (nextInner.size() != innerDims.size() || !std::equal(nextInner.begin(), nextInner.end(), innerDims.begin()))
                {
                    return false;
                }
            }

            if (hasInner)
                outDims.insert(outDims.end(), innerDims.begin(), innerDims.end());
            return true;
        }

        return false;
    }

    struct ExplicitArrayNode
    {
        SmallVector4<uint64_t> dims;
        TypeInfoFlags          flags;
    };

    bool collectExplicitArrayNodes(Sema& sema, TypeRef typeRef, std::vector<ExplicitArrayNode>& outNodes, TypeRef& outBaseTypeRef)
    {
        while (typeRef.isValid())
        {
            const TypeInfo& type = sema.typeMgr().get(typeRef);
            if (!type.isArray())
                break;
            SmallVector4<uint64_t> dims;
            const auto&            payloadDims = type.payloadArrayDims();
            dims.insert(dims.end(), payloadDims.begin(), payloadDims.end());
            outNodes.push_back({std::move(dims), type.flags()});
            typeRef = type.payloadArrayElemTypeRef();
        }

        outBaseTypeRef = typeRef;
        return !outNodes.empty();
    }

    TypeRef deduceArrayTypeFromInit(Sema& sema, TypeRef explicitTypeRef, const SemaNodeView& initView)
    {
        if (explicitTypeRef.isInvalid() || initView.typeRef().isInvalid())
            return TypeRef::invalid();

        std::vector<ExplicitArrayNode> nodes;
        TypeRef                        baseTypeRef = TypeRef::invalid();
        if (!collectExplicitArrayNodes(sema, explicitTypeRef, nodes, baseTypeRef))
            return TypeRef::invalid();

        bool   hasUnknown       = false;
        size_t explicitDimCount = 0;
        for (const auto& node : nodes)
        {
            if (node.dims.empty())
            {
                hasUnknown = true;
                explicitDimCount += 1;
            }
            else
            {
                explicitDimCount += node.dims.size();
            }
        }

        if (!hasUnknown)
            return TypeRef::invalid();

        SmallVector4<uint64_t> initDims;
        if (!deduceArrayDimsFromType(sema, initView.typeRef(), initDims))
            return TypeRef::invalid();

        if (nodes.size() == 1 && nodes[0].dims.empty())
        {
            if (initDims.empty())
                return TypeRef::invalid();
            if (initDims.size() > 1)
            {
                TypeRef elemTypeRef = baseTypeRef;
                for (const uint64_t& initDim : std::ranges::reverse_view(initDims))
                {
                    SmallVector4<uint64_t> oneDim;
                    oneDim.push_back(initDim);
                    const TypeInfo arrayType = TypeInfo::makeArray(oneDim.span(), elemTypeRef, nodes[0].flags);
                    elemTypeRef              = sema.typeMgr().addType(arrayType);
                }

                return elemTypeRef;
            }

            nodes[0].dims = std::move(initDims);
        }
        else
        {
            if (initDims.size() != explicitDimCount)
                return TypeRef::invalid();

            size_t dimIndex = 0;
            for (auto& node : nodes)
            {
                if (node.dims.empty())
                {
                    node.dims.push_back(initDims[dimIndex++]);
                    continue;
                }

                for (auto dim : node.dims)
                {
                    if (initDims[dimIndex++] != dim)
                        return TypeRef::invalid();
                }
            }
        }

        TypeRef elemTypeRef = baseTypeRef;
        for (auto& node : std::ranges::reverse_view(nodes))
        {
            const TypeInfo arrayType = TypeInfo::makeArray(node.dims.span(), elemTypeRef, node.flags);
            elemTypeRef              = sema.typeMgr().addType(arrayType);
        }

        return elemTypeRef;
    }

    void storeFieldDefaultConstants(const std::span<Symbol*>& symbols, ConstantRef cstRef)
    {
        if (cstRef.isInvalid())
            return;

        for (Symbol* s : symbols)
        {
            auto* const symVar = getVariableSymbol(s);
            if (!symVar)
                continue;

            const SymbolMap* const owner = symVar->ownerSymMap();
            if (!owner || !owner->isStruct())
                continue;
            symVar->setDefaultValueRef(cstRef);
        }
    }

    void storeParameterDefaultConstants(const std::span<Symbol*>& symbols, bool isParameter, ConstantRef cstRef)
    {
        if (!isParameter || cstRef.isInvalid())
            return;

        for (Symbol* s : symbols)
        {
            auto* const symVar = getVariableSymbol(s);
            if (!symVar)
                continue;

            symVar->setDefaultValueRef(cstRef);
        }
    }

    void storeVariableDefaultConstants(const std::span<Symbol*>& symbols, ConstantRef cstRef)
    {
        if (cstRef.isInvalid())
            return;

        for (Symbol* s : symbols)
        {
            auto* const symVar = getVariableSymbol(s);
            if (!symVar)
                continue;

            symVar->setDefaultValueRef(cstRef);
        }
    }

    void storeLetConstants(const std::span<Symbol*>& symbols, bool isLet, ConstantRef cstRef)
    {
        if (!isLet || cstRef.isInvalid())
            return;

        for (Symbol* s : symbols)
        {
            auto* const symVar = getVariableSymbol(s);
            if (!symVar)
                continue;

            symVar->setCstRef(cstRef);
        }
    }

    void storeGlobalVariableConstants(const std::span<Symbol*>& symbols, ConstantRef cstRef)
    {
        if (cstRef.isInvalid())
            return;

        for (Symbol* s : symbols)
        {
            auto* const symVar = getVariableSymbol(s);
            if (!symVar)
                continue;

            if (!isGlobalStorageVariable(*symVar))
                continue;
            symVar->setCstRef(cstRef);
        }
    }

    void storeDestructuringLetConstants(Sema& sema, const std::span<Symbol*>& symbols, const std::span<const SymbolVariable*>& fields, ConstantRef cstRef)
    {
        if (symbols.empty() || symbols.size() != fields.size() || cstRef.isInvalid())
            return;

        TaskContext&         ctx                 = sema.ctx();
        const ConstantValue& cst                 = sema.cstMgr().get(cstRef);
        const bool           fromAggregateStruct = cst.isAggregateStruct();
        const bool           fromStructBytes     = cst.isStruct();
        if (!fromAggregateStruct && !fromStructBytes)
            return;

        const std::vector<ConstantRef>* aggregateValues = fromAggregateStruct ? &cst.getAggregateStruct() : nullptr;
        const ByteSpan                  structBytes     = fromStructBytes ? cst.getStruct() : ByteSpan{};

        const size_t count = symbols.size();
        for (size_t i = 0; i < count; ++i)
        {
            Symbol* const               sym    = symbols[i];
            const SymbolVariable* const field  = fields[i];
            auto* const                 symVar = getVariableSymbol(sym);
            if (!symVar || !field)
                continue;

            ConstantRef fieldCstRef = ConstantRef::invalid();
            if (aggregateValues)
            {
                if (i < aggregateValues->size())
                    fieldCstRef = (*aggregateValues)[i];
            }
            else
            {
                const TypeRef   fieldTypeRef = field->typeRef();
                const TypeInfo& fieldType    = sema.typeMgr().get(fieldTypeRef);
                const uint64_t  fieldOffset  = field->offset();
                const uint64_t  fieldSize    = fieldType.sizeOf(ctx);
                if (fieldOffset + fieldSize > structBytes.size())
                    continue;

                const auto fieldBytes = ByteSpan{structBytes.data() + fieldOffset, fieldSize};
                if (fieldType.isStruct())
                {
                    const ConstantValue fieldCst = ConstantValue::makeStructBorrowed(ctx, fieldTypeRef, fieldBytes);
                    fieldCstRef                  = sema.cstMgr().addConstant(ctx, fieldCst);
                }
                else if (fieldType.isArray())
                {
                    const ConstantValue fieldCst = ConstantValue::makeArrayBorrowed(ctx, fieldTypeRef, fieldBytes);
                    fieldCstRef                  = sema.cstMgr().addConstant(ctx, fieldCst);
                }
                else
                {
                    TypeRef valueTypeRef = fieldTypeRef;
                    if (fieldType.isEnum())
                        valueTypeRef = fieldType.payloadSymEnum().underlyingTypeRef();

                    ConstantValue fieldCst = ConstantValue::make(ctx, fieldBytes.data(), valueTypeRef, ConstantValue::PayloadOwnership::Borrowed);
                    if (!fieldCst.isValid())
                        continue;

                    fieldCstRef = sema.cstMgr().addConstant(ctx, fieldCst);
                    if (fieldType.isEnum())
                    {
                        fieldCst = ConstantValue::makeEnumValue(ctx, fieldCstRef, fieldTypeRef);
                        fieldCst.setTypeRef(fieldTypeRef);
                        fieldCstRef = sema.cstMgr().addConstant(ctx, fieldCst);
                    }
                }
            }

            if (fieldCstRef.isValid())
                symVar->setCstRef(fieldCstRef);
        }
    }

    struct SemaPostVarDeclArgs
    {
        const AstNode*              owner;
        TokenRef                    tokDiag;
        AstNodeRef                  nodeInitRef;
        AstNodeRef                  nodeTypeRef;
        EnumFlags<AstVarDeclFlagsE> flags;
    };

    Result semaPostVarDeclCommon(Sema& sema, const SemaPostVarDeclArgs& context, const std::span<Symbol*>& symbols)
    {
        SemaNodeView nodeInitView = sema.viewNodeTypeConstant(context.nodeInitRef);
        if (context.nodeInitRef.isValid())
            SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, nodeInitView));

        const SemaNodeView nodeTypeView    = sema.viewType(context.nodeTypeRef);
        TypeRef            explicitTypeRef = nodeTypeView.typeRef();

        if (nodeInitView.typeRef().isValid())
        {
            const TypeRef deducedTypeRef = deduceArrayTypeFromInit(sema, explicitTypeRef, nodeInitView);
            if (deducedTypeRef.isValid())
            {
                explicitTypeRef = deducedTypeRef;
                if (context.nodeTypeRef.isValid())
                    sema.setType(context.nodeTypeRef, explicitTypeRef);
            }
        }

        const TypeInfo* explicitType = explicitTypeRef.isValid() ? &sema.typeMgr().get(explicitTypeRef) : nullptr;

        const bool isConst                 = context.flags.has(AstVarDeclFlagsE::Const);
        const bool isLet                   = context.flags.has(AstVarDeclFlagsE::Let);
        const bool isParameter             = context.flags.has(AstVarDeclFlagsE::Parameter);
        const bool isUsing                 = context.flags.has(AstVarDeclFlagsE::Using);
        bool       isExplicitUndefinedInit = false;

        // Initialized to 'undefined'
        if (context.nodeInitRef.isValid() && nodeInitView.cstRef() == sema.cstMgr().cstUndefined())
        {
            if (isConst)
                return SemaError::raise(sema, DiagnosticId::sema_err_const_missing_init, SourceCodeRef{context.owner->srcViewRef(), context.tokDiag});
            if (isLet)
                return SemaError::raise(sema, DiagnosticId::sema_err_let_missing_init, SourceCodeRef{context.owner->srcViewRef(), context.tokDiag});
            if (context.nodeTypeRef.isInvalid())
                return SemaError::raise(sema, DiagnosticId::sema_err_not_type, SourceCodeRef{context.owner->srcViewRef(), context.tokDiag});

            if (!isParameter && explicitTypeRef.isValid() && explicitType && explicitType->isReference())
                return SemaError::raise(sema, DiagnosticId::sema_err_ref_missing_init, SourceCodeRef{context.owner->srcViewRef(), context.tokDiag});

            isExplicitUndefinedInit = true;
        }

        // Implicit cast from initializer to the specified type
        if (nodeInitView.typeRef().isValid() && explicitTypeRef.isValid())
        {
            SWC_RESULT(Cast::cast(sema, nodeInitView, explicitTypeRef, CastKind::Initialization));
        }
        else if (nodeInitView.cstRef().isValid())
        {
            ConstantRef newCstRef;
            SWC_RESULT(Cast::concretizeConstant(sema, newCstRef, nodeInitView.nodeRef(), nodeInitView.cstRef(), TypeInfo::Sign::Unknown, !isConst));
            sema.setConstant(nodeInitView.nodeRef(), newCstRef);
            nodeInitView.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);

            if (nodeInitView.type()->isInt())
            {
                const TypeRef newTypeRef = sema.typeMgr().promote(nodeInitView.typeRef(), nodeInitView.typeRef(), false);
                SWC_RESULT(Cast::cast(sema, nodeInitView, newTypeRef, CastKind::Implicit));
            }
        }

        if (context.nodeInitRef.isValid())
            storeFieldDefaultConstants(symbols, nodeInitView.cstRef());

        if (!sema.curScope().isLocal() && !sema.curScope().isParameters() && !isConst && context.nodeInitRef.isValid())
            SWC_RESULT(SemaCheck::isConstant(sema, nodeInitView.nodeRef()));

        const TypeRef finalTypeRef = explicitTypeRef.isValid() ? explicitTypeRef : nodeInitView.typeRef();
        const bool    isRefType    = finalTypeRef.isValid() && sema.typeMgr().get(finalTypeRef).isReference();
        if (isConst && isRefType)
            return SemaError::raise(sema, DiagnosticId::sema_err_const_ref_type, SourceCodeRef{context.owner->srcViewRef(), context.tokDiag});

        if (isUsing && finalTypeRef.isValid())
        {
            const TypeInfo& ultimateType = sema.typeMgr().get(finalTypeRef);
            if (!ultimateType.isStruct())
            {
                if (!ultimateType.isAnyPointer() || !sema.typeMgr().get(ultimateType.payloadTypeRef()).isStruct())
                {
                    Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_using_member_type, SourceCodeRef{context.owner->srcViewRef(), context.tokDiag});
                    diag.addArgument(Diagnostic::ARG_TYPE, finalTypeRef);
                    diag.report(sema.ctx());
                    return Result::Error;
                }
            }
        }

        ConstantRef implicitStructCstRef = ConstantRef::invalid();
        if (context.nodeInitRef.isInvalid() && !isParameter && explicitTypeRef.isValid() && explicitType && explicitType->isStruct())
        {
            SWC_RESULT(sema.waitSemaCompleted(explicitType, context.nodeTypeRef));
            implicitStructCstRef = explicitType->payloadSymStruct().computeDefaultValue(sema, explicitTypeRef);
        }
        const bool hasImplicitStructInit = implicitStructCstRef.isValid();

        // Constant
        if (isConst)
        {
            if (context.nodeInitRef.isInvalid())
            {
                if (!hasImplicitStructInit)
                    return SemaError::raise(sema, DiagnosticId::sema_err_const_missing_init, SourceCodeRef{context.owner->srcViewRef(), context.tokDiag});
                completeConst(sema, symbols, implicitStructCstRef, explicitTypeRef);
                return Result::Continue;
            }
            if (nodeInitView.cstRef().isInvalid())
                return SemaError::raiseExprNotConst(sema, nodeInitView.nodeRef());

            completeConst(sema, symbols, nodeInitView.cstRef(), nodeInitView.typeRef());
            return Result::Continue;
        }

        // Variable
        if (isLet && context.nodeInitRef.isInvalid() && !hasImplicitStructInit)
            return SemaError::raise(sema, DiagnosticId::sema_err_let_missing_init, SourceCodeRef{context.owner->srcViewRef(), context.tokDiag});
        if (!isLet && !isParameter && isRefType && context.nodeInitRef.isInvalid())
            return SemaError::raise(sema, DiagnosticId::sema_err_ref_missing_init, SourceCodeRef{context.owner->srcViewRef(), context.tokDiag});

        storeLetConstants(symbols, isLet, context.nodeInitRef.isValid() ? nodeInitView.cstRef() : implicitStructCstRef);
        storeGlobalVariableConstants(symbols, context.nodeInitRef.isValid() ? nodeInitView.cstRef() : implicitStructCstRef);
        storeParameterDefaultConstants(symbols, isParameter, context.nodeInitRef.isValid() ? nodeInitView.cstRef() : ConstantRef::invalid());
        storeVariableDefaultConstants(symbols, context.nodeInitRef.isValid() ? nodeInitView.cstRef() : implicitStructCstRef);

        if (context.nodeInitRef.isValid() || hasImplicitStructInit)
        {
            for (Symbol* s : symbols)
            {
                auto& symVar = s->cast<SymbolVariable>();
                if (isExplicitUndefinedInit)
                    symVar.addExtraFlag(SymbolVariableFlagsE::ExplicitUndefined);
                symVar.addExtraFlag(SymbolVariableFlagsE::Initialized);
            }
        }

        SWC_RESULT(completeVar(sema, symbols, explicitTypeRef.isValid() ? explicitTypeRef : nodeInitView.typeRef()));
        return Result::Continue;
    }
}

Result AstSingleVarDecl::semaPreDecl(Sema& sema) const
{
    if (hasFlag(AstVarDeclFlagsE::Const))
        SemaHelpers::registerSymbol<SymbolConstant>(sema, *this, tokNameRef);
    else
    {
        SemaHelpers::registerSymbol<SymbolVariable>(sema, *this, tokNameRef);
        if (hasFlag(AstVarDeclFlagsE::Let))
        {
            auto& symVar = sema.curViewSymbol().sym()->cast<SymbolVariable>();
            symVar.addExtraFlag(SymbolVariableFlagsE::Let);
        }
    }

    return Result::SkipChildren;
}

Result AstSingleVarDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
        SemaHelpers::declareSymbol(sema, *this);
    const Symbol& sym = *sema.curViewSymbol().sym();
    return Match::ghosting(sema, sym);
}

Result AstSingleVarDecl::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeTypeRef && nodeInitRef.isValid())
    {
        const SemaNodeView nodeTypeView = sema.viewType(nodeTypeRef);
        SemaFrame          frame        = sema.frame();
        frame.pushBindingType(nodeTypeView.typeRef());
        sema.pushFramePopOnPostChild(frame, nodeInitRef);
    }

    return Result::Continue;
}

Result AstSingleVarDecl::semaPostNode(Sema& sema) const
{
    Symbol&                   sym     = *sema.curViewSymbol().sym();
    Symbol*                   one[]   = {&sym};
    const SemaPostVarDeclArgs context = {this, tokNameRef, nodeInitRef, nodeTypeRef, flags()};
    return semaPostVarDeclCommon(sema, context, std::span<Symbol*>{one});
}

Result AstMultiVarDecl::semaPreDecl(Sema& sema) const
{
    SmallVector<TokenRef> tokNames;
    sema.ast().appendTokens(tokNames, spanNamesRef);

    SmallVector<const Symbol*> symbols;
    for (const auto& tokNameRef : tokNames)
    {
        if (hasFlag(AstVarDeclFlagsE::Const))
        {
            const Symbol& sym = SemaHelpers::registerSymbol<SymbolConstant>(sema, *this, tokNameRef);
            symbols.push_back(&sym);
        }
        else
        {
            const Symbol& sym = SemaHelpers::registerSymbol<SymbolVariable>(sema, *this, tokNameRef);
            symbols.push_back(&sym);
            if (hasFlag(AstVarDeclFlagsE::Let))
            {
                auto& symVar = sema.curViewSymbol().sym()->cast<SymbolVariable>();
                symVar.addExtraFlag(SymbolVariableFlagsE::Let);
            }
        }
    }

    sema.setSymbolList(sema.curNodeRef(), symbols.span());
    return Result::SkipChildren;
}

Result AstMultiVarDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
    {
        SemaNodeView nodeSymbolsView = sema.curViewSymbolList();
        if (!nodeSymbolsView.hasSymbolList())
            semaPreDecl(sema);
        nodeSymbolsView.recompute(sema, SemaNodeViewPartE::Symbol);
        const std::span<Symbol*> symbols = nodeSymbolsView.symList();
        for (Symbol* sym : symbols)
        {
            sym->registerAttributes(sema);
            sym->setDeclared(sema.ctx());
        }
    }

    const std::span<Symbol*> symbols = sema.curViewSymbolList().symList();
    for (const Symbol* sym : symbols)
    {
        SWC_RESULT(Match::ghosting(sema, *sym));
    }

    return Result::Continue;
}

Result AstMultiVarDecl::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeTypeRef && nodeInitRef.isValid())
    {
        const SemaNodeView nodeTypeView = sema.viewType(nodeTypeRef);
        SemaFrame          frame        = sema.frame();
        frame.pushBindingType(nodeTypeView.typeRef());
        sema.pushFramePopOnPostChild(frame, nodeInitRef);
    }

    return Result::Continue;
}

Result AstMultiVarDecl::semaPostNode(Sema& sema) const
{
    const std::span<Symbol*>  symbols = sema.curViewSymbolList().symList();
    const SemaPostVarDeclArgs context = {this, tokRef(), nodeInitRef, nodeTypeRef, flags()};
    return semaPostVarDeclCommon(sema, context, symbols);
}

Result AstVarDeclDestructuring::semaPostNode(Sema& sema) const
{
    const SemaNodeView nodeInitView = sema.viewType(nodeInitRef);
    if (!nodeInitView.type()->isStruct())
    {
        Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_decomposition_not_struct, nodeInitView.nodeRef());
        diag.addArgument(Diagnostic::ARG_TYPE, nodeInitView.typeRef());
        diag.report(sema.ctx());
        return Result::Error;
    }

    const SymbolStruct& symStruct = nodeInitView.type()->payloadSymStruct();
    const auto&         fields    = symStruct.fields();

    SmallVector<TokenRef> tokNames;
    sema.ast().appendTokens(tokNames, spanNamesRef);

    if (tokNames.size() > fields.size())
    {
        Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_decomposition_too_many_names, nodeRef(sema.ast()));
        diag.addArgument(Diagnostic::ARG_COUNT, static_cast<uint32_t>(fields.size()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    if (tokNames.size() < fields.size())
    {
        Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_decomposition_not_enough_names, nodeRef(sema.ast()));
        diag.addArgument(Diagnostic::ARG_COUNT, static_cast<uint32_t>(fields.size()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    SmallVector<Symbol*>               symbols;
    SmallVector<const SymbolVariable*> fieldsForSymbols;
    for (size_t i = 0; i < tokNames.size(); i++)
    {
        const auto& tokNameRef = tokNames[i];
        if (tokNameRef.isInvalid())
            continue;

        auto& sym = SemaHelpers::registerSymbol<SymbolVariable>(sema, *this, tokNameRef);
        if (hasFlag(AstVarDeclFlagsE::Let))
            sym.addExtraFlag(SymbolVariableFlagsE::Let);
        sym.setDeclared(sema.ctx());

        symbols.push_back(&sym);

        const SymbolVariable* field = fields[i];
        sym.setTypeRef(field->typeRef());
        sym.setTyped(sema.ctx());
        sym.setSemaCompleted(sema.ctx());
        fieldsForSymbols.push_back(field);

        SWC_RESULT(Match::ghosting(sema, sym));
    }

    sema.setSymbolList(sema.curNodeRef(), symbols.span());
    const SemaPostVarDeclArgs context = {this, tokRef(), nodeInitRef, AstNodeRef::invalid(), flags()};
    SWC_RESULT(semaPostVarDeclCommon(sema, context, symbols.span()));

    const SemaNodeView refreshedInitView = sema.viewNodeTypeConstant(nodeInitRef);
    storeDestructuringLetConstants(sema, symbols.span(), fieldsForSymbols.span(), refreshedInitView.cstRef());

    return Result::Continue;
}

Result AstInitializerExpr::semaPostNode(Sema& sema)
{
    constexpr AstModifierFlags allowed = AstModifierFlagsE::NoDrop |
                                         AstModifierFlagsE::Ref |
                                         AstModifierFlagsE::ConstRef |
                                         AstModifierFlagsE::Move |
                                         AstModifierFlagsE::MoveRaw;
    SWC_RESULT(SemaCheck::modifiers(sema, *this, modifierFlags, allowed));

    sema.inheritPayload(*this, nodeExprRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
