#pragma once
#include "Core/Store.h"
#include "Core/StringMap.h"
#include "Lexer/SourceView.h"
#include "Math/Hash.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;

struct Identifier
{
    std::string_view name;
};

using IdentifierRef = StrongRef<Identifier>;

class IdentifierManager
{
public:
    void              setup(TaskContext&);
    IdentifierRef     addIdentifier(const TaskContext& ctx, SourceViewRef srcViewRef, TokenRef tokRef);
    IdentifierRef     addIdentifier(std::string_view name);
    IdentifierRef     addIdentifier(std::string_view name, uint32_t hash);
    const Identifier& get(IdentifierRef idRef) const;

    IdentifierRef nameSwag() const { return nameSwag_; }
    IdentifierRef nameAttributeUsage() const { return nameAttributeUsage_; }
    IdentifierRef nameEnumFlags() const { return nameEnumFlags_; }
    IdentifierRef nameStrict() const { return nameStrict_; }
    IdentifierRef nameTargetOs() const { return nameTargetOs_; }
    IdentifierRef nameTypeInfo() const { return nameTypeInfo_; }
    IdentifierRef nameTypeInfoNative() const { return nameTypeInfoNative_; }
    IdentifierRef nameTypeInfoPointer() const { return nameTypeInfoPointer_; }
    IdentifierRef nameTypeInfoStruct() const { return nameTypeInfoStruct_; }
    IdentifierRef nameTypeInfoFunc() const { return nameTypeInfoFunc_; }
    IdentifierRef nameTypeInfoEnum() const { return nameTypeInfoEnum_; }
    IdentifierRef nameTypeInfoArray() const { return nameTypeInfoArray_; }
    IdentifierRef nameTypeInfoSlice() const { return nameTypeInfoSlice_; }
    IdentifierRef nameTypeInfoAlias() const { return nameTypeInfoAlias_; }
    IdentifierRef nameTypeInfoVariadic() const { return nameTypeInfoVariadic_; }
    IdentifierRef nameTypeInfoGeneric() const { return nameTypeInfoGeneric_; }
    IdentifierRef nameTypeInfoNamespace() const { return nameTypeInfoNamespace_; }
    IdentifierRef nameTypeInfoCodeBlock() const { return nameTypeInfoCodeBlock_; }
    IdentifierRef nameTypeInfoKind() const { return nameTypeInfoKind_; }
    IdentifierRef nameTypeInfoNativeKind() const { return nameTypeInfoNativeKind_; }
    IdentifierRef nameTypeInfoFlags() const { return nameTypeInfoFlags_; }
    IdentifierRef nameTypeValue() const { return nameTypeValue_; }
    IdentifierRef nameTypeValueFlags() const { return nameTypeValueFlags_; }
    IdentifierRef nameAttribute() const { return nameAttribute_; }
    IdentifierRef nameAttributeParam() const { return nameAttributeParam_; }
    IdentifierRef nameInterface() const { return nameInterface_; }
    IdentifierRef nameSourceCodeLocation() const { return nameSourceCodeLocation_; }
    IdentifierRef nameContext() const { return nameContext_; }

private:
    struct Shard
    {
        Store                     store;
        StringMap<IdentifierRef>  map;
        mutable std::shared_mutex mutex;
    };

    static constexpr uint32_t SHARD_BITS  = 3;
    static constexpr uint32_t SHARD_COUNT = 1u << SHARD_BITS;
    static constexpr uint32_t LOCAL_BITS  = 32 - SHARD_BITS;
    static constexpr uint32_t LOCAL_MASK  = (1u << LOCAL_BITS) - 1;
    Shard                     shards_[SHARD_COUNT];

    IdentifierRef nameSwag_               = IdentifierRef::invalid();
    IdentifierRef nameAttributeUsage_     = IdentifierRef::invalid();
    IdentifierRef nameEnumFlags_          = IdentifierRef::invalid();
    IdentifierRef nameStrict_             = IdentifierRef::invalid();
    IdentifierRef nameTargetOs_           = IdentifierRef::invalid();
    IdentifierRef nameTypeInfo_           = IdentifierRef::invalid();
    IdentifierRef nameTypeInfoNative_     = IdentifierRef::invalid();
    IdentifierRef nameTypeInfoPointer_    = IdentifierRef::invalid();
    IdentifierRef nameTypeInfoStruct_     = IdentifierRef::invalid();
    IdentifierRef nameTypeInfoFunc_       = IdentifierRef::invalid();
    IdentifierRef nameTypeInfoEnum_       = IdentifierRef::invalid();
    IdentifierRef nameTypeInfoArray_      = IdentifierRef::invalid();
    IdentifierRef nameTypeInfoSlice_      = IdentifierRef::invalid();
    IdentifierRef nameTypeInfoAlias_      = IdentifierRef::invalid();
    IdentifierRef nameTypeInfoVariadic_   = IdentifierRef::invalid();
    IdentifierRef nameTypeInfoGeneric_    = IdentifierRef::invalid();
    IdentifierRef nameTypeInfoNamespace_  = IdentifierRef::invalid();
    IdentifierRef nameTypeInfoCodeBlock_  = IdentifierRef::invalid();
    IdentifierRef nameTypeInfoKind_       = IdentifierRef::invalid();
    IdentifierRef nameTypeInfoNativeKind_ = IdentifierRef::invalid();
    IdentifierRef nameTypeInfoFlags_      = IdentifierRef::invalid();
    IdentifierRef nameTypeValue_          = IdentifierRef::invalid();
    IdentifierRef nameTypeValueFlags_     = IdentifierRef::invalid();
    IdentifierRef nameAttribute_          = IdentifierRef::invalid();
    IdentifierRef nameAttributeParam_     = IdentifierRef::invalid();
    IdentifierRef nameInterface_          = IdentifierRef::invalid();
    IdentifierRef nameSourceCodeLocation_ = IdentifierRef::invalid();
    IdentifierRef nameContext_            = IdentifierRef::invalid();
};

SWC_END_NAMESPACE();

template<>
struct std::hash<swc::IdentifierRef>
{
    size_t operator()(const swc::IdentifierRef& r) const noexcept
    {
        return swc::Math::hash(r.get());
    }
};
