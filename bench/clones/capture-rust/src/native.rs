use image::RgbaImage;
use std::ptr::null_mut;
use windows_sys::Win32::{
    Foundation::*,
    Graphics::Gdi::*,
    UI::{HiDpi::*, Input::KeyboardAndMouse::GetActiveWindow, WindowsAndMessaging::*},
};

#[derive(Clone, Copy, Debug)]
pub struct ScreenRect {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
}

#[derive(Clone, Copy)]
pub struct WindowToken(isize);

impl WindowToken {
    #[cfg(test)]
    pub(crate) const fn headless() -> Self {
        Self(0)
    }

    pub fn active() -> Result<Self, String> {
        let window = unsafe { GetActiveWindow() };
        if window.is_null() {
            Err("The capture window is unavailable.".into())
        } else {
            Ok(Self(window as isize))
        }
    }
    fn handle(self) -> Option<HWND> {
        let window = self.0 as HWND;
        let mut process = 0;
        unsafe {
            GetWindowThreadProcessId(window, &mut process);
        }
        (process == std::process::id()).then_some(window)
    }
    pub fn rect(self) -> Result<ScreenRect, String> {
        let window = self.handle().ok_or("The capture window has closed.")?;
        let mut r = RECT::default();
        if unsafe { GetWindowRect(window, &mut r) } == 0 {
            return Err(std::io::Error::last_os_error().to_string());
        }
        Ok(ScreenRect {
            x: r.left,
            y: r.top,
            width: r.right - r.left,
            height: r.bottom - r.top,
        })
    }
    pub fn visible(self) -> bool {
        self.handle()
            .is_some_and(|window| unsafe { IsWindowVisible(window) != 0 })
    }
    pub fn client_rect(self) -> Result<ScreenRect, String> {
        let window = self.handle().ok_or("The capture window has closed.")?;
        let mut rect = RECT::default();
        let mut origin = POINT::default();
        if unsafe { GetClientRect(window, &mut rect) } == 0
            || unsafe { ClientToScreen(window, &mut origin) } == 0
        {
            return Err(std::io::Error::last_os_error().to_string());
        }
        Ok(ScreenRect {
            x: origin.x,
            y: origin.y,
            width: rect.right,
            height: rect.bottom,
        })
    }
    pub fn place_client(self, rect: ScreenRect) {
        if let (Ok(outer), Ok(client)) = (self.rect(), self.client_rect()) {
            self.place(
                ScreenRect {
                    x: rect.x - (client.x - outer.x),
                    y: rect.y - (client.y - outer.y),
                    width: rect.width + outer.width - client.width,
                    height: rect.height + outer.height - client.height,
                },
                true,
            );
        }
    }
    pub fn hide(self) {
        if let Some(window) = self.handle() {
            unsafe {
                ShowWindow(window, SW_HIDE);
            }
        }
    }
    pub fn show(self) {
        // This posts to the native message loop, even when no hidden-window frames run.
        if let Some(window) = self.handle() {
            unsafe {
                ShowWindowAsync(window, SW_SHOW);
            }
        }
    }
    pub fn place(self, rect: ScreenRect, topmost: bool) {
        if let Some(window) = self.handle() {
            unsafe {
                SetWindowPos(
                    window,
                    if topmost {
                        HWND_TOPMOST
                    } else {
                        HWND_NOTOPMOST
                    },
                    rect.x,
                    rect.y,
                    rect.width,
                    rect.height,
                    SWP_SHOWWINDOW | SWP_NOACTIVATE,
                );
            }
        }
    }
}

pub struct Captured {
    pub rect: ScreenRect,
    pub image: RgbaImage,
}

