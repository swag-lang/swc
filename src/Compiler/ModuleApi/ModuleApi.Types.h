#pragma once
#include "Support/Core/RefTypes.h"

// Value records shared with CompilerInstance; publication services stay in ModuleApi.h.
SWC_BEGIN_NAMESPACE();

class Symbol;
class SourceContent;

struct ModuleApiPublicEntry
{
    AstNodeRef                 rootRef = AstNodeRef::invalid();
    const Symbol*              symbol  = nullptr;
    std::vector<IdentifierRef> namespacePath;
};

struct ModuleApiFileEntry
{
    // Candidate public symbols recorded while sema is still running. AST-dependent
    // classification is deferred to resolvePendingEntries(), which runs post-sema:
    // walking a file's AST while other sema jobs mutate it is a data race.
    std::vector<const Symbol*> pendingSymbols;

    // Resolved entries, produced from pendingSymbols by resolvePendingEntries().
    std::vector<ModuleApiPublicEntry> publicEntries;
};

using ModuleApiFileEntries = std::unordered_map<SourceViewRef, ModuleApiFileEntry>;

struct ModuleApiPerThreadData
{
    ModuleApiFileEntries files;
};

namespace ModuleApi
{
    struct SourceSnapshot
    {
        fs::path                             path;
        std::shared_ptr<const SourceContent> content;
        fs::file_time_type                   writeTime{};
    };
}

SWC_END_NAMESPACE();
