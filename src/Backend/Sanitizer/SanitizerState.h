#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Backend/Sanitizer/SanitizerValue.h"
#include "Compiler/Lexer/SourceCodeRange.h"

SWC_BEGIN_NAMESPACE();

// One place inside an object the frame does not hold: the object is named by where its
// POINTER lives - a frame slot, or a register the function defines once - and the place
// by the offset from it. Two accesses through two different registers reloaded from the
// same variable name the same location, which is what a release and the use that follows
// it are written as.
struct SanitizerLocation
{
    bool     fromSlot   = false;
    uint32_t basePacked = 0;
    int64_t  slot       = 0;
    int64_t  offset     = 0;

    bool operator==(const SanitizerLocation&) const = default;

    auto operator<=>(const SanitizerLocation& other) const
    {
        return std::tie(fromSlot, slot, basePacked, offset) <=> std::tie(other.fromSlot, other.slot, other.basePacked, other.offset);
    }
};

static_assert(sizeof(SanitizerLocation) == 24);

// Per-register information carried along the flow.
struct SanitizerRegInfo
{
    SanitizerValue value;

    // Keep the presence flags together: these records are copied for every tracked
    // register at each flow join, so padding multiplies across the whole analysis.
    bool hasOriginSlot        = false;
    bool hasZeroTest          = false;
    bool zeroTestTrueIfZero   = false;
    bool hasOriginReg         = false;
    bool hasOriginLocation    = false;
    bool hasAddressLocation   = false;
    bool releasedPointer      = false;
    bool hasPointerOriginSlot = false;

    // If the register was loaded from a local stack slot, remember which, so a guard
    // testing this register can narrow the slot it came from (in unoptimized IR the
    // guarded block reloads the value from the same slot).
    int64_t originSlot = 0;

    // If the register is a boolean produced by a zero test (`setcc` after `cmp x,0`),
    // remember which slot was tested and whether the bool is true when that slot is
    // zero. A branch on the bool then narrows the underlying slot.
    int64_t zeroTestSlot = 0;

    // The nearest VIRTUAL register this value was copied from. A call's arguments are
    // moved into the convention's physical registers, which the call then clobbers, so a
    // release has to name the register the value actually lives in.
    MicroReg originReg;
    // Only the bytes actually loaded and compared can be narrowed by a guard.
    uint8_t originSlotBits   = 0;
    uint8_t zeroTestSlotBits = 0;

    // The place this value was loaded FROM when it was not a frame slot. A pointer a heap
    // object owns lives there and nowhere else, so 'object.buffer' released and read again
    // - the commonest shape a real use-after-free has - is nameable exactly here.
    SanitizerLocation originLocation;

    // The place this register's ADDRESS designates, which is a different question from
    // the one above: the codegen forms a field's address first and reads through it
    // second, so without this the two accesses to one field would name two registers and
    // nothing would connect them.
    SanitizerLocation addressLocation;

    // The pointer this register holds was handed to a freeing callee. A register is a
    // value: only a redefinition changes it, so the fact travels with the copies the
    // codegen makes and outlives the calls in between. This is what names a released
    // PARAMETER, which has no frame slot of its own to be keyed on.
    SourceCodeRef releasedOrigin;

    // Which slot the POINTER in this register came from, which is a different question from
    // the one above: 'originSlot' says the register holds the value stored in that slot, and
    // a guard narrowing it relies on that. A field or an element address is derived by
    // arithmetic, so it no longer holds the slot's value - and it still addresses the same
    // object, which is what decides whether reading through it touches released memory.
    // Reading a field of a freed object is what a use-after-free almost always looks like,
    // so the two facts have to travel separately.
    int64_t pointerOriginSlot = 0;

