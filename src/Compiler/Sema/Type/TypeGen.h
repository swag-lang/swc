#pragma once
#include <span>

#include "Compiler/Parser/Ast/AstNode.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class DataSegment;
class TypeManager;
class TaskContext;
class TypeInfo;
class SymbolFunction;
class SymbolImpl;

namespace Runtime
{
    struct TypeInfo;
}

class TypeGen
{
public:
    enum class LockMode : uint8_t
    {
        Wait,
        TryLock,
    };

    struct TypeGenResult
    {
        std::span<const std::byte> span;
        TypeRef                    rtTypeRef;
        uint32_t                   offset = 0;
    };

    struct TypeGenCache
    {
        enum class State : uint8_t
        {
            CommonInit,
            Done,
        };

        struct Entry
        {
            uint32_t                           offset = 0;
            TypeRef                            rtTypeRef;
            State                              state            = State::CommonInit;
            bool                               backRefPublished = false;
            SmallVector<TypeRef>               deps;
            uint32_t                           enumValuesOffset   = 0;
            uint32_t                           enumValuesCount    = 0;
            uint32_t                           structFieldsOffset = 0;
            uint32_t                           structFieldsCount  = 0;
            SmallVector<TypeRef>               structFieldTypes;
            uint32_t                           structMethodsOffset = 0;
            uint32_t                           structMethodsCount  = 0;
            SmallVector<TypeRef>               structMethodTypes;
            std::vector<const SymbolFunction*> structMethods;
            uint32_t                           structInterfacesOffset = 0;
            uint32_t                           structInterfacesCount  = 0;
            SmallVector<TypeRef>               structInterfaceTypes;
            std::vector<const SymbolImpl*>     structInterfaces;
            TypeRef                            structFromGenericTypeRef = TypeRef::invalid();
            uint32_t                           structGenericsOffset     = 0;
            uint32_t                           structGenericsCount      = 0;
            SmallVector<TypeRef>               structGenericTypes;
            uint32_t                           usingFieldsOffset = 0;
            uint32_t                           usingFieldsCount  = 0;
            SmallVector<TypeRef>               usingFieldTypes;
            uint32_t                           funcParamsOffset = 0;
            uint32_t                           funcParamsCount  = 0;
            SmallVector<TypeRef>               funcParamTypes;
            uint32_t                           funcGenericsOffset = 0;
            uint32_t                           funcGenericsCount  = 0;
            SmallVector<TypeRef>               funcGenericTypes;
            TypeRef                            funcReturnTypeRef = TypeRef::invalid();
        };

        mutable std::shared_mutex          mutex;
        std::unordered_map<TypeRef, Entry> entries;
        SmallVector<TypeRef>               pendingBackRefs;
    };

    struct LifecycleFlags
    {
        bool hasPostCopy = false;
        bool hasPostMove = false;
        bool hasDrop     = false;
        bool canCopy     = true;
    };

    Result  makeTypeInfo(Sema& sema, DataSegment& storage, TypeRef typeRef, AstNodeRef ownerNodeRef, TypeGenResult& result, LockMode lockMode = LockMode::Wait);
    TypeRef getBackTypeRef(const void* ptr) const;

    static LifecycleFlags lifecycleFlagsOfType(TaskContext& ctx, const TypeInfo& type);
    static LifecycleFlags lifecycleFlagsOfTypeRef(TaskContext& ctx, TypeRef typeRef);

private:
    enum class LayoutKind
    {
        Base,
        Native,
        Enum,
        Array,
        Slice,
        Pointer,
        Interface,
        Struct,
        Alias,
        Variadic,
        TypedVariadic,
        CodeBlock,
        Func,
    };

    TypeGenCache&                                  cacheFor(const DataSegment& storage);
    static LayoutKind                              layoutKindOf(const TypeInfo& type);
    static Result                                  rtTypeRefFor(Sema& sema, LayoutKind kind, TypeRef& typeRef, const SourceCodeRef& codeRef);
    static void                                    initTypeInfoPayload(Sema& sema, DataSegment& storage, Runtime::TypeInfo& rtType, uint32_t offset, LayoutKind kind, const TypeInfo& type, TypeGenCache::Entry& entry);
    static SmallVector<TypeRef>                    computeDeps(TypeManager& tm, Sema& sema, const TypeInfo& type, LayoutKind kind);
    static void                                    wireRelocations(Sema& sema, const TypeGenCache& cache, DataSegment& storage, TypeRef key, const TypeGenCache::Entry& entry, LayoutKind kind);
    static std::pair<uint32_t, Runtime::TypeInfo*> allocateTypeInfoPayload(DataSegment& storage, LayoutKind kind);
    static TypeRef                                 resolveArrayPointedTypeRef(TypeManager& tm, const TypeInfo& arrayType);
    static TypeRef                                 resolveArrayFinalTypeRef(const TypeManager& tm, const TaskContext& ctx, const TypeInfo& arrayType);

    static Result processTypeInfo(Sema& sema, TypeGenResult& result, DataSegment& storage, TypeRef typeRef, AstNodeRef ownerNodeRef, TypeGenCache& cache);

    mutable std::shared_mutex                                             cachesMutex_;
    std::unordered_map<const DataSegment*, std::unique_ptr<TypeGenCache>> caches_;
    mutable std::shared_mutex                                             ptrToTypeMutex_;
    std::unordered_map<const void*, TypeRef>                              ptrToType_;
};

SWC_END_NAMESPACE();
