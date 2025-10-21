#include "pch.h"

#include "Report/DiagnosticIds.h"

DiagnosticIds::DiagnosticIds()
{
    initIds();
}

std::string_view DiagnosticIds::diagMessage(DiagnosticId id) const
{
    SWAG_ASSERT(static_cast<size_t>(id) < infos_.size());
    return infos_[static_cast<size_t>(id)].msg;
}

std::string_view DiagnosticIds::diagName(DiagnosticId id) const
{
    SWAG_ASSERT(static_cast<size_t>(id) < infos_.size());
    return infos_[static_cast<size_t>(id)].name;
}

void DiagnosticIds::addId(DiagnosticId id, const std::string_view name, const std::string_view msg)
{
    const auto index = static_cast<size_t>(id);
    if (index >= infos_.size())
        infos_.resize(index + 1);
    infos_[index] = {.id = id, .name = name, .msg = msg};
}

void DiagnosticIds::initIds()
{
#define SWAG_DIAG_DEF(id, msg) addId(DiagnosticId::id, #id, msg);
#include "DiagnosticIds.inc"
#undef SWAG_DIAG_DEF
}
