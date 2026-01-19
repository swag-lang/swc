#pragma once

#include <mutex>
#include <unordered_map>
#include <vector>

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
        TypeRef          structTypeRef;
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
            uint32_t offset = 0;
            TypeRef  structTypeRef;
            State    state = State::CommonInit;

            // Flattened list of dependencies that must be completed before this type can be marked as Done.
            std::vector<uint32_t> deps;
        };

        std::mutex                          mutex;
        std::unordered_map<uint32_t, Entry> entries;
    };

    Result makeTypeInfo(Sema& sema, DataSegment& storage, TypeRef typeRef, AstNodeRef ownerNodeRef, TypeGenResult& result);

private:
    TypeGenCache& cacheFor(const DataSegment& storage);

    std::mutex                                                            cachesMutex_;
    std::unordered_map<const DataSegment*, std::unique_ptr<TypeGenCache>> caches_;
};

SWC_END_NAMESPACE();