    bool operator==(const SanitizerRegInfo& o) const
    {
        return value == o.value && hasOriginSlot == o.hasOriginSlot && originSlot == o.originSlot && originSlotBits == o.originSlotBits &&
               hasZeroTest == o.hasZeroTest && zeroTestSlot == o.zeroTestSlot && zeroTestSlotBits == o.zeroTestSlotBits && zeroTestTrueIfZero == o.zeroTestTrueIfZero &&
               hasPointerOriginSlot == o.hasPointerOriginSlot && pointerOriginSlot == o.pointerOriginSlot &&
               hasOriginReg == o.hasOriginReg && originReg == o.originReg &&
               releasedPointer == o.releasedPointer &&
               releasedOrigin.srcViewRef == o.releasedOrigin.srcViewRef && releasedOrigin.tokRef == o.releasedOrigin.tokRef &&
               hasOriginLocation == o.hasOriginLocation && originLocation == o.originLocation &&
               hasAddressLocation == o.hasAddressLocation && addressLocation == o.addressLocation;
    }
};

static_assert(sizeof(SanitizerRegInfo) == 120 + sizeof(SourceCodeRef));

struct SanitizerMovedRange
{
    uint64_t      size = 0;
    SourceCodeRef origin;
};

// A hash map that owns nothing until it first holds an entry. A state carries maps almost
// no function ever fills, and a standard hash map allocates its sentinel and its buckets when it
// is constructed, copied and moved: every state stored at a chain head, copied into a walk or
// handed to a successor paid for each map. Once created the map stays, so what it holds and the
// order it is read in are those of the map it wraps.
template<typename K, typename V>
class SanitizerSparseMap
{
public:
    using Map            = std::unordered_map<K, V>;
    using iterator       = typename Map::iterator;
    using const_iterator = typename Map::const_iterator;

    SanitizerSparseMap() = default;
    SanitizerSparseMap(const SanitizerSparseMap& other) :
        map_(other.map_ ? std::make_unique<Map>(*other.map_) : nullptr)
    {
    }

    SanitizerSparseMap(SanitizerSparseMap&&) noexcept            = default;
    SanitizerSparseMap& operator=(SanitizerSparseMap&&) noexcept = default;

    SanitizerSparseMap& operator=(const SanitizerSparseMap& other)
    {
        if (this == &other)
            return *this;

        if (!other.map_)
            map_.reset();
        else if (map_)
            *map_ = *other.map_;
        else
            map_ = std::make_unique<Map>(*other.map_);
        return *this;
    }

    bool empty() const noexcept { return !map_ || map_->empty(); }

    // Without a map every iterator is the value-initialized one, which compares equal to itself:
    // a search finds nothing and a loop does not start.
    iterator       begin() noexcept { return map_ ? map_->begin() : iterator{}; }
    iterator       end() noexcept { return map_ ? map_->end() : iterator{}; }
    const_iterator begin() const noexcept { return map_ ? std::as_const(*map_).begin() : const_iterator{}; }
    const_iterator end() const noexcept { return map_ ? std::as_const(*map_).end() : const_iterator{}; }
    iterator       find(const K& key) { return map_ ? map_->find(key) : iterator{}; }
    const_iterator find(const K& key) const { return map_ ? std::as_const(*map_).find(key) : const_iterator{}; }

    void insertOrAssign(const K& key, const V& value)
    {
        if (!map_)
            map_ = std::make_unique<Map>();
        map_->insert_or_assign(key, value);
    }

    // An iterator only exists for a created map.
    iterator erase(iterator it) { return map_->erase(it); }
    size_t   erase(const K& key) { return map_ ? map_->erase(key) : 0; }

    void clear() noexcept
    {
        if (map_)
            map_->clear();
    }

    template<typename Pred>
    void eraseIf(Pred pred)
    {
        if (map_)
            std::erase_if(*map_, pred);
    }

private:
    std::unique_ptr<Map> map_;
};

// The register and stack facts of a state, held in one open-addressed table. A state is copied
// at every chain head, walk and successor, and a node-based map pays one allocation per fact for
// each copy; this one copies a single array. Nothing reads these facts in table order: every
// pass over them keeps or drops each entry on its own merits.
template<typename K, typename V>
class SanitizerFlatMap
{
    static_assert(std::is_trivially_copyable_v<K> && std::is_trivially_copyable_v<V>, "SanitizerFlatMap holds trivially copyable entries");

public:
    bool   empty() const noexcept { return count_ == 0; }
    size_t size() const noexcept { return count_; }

