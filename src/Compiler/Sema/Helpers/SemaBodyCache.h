#pragma once
#include "Backend/RuntimeBuildConfig.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class CompilerInstance;
class Sema;
class SourceFile;
class SymbolFunction;

// Records which already checked source-dependency bodies can be left dormant.
// When a body is needed, its declaration's semantic context is used to check it.
class SemaBodyCache
{
public:
    SemaBodyCache(CompilerInstance& compiler, std::span<SourceFile* const> parsedFiles);

    void beginOwner(uint32_t sourceOwner);
    void recordInput();
    const Runtime::BuildCfg* deferredBuildConfig(const SourceFile& file, TokenRef token) const;
    static bool isEligible(const SourceFile& file, const SymbolFunction& function);
    void publish(std::span<SymbolFunction* const> functions, const std::unordered_set<uint32_t>& messageOwners) const;

    static void recordEffect(Sema& sema);

private:
    struct Group
    {
        Utf8 key;
        std::vector<const SourceFile*> files;
        std::unordered_map<uint32_t, uint32_t> fileIndices;
        std::vector<std::unordered_set<uint32_t>> deferred;
        Runtime::BuildCfg             config;
        std::array<uint8_t, 32>        configDigest{};
        bool loaded    = false;
        bool checked   = false;
        bool inputRead = false;
    };

    static bool load(Group& group);
    bool hasVisibleInput(uint32_t owner) const;

    CompilerInstance& compiler_;
    std::map<uint32_t, Group> groups_;
    mutable std::shared_mutex mutex_;
    std::unordered_set<const SymbolFunction*> effects_;
    uint32_t activeOwner_      = 0;
    bool     application_      = false;
    bool     runtimeInputRead_ = false;
};

SWC_END_NAMESPACE();
