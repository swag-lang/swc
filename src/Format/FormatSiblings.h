#pragma once
#include "Format/FormatModel.h"

SWC_BEGIN_NAMESPACE();

// Sibling constructs that read as one pattern: the branches of an `if` chain,
// consecutive guards, closures assigned or passed side by side, and functions
// declared one after the other. Grouping them is shared by the rewrite that
// changes their syntax and by the layout that changes their lines.
namespace FormatSiblings
{
    // How one body is written, and what it could become without changing meaning.
    struct BodyShape
    {
        uint32_t first       = FormatPiece::INVALID_INDEX; // first piece of the body content
        uint32_t last        = FormatPiece::INVALID_INDEX; // last piece of the body content
        bool     valid       = false;                      // located, and editable from end to end
        bool     braced      = false;                      // `{ ... }` rather than `do` or `=>`
        bool     oneLine     = false;                      // the whole body sits on one line
        bool     compact     = false;                      // a single statement that reads on one line
        bool     unbraceable = false;                      // compact, and safe to write after `do` or `=>`
        bool     braceable   = false;                      // safe to wrap in braces
    };

    BodyShape branchShape(const FormatModel& model, const FormatBranch& branch);
    BodyShape functionShape(const FormatModel& model, const FormatFunctionBody& body);

    // The piece a statement-level construct starts on when it is the value of
    // an assignment or declaration, or INVALID when it is not.
    uint32_t assignedStatementStart(const FormatModel& model, uint32_t valuePiece, uint32_t valueLast);

    // Branch groups: chains of two branches or more (when `chains` is set),
    // and runs of consecutive single-branch `if` statements grouped by
    // `guards`. Each entry lists (chain index, branch index) pairs.
    using BranchRef = std::pair<uint32_t, uint32_t>;
    std::vector<std::vector<BranchRef>> branchGroups(const FormatModel& model, bool chains, FormatAlignMode guards);

    // Closure groups: closures assigned by consecutive statements, grouped by
    // `mode`, and closures passed in the same argument or literal list.
    std::vector<std::vector<uint32_t>> closureGroups(const FormatModel& model, FormatAlignMode mode);

    // Function groups: consecutive function declarations of one scope.
    std::vector<std::vector<uint32_t>> functionGroups(const FormatModel& model, FormatAlignMode mode);

    bool isActive(FormatAlignMode mode);
}

SWC_END_NAMESPACE();
