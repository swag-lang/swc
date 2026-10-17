#pragma once
#include "Backend/Micro/MicroPass.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

// Puts the value-borrow extent test in front of every write check the optimizer kept.
//
//     rcx = %address, rdx = %size, r8 = %location, r9 = %extentCache
//     extent = [r9]
//     cmp extent, 0             the module has not resolved the extent yet
//     je  check
//     cmp [extent + high], rcx  above every open borrow
//     jbe done
//     gap = [extent + low]
//     cmp gap, rcx              at or above the lowest open borrow
//     jbe check
//     sub gap, rcx
//     cmp rdx, gap              ends at or below it
//     jbe done
//   check:
//     call __valueBorrowWrite
//   done:
//
// Every open borrow lies inside the process-wide extent the runtime keeps, so a write outside
// it needs no call, and while no borrow is open the extent is empty. Lowering emits the bare
// call so instruction combining can drop the checks of writes it proves land in the frame;
// the test is added once that is settled, so a dropped check leaves nothing behind.
class MicroValueBorrowFastPathPass final : public MicroPass
{
public:
    std::string_view name() const override { return "value-borrow-fast-path"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