pub fn capture_async(
    window: WindowToken,
    active_window: bool,
    region: Option<ScreenRect>,
    cursor: bool,
    delay: std::time::Duration,
    ctx: eframe::egui::Context,
) -> Result<std::sync::mpsc::Receiver<Result<Captured, String>>, String> {
    let (worker, result) = std::sync::mpsc::channel();
    let (finished, receiver) = std::sync::mpsc::channel();
    std::thread::Builder::new()
        .name("capture-screen".into())
        .spawn(move || {
            std::thread::sleep(delay);
            let rect = region.unwrap_or_else(|| {
                if active_window {
                    foreground_rect().unwrap_or_else(desktop_rect)
                } else {
                    desktop_rect()
                }
            });
            let _ = worker.send(capture(rect, cursor).map(|image| Captured { rect, image }));
        })
        .map_err(|e| e.to_string())?;
    if let Err(error) = std::thread::Builder::new()
        .name("capture-completion".into())
        .spawn(move || {
            let outcome = result
                .recv_timeout(delay + std::time::Duration::from_secs(15))
                .unwrap_or_else(|e| Err(format!("Screen capture did not complete: {e}")));
            let _ = finished.send(outcome);
            window.show();
            ctx.request_repaint();
        })
    {
        window.show();
        return Err(error.to_string());
    }
    Ok(receiver)
}

pub fn enable_dpi() {
    unsafe {
        SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    }
}

/// Gets the installed face selected by Windows, without depending on font file paths.
pub fn font_bytes(name: &str, bold: bool, italic: bool) -> Option<Vec<u8>> {
    unsafe {
        let dc = CreateCompatibleDC(null_mut());
        if dc.is_null() {
            return None;
        }
        let mut description = LOGFONTW::default();
        description.lfHeight = -48;
        description.lfWeight = if bold { 700 } else { 400 };
        description.lfItalic = italic as u8;
        for (dst, src) in description
            .lfFaceName
            .iter_mut()
            .take(31)
            .zip(name.encode_utf16())
        {
            *dst = src;
        }
        let font = CreateFontIndirectW(&description);
        if font.is_null() {
            DeleteDC(dc);
            return None;
        }
        let old = SelectObject(dc, font);
        let size = GetFontData(dc, 0, 0, null_mut(), 0);
        let result = if size != GDI_ERROR as u32 && size > 0 && size < 64 * 1024 * 1024 {
            let mut bytes = vec![0; size as usize];
            if GetFontData(dc, 0, 0, bytes.as_mut_ptr().cast(), size) == size {
                Some(bytes)
            } else {
                None
            }
        } else {
            None
        };
        SelectObject(dc, old);
        DeleteObject(font);
        DeleteDC(dc);
        result
    }
}

pub fn desktop_rect() -> ScreenRect {
    unsafe {
        ScreenRect {
            x: GetSystemMetrics(SM_XVIRTUALSCREEN),
            y: GetSystemMetrics(SM_YVIRTUALSCREEN),
            width: GetSystemMetrics(SM_CXVIRTUALSCREEN),
            height: GetSystemMetrics(SM_CYVIRTUALSCREEN),
        }
    }
}

pub fn foreground_rect() -> Option<ScreenRect> {
    unsafe {
        let window = GetForegroundWindow();
        let mut r = RECT::default();
        if window.is_null() || GetWindowRect(window, &mut r) == 0 {
            return None;
        }
        Some(ScreenRect {
            x: r.left,
            y: r.top,
            width: r.right - r.left,
            height: r.bottom - r.top,
        })
    }
}

