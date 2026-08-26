//! Format: H.265/HEVC decoder component.
//! Supported: Progressive Main and Main 10 streams: 8- and 10-bit 4:2:0, I/P/B slices, tiles, wavefront parallel processing, dependent slice segments, sample adaptive offset, and in-loop deblocking.
//! Not supported: 4:2:2 and 4:4:4 chroma, bit depths above 10, pulse code modulation blocks, separate colour planes, and the range, multilayer, 3D, and screen content extensions.
//! Role: This file owns the normative coefficient scan orders.
//
#global namespace Hevc
#global internal

using Core

// The three scan orders residual coding uses, clause 7.4.9.11.
const ScanDiagonal   = 0'u32
const ScanHorizontal = 1'u32
const ScanVertical   = 2'u32

// The scan orders of clauses 6.5.3 to 6.5.5, for blocks of one to eight units on a side.
//
// Residual coding walks a transform block twice: once over its four-by-four sub-blocks, and once
// over the coefficients inside each of them. Both walks read this table, indexed by the base-two
// logarithm of the side in units, so one table answers a 4x4 block of coefficients and an 8x8
// block of sub-blocks alike.
var ScanX: [4, 3, 64] u8
var ScanY: [4, 3, 64] u8

// Where each position of a block sits in the scan, which is the same table read the other way.
//
// Residual coding is told the last significant coefficient by its position, and everything it
// reads afterwards is indexed by scan order. A scan is a permutation, so its inverse answers
// where that coefficient sits at once; walking the scan backwards to find it costs up to a
// thousand steps on a 32x32 block, and a block states its last coefficient every time.
var ScanIndex: [4, 3, 64] u8

// The position of each sample in the up-right diagonal scan, which is the order a quantization
// matrix is transmitted in, equations 7-44 and 7-45.
var DiagScan4x4Index: [16] u8
var DiagScan8x8Index: [64] u8

// Fills the scan order tables, clauses 6.5.3 to 6.5.5.
private func buildScanOrders()
{
    for log2Size in 4'u32
    {
        let size = 1'u32 << log2Size

        // Up-right diagonal, clause 6.5.3.
        var position = 0'u32
        var x, y     = 0's32
        while position < size * size
        {
            while y >= 0
            {
                if x < cast(s32) size and y < cast(s32) size
                {
                    ScanX[log2Size, ScanDiagonal, position] = cast(u8) x
                    ScanY[log2Size, ScanDiagonal, position] = cast(u8) y
                    position += 1
                }

                y -= 1
                x += 1
            }

            y = x
            x = 0
        }

        // Horizontal, clause 6.5.4.
        position = 0
        for row in size
        {
            for column in size
            {
                ScanX[log2Size, ScanHorizontal, position] = cast(u8) column
                ScanY[log2Size, ScanHorizontal, position] = cast(u8) row
                position += 1
            }
        }

        // Vertical, clause 6.5.5.
        position = 0
        for column in size
        {
            for row in size
            {
                ScanX[log2Size, ScanVertical, position] = cast(u8) column
                ScanY[log2Size, ScanVertical, position] = cast(u8) row
                position += 1
            }
        }
    }

    for log2Size in 4'u32
    {
        let size = 1'u32 << log2Size
        for order in 3'u32
        {
            for position in size * size
            {
                let x = cast(u32) ScanX[log2Size, order, position]
                let y = cast(u32) ScanY[log2Size, order, position]
                ScanIndex[log2Size, order, y * size + x] = cast(u8) position
            }
        }
    }

    for position in 16'u32
    {
        let x = cast(u32) ScanX[2, ScanDiagonal, position]
        let y = cast(u32) ScanY[2, ScanDiagonal, position]
        DiagScan4x4Index[y * 4 + x] = cast(u8) position
    }

    for position in 64'u32
    {
        let x = cast(u32) ScanX[3, ScanDiagonal, position]
        let y = cast(u32) ScanY[3, ScanDiagonal, position]
        DiagScan8x8Index[y * 8 + x] = cast(u8) position
    }
}

#init
{
    buildScanOrders()
}
