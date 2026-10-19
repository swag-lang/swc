#pragma once
#include "Support/Core/Flags.h"
#include "Support/Core/RefTypes.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();
class SymbolMap;
class Symbol;
class SymbolVariable;
struct SemaInlinePayload;

enum class SemaScopeFlagsE
{
    Zero       = 0,
    TopLevel   = 1 << 0,
    Type       = 1 << 1,
    Parameters = 1 << 2,
    Local      = 1 << 3,
    Impl       = 1 << 4,
    Interface  = 1 << 5,
};
using SemaScopeFlags = EnumFlags<SemaScopeFlagsE>;

class SemaScope
{
public:
    struct AutoMemberBinding
    {
        const SymbolMap* symMap      = nullptr;
        TypeRef          typeRef     = TypeRef::invalid();
        SymbolVariable*  symVar      = nullptr;
        AstNodeRef       baseExprRef = AstNodeRef::invalid();

        // Later bindings are nested more deeply. Rank by creation order because
        // subjects need not sit on the innermost physical scope, and binding vars
        // share one flat list with the receiver.
        uint64_t order = 0;

        // Track the subject's expansion: caller-owned subjects visible to an
        // inlined body rank behind that body's receiver, like caller binding vars.
        const SemaInlinePayload* inlinePayload = nullptr;
    };

    static constexpr uint32_t UNIQ_COUNT = 10;

    SemaScope() = default;

    SemaScope(SemaScopeFlags flags, SemaScope* parent) :
        parent_(parent),
        lookupParent_(parent),
        flags_(flags),
        depth_(parent ? parent->depth() + 1 : 1)
    {
    }

    SemaScope* parent() const { return parent_; }
    void       setParent(SemaScope* parent)
    {
        parent_ = parent;
        depth_  = parent ? parent->depth() + 1 : 1;
    }

    // Physical scope depth is independent of redirected macro/mixin lookup parents.
    uint32_t depth() const { return depth_; }

    SemaScope* lookupParent() const { return lookupParent_ ? lookupParent_ : parent_; }
    void       setLookupParent(SemaScope* parent) { lookupParent_ = parent; }

    SemaScopeFlags flags() const { return flags_; }
    bool           hasFlag(SemaScopeFlags flag) const { return flags_.has(flag); }
    bool           isTopLevel() const { return hasFlag(SemaScopeFlagsE::TopLevel); }
    bool           isLocal() const { return hasFlag(SemaScopeFlagsE::Local); }
    bool           isImpl() const { return hasFlag(SemaScopeFlagsE::Impl); }
    bool           isInterface() const { return hasFlag(SemaScopeFlagsE::Interface); }
    bool           isType() const { return hasFlag(SemaScopeFlagsE::Type); }
    bool           isParameters() const { return hasFlag(SemaScopeFlagsE::Parameters); }

    void             setSymMap(SymbolMap* symMap) { symMap_ = symMap; }
    SymbolMap*       symMap() { return symMap_; }
    const SymbolMap* symMap() const { return symMap_; }

    void        addUsingSymMap(SymbolMap* symMap) { usingSymMaps_.push_back(symMap); }
    static void addUsingSymMapIfMissing(SemaScope& scope, SymbolMap* usingSymMap)
    {
        SWC_ASSERT(usingSymMap != nullptr);
        for (const SymbolMap* existing : scope.usingSymMaps())
        {
            if (existing == usingSymMap)
                return;
        }

        scope.addUsingSymMap(usingSymMap);
    }

    const SmallVector<SymbolMap*>& usingSymMaps() const { return usingSymMaps_; }

    // Name bits skip scopes that cannot contain a lookup. Impl names can change
    // after declaration, so impl symbols set every bit to avoid false negatives.
    template<typename S>
    void addSymbol(S* symbol)
    {
        symbols_.push_back(symbol);
        symbolNames_ |= symbol->isImpl() ? ~0ull : nameBit(symbol->idRef());
    }

    const SmallVector<Symbol*>& symbols() const { return symbols_; }
    bool                        mayHaveSymbolNamed(IdentifierRef idRef) const { return (symbolNames_ & nameBit(idRef)) != 0; }

    void addAutoMemberBinding(const AutoMemberBinding& binding)
    {
        if (!binding.symMap && !binding.typeRef.isValid() && !binding.symVar && binding.baseExprRef.isInvalid())
            return;

        autoMemberBindings_.push_back(binding);
    }

    const std::vector<AutoMemberBinding>& autoMemberBindings() const { return autoMemberBindings_; }

    IdentifierRef uniqIdentifier(const uint32_t index) const
    {
        SWC_ASSERT(index < UNIQ_COUNT);
        return uniqIdentifiers_[index];
    }

    void setUniqIdentifier(const uint32_t index, const IdentifierRef idRef)
    {
        SWC_ASSERT(index < UNIQ_COUNT);
        uniqIdentifiers_[index] = idRef;
    }

private:
    static uint64_t nameBit(IdentifierRef idRef) { return 1ull << ((static_cast<uint64_t>(idRef.get()) * 0x9E3779B97F4A7C15ull) >> 58); }

    SemaScope* parent_       = nullptr;
    SemaScope* lookupParent_ = nullptr;

    SemaScopeFlags flags_ = SemaScopeFlagsE::Zero;
    uint32_t       depth_ = 1;

    SymbolMap*              symMap_ = nullptr;
    SmallVector<SymbolMap*> usingSymMaps_;

    SmallVector<Symbol*> symbols_;
    uint64_t             symbolNames_ = 0;

    std::vector<AutoMemberBinding> autoMemberBindings_;

    std::array<IdentifierRef, UNIQ_COUNT> uniqIdentifiers_ = {};
};

// Allocate frequently opened scopes in chunks. Destroy closed scopes in place,
// but never reuse their addresses: inline payloads retain references to the
// scope they expanded from.
class SemaScopeArena
{
public:
    SemaScopeArena()                                 = default;
    SemaScopeArena(const SemaScopeArena&)            = delete;
    SemaScopeArena& operator=(const SemaScopeArena&) = delete;

    template<typename... Args>
    SemaScope* create(Args&&... args)
    {
        if (chunks_.empty() || chunkUsed_ == chunkCapacity_)
        {
            chunkCapacity_ = chunks_.empty() ? K_FIRST_CHUNK_SCOPES : std::min(chunkCapacity_ * 2, K_MAX_CHUNK_SCOPES);
            chunks_.push_back(std::make_unique_for_overwrite<Slot[]>(chunkCapacity_));
            chunkUsed_ = 0;
        }

        Slot& slot = chunks_.back()[chunkUsed_++];
        return std::construct_at(reinterpret_cast<SemaScope*>(slot.bytes), std::forward<Args>(args)...);
    }

private:
    struct Slot
    {
        alignas(SemaScope) std::byte bytes[sizeof(SemaScope)];
    };

    static constexpr size_t K_FIRST_CHUNK_SCOPES = 4;
    static constexpr size_t K_MAX_CHUNK_SCOPES   = 16;

    std::vector<std::unique_ptr<Slot[]>> chunks_;

    size_t chunkCapacity_ = 0;
    size_t chunkUsed_     = 0;
};

// Ends a scope taken from a SemaScopeArena: the arena keeps the storage.
struct SemaScopeRelease
{
    void operator()(SemaScope* scope) const noexcept { std::destroy_at(scope); }
};

using SemaScopePtr = std::unique_ptr<SemaScope, SemaScopeRelease>;

SWC_END_NAMESPACE();