pub fn capture(rect: ScreenRect, cursor: bool) -> Result<RgbaImage, String> {
    if rect.width <= 0
        || rect.height <= 0
        || rect.width > 32768
        || rect.height > 32768
        || rect.width as u64 * rect.height as u64 > 64 * 1024 * 1024
    {
        return Err("Invalid capture dimensions.".into());
    }
    unsafe {
        let screen = GetDC(null_mut());
        if screen.is_null() {
            return Err(std::io::Error::last_os_error().to_string());
        }
        let dc = CreateCompatibleDC(screen);
        let bitmap = CreateCompatibleBitmap(screen, rect.width, rect.height);
        if dc.is_null() || bitmap.is_null() {
            if !bitmap.is_null() {
                DeleteObject(bitmap);
            }
            if !dc.is_null() {
                DeleteDC(dc);
            }
            ReleaseDC(null_mut(), screen);
            return Err(std::io::Error::last_os_error().to_string());
        }
        let old = SelectObject(dc, bitmap);
        let ok = BitBlt(
            dc,
            0,
            0,
            rect.width,
            rect.height,
            screen,
            rect.x,
            rect.y,
            SRCCOPY | CAPTUREBLT,
        );
        if cursor {
            let mut info = CURSORINFO {
                cbSize: size_of::<CURSORINFO>() as u32,
                ..Default::default()
            };
            if GetCursorInfo(&mut info) != 0 && info.flags == CURSOR_SHOWING {
                let mut icon = ICONINFO::default();
                if GetIconInfo(info.hCursor, &mut icon) != 0 {
                    DrawIconEx(
                        dc,
                        info.ptScreenPos.x - rect.x - icon.xHotspot as i32,
                        info.ptScreenPos.y - rect.y - icon.yHotspot as i32,
                        info.hCursor,
                        0,
                        0,
                        0,
                        null_mut(),
                        DI_NORMAL,
                    );
                    if !icon.hbmMask.is_null() {
                        DeleteObject(icon.hbmMask);
                    }
                    if !icon.hbmColor.is_null() {
                        DeleteObject(icon.hbmColor);
                    }
                }
            }
        }
        SelectObject(dc, old);
        let mut info = BITMAPINFO::default();
        info.bmiHeader = BITMAPINFOHEADER {
            biSize: size_of::<BITMAPINFOHEADER>() as u32,
            biWidth: rect.width,
            biHeight: -rect.height,
            biPlanes: 1,
            biBitCount: 32,
            biCompression: BI_RGB,
            ..Default::default()
        };
        let mut pixels = vec![0u8; rect.width as usize * rect.height as usize * 4];
        let rows = if ok != 0 {
            GetDIBits(
                dc,
                bitmap,
                0,
                rect.height as u32,
                pixels.as_mut_ptr().cast(),
                &mut info,
                DIB_RGB_COLORS,
            )
        } else {
            0
        };
        DeleteObject(bitmap);
        DeleteDC(dc);
        ReleaseDC(null_mut(), screen);
        if rows != rect.height {
            return Err(std::io::Error::last_os_error().to_string());
        }
        for p in pixels.chunks_exact_mut(4) {
            p.swap(0, 2);
            p[3] = 255;
        }
        RgbaImage::from_raw(rect.width as u32, rect.height as u32, pixels)
            .ok_or_else(|| "Invalid capture buffer.".into())
    }
}

pub fn clipboard_image() -> Result<RgbaImage, String> {
    let mut clipboard = arboard::Clipboard::new().map_err(|e| e.to_string())?;
    let image = clipboard.get_image().map_err(|e| e.to_string())?;
    RgbaImage::from_raw(
        image.width as u32,
        image.height as u32,
        image.bytes.into_owned(),
    )
    .ok_or_else(|| "Invalid clipboard image.".into())
}

pub fn copy_image(image: &RgbaImage) -> Result<(), String> {
    arboard::Clipboard::new()
        .map_err(|e| e.to_string())?
        .set_image(arboard::ImageData {
            width: image.width() as usize,
            height: image.height() as usize,
            bytes: std::borrow::Cow::Borrowed(image.as_raw()),
        })
        .map_err(|e| e.to_string())
}

pub fn memory_bytes() -> (u64, u64) {
    use windows_sys::Win32::System::{ProcessStatus::*, Threading::*};
    unsafe {
        let mut info = PROCESS_MEMORY_COUNTERS_EX::default();
        info.cb = size_of::<PROCESS_MEMORY_COUNTERS_EX>() as u32;
        if GetProcessMemoryInfo(
            GetCurrentProcess(),
            (&mut info as *mut PROCESS_MEMORY_COUNTERS_EX).cast(),
            info.cb,
        ) == 0
        {
            return (0, 0);
        }
        (info.WorkingSetSize as u64, info.PrivateUsage as u64)
    }
}
