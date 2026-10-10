#pragma once
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Support/Core/PagedStore.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class SymbolFunction;
class SymbolStruct;
struct SemaNodeView;
class TaskContext;
class CompilerInstance;
enum class TokenId : uint16_t;

enum class RuntimeTypeKind : uint32_t
{
    TargetOs,
    TargetArch,
    CompilerCommand,
    Operator,
    TypeInfoKind,
    TypeInfoNativeKind,
    TypeInfoFlags,
    TypeValueFlags,
    TypeInfo,
    TypeInfoNative,
    TypeInfoPointer,
    TypeInfoStruct,
    TypeInfoFunc,
    TypeInfoEnum,
    TypeInfoArray,
    TypeInfoSlice,
    TypeInfoAlias,
    TypeInfoVariadic,
    TypeInfoGeneric,
    TypeInfoNamespace,
    TypeInfoCodeBlock,
    TypeInfoSimd,
    TypeValue,
    Attribute,
    AttributeParam,
    Interface,
    SourceCodeLocation,
    ErrorValue,
    ScratchAllocator,
    Context,
    ContextFlags,
    Module,
    ProcessInfos,
    Gvtd,
    BuildCfg,
    Count
};

class TypeManager
{
public:
    void setup(TaskContext& ctx);

    TypeRef typeBool() const { return typeBool_; }
    TypeRef typeChar() const { return typeChar_; }
    TypeRef typeString() const { return typeString_; }
    TypeRef typeAny() const { return typeAny_; }
    TypeRef typeVoid() const { return typeVoid_; }
    TypeRef typeNull() const { return typeNull_; }
    TypeRef typeRune() const { return typeRune_; }
    TypeRef typeCString() const { return typeCString_; }
    TypeRef typeVariadic() const { return typeVariadic_; }
    TypeRef typeTypeInfo() const { return typeTypeInfo_; }

    TypeRef typeBlockPtrVoid() const { return typeBlockPtrVoid_; }
    TypeRef typeConstBlockPtrVoid() const { return typeConstBlockPtrVoid_; }
    TypeRef typeBlockPtrU8() const { return typeBlockPtrU8_; }
    TypeRef typeConstBlockPtrU8() const { return typeConstBlockPtrU8_; }
    TypeRef typeValuePtrVoid() const { return typeValuePtrVoid_; }
    TypeRef typeConstValuePtrVoid() const { return typeConstValuePtrVoid_; }
    TypeRef typeValuePtrU8() const { return typeValuePtrU8_; }
    TypeRef typeConstValuePtrU8() const { return typeConstValuePtrU8_; }

    // Maps a native type keyword ('s32', 'bool', ...) to its type. Invalid for any other token.
    TypeRef builtinType(TokenId tokenId) const;

    TypeRef typeInt(uint32_t bits, TypeInfo::Sign sign) const;
    TypeRef typeInt() const { return typeInt_; }
    TypeRef typeIntSigned() const { return typeIntSigned_; }
    TypeRef typeIntUnsigned() const { return typeIntUnsigned_; }
    TypeRef typeFloat(uint32_t bits) const;
    TypeRef typeF32() const { return typeF32_; }
    TypeRef typeF64() const { return typeF64_; }
    TypeRef typeS8() const { return typeS8_; }
    TypeRef typeU8() const { return typeU8_; }
    TypeRef typeS16() const { return typeS16_; }
    TypeRef typeU16() const { return typeU16_; }
    TypeRef typeS32() const { return typeS32_; }
    TypeRef typeU32() const { return typeU32_; }
    TypeRef typeS64() const { return typeS64_; }
    TypeRef typeU64() const { return typeU64_; }

    TypeRef         addType(const TypeInfo& typeInfo);
    // Intern an array or aggregate type from its parts, like addType of the matching
    // TypeInfo::make*. A type that already exists is found without building its payload.
    TypeRef addArrayType(std::span<const uint64_t> dims, TypeRef elementTypeRef, TypeInfoFlags flags = TypeInfoFlagsE::Zero, std::span<const TypeRef> indexTypeRefs = {});
    TypeRef addArrayTypeAfterFirstDimension(const TypeInfo& arrayType);
    TypeRef addAggregateStructType(std::span<const IdentifierRef> names, std::span<const TypeRef> types);
    TypeRef addAggregateArrayType(std::span<const TypeRef> types);
    const TypeInfo& get(TypeRef typeRef) const;
    TypeRef         unwrapAliasEnum(const TaskContext& ctx, TypeRef typeRef) const;
    TypeRef         unwrapNonStrictAlias(TypeRef typeRef) const;
    TypeRef         promote(TypeRef lhs, TypeRef rhs, bool force32BitInts) const;
    static uint32_t chooseConcreteScalarWidth(uint32_t minRequiredBits, bool& overflow);

    // Strips aliases only, leaving an enum wrapper in place; an invalid reference is handed
    // straight back. Inline because operator-overload resolution asks it of every operand.
    TypeRef unwrapAlias(const TaskContext& ctx, TypeRef typeRef) const
    {
        if (typeRef.isInvalid())
            return typeRef;
        const TypeInfo& typeInfo = get(typeRef);
        if (!typeInfo.isAlias())
            return typeRef;
        return typeInfo.unwrap(ctx, typeRef, TypeExpandE::Alias);
    }

    // Like unwrapAliasEnum, but keeps the type itself when it is neither an alias nor an enum.
    // Inline, and reaching TypeInfo directly, because the cast paths call it on every operand.
    TypeRef unwrapAliasEnumOrSelf(const TaskContext& ctx, TypeRef typeRef) const
    {
        if (!typeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& typeInfo = get(typeRef);
        if (!typeInfo.isAlias() && !typeInfo.isEnum())
            return typeRef;

        const TypeRef unwrappedTypeRef = typeInfo.unwrapAliasEnum(ctx, typeRef);
        return unwrappedTypeRef.isValid() ? unwrappedTypeRef : typeRef;
    }

    // Selects one of 'SymbolStruct::opDrop', 'opPostCopy' or 'opPostMove'.
    using LifecycleOperator = const SymbolFunction* (SymbolStruct::*) () const;

    // True when the type, or anything inside it, declares that lifecycle operator directly.
    // Aliases and array element types are transparent, and a struct is also reached through
    // its fields. Generated wrappers are deliberately not consulted, so the answer never
    // depends on when they were built.
    bool hasLifecycleOperator(const TaskContext& ctx, TypeRef typeRef, LifecycleOperator lifecycleOperator) const;

    bool    isTypeInfoRuntimeStruct(IdentifierRef idRef) const;
    bool    isRuntimeTypeInfoPointer(const TaskContext& ctx, TypeRef typeRef) const;
    void    registerRuntimeType(IdentifierRef idRef, TypeRef typeRef);
    TypeRef runtimeType(RuntimeTypeKind kind) const;
    TypeRef runtimeType(IdentifierManager::PredefinedName name) const;

    TypeRef structTypeInfo() const { return runtimeType(RuntimeTypeKind::TypeInfo); }
    TypeRef structTypeInfoNative() const { return runtimeType(RuntimeTypeKind::TypeInfoNative); }
    TypeRef structTypeInfoPointer() const { return runtimeType(RuntimeTypeKind::TypeInfoPointer); }
    TypeRef structTypeInfoStruct() const { return runtimeType(RuntimeTypeKind::TypeInfoStruct); }
    TypeRef structTypeInfoFunc() const { return runtimeType(RuntimeTypeKind::TypeInfoFunc); }
    TypeRef structTypeInfoEnum() const { return runtimeType(RuntimeTypeKind::TypeInfoEnum); }
    TypeRef structTypeInfoArray() const { return runtimeType(RuntimeTypeKind::TypeInfoArray); }
    TypeRef structTypeInfoSlice() const { return runtimeType(RuntimeTypeKind::TypeInfoSlice); }
    TypeRef structTypeInfoAlias() const { return runtimeType(RuntimeTypeKind::TypeInfoAlias); }
    TypeRef structTypeInfoVariadic() const { return runtimeType(RuntimeTypeKind::TypeInfoVariadic); }
    TypeRef structTypeInfoGeneric() const { return runtimeType(RuntimeTypeKind::TypeInfoGeneric); }
    TypeRef structTypeInfoNamespace() const { return runtimeType(RuntimeTypeKind::TypeInfoNamespace); }
    TypeRef structTypeInfoCodeBlock() const { return runtimeType(RuntimeTypeKind::TypeInfoCodeBlock); }
    TypeRef structTypeValue() const { return runtimeType(RuntimeTypeKind::TypeValue); }
    TypeRef structAttribute() const { return runtimeType(RuntimeTypeKind::Attribute); }
    TypeRef structAttributeParam() const { return runtimeType(RuntimeTypeKind::AttributeParam); }
    TypeRef structInterface() const { return runtimeType(RuntimeTypeKind::Interface); }
    TypeRef structSourceCodeLocation() const { return runtimeType(RuntimeTypeKind::SourceCodeLocation); }
    TypeRef structErrorValue() const { return runtimeType(RuntimeTypeKind::ErrorValue); }
    TypeRef structScratchAllocator() const { return runtimeType(RuntimeTypeKind::ScratchAllocator); }
    TypeRef structContext() const { return runtimeType(RuntimeTypeKind::Context); }
    TypeRef structModule() const { return runtimeType(RuntimeTypeKind::Module); }
    TypeRef structProcessInfos() const { return runtimeType(RuntimeTypeKind::ProcessInfos); }
    TypeRef structGvtd() const { return runtimeType(RuntimeTypeKind::Gvtd); }
    TypeRef structBuildCfg() const { return runtimeType(RuntimeTypeKind::BuildCfg); }

    TypeRef enumContextFlags() const { return runtimeType(RuntimeTypeKind::ContextFlags); }
    TypeRef enumTargetOs() const { return runtimeType(RuntimeTypeKind::TargetOs); }
    TypeRef enumTargetArch() const { return runtimeType(RuntimeTypeKind::TargetArch); }
    TypeRef enumCompilerCommand() const { return runtimeType(RuntimeTypeKind::CompilerCommand); }
    TypeRef enumOperator() const { return runtimeType(RuntimeTypeKind::Operator); }
    TypeRef enumTypeInfoKind() const { return runtimeType(RuntimeTypeKind::TypeInfoKind); }
    TypeRef enumTypeInfoNativeKind() const { return runtimeType(RuntimeTypeKind::TypeInfoNativeKind); }
    TypeRef enumTypeInfoFlags() const { return runtimeType(RuntimeTypeKind::TypeInfoFlags); }
    TypeRef enumTypeValueFlags() const { return runtimeType(RuntimeTypeKind::TypeValueFlags); }

private:
    static constexpr uint32_t INTERN_STRIPE_BITS  = 4;
    static constexpr uint32_t INTERN_STRIPE_COUNT = 1u << INTERN_STRIPE_BITS;

    struct StoredTypeDeleter
    {
        // The shard owns the bytes; the intern table owns the payload's lifetime.
        void operator()(TypeInfo* type) const noexcept { std::destroy_at(type); }
    };
    using StoredType = std::unique_ptr<TypeInfo, StoredTypeDeleter>;

    struct StoredTypeHash
    {
        using is_transparent = void;
        size_t operator()(const StoredType& type) const noexcept { return type->hash(); }
        size_t operator()(const TypeInfo& type) const noexcept { return type.hash(); }
    };

    struct StoredTypeEqual
    {
        using is_transparent = void;
        bool operator()(const StoredType& lhs, const StoredType& rhs) const noexcept { return *lhs == *rhs; }
        bool operator()(const StoredType& lhs, const TypeInfo& rhs) const noexcept { return *lhs == rhs; }
        bool operator()(const TypeInfo& lhs, const StoredType& rhs) const noexcept { return lhs == *rhs; }
    };

    // Open-addressed and append-only: a slot, once filled, keeps its type. Readers probe it
    // without a lock; writers fill it under the stripe mutex, hash before type.
    struct InternTable
    {
        std::unique_ptr<std::atomic<const TypeInfo*>[]> types;
        std::unique_ptr<std::atomic<size_t>[]>          hashes;
        uint32_t                                        capacity = 0; // power of two
        uint32_t                                        size     = 0; // writer-only
    };

    // Each stripe owns its cache line: neighbours locked by other workers must not share it.
    // 'map' owns the interned payloads; 'table' answers lookups without a lock. Every table
    // generation stays alive with the stripe, for readers still probing an older one.
    struct alignas(64) InternStripe
    {
        std::unordered_set<StoredType, StoredTypeHash, StoredTypeEqual> map;
        std::atomic<InternTable*>                                       table = nullptr;
        std::vector<std::unique_ptr<InternTable>>                       tables;
        std::mutex                                                      mutex; // writers only
    };

    struct Shard
    {
        // Keep storage alive until all interned payloads have been destroyed.
        PagedStore                                    store;
        std::array<InternStripe, INTERN_STRIPE_COUNT> internStripes;
        mutable std::mutex                            storeMutex;
    };

    static constexpr uint32_t SHARD_BITS  = 3;
    static constexpr uint32_t SHARD_COUNT = 1u << SHARD_BITS;
    static constexpr uint32_t LOCAL_BITS  = 32 - SHARD_BITS;
    static constexpr uint32_t LOCAL_MASK  = (1u << LOCAL_BITS) - 1;
    CompilerInstance*         compiler_   = nullptr;
    Shard                     shards_[SHARD_COUNT];

    static TypeRef findInterned(const InternTable* table, const TypeInfo& typeInfo, size_t hash) noexcept;
    template<typename Matches>
    static TypeRef     findInternedIf(const InternTable* table, size_t hash, const Matches& matches) noexcept;
    const InternTable* publishedInternTable(uint32_t stableHash) const noexcept;
    static void    publishInterned(InternStripe& stripe, const TypeInfo* type, size_t hash);

    // Runtime types
    std::unordered_map<IdentifierRef, RuntimeTypeKind>                               mapRtKind_;
    std::array<std::atomic<uint32_t>, static_cast<uint32_t>(RuntimeTypeKind::Count)> runtimeTypeRefs_{};

    // Predefined types
    TypeRef typeBool_              = TypeRef::invalid();
    TypeRef typeChar_              = TypeRef::invalid();
    TypeRef typeString_            = TypeRef::invalid();
    TypeRef typeIntUnsigned_       = TypeRef::invalid();
    TypeRef typeIntSigned_         = TypeRef::invalid();
    TypeRef typeInt_               = TypeRef::invalid();
    TypeRef typeFloat_             = TypeRef::invalid();
    TypeRef typeU8_                = TypeRef::invalid();
    TypeRef typeU16_               = TypeRef::invalid();
    TypeRef typeU32_               = TypeRef::invalid();
    TypeRef typeU64_               = TypeRef::invalid();
    TypeRef typeS8_                = TypeRef::invalid();
    TypeRef typeS16_               = TypeRef::invalid();
    TypeRef typeS32_               = TypeRef::invalid();
    TypeRef typeS64_               = TypeRef::invalid();
    TypeRef typeF32_               = TypeRef::invalid();
    TypeRef typeF64_               = TypeRef::invalid();
    TypeRef typeAny_               = TypeRef::invalid();
    TypeRef typeVoid_              = TypeRef::invalid();
    TypeRef typeNull_              = TypeRef::invalid();
    TypeRef typeRune_              = TypeRef::invalid();
    TypeRef typeCString_           = TypeRef::invalid();
    TypeRef typeBlockPtrVoid_      = TypeRef::invalid();
    TypeRef typeConstBlockPtrVoid_ = TypeRef::invalid();
    TypeRef typeBlockPtrU8_        = TypeRef::invalid();
    TypeRef typeConstBlockPtrU8_   = TypeRef::invalid();
    TypeRef typeValuePtrVoid_      = TypeRef::invalid();
    TypeRef typeConstValuePtrVoid_ = TypeRef::invalid();
    TypeRef typeValuePtrU8_        = TypeRef::invalid();
    TypeRef typeConstValuePtrU8_   = TypeRef::invalid();
    TypeRef typeVariadic_          = TypeRef::invalid();
    TypeRef typeTypeInfo_          = TypeRef::invalid();

    std::vector<std::vector<TypeRef>>      promoteTable_;
    std::unordered_map<uint32_t, uint32_t> promoteIndex_;

    TypeRef computePromotion(TypeRef lhsRef, TypeRef rhsRef) const;
    void    buildPromoteTable();
};

SWC_END_NAMESPACE();
