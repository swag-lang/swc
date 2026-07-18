#global export
#global #if #os == Swag.TargetOs.Windows
#global #[Swag.ExplicitNullability]
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
    DebugEventCallback:       #null *void
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
    func GdiplusStartup(token: #nonull *u64, input: #nonull const *GdiplusStartupInput, output: #null *void)->GpStatus;
    func GdiplusShutdown(token: u64);
}

#[Foreign("Gdiplus"), Discardable]
{
    func GdipCreateBitmapFromScan0(width, height, stride: s32, format: s32, scan0: #null [*] u8, bitmap: #nonull *#null *GpBitmap)->GpStatus;
    func GdipDisposeImage(image: #nonull *GpImage)->GpStatus;
    func GdipGetImageGraphicsContext(image: #nonull *GpImage, graphics: #nonull *#null *GpGraphics)->GpStatus;
    func GdipDeleteGraphics(graphics: #nonull *GpGraphics)->GpStatus;
    func GdipSetSmoothingMode(graphics: #nonull *GpGraphics, smoothingMode: s32)->GpStatus;
    func GdipSetPixelOffsetMode(graphics: #nonull *GpGraphics, pixelOffsetMode: s32)->GpStatus;
    func GdipSetTextRenderingHint(graphics: #nonull *GpGraphics, mode: s32)->GpStatus;
    func GdipGraphicsClear(graphics: #nonull *GpGraphics, color: u32)->GpStatus;
    func GdipCreateFontFamilyFromName(name: LPCWSTR, collection: #null *void, fontFamily: #nonull *#null *GpFontFamily)->GpStatus;
    func GdipDeleteFontFamily(fontFamily: #nonull *GpFontFamily)->GpStatus;
    func GdipCreateStringFormat(formatAttributes: s32, language: u16, format: #nonull *#null *GpStringFormat)->GpStatus;
    func GdipDeleteStringFormat(format: #nonull *GpStringFormat)->GpStatus;
    func GdipCreatePath(fillMode: s32, path: #nonull *#null *GpPath)->GpStatus;
    func GdipDeletePath(path: #nonull *GpPath)->GpStatus;
    func GdipAddPathString(path: #nonull *GpPath, text: LPCWSTR, length: s32, family: #nonull *GpFontFamily, style: s32, emSize: f32, layoutRect: #nonull const *GpRectF, format: #nonull *GpStringFormat)->GpStatus;
    func GdipGetPathWorldBounds(path: #nonull *GpPath, bounds: #nonull *GpRectF, matrix: #null *GpMatrix, pen: #null *GpPen)->GpStatus;
    func GdipCreatePen1(color: u32, width: f32, unit: s32, pen: #nonull *#null *GpPen)->GpStatus;
    func GdipSetPenLineJoin(pen: #nonull *GpPen, lineJoin: s32)->GpStatus;
    func GdipDeletePen(pen: #nonull *GpPen)->GpStatus;
    func GdipCreateSolidFill(color: u32, brush: #nonull *#null *GpSolidFill)->GpStatus;
    func GdipDeleteBrush(brush: #nonull *GpBrush)->GpStatus;
    func GdipDrawPath(graphics: #nonull *GpGraphics, pen: #nonull *GpPen, path: #nonull *GpPath)->GpStatus;
    func GdipFillPath(graphics: #nonull *GpGraphics, brush: #nonull *GpBrush, path: #nonull *GpPath)->GpStatus;
}
