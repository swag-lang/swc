#pragma once

SWC_BEGIN_NAMESPACE();

enum class DiagnosticId
{
    None = 0,
#define SWC_DIAG_DEF(id, msg) id,
#include "DiagnosticIds.inc"

#undef SWC_DIAG_DEF
};

struct DiagnosticIdInfo
{
    DiagnosticId     id;
    std::string_view name;
    std::string_view msg;
};

constexpr DiagnosticIdInfo DIAGNOSTIC_INFOS[] = {
    {DiagnosticId::None, "", ""},
#define SWC_DIAG_DEF(id, msg) {DiagnosticId::id, #id, msg},
#include "DiagnosticIds.inc"

#undef SWC_DIAG_DEF
};

namespace DiagnosticIds
{
    inline std::string_view diagMessage(DiagnosticId id)
    {
        return DIAGNOSTIC_INFOS[static_cast<size_t>(id)].msg;
    }

    inline std::string_view diagName(DiagnosticId id)
    {
        return DIAGNOSTIC_INFOS[static_cast<size_t>(id)].name;
    }
}

SWC_END_NAMESPACE();
