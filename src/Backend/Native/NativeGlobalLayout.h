#pragma once
#include "Support/Core/DataSegment.h"

SWC_BEGIN_NAMESPACE();

class NativeBackendBuilder;
struct MicroRelocation;

// Places the global storage that native code reaches into the .data and .bss sections.
//
// Semantic analysis reserves global storage in compilation scheduling order, so the segment
// offsets of the same program differ from one build to the next. The layout instead orders the
// reached allocations by discovery from the startup code, the functions and the globals, which
// the backend has already put in source order. The sections then depend on the program alone,
// and storage that nothing reaches is left out.
class NativeGlobalLayout
{
public:
    struct Allocation
    {
        uint32_t sourceOffset  = 0;
        uint32_t size          = 0;
        uint32_t align         = 1;
        uint32_t emittedOffset = 0;
    };

    void build(const NativeBackendBuilder& builder);

    // Initialized allocations in emission order.
    std::span<const Allocation> initAllocations() const { return init_.order; }
    uint32_t                    initSize() const { return init_.size; }
    uint32_t                    zeroSize() const { return zero_.size; }

    // The emitted offset of a segment offset that the layout reached.
    uint32_t map(DataSegmentKind kind, uint32_t sourceOffset) const noexcept;

private:
    struct Segment
    {
        std::vector<Allocation>      order;
        std::vector<Allocation>      bySource;
        std::unordered_set<uint32_t> reached;
        uint32_t                     size = 0;
    };

    const Segment& segment(DataSegmentKind kind) const noexcept;
    void           reach(const NativeBackendBuilder& builder, DataSegmentKind kind, uint32_t sourceOffset);
    void           reachCode(const NativeBackendBuilder& builder, std::span<const MicroRelocation> relocations);
    static void    place(Segment& segment);

    Segment zero_;
    Segment init_;
};

SWC_END_NAMESPACE();
