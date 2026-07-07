#pragma once

SWC_BEGIN_NAMESPACE();

// Abstract value tracked for a register or a stack slot by the sanitizer.
// `Constant 0` is a provable zero (a null pointer, or a zero divisor). `NonZero`,
// `StackAddr` and `GlobalAddr` are known non-zero. `Unknown` is anything else and is
// never flagged, so a check only ever fires on values it can prove are zero on every
// path — no false positives.
enum class SanitizerValueKind : uint8_t
{
    Unknown,
    Constant,
    NonZero,    // known non-zero, exact value unknown (e.g. narrowed by a guard)
    StackAddr,  // address of a local stack slot (non-zero)
    GlobalAddr, // address of a global / function (non-zero)
};

struct SanitizerValue
{
    static constexpr int64_t K_NO_ORIGIN = INT64_MIN;

    SanitizerValueKind kind        = SanitizerValueKind::Unknown;
    uint64_t           constant    = 0;           // Constant
    int64_t            stackOffset = 0;           // StackAddr
    // StackAddr only: frame offset the address was FORMED from (the start of the
    // object an indexing/lea derived it from). K_NO_ORIGIN when not tracked (the raw
    // stack base register). Lets the bound check compare a derived access against the
    // extents of the variable it provably indexes.
    int64_t stackOrigin = K_NO_ORIGIN;

    static SanitizerValue makeConstant(uint64_t value) { return {SanitizerValueKind::Constant, value, 0, K_NO_ORIGIN}; }
    static SanitizerValue makeNonZero() { return {SanitizerValueKind::NonZero, 0, 0, K_NO_ORIGIN}; }
    static SanitizerValue makeStackAddr(int64_t offset, int64_t origin = K_NO_ORIGIN) { return {SanitizerValueKind::StackAddr, 0, offset, origin}; }
    static SanitizerValue makeGlobalAddr() { return {SanitizerValueKind::GlobalAddr, 0, 0, K_NO_ORIGIN}; }

    bool hasStackOrigin() const
    {
        return kind == SanitizerValueKind::StackAddr && stackOrigin != K_NO_ORIGIN;
    }

    bool isConstant() const
    {
        return kind == SanitizerValueKind::Constant;
    }

    bool isZero() const
    {
        return kind == SanitizerValueKind::Constant && constant == 0;
    }

    bool isKnownNonZero() const
    {
        return kind == SanitizerValueKind::NonZero ||
               kind == SanitizerValueKind::StackAddr ||
               kind == SanitizerValueKind::GlobalAddr ||
               (kind == SanitizerValueKind::Constant && constant != 0);
    }

    bool isStackAddr() const
    {
        return kind == SanitizerValueKind::StackAddr;
    }

    bool operator==(const SanitizerValue& o) const
    {
        return kind == o.kind && constant == o.constant && stackOffset == o.stackOffset && stackOrigin == o.stackOrigin;
    }
};

SWC_END_NAMESPACE();
