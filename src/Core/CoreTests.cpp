#include "pch.h"
#if SWC_HAS_ASSERT

#include "Core/ConstInt.h"
#include "Core/CoreTests.h"
#include "Report/Check.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    void test_ConstInt()
    {
        {
            using C16 = ConstInt<16>;
            SWC_ASSERT(C16::BIT_COUNT == 16);

            // basic construction / zero
            C16 z{0};
            SWC_ASSERT(z.is_zero());
            SWC_ASSERT(z.fits_in_uint64());
            SWC_ASSERT(z.to_uint64() == 0);

            // ctor from uint64 + assign
            C16 a(5);
            SWC_ASSERT(!a.is_zero());
            SWC_ASSERT(a.to_uint64() == 5);
            a.assign(7);
            SWC_ASSERT(a.to_uint64() == 7);

            // get/set_bit
            C16 b(0);
            b.set_bit(0, true);
            b.set_bit(3, true);
            SWC_ASSERT(b.to_uint64() == (1u | 8u));
            SWC_ASSERT(b.get_bit(3) && !b.get_bit(2));

            // comparisons
            C16 c(10), d(10), e(11);
            SWC_ASSERT(c.equals(d));
            SWC_ASSERT(!c.equals(e));
            SWC_ASSERT(c.less_than(e));
            SWC_ASSERT(e.greater_than(c));
            SWC_ASSERT(c.less_equal(d) && c.less_equal(e));
            SWC_ASSERT(e.greater_equal(d));

            // add_wrapped + add with overflow
            C16  max16((1u << 16) - 1u);
            bool ov   = false;
            C16  sum1 = C16(10).add_wrapped(C16(20));
            SWC_ASSERT(sum1.to_uint64() == 30);
            C16 sum2 = max16.add(C16(1), ov);
            SWC_ASSERT(ov);
            (void) sum2;

            ov       = false;
            C16 sum3 = C16(100).add(C16(200), ov);
            SWC_ASSERT(!ov && sum3.to_uint64() == 300);

            // sub_wrapped + sub with overflow
            C16 sub1 = C16(5).sub_wrapped(C16(7)); // wraps
            SWC_ASSERT(sub1.to_uint64() == static_cast<std::uint16_t>(5 - 7));
            ov       = false;
            C16 sub2 = C16(5).sub(C16(7), ov);
            SWC_ASSERT(ov);
            (void) sub2;

            ov       = false;
            C16 sub3 = C16(7).sub(C16(5), ov);
            SWC_ASSERT(!ov && sub3.to_uint64() == 2);

            // mul_wrapped + mul with overflow
            C16 m1(100), m2(200);
            C16 mWr = m1.mul_wrapped(m2);
            SWC_ASSERT(mWr.to_uint64() == static_cast<std::uint16_t>(100 * 200));

            ov      = false;
            C16 mOk = C16(100).mul(C16(5), ov);
            SWC_ASSERT(!ov && mOk.to_uint64() == 500);

            ov       = false;
            C16 mBig = C16(300).mul(C16(300), ov);
            SWC_ASSERT(ov);
            (void) mBig;

            // bit ops
            C16 aa(0b0101), bb(0b0011);
            C16 aAnd = aa.bit_and(bb);
            C16 aor  = aa.bit_or(bb);
            C16 aXor = aa.bit_xor(bb);
            C16 aNot = aa.bit_not();
            SWC_ASSERT(aAnd.to_uint64() == 0b0001);
            SWC_ASSERT(aor.to_uint64() == 0b0111);
            SWC_ASSERT(aXor.to_uint64() == 0b0110);
            SWC_ASSERT((aNot.to_uint64() & 0xFFFFu) == static_cast<std::uint16_t>(~0b0101u));

            // shifts (wrapped + overflow)
            C16 s(1);
            C16 s2 = s.shl_wrapped(3);
            C16 s3 = s2.shr(1);
            SWC_ASSERT(s2.to_uint64() == 8);
            SWC_ASSERT(s3.to_uint64() == 4);

            ov       = false;
            C16 s_ok = s.shl(4, ov);
            SWC_ASSERT(!ov && s_ok.to_uint64() == 16);

            ov = false;
            C16 high(1u << 15);
            C16 s_ov = high.shl(1, ov);
            SWC_ASSERT(ov);
            (void) s_ov;

            ov        = false;
            C16 s_ov2 = s.shl(16, ov);
            SWC_ASSERT(ov);
            (void) s_ov2;

            // div/mod + div_by_zero
            {
                bool div0 = false;
                C16  q    = C16(100).div(C16(7), div0);
                C16  r    = C16(100).mod(C16(7), div0);
                SWC_ASSERT(!div0);
                SWC_ASSERT(q.to_uint64() == 14);
                SWC_ASSERT(r.to_uint64() == 2);
            }
            {
                bool div0 = false;
                C16  q    = C16(5).div(C16(0), div0);
                C16  r    = C16(5).mod(C16(0), div0);
                SWC_ASSERT(div0);
                (void) q;
                (void) r;
            }

            // div_mod combined
            {
                bool div0 = false;
                C16  q, r;
                C16(55).div_mod(C16(10), q, r, div0);
                SWC_ASSERT(!div0);
                SWC_ASSERT(q.to_uint64() == 5);
                SWC_ASSERT(r.to_uint64() == 5);
            }
        }

        {
            // multi-word tests, including TOP_MASK behavior
            using C70 = ConstInt<70>;
            SWC_ASSERT(C70::NUM_WORDS >= 2);

            C70 x(0);
            SWC_ASSERT(x.is_zero());

            // highest bit
            x.set_bit(69, true);
            SWC_ASSERT(x.get_bit(69));
            SWC_ASSERT(!x.get_bit(70));

            // shifting the highest bit causes overflow
            bool ov = false;
            C70  y  = x.shl(1, ov);
            SWC_ASSERT(ov);
            (void) y;

            // small values still behave as normal uint64
            C70 one(1);
            C70 two = one.add_wrapped(one);
            SWC_ASSERT(two.to_uint64() == 2);
            SWC_ASSERT(two.fits_in_uint64());

            // multiplication with high bits going into the upper limb
            C70 bigA(1);
            bigA.set_bit(40, true); // create something that uses higher bits
            C70 bigB(3);
            ov       = false;
            C70 bigC = bigA.mul(bigB, ov);
            // We don't care about exact value, just that it fits and we can round-trip via div
            SWC_ASSERT(!ov);
            bool div0 = false;
            C70  q    = bigC.div(bigB, div0);
            SWC_ASSERT(!div0);
            SWC_ASSERT(q.equals(bigA));
        }
    }
}

void runCoreTests()
{
    test_ConstInt();
}

SWC_END_NAMESPACE()

#endif // SWC_HAS_ASSERT
