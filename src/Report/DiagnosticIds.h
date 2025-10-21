#pragma once

enum class DiagnosticId
{
#define SWAG_DIAG_DEF(id, msg) id,
#include "DiagnosticIds.inc"
#undef SWAG_DIAG_DEF
};

struct DiagnosticIdInfo
{
    DiagnosticId     id;
    std::string_view name;
    std::string_view msg;
};

class DiagnosticIds
{
public:
    DiagnosticIds();

    std::string_view diagMessage(DiagnosticId id) const;
    std::string_view diagName(DiagnosticId id) const;

private:
    std::vector<DiagnosticIdInfo> infos_;

    void addId(DiagnosticId id, std::string_view name, const std::string_view msg);
    void initIds();
};
