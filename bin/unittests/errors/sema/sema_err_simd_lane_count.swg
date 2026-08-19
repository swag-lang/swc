#global private

// An array literal building a vector provides one value per lane.
const A = cast(#simd [4] s32) [1, 2, 3]             // swc-expected-error {{sema_err_simd_lane_count}}
const B = cast(#simd [4] s32) [1, 2, 3, 4, 5]       // swc-expected-error {{sema_err_simd_lane_count}}
