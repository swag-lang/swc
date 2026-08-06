#pragma once
#include "Support/Core/SmallVector.h"
#include "Support/Core/Utf8.h"
#include "Support/Report/DiagnosticDef.h"

SWC_BEGIN_NAMESPACE();

// One layer of warning decisions. Three layers exist: the command line, the module build
// configuration, and the '#[Swag.Warning]' attributes in scope where a warning is raised.
// A layer holds at most one blanket decision and at most one decision per named warning.
//
// A warning is named by its diagnostic identifier, the same string '--diagnostic-id'
// prints and a 'swc-expected-warning' directive matches on.
class WarningPolicy
{
public:
    // Stands for every warning wherever a warning list is accepted.
    static constexpr std::string_view ALL = "all";

    void reset();
    bool empty() const { return !blanketLevel_.has_value() && levels_.empty(); }

    void setBlanketLevel(WarningLevel level) { blanketLevel_ = level; }
    void setLevel(DiagnosticId id, WarningLevel level);

    std::optional<WarningLevel> blanketLevel() const { return blanketLevel_; }
    std::optional<WarningLevel> levelOf(DiagnosticId id) const;

    // Reads "id|id|..." ('|' and ',' both separate) and gives every named warning 'level'.
    // Returns the first name that is not a warning identifier, if there is one.
    std::optional<Utf8> addList(std::string_view names, WarningLevel level);

    static bool              isWarningId(DiagnosticId id);
    static DiagnosticId      findId(std::string_view name);
    static std::vector<Utf8> allIdNames();

private:
    struct Entry
    {
        DiagnosticId id    = DiagnosticId::None;
        WarningLevel level = WarningLevel::Warning;
    };

    SmallVector4<Entry>         levels_;
    std::optional<WarningLevel> blanketLevel_;
};

// What the layers say about one warning at one report site. The source layer arrives as two
// plain levels rather than a policy, because it is resolved where the attributes are in scope.
struct WarningLevelQuery
{
    DiagnosticId                id       = DiagnosticId::None;
    const WarningPolicy*        cmdLine  = nullptr;
    const WarningPolicy*        buildCfg = nullptr;
    std::optional<WarningLevel> sourceBlanketLevel;
    std::optional<WarningLevel> sourceLevel;
};

// Settles how one warning is reported. A decision that names the warning outranks a blanket
// decision, and at equal reach the innermost layer wins: source attribute, then build
// configuration, then command line.
WarningLevel resolveWarningLevel(const WarningLevelQuery& query);

SWC_END_NAMESPACE();
