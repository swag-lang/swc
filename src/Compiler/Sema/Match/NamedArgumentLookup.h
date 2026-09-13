#pragma once
#include "Support/Core/RefTypes.h"
#include <optional>
#include <span>
#include <unordered_map>

SWC_BEGIN_NAMESPACE();

namespace Match
{
    // One lookup belongs to one call's parameter list and receiver boundary.
    class NamedArgumentLookup
    {
    public:
        template<typename Param>
        bool tryFind(uint32_t& outIndex, std::span<const Param> params, IdentifierRef idRef, uint32_t paramStart)
        {
            // Small calls keep the linear lookup. Long named-argument lists build one
            // local index instead of rescanning every parameter for every argument.
            if (++namedLookups_ > 8 && params.size() > paramStart + 16 && !namedParamIndices_)
            {
                namedParamIndices_.emplace();
                namedParamIndices_->reserve(params.size() - paramStart);
                for (uint32_t i = paramStart; i < params.size(); ++i)
                    namedParamIndices_->try_emplace(params[i].idRef, i);
            }

            if (namedParamIndices_)
            {
                const auto it = namedParamIndices_->find(idRef);
                if (it == namedParamIndices_->end())
                    return false;
                outIndex = it->second;
                return true;
            }

            for (uint32_t i = paramStart; i < params.size(); ++i)
            {
                if (params[i].idRef == idRef)
                {
                    outIndex = i;
                    return true;
                }
            }

            return false;
        }

    private:
        uint32_t                                                   namedLookups_ = 0;
        std::optional<std::unordered_map<IdentifierRef, uint32_t>> namedParamIndices_;
    };
}

SWC_END_NAMESPACE();
