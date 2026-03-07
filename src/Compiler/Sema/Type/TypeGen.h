#pragma once
#include "Compiler/Parser/Ast/AstNode.h"

SWC_BEGIN_NAMESPACE();
class Sema;
class DataSegment;
class TypeManager;
class TaskContext;
class TypeInfo;

namespace Runtime
{
    struct TypeInfo;
}

class TypeGen
{
public:
    struct TypeGenResult
    {
        ByteSpan span;
        TypeRef  rtTypeRef;
        uint32_t offset = 0;
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
            uint32_t             offset = 0;
            TypeRef              rtTypeRef;
            State                state = State::CommonInit;
            SmallVector<TypeRef> deps;
            uint32_t             structFieldsOffset = 0;
            uint32_t             structFieldsCount  = 0;
            SmallVector<TypeRef> structFieldTypes;
            uint32_t             funcParamsOffset = 0;
            uint32_t             funcParamsCount  = 0;
            SmallVector<TypeRef> funcParamTypes;
            TypeRef              funcReturnTypeRef = TypeRef::invalid();
        };

        std::mutex                         mutex;
        std::unordered_map<TypeRef, Entry> entries;
    };

    Result  makeTypeInfo(Sema& sema, DataSegment& storage, TypeRef typeRef, AstNodeRef ownerNodeRef, TypeGenResult& result);
    TypeRef getBackTypeRef(const void* ptr) const;

private:
    enum class LayoutKind
    {
        Base,
        Native,
        Enum,
        Array,
        Slice,
        Pointer,
        Struct,
        Alias,
        Variadic,
        TypedVariadic,
        Func,
    };

    TypeGenCache&                           cacheFor(const DataSegment& storage);
    LayoutKind                              layoutKindOf(const TypeInfo& type) const;
    Result                                  rtTypeRefFor(Sema& sema, LayoutKind kind, TypeRef& typeRef, const SourceCodeRef& codeRef) const;
    void                                    initTypeInfoPayload(Sema& sema, DataSegment& storage, Runtime::TypeInfo& rtType, uint32_t offset, LayoutKind kind, const TypeInfo& type, TypeGenCache::Entry& entry) const;
    SmallVector<TypeRef>                    computeDeps(const TypeManager& tm, const TaskContext& ctx, const TypeInfo& type, LayoutKind kind) const;
    void                                    wireRelocations(Sema& sema, const TypeGenCache& cache, DataSegment& storage, TypeRef key, const TypeGenCache::Entry& entry, LayoutKind kind) const;
    std::pair<uint32_t, Runtime::TypeInfo*> allocateTypeInfoPayload(DataSegment& storage, LayoutKind kind) const;

    Result processTypeInfo(Sema& sema, TypeGenResult& result, DataSegment& storage, TypeRef typeRef, AstNodeRef ownerNodeRef, TypeGenCache& cache) const;

    std::mutex                                                            cachesMutex_;
    std::unordered_map<const DataSegment*, std::unique_ptr<TypeGenCache>> caches_;
    mutable std::mutex                                                    ptrToTypeMutex_;
    std::unordered_map<const void*, TypeRef>                              ptrToType_;
};

SWC_END_NAMESPACE();
