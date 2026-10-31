use crate::document::Document;
use image::RgbaImage;
use serde::{Deserialize, Serialize};
use std::{
    fs,
    io::{Cursor, Read, Write},
    path::{Path, PathBuf},
};

const MAX_DOCUMENT: u64 = 512 * 1024 * 1024;
fn default_true() -> bool {
    true
}

pub fn png(image: &RgbaImage) -> Result<Vec<u8>, String> {
    let mut output = Cursor::new(Vec::new());
    image
        .write_to(&mut output, image::ImageFormat::Png)
        .map_err(|e| e.to_string())?;
    Ok(output.into_inner())
}

pub fn encode(doc: &Document) -> Result<Vec<u8>, String> {
    crate::scc::encode(doc)
}

pub fn decode(bytes: &[u8]) -> Result<Document, String> {
    crate::scc::decode(bytes)
}

pub fn load(path: &Path) -> Result<Document, String> {
    let mut file = fs::File::open(path).map_err(|e| e.to_string())?;
    if file.metadata().map_err(|e| e.to_string())?.len() > MAX_DOCUMENT {
        return Err("Capture file exceeds the size limit.".into());
    }
    let mut bytes = vec![];
    (&mut file)
        .take(MAX_DOCUMENT + 1)
        .read_to_end(&mut bytes)
        .map_err(|e| e.to_string())?;
    decode(&bytes)
}

pub fn recent_paths(folder: &Path) -> Vec<PathBuf> {
    let mut entries: Vec<_> = fs::read_dir(folder)
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .filter(|entry| {
            entry
                .path()
                .extension()
                .is_some_and(|e| e.eq_ignore_ascii_case("scc"))
                && !entry
                    .file_name()
                    .to_string_lossy()
                    .eq_ignore_ascii_case("settings.scc")
        })
        .collect();
    entries
        .sort_by_key(|entry| std::cmp::Reverse(entry.metadata().and_then(|m| m.modified()).ok()));
    entries.into_iter().map(|entry| entry.path()).collect()
}

pub fn newest_capture(folder: &Path) -> Option<(PathBuf, Document)> {
    recent_paths(folder)
        .into_iter()
        .find_map(|path| load(&path).ok().map(|doc| (path, doc)))
}

