#pragma once
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();
class Sema;
class TaskContext;
class TypeInfo;
struct SemaNodeView;
class SymbolFunction;
struct AstNode;
struct SourceCodeRange;

namespace ConstantHelpers
{
    struct ConstantPayloadWrite
    {
        uint64_t    offset   = 0;
        TypeRef     typeRef  = TypeRef::invalid();
        ConstantRef valueRef = ConstantRef::invalid();
    };

    bool        hasSourceFunctionRelocation(Sema& sema, const void* fieldPtr);
    Result      waitStaticPayloadTypeReady(Sema& sema, TypeRef typeRef, AstNodeRef waitNodeRef);
    uint64_t    materializeConstantStorageAndGetAddress(Sema& sema, const SemaNodeView& view);
    ConstantRef materializeStaticPayloadConstant(Sema& sema, TypeRef typeRef, std::span<const std::byte> payload);
    bool        typeHasUnionStorage(const TaskContext& ctx, const TypeInfo& declaredType);
    ConstantRef materializeAggregateConstructionConstant(Sema& sema, TypeRef typeRef, std::span<const ConstantPayloadWrite> writes = {});
    uint32_t    staticPayloadPlacementShardIndex(const TaskContext& ctx, const TypeInfo& originalType, std::span<const std::byte> payload, bool hasRequiredShard, uint32_t requiredShard);
    // The caller has checked that payload has typeInfo's layout size.
    bool   resolveStaticPayloadRequiredShardIndex(Sema& sema, uint32_t& outShardIndex, bool& hasRequiredShard, const TypeInfo& typeInfo, std::span<const std::byte> payload);
    Result makeSourceCodeLocation(Sema& sema, ConstantRef& outCstRef, const AstNode& node, const SymbolFunction* function = nullptr);
    Result makeSourceCodeLocation(Sema& sema, ConstantRef& outCstRef, const SourceCodeRange& codeRange, const SymbolFunction* function = nullptr);
}

SWC_END_NAMESPACE();
