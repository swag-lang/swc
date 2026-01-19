#pragma once
#include "Parser/AstNode.h"
#include "Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();
class DataSegment;

class TypeGen
{
public:
    struct TypeGenResult
    {
        std::string_view view;
        TypeRef          rtTypeRef;
        uint32_t         offset = 0;
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