    const V* find(const K& key) const noexcept
    {
        const size_t index = findIndex(key);
        return index == K_NOT_FOUND ? nullptr : &slots_[index].value;
    }

    V* find(const K& key) noexcept { return const_cast<V*>(std::as_const(*this).find(key)); }

    void insertOrAssign(const K& key, const V& value) { getOrInsert(key) = value; }

    // The value of the key, value-initialized when the key is new, like 'operator[]'. The table
    // grows before an insertion, so the returned value stays where it is until the next one.
    V& getOrInsert(const K& key)
    {
        const size_t found = findIndex(key);
        if (found != K_NOT_FOUND)
            return slots_[found].value;

        if (slots_.empty())
            rehash(K_INITIAL_CAPACITY);
        else if ((count_ + tombstones_ + 1) * 4 > slots_.size() * 3)
            rehash((count_ + 1) * 4 > slots_.size() * 2 ? slots_.size() * 2 : slots_.size());

        const size_t mask  = slots_.size() - 1;
        size_t       index = slotIndex(key, mask);
        while (slots_[index].state == SlotState::Used)
            index = (index + 1) & mask;
        if (slots_[index].state == SlotState::Erased)
            --tombstones_;
        slots_[index] = {.key = key, .state = SlotState::Used, .value = V{}};
        ++count_;
        return slots_[index].value;
    }

    size_t erase(const K& key) noexcept
    {
        const size_t index = findIndex(key);
        if (index == K_NOT_FOUND)
            return 0;
        eraseAt(index);
        return 1;
    }

    void clear() noexcept
    {
        if (!count_ && !tombstones_)
            return;
        for (Slot& slot : slots_)
            slot.state = SlotState::Free;
        count_      = 0;
        tombstones_ = 0;
    }

    // Drops every entry the predicate holds for, and says how many went. The predicate sees the
    // value mutably, so a pass that rewrites what it keeps runs once.
    template<typename Pred>
    size_t eraseIf(Pred pred)
    {
        const size_t before = count_;
        for (size_t index = 0; index < slots_.size() && count_; ++index)
        {
            if (slots_[index].state == SlotState::Used && pred(std::as_const(slots_[index].key), slots_[index].value))
                eraseAt(index);
        }
        return before - count_;
    }

    template<typename Fn>
    void forEach(Fn fn)
    {
        for (Slot& slot : slots_)
        {
            if (slot.state == SlotState::Used)
                fn(std::as_const(slot.key), slot.value);
        }
    }

private:
    enum class SlotState : uint8_t
    {
        Free,
        Used,
        Erased,
    };

    struct Slot
    {
        K         key{};
        SlotState state = SlotState::Free;
        V         value{};
    };

    static constexpr size_t K_INITIAL_CAPACITY = 8;
    static constexpr size_t K_NOT_FOUND        = std::numeric_limits<size_t>::max();

    static size_t slotIndex(const K& key, size_t mask) noexcept
    {
        return static_cast<size_t>(static_cast<uint64_t>(key) * 0x9E3779B97F4A7C15ULL >> 32) & mask;
    }

    size_t findIndex(const K& key) const noexcept
    {
        if (!count_)
            return K_NOT_FOUND;

        const size_t mask  = slots_.size() - 1;
        size_t       index = slotIndex(key, mask);
        while (slots_[index].state != SlotState::Free)
        {
            if (slots_[index].state == SlotState::Used && slots_[index].key == key)
                return index;
            index = (index + 1) & mask;
        }

        return K_NOT_FOUND;
    }

    void eraseAt(size_t index) noexcept
    {
        slots_[index].state = SlotState::Erased;
        --count_;
        ++tombstones_;
    }

    void rehash(size_t capacity)
    {
        std::vector<Slot> previous(capacity);
        previous.swap(slots_);
        tombstones_ = 0;

        const size_t mask = slots_.size() - 1;
        for (const Slot& slot : previous)
        {
            if (slot.state != SlotState::Used)
                continue;
            size_t index = slotIndex(slot.key, mask);
            while (slots_[index].state != SlotState::Free)
                index = (index + 1) & mask;
            slots_[index] = slot;
        }
    }

    std::vector<Slot> slots_;
    size_t            count_      = 0;
    size_t            tombstones_ = 0;
};

