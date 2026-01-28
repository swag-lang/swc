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
    const Identifier& getNoLock(IdentifierRef idRef) const;
    const Identifier& get(IdentifierRef idRef) const;

    IdentifierRef nameSwag() const { return nameSwag_; }
    IdentifierRef nameAttributeUsage() const { return nameAttributeUsage_; }
    IdentifierRef nameAttrMulti() const { return nameAttrMulti_; }
    IdentifierRef nameConstExpr() const { return nameConstExpr_; }
    IdentifierRef namePrintBc() const { return namePrintBc_; }
    IdentifierRef namePrintBcGen() const { return namePrintBcGen_; }
    IdentifierRef namePrintAsm() const { return namePrintAsm_; }
    IdentifierRef nameCompiler() const { return nameCompiler_; }
    IdentifierRef nameInline() const { return nameInline_; }
    IdentifierRef nameNoInline() const { return nameNoInline_; }
    IdentifierRef namePlaceHolder() const { return namePlaceHolder_; }
    IdentifierRef nameNoPrint() const { return nameNoPrint_; }
    IdentifierRef nameMacro() const { return nameMacro_; }
    IdentifierRef nameMixin() const { return nameMixin_; }
    IdentifierRef nameImplicit() const { return nameImplicit_; }
    IdentifierRef nameEnumFlags() const { return nameEnumFlags_; }
    IdentifierRef nameEnumIndex() const { return nameEnumIndex_; }
    IdentifierRef nameNoDuplicate() const { return nameNoDuplicate_; }
    IdentifierRef nameComplete() const { return nameComplete_; }
    IdentifierRef nameOverload() const { return nameOverload_; }
    IdentifierRef nameCalleeReturn() const { return nameCalleeReturn_; }
    IdentifierRef nameDiscardable() const { return nameDiscardable_; }
    IdentifierRef nameNotGeneric() const { return nameNotGeneric_; }
    IdentifierRef nameTls() const { return nameTls_; }
    IdentifierRef nameNoCopy() const { return nameNoCopy_; }
    IdentifierRef nameOpaque() const { return nameOpaque_; }
    IdentifierRef nameIncomplete() const { return nameIncomplete_; }
    IdentifierRef nameNoDoc() const { return nameNoDoc_; }
    IdentifierRef nameStrict() const { return nameStrict_; }
    IdentifierRef nameGlobal() const { return nameGlobal_; }
    IdentifierRef nameMe() const { return nameMe_; }
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
    IdentifierRef nameErrorValue() const { return nameErrorValue_; }
    IdentifierRef nameScratchAllocator() const { return nameScratchAllocator_; }
    IdentifierRef nameContext() const { return nameContext_; }
    IdentifierRef nameContextFlags() const { return nameContextFlags_; }
    IdentifierRef nameModule() const { return nameModule_; }
    IdentifierRef nameProcessInfos() const { return nameProcessInfos_; }
    IdentifierRef nameGvtd() const { return nameGvtd_; }

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

    IdentifierRef nameSwag_           = IdentifierRef::invalid();
    IdentifierRef nameAttributeUsage_ = IdentifierRef::invalid();

    // Predefined Swag attributes (bootstrap.swg) with no parameters
    IdentifierRef nameAttrMulti_   = IdentifierRef::invalid();
    IdentifierRef nameConstExpr_   = IdentifierRef::invalid();
    IdentifierRef namePrintBc_     = IdentifierRef::invalid();
    IdentifierRef namePrintBcGen_  = IdentifierRef::invalid();
    IdentifierRef namePrintAsm_    = IdentifierRef::invalid();
    IdentifierRef nameCompiler_    = IdentifierRef::invalid();
    IdentifierRef nameInline_      = IdentifierRef::invalid();
    IdentifierRef nameNoInline_    = IdentifierRef::invalid();
    IdentifierRef namePlaceHolder_ = IdentifierRef::invalid();
    IdentifierRef nameNoPrint_     = IdentifierRef::invalid();
    IdentifierRef nameMacro_       = IdentifierRef::invalid();
    IdentifierRef nameMixin_       = IdentifierRef::invalid();
    IdentifierRef nameImplicit_    = IdentifierRef::invalid();

    IdentifierRef nameEnumFlags_          = IdentifierRef::invalid();
    IdentifierRef nameEnumIndex_          = IdentifierRef::invalid();
    IdentifierRef nameNoDuplicate_        = IdentifierRef::invalid();
    IdentifierRef nameComplete_           = IdentifierRef::invalid();
    IdentifierRef nameOverload_           = IdentifierRef::invalid();
    IdentifierRef nameCalleeReturn_       = IdentifierRef::invalid();
    IdentifierRef nameDiscardable_        = IdentifierRef::invalid();
    IdentifierRef nameNotGeneric_         = IdentifierRef::invalid();
    IdentifierRef nameTls_                = IdentifierRef::invalid();
    IdentifierRef nameNoCopy_             = IdentifierRef::invalid();
    IdentifierRef nameOpaque_             = IdentifierRef::invalid();
    IdentifierRef nameIncomplete_         = IdentifierRef::invalid();
    IdentifierRef nameStrict_             = IdentifierRef::invalid();
    IdentifierRef nameNoDoc_              = IdentifierRef::invalid();
    IdentifierRef nameGlobal_             = IdentifierRef::invalid();
    IdentifierRef nameMe_                 = IdentifierRef::invalid();
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
    IdentifierRef nameErrorValue_         = IdentifierRef::invalid();
    IdentifierRef nameScratchAllocator_   = IdentifierRef::invalid();
    IdentifierRef nameContext_            = IdentifierRef::invalid();
    IdentifierRef nameContextFlags_       = IdentifierRef::invalid();
    IdentifierRef nameModule_             = IdentifierRef::invalid();
    IdentifierRef nameProcessInfos_       = IdentifierRef::invalid();
    IdentifierRef nameGvtd_               = IdentifierRef::invalid();
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
