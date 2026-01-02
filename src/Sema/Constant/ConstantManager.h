#pragma once
#include "Core/Store.h"
#include "Main/CompilerInstance.h"
#include "Sema/Constant/ConstantValue.h"
#include "Sema/Core/Sema.h"

SWC_BEGIN_NAMESPACE()
class CompilerInstance;

class ConstantManager
{
public:
    void        setup(const TaskContext& ctx);
    ConstantRef addS32(const TaskContext& ctx, int32_t value);
    ConstantRef addInt(const TaskContext& ctx, uint64_t value);

    ConstantRef          addConstant(const TaskContext& ctx, const ConstantValue& value);
    ConstantRef          cstTrue() const { return cstBool_true_; }
    ConstantRef          cstFalse() const { return cstBool_false_; }
    ConstantRef          cstBool(bool value) const { return value ? cstBool_true_ : cstBool_false_; }
    ConstantRef          cstS32(int32_t value) const;
    ConstantRef          cstNegBool(ConstantRef cstRef) const { return cstRef == cstBool_true_ ? cstBool_false_ : cstBool_true_; }
    const ConstantValue& get(ConstantRef constantRef) const;

    bool            concretizeConstant(Sema& sema, ConstantRef& result, ConstantRef cstRef, TypeInfo::Sign hintSign);
    Result          concretizeConstant(Sema& sema, ConstantRef& result, AstNodeRef nodeOwnerRef, ConstantRef cstRef, TypeInfo::Sign hintSign);

private:
    struct Shard
    {
        Store                                                             store;
        std::unordered_map<ConstantValue, ConstantRef, ConstantValueHash> map;
        std::unordered_set<std::string>                                   cacheStr;
        mutable std::shared_mutex                                         mutex;
    };

    static constexpr uint32_t SHARD_BITS  = 3;
    static constexpr uint32_t SHARD_COUNT = 1u << SHARD_BITS;
    static constexpr uint32_t LOCAL_BITS  = 32 - SHARD_BITS;
    static constexpr uint32_t LOCAL_MASK  = (1u << LOCAL_BITS) - 1;
    Shard                     shards_[SHARD_COUNT];

    ConstantRef cstBool_true_  = ConstantRef::invalid();
    ConstantRef cstBool_false_ = ConstantRef::invalid();
    ConstantRef cstS32_0_      = ConstantRef::invalid();
    ConstantRef cstS32_1_      = ConstantRef::invalid();
    ConstantRef cstS32_neg1_   = ConstantRef::invalid();
};

SWC_END_NAMESPACE()
