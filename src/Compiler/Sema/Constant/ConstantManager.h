#pragma once
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Support/Core/DataSegment.h"

SWC_BEGIN_NAMESPACE();
class CompilerInstance;

class ConstantManager
{
public:
    void             setup(TaskContext& ctx);
    ConstantRef      addS32(TaskContext& ctx, int32_t value);
    ConstantRef      addInt(TaskContext& ctx, uint64_t value);
    std::string_view addString(const TaskContext& ctx, std::string_view str);
    ConstantRef      addConstant(TaskContext& ctx, const ConstantValue& value);
    std::string_view addPayloadBuffer(std::string_view payload);

    ConstantRef          cstNull() const { return cstNull_; }
    ConstantRef          cstUndefined() const { return cstUndefined_; }
    ConstantRef          cstTrue() const { return cstBool_true_; }
    ConstantRef          cstFalse() const { return cstBool_false_; }
    ConstantRef          cstBool(bool value) const { return value ? cstBool_true_ : cstBool_false_; }
    ConstantRef          cstS32(int32_t value) const;
    ConstantRef          cstNegBool(ConstantRef cstRef) const { return cstRef == cstBool_true_ ? cstBool_false_ : cstBool_true_; }
    const ConstantValue& get(ConstantRef constantRef) const;

    Result  makeTypeInfo(Sema& sema, ConstantRef& outRef, TypeRef typeRef, AstNodeRef ownerNodeRef);
    TypeRef getBackTypeInfoTypeRef(Sema& sema, ConstantRef cstRef) const;

    struct Shard
    {
        DataSegment                                                       dataSegment;
        std::unordered_map<ConstantValue, ConstantRef, ConstantValueHash> map;
        mutable std::shared_mutex                                         mutex;
    };

    static constexpr uint32_t SHARD_BITS  = 3;
    static constexpr uint32_t SHARD_COUNT = 1u << SHARD_BITS;
    static constexpr uint32_t LOCAL_BITS  = 32 - SHARD_BITS;
    static constexpr uint32_t LOCAL_MASK  = (1u << LOCAL_BITS) - 1;

private:
    Shard shards_[SHARD_COUNT];

    ConstantRef cstBool_true_  = ConstantRef::invalid();
    ConstantRef cstBool_false_ = ConstantRef::invalid();
    ConstantRef cstS32_0_      = ConstantRef::invalid();
    ConstantRef cstS32_1_      = ConstantRef::invalid();
    ConstantRef cstS32_neg1_   = ConstantRef::invalid();
    ConstantRef cstNull_       = ConstantRef::invalid();
    ConstantRef cstUndefined_  = ConstantRef::invalid();
};

SWC_END_NAMESPACE();
