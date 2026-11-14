#include <cstdint>
extern "C" {
__declspec(noinline) uint64_t bit0Product64(uint64_t a,uint64_t b) { return ((a >> 0) & 1) * b; }
__declspec(noinline) uint64_t bit1Product64(uint64_t a,uint64_t b) { return ((a >> 1) & 1) * b; }
__declspec(noinline) uint64_t bit7Product64(uint64_t a,uint64_t b) { return ((a >> 7) & 1) * b; }
__declspec(noinline) uint64_t bit8Product64(uint64_t a,uint64_t b) { return ((a >> 8) & 1) * b; }
__declspec(noinline) uint64_t bit15Product64(uint64_t a,uint64_t b) { return ((a >> 15) & 1) * b; }
__declspec(noinline) uint64_t bit16Product64(uint64_t a,uint64_t b) { return ((a >> 16) & 1) * b; }
__declspec(noinline) uint64_t bit17Product64(uint64_t a,uint64_t b) { return ((a >> 17) & 1) * b; }
__declspec(noinline) uint64_t bit31Product64(uint64_t a,uint64_t b) { return ((a >> 31) & 1) * b; }
__declspec(noinline) uint64_t bit32Product64(uint64_t a,uint64_t b) { return ((a >> 32) & 1) * b; }
__declspec(noinline) uint64_t bit40Product64(uint64_t a,uint64_t b) { return ((a >> 40) & 1) * b; }
__declspec(noinline) uint64_t bit63Product64(uint64_t a,uint64_t b) { return ((a >> 63) & 1) * b; }
__declspec(noinline) uint32_t bit7Product32(uint32_t a,uint32_t b) { return ((a >> 7) & 1) * b; }
__declspec(noinline) uint32_t bit15Product32(uint32_t a,uint32_t b) { return ((a >> 15) & 1) * b; }
__declspec(noinline) uint32_t bit31Product32(uint32_t a,uint32_t b) { return ((a >> 31) & 1) * b; }
}