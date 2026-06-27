#global export
#global #if #os == Swag.TargetOs.Windows
#foreignlib("gdiplus")
using Win32

#[Swag.Strict]
{
    alias GpStatus       = s32
    alias GpGraphics     = void
    alias GpImage        = void
    alias GpBitmap       = void
    alias GpBrush        = void
    alias GpSolidFill    = void
    alias GpFontFamily   = void
    alias GpStringFormat = void
    alias GpPath         = void
    alias GpPen          = void
    alias GpMatrix       = void
}

const GdipOk                         = 0
const GdipFillModeAlternate          = 0
const GdipFontStyleRegular           = 0
const GdipUnitPixel                  = 2
const GdipSmoothingModeHighQuality   = 4
const GdipPixelOffsetModeHighQuality = 2
const GdipTextRenderingHintAAGridFit = 3
const GdipLineJoinRound              = 2
const GdipPixelFormat32bppPARGB      = 0x000E200B

struct GdiplusStartupInput
{
    GdiplusVersion:           u32
    DebugEventCallback:       *void
    SuppressBackgroundThread: BOOL
    SuppressExternalCodecs:   BOOL
}

struct GpRectF
{
    x:      f32
    y:      f32
    width:  f32
    height: f32
}

#[Foreign("Gdiplus")]
{
    func GdiplusStartup(token: *u64, input: const *GdiplusStartupInput, output: #null *void)->GpStatus;
    func GdiplusShutdown(token: u64);
}

#[Foreign("Gdiplus"), Discardable]
{
    func GdipCreateBitmapFromScan0(width, height, stride: s32, format: s32, scan0: [*] u8, bitmap: **GpBitmap)->GpStatus;
    func GdipDisposeImage(image: *GpImage)->GpStatus;
    func GdipGetImageGraphicsContext(image: *GpImage, graphics: **GpGraphics)->GpStatus;
    func GdipDeleteGraphics(graphics: *GpGraphics)->GpStatus;
    func GdipSetSmoothingMode(graphics: *GpGraphics, smoothingMode: s32)->GpStatus;
    func GdipSetPixelOffsetMode(graphics: *GpGraphics, pixelOffsetMode: s32)->GpStatus;
    func GdipSetTextRenderingHint(graphics: *GpGraphics, mode: s32)->GpStatus;
    func GdipGraphicsClear(graphics: *GpGraphics, color: u32)->GpStatus;
    func GdipCreateFontFamilyFromName(name: LPCWSTR, collection: #null *void, fontFamily: **GpFontFamily)->GpStatus;
    func GdipDeleteFontFamily(fontFamily: *GpFontFamily)->GpStatus;
    func GdipCreateStringFormat(formatAttributes: s32, language: u16, format: **GpStringFormat)->GpStatus;
    func GdipDeleteStringFormat(format: *GpStringFormat)->GpStatus;
    func GdipCreatePath(fillMode: s32, path: **GpPath)->GpStatus;
    func GdipDeletePath(path: *GpPath)->GpStatus;
    func GdipAddPathString(path: *GpPath, text: LPCWSTR, length: s32, family: *GpFontFamily, style: s32, emSize: f32, layoutRect: const *GpRectF, format: *GpStringFormat)->GpStatus;
    func GdipGetPathWorldBounds(path: *GpPath, bounds: *GpRectF, matrix: #null *GpMatrix, pen: #null *GpPen)->GpStatus;
    func GdipCreatePen1(color: u32, width: f32, unit: s32, pen: **GpPen)->GpStatus;
    func GdipSetPenLineJoin(pen: *GpPen, lineJoin: s32)->GpStatus;
    func GdipDeletePen(pen: *GpPen)->GpStatus;
    func GdipCreateSolidFill(color: u32, brush: **GpSolidFill)->GpStatus;
    func GdipDeleteBrush(brush: *GpBrush)->GpStatus;
    func GdipDrawPath(graphics: *GpGraphics, pen: *GpPen, path: *GpPath)->GpStatus;
    func GdipFillPath(graphics: *GpGraphics, brush: *GpBrush, path: *GpPath)->GpStatus;
}