// Abstract machine state at one program point: the tracked value of every virtual
// register and simulated local stack slot, plus which register the CPU flags encode a
// comparison of against zero.
struct SanitizerState
{
    SanitizerFlatMap<uint32_t, SanitizerRegInfo> regs;  // key: MicroReg.packed
    SanitizerFlatMap<int64_t, SanitizerValue>    stack; // key: stack slot offset

    // The upper eight bytes of a 128-bit register copy. Keep this sparse instead of
    // widening every scalar register's information. Loads snapshot both lanes before
    // subsequent stores can change the source memory.
    SanitizerSparseMap<uint32_t, SanitizerValue> upperRegValues;

    // Frame ranges abandoned by a '#move'/'#relocate' (moved-from, not reset), set by a
    // 'SanityInvalidate' marker: key = slot offset. A range is moved-from only when it
    // is on *every* path (join = intersection); any store into the range revalidates
    // it, and calls conservatively clear the whole set. The source identifies the move
    // when every incoming path agrees on it; an ambiguous join keeps the fact without
    // claiming one origin.
    SanitizerSparseMap<int64_t, SanitizerMovedRange> movedFrom;

    // Slots holding a pointer that was handed to a FREEING callee (freesParamsMask):
    // dereferencing that pointer again is a use-after-free, freeing it again a double
    // free. Same discipline as movedFrom: join = intersection, any store that could
    // alias the slot revalidates it, calls conservatively clear the set (the freeing
    // call itself re-marks its arguments afterwards). The value remembers the freeing
    // call so a proven fault can point back to its origin.
    SanitizerSparseMap<int64_t, SourceCodeRef> freedPtrSlots;

    // Proven slot copies: the key holds the very value the mapped slot holds. Only slots
    // inside a declared local whose address is never formed take part, so nothing but an
    // explicit store to one of the two can break the equality - neither a callee nor a
    // store through a pointer can reach them. Releasing one member releases the whole
    // class, which is what turns 'let b = a' followed by a release of 'a' from a miss
    // into a proof. Same join as the sets above: intersection.
    SanitizerSparseMap<int64_t, int64_t> aliasPtrSlots;

    // Register-only pointer values copied into allocator request fields. A release
    // through the request must still name the original virtual register.
    SanitizerSparseMap<int64_t, MicroReg> aliasPtrRegs;
    // Object fields copied into a request retain their source until that field is
    // replaced or its owner is handed to a call that can replace it.
    SanitizerSparseMap<int64_t, SanitizerLocation> aliasPtrLocations;
    // A marker immediately precedes interface dispatch. Re-state this release
    // after that call invalidates the older facts about object fields.
    std::optional<SanitizerLocation> pendingReleaseLocation;
    SourceCodeRef                    pendingReleaseOrigin;

    // Declared locals whose address has left the engine's sight: handed to a callee,
    // stored, or folded into a value it no longer recognizes as an address. A later call
    // can write through it, so the two sets above keep nothing about such an object past
    // one. Unlike every other fact here this one is a MAY fact - the join is a union -
    // and an address the codegen only ever uses as the base of an access never enters it,
    // which is what leaves an ordinary local protected. Keyed by the start of the
    // variable's storage; a compiler temporary is never protected in the first place.
    std::optional<std::unordered_set<int64_t>> escapedFrameObjects;

    // Released pointers that did not live in the frame: keyed by the base register the
    // access went through and the offset from it. A callee can write through any pointer
    // it is handed, so unlike the frame facts these keep nothing across a call - which is
    // enough, because a release and the use that follows it sit in one body.
    std::optional<std::map<SanitizerLocation, SourceCodeRef>> freedPtrLocations;

    const SourceCodeRef* findFreedPtrLocation(const SanitizerLocation& location) const
    {
        if (!freedPtrLocations)
            return nullptr;
        const auto it = freedPtrLocations->find(location);
        return it == freedPtrLocations->end() ? nullptr : &it->second;
    }

    MicroReg flagsSubject = MicroReg::invalid();
    uint8_t  flagsBits    = 0;
};

SWC_END_NAMESPACE();