pub fn atomic_write(path: &Path, bytes: &[u8]) -> Result<(), String> {
    let parent = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    let name = format!(
        ".capture-{}-{}.tmp",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos()
    );
    let temporary = parent.join(name);
    let result = (|| -> std::io::Result<()> {
        let mut file = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temporary)?;
        file.write_all(bytes)?;
        file.sync_all()?;
        drop(file);
        fs::rename(&temporary, path)
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result.map_err(|e| e.to_string())
}

pub fn save(path: &Path, doc: &Document) -> Result<(), String> {
    atomic_write(path, &encode(doc)?)
}

#[derive(Clone, Serialize, Deserialize)]
pub struct Settings {
    pub theme: String,
    pub french: bool,
    pub capture_cursor: bool,
    pub capture_delay: u32,
    #[serde(default = "default_true")]
    pub hide_before_capture: bool,
    #[serde(default = "default_true")]
    pub capture_to_editor: bool,
    #[serde(default = "default_true")]
    pub capture_to_clipboard: bool,
    #[serde(default = "default_true")]
    pub capture_cross: bool,
    pub snap: bool,
    pub library: PathBuf,
    #[serde(default)]
    pub last_capture: Option<PathBuf>,
    #[serde(default)]
    pub inspector_folded: bool,
    #[serde(default)]
    pub show_recent: bool,
    #[serde(default)]
    pub edit_mode: u32,
    #[serde(default)]
    pub imported_from: Option<PathBuf>,
    #[serde(default)]
    pub window_rect: Option<[f32; 4]>,
    #[serde(default)]
    pub maximized: bool,
    #[serde(default)]
    pub presets: Vec<Vec<crate::document::Style>>,
}

impl Settings {
    pub fn default_at(root: &Path) -> Self {
        Self {
            theme: "Dark".into(),
            french: false,
            capture_cursor: false,
            capture_delay: 0,
            hide_before_capture: true,
            capture_to_editor: true,
            capture_to_clipboard: true,
            capture_cross: true,
            snap: true,
            library: root.join("captures"),
            last_capture: None,
            inspector_folded: false,
            show_recent: false,
            edit_mode: 0,
            imported_from: None,
            window_rect: None,
            maximized: false,
            presets: vec![],
        }
    }
    pub fn load(root: &Path) -> Self {
        fs::read(root.join("settings.json"))
            .ok()
            .and_then(|b| serde_json::from_slice(&b).ok())
            .unwrap_or_else(|| Self::default_at(root))
    }
    pub fn save(&self, root: &Path) -> Result<(), String> {
        atomic_write(
            &root.join("settings.json"),
            &serde_json::to_vec_pretty(self).map_err(|e| e.to_string())?,
        )
    }

    pub fn import_swag(path: &Path, root: &Path) -> Result<Self, String> {
        let bytes = fs::read(path).map_err(|e| e.to_string())?;
        let state = crate::scc::application_state(&bytes)?;
        let mut result = Self::default_at(root);
        let folder = state.s("MainWnd.libraryFolder");
        result.library = if folder.is_empty() {
            path.parent()
                .ok_or("Settings path has no parent.")?
                .to_path_buf()
        } else {
            folder.into()
        };
        result.snap = state.n("MainWnd.snap", 0) != 0;
        result.inspector_folded = state.n("MainWnd.inspectorFolded", 0) != 0;
        result.show_recent = state.n("MainWnd.showRecent", 0) != 0;
        result.edit_mode = state.n("MainWnd.editMode", 0) as u32;
        if let Some(window) = state.get("capture.mainwnd") {
            result.maximized = window.n("isMaximized", 0) != 0;
            let scale = window.f("savedDpiScale", 1.).max(0.5);
            if let Some(rect) = window.get(if result.maximized {
                "restoredPosition"
            } else {
                "position"
            }) {
                let values = if let Some(bytes) = rect.bytes().filter(|b| b.len() == 16) {
                    std::array::from_fn(|i| {
                        f32::from_le_bytes(bytes[i * 4..i * 4 + 4].try_into().unwrap()) / scale
                    })
                } else {
                    [
                        rect.f("x", 0.) / scale,
                        rect.f("y", 0.) / scale,
                        rect.f("width", 1200.) / scale,
                        rect.f("height", 800.) / scale,
                    ]
                };
                if values.iter().all(|v| v.is_finite()) && values[2] > 100. && values[3] > 100. {
                    result.window_rect = Some(values);
                }
            }
        }
        result.presets = crate::document::Tool::ALL
            .iter()
            .map(|tool| {
                let name = match tool {
                    crate::document::Tool::Select => return vec![],
                    crate::document::Tool::PixelSelection => "PixSel",
                    other => other.name(),
                };
                let Some(group) = state.get(&format!("QuickWnd.qs{name}")) else {
                    return vec![];
                };
                group
                    .get("forms")
                    .map(|v| {
                        v.items()
                            .iter()
                            .filter_map(|v| {
                                if let crate::tagbin::Value::Interface { key, value } = v {
                                    crate::scc::decode_form(0, key, value).ok().map(|f| f.style)
                                } else {
                                    None
                                }
                            })
                            .collect()
                    })
                    .unwrap_or_default()
            })
            .collect();
        if let Some(editor) = state.get("MainWnd.editorOptions") {
            result.theme = match editor.n("theme", 0) {
                1 => "Light",
                2 => "System",
                _ => "Dark",
            }
            .into();
            result.french = editor.n("language", 1) == 2;
        }
        if let Some(capture) = state.get("MainWnd.captureOptions") {
            result.capture_cursor = capture.n("captureCursor", 0) != 0;
            result.capture_delay = capture.n("delay", 0).min(60) as u32;
            result.hide_before_capture = capture.n("hideEditorBefore", 1) != 0;
            result.capture_to_editor = capture.n("sendToEditor", 1) != 0;
            result.capture_to_clipboard = capture.n("sendToClipboard", 1) != 0;
            result.capture_cross = capture.n("drawCross", 1) != 0;
        }
        result.last_capture = newest_capture(&result.library).map(|(path, _)| path);
        result.imported_from = Some(path.to_path_buf());
        atomic_write(&root.join("swag-settings.scc"), &bytes)?;
        atomic_write(
            &root.join("swag-state.json"),
            serde_json::to_string_pretty(&state)
                .map_err(|e| e.to_string())?
                .as_bytes(),
        )?;
        result.save(root)?;
        Ok(result)
    }
}

pub fn data_root() -> PathBuf {
    std::env::var_os("LOCALAPPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir)
        .join("SwagCaptureRust")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::document::*;
    use std::sync::Arc;
    #[test]
    fn startup_uses_modification_time_and_skips_settings_and_invalid_captures() {
        let root = std::env::temp_dir().join(format!("capture-recent-{}", std::process::id()));
        fs::create_dir_all(&root).unwrap();
        let older = root.join("z.scc");
        let newer = root.join("a.scc");
        let broken = root.join("broken.scc");
        for path in [&older, &newer, &root.join("settings.scc")] {
            save(path, &Document::blank(32, 24)).unwrap();
        }
        fs::write(&broken, b"invalid capture").unwrap();
        for (seconds, path) in [(10, &older), (20, &newer), (30, &broken)] {
            fs::File::options()
                .write(true)
                .open(path)
                .unwrap()
                .set_times(
                    fs::FileTimes::new().set_modified(
                        std::time::UNIX_EPOCH + std::time::Duration::from_secs(seconds),
                    ),
                )
                .unwrap();
        }
        assert_eq!(recent_paths(&root), vec![broken, newer.clone(), older]);
        let (path, doc) = newest_capture(&root).unwrap();
        assert_eq!(path, newer);
        assert_eq!((doc.width, doc.height), (32, 24));
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn round_trip_keeps_pixels_objects_and_original() {
        let mut doc = Document::blank(128, 96);
        doc.create(Tool::Text, eframe::egui::pos2(2., 3.), Style::default());
        doc.forms[0].text = "Éditeur 日本語".into();
        doc.create(Tool::Image, eframe::egui::pos2(30., 30.), Style::default());
        doc.forms[1].image = Some(Arc::new(RgbaImage::from_pixel(
            2,
            2,
            image::Rgba([1, 2, 3, 4]),
        )));
        doc.crop(eframe::egui::Rect::from_min_size(
            eframe::egui::Pos2::ZERO,
            eframe::egui::vec2(64., 48.),
        ));
        let bytes = encode(&doc).unwrap();
        let result = decode(&bytes).unwrap();
        assert_eq!(result.forms[0].text, doc.forms[0].text);
        assert_eq!(result.background, doc.background);
        assert_eq!(result.original, doc.original);
        assert_eq!(result.forms[1].image, doc.forms[1].image);
        for len in [0, 7, 8, 16, bytes.len() - 1] {
            assert!(decode(&bytes[..len]).is_err());
        }
    }
}
