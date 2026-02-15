#pragma once
#include "Compiler/Sema/Type/TypeGen.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class DataSegment;
class TypeManager;
class TaskContext;
class TypeInfo;
struct AstNode;

namespace Runtime
{
    struct TypeInfo;
    struct TypeInfoNative;
    struct TypeInfoArray;
    struct TypeInfoStruct;
    struct TypeInfoFunc;
}

namespace TypeGenInternal
{
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

    LayoutKind layoutKindOf(const TypeInfo& type);
    TypeRef    rtTypeRefFor(const TypeManager& tm, LayoutKind kind);
    Result     ensureTypeInfoStructReady(Sema& sema, const TypeManager& tm, LayoutKind kind, TypeRef rtTypeRef, const AstNode& node);

    void initCommon(Sema& sema, DataSegment& storage, Runtime::TypeInfo& rtType, uint32_t offset, const TypeInfo& type, TypeGen::TypeGenResult& result);
    void initNative(Runtime::TypeInfoNative& rtType, const TypeInfo& type);
    void initArray(Runtime::TypeInfoArray& rtType, const TypeInfo& type);
    void initStruct(Sema& sema, DataSegment& storage, Runtime::TypeInfoStruct& rtType, uint32_t offset, const TypeInfo& type, TypeGen::TypeGenCache::Entry& entry);
    void initFunc(const Runtime::TypeInfoFunc& rtType, const TypeInfo& type);

    SmallVector<TypeRef> computeDeps(const TypeManager& tm, const TaskContext& ctx, const TypeInfo& type, LayoutKind kind);
    void                 wireRelocations(Sema& sema, const TypeGen::TypeGenCache& cache, DataSegment& storage, TypeRef key, const TypeGen::TypeGenCache::Entry& entry, LayoutKind kind);

    std::pair<uint32_t, Runtime::TypeInfo*> allocateTypeInfoPayload(DataSegment& storage, LayoutKind kind, const TypeInfo& type);
    Result                                  processTypeInfo(Sema& sema, DataSegment& storage, TypeRef typeRef, AstNodeRef ownerNodeRef, TypeGen::TypeGenResult& result, TypeGen::TypeGenCache& cache);
}

SWC_END_NAMESPACE();
