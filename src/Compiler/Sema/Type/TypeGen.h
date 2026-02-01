#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();
class DataSegment;

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
        };

        std::mutex                         mutex;
        std::unordered_map<TypeRef, Entry> entries;
    };

    Result makeTypeInfo(Sema& sema, DataSegment& storage, TypeRef typeRef, AstNodeRef ownerNodeRef, TypeGenResult& result);

private:
    TypeGenCache& cacheFor(const DataSegment& storage);

    std::mutex                                                            cachesMutex_;
    std::unordered_map<const DataSegment*, std::unique_ptr<TypeGenCache>> caches_;
};

SWC_END_NAMESPACE();
