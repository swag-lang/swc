#pragma once
#include "Parser/AstNode.h"
#include "Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();
class DataSegment;

struct TypeGenRecContext
{
    std::unordered_set<uint32_t> inProgress;
};

class TypeGen
{
public:
    struct TypeGenResult
    {
        std::string_view view;
        TypeRef          structTypeRef;
        uint32_t         offset = 0;
    };

    Result makeTypeInfo(Sema& sema, DataSegment& storage, TypeRef typeRef, AstNodeRef ownerNodeRef, TypeGenResult& result);

private:
    struct StorageCache
    {
        std::recursive_mutex                   mutex;
        std::unordered_map<uint32_t, uint32_t> offsets;
    };

    StorageCache& cacheFor(const DataSegment& storage);

    std::mutex                                                            cachesMutex_;
    std::unordered_map<const DataSegment*, std::unique_ptr<StorageCache>> caches_;
};

SWC_END_NAMESPACE();
