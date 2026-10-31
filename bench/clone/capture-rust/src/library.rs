//! Library indexing and preview decoding never run on the UI thread.
use crate::{scc, storage, tagbin};
use image::RgbaImage;
use std::{
    fs::File,
    io::{Cursor, Read, Seek, SeekFrom},
    path::{Path, PathBuf},
    sync::mpsc::{self, Receiver, Sender, TryRecvError},
};

#[derive(Clone)]
pub struct Metadata {
    pub title: String,
    pub tags: String,
    pub favorite: bool,
    pub rating: u8,
    pub width: u32,
    pub height: u32,
    preview: tagbin::Value,
}

fn read_exact(file: &mut File, size: usize) -> Result<Vec<u8>, String> {
    let mut bytes = vec![0; size];
    file.read_exact(&mut bytes).map_err(|e| e.to_string())?;
    Ok(bytes)
}

pub fn metadata(path: &Path) -> Result<Metadata, String> {
    let mut file = File::open(path).map_err(|e| e.to_string())?;
    let file_size = file.metadata().map_err(|e| e.to_string())?.len();
    let prefix = read_exact(&mut file, 32)?;
    if &prefix[..8] != b"SWAGSCC\0" || prefix[8..16] != [1, 0, 0, 0, 0, 0, 0, 0] {
        return Err("Unsupported SCC envelope.".into());
    }
    let size = u64::from_le_bytes(prefix[16..24].try_into().unwrap());
    if size > 16 * 1024 * 1024 || size.saturating_add(32) > file_size {
        return Err("Invalid SCC library header length.".into());
    }
    let bytes = read_exact(&mut file, size as usize)?;
    if crc32fast::hash(&bytes) != u32::from_le_bytes(prefix[24..28].try_into().unwrap()) {
        return Err("SCC header checksum does not match.".into());
    }
    let header = tagbin::decode(&bytes, "core.scc.header")?;
    if scc::read_guid(header.get("containerKind"))? != scc::CONTAINER
        || header.n("declaredFileSize", 0) != file_size
    {
        return Err("Invalid capture library header.".into());
    }
    let manifest = header.get("manifest").ok_or("Missing capture manifest.")?;
    let profile = manifest
        .get("profileData")
        .and_then(tagbin::Value::bytes)
        .ok_or("Missing capture library metadata.")?;
    let profile = tagbin::decode(profile, "swag.capture.library-metadata")?;
    let preview = header
        .get("chunks")
        .ok_or("Missing capture chunks.")?
        .items()
        .iter()
        .find(|chunk| scc::read_guid(chunk.get("roleId")).ok() == Some(scc::PREVIEW))
        .cloned()
        .ok_or("Missing capture preview.")?;
    let start = preview.n("offset", 0);
    let length = preview.n("storedSize", 0);
    if start < size + 32
        || length > 16 * 1024 * 1024
        || start.checked_add(length).is_none_or(|end| end > file_size)
        || preview.n("decodedSize", 0) > 16 * 1024 * 1024
    {
        return Err("Invalid capture preview range.".into());
    }
    Ok(Metadata {
        title: {
            let title = manifest.s("name");
            if title.is_empty() {
                profile.s("sourceApplication")
            } else {
                title
            }
        },
        tags: manifest
            .get("tags")
            .map(|v| {
                v.items()
                    .iter()
                    .filter_map(tagbin::Value::string)
                    .collect::<Vec<_>>()
                    .join(", ")
            })
            .unwrap_or_default(),
        favorite: profile.n("favorite", 0) != 0,
        rating: profile.n("rating", 0).min(5) as u8,
        width: profile.n("width", 0) as u32,
        height: profile.n("height", 0) as u32,
        preview,
    })
}

pub fn preview(path: &Path, metadata: &Metadata) -> Result<RgbaImage, String> {
    let chunk = &metadata.preview;
    let mut file = File::open(path).map_err(|e| e.to_string())?;
    file.seek(SeekFrom::Start(chunk.n("offset", 0)))
        .map_err(|e| e.to_string())?;
    let bytes = read_exact(&mut file, chunk.n("storedSize", 0) as usize)?;
    if crc32fast::hash(&bytes) as u64 != chunk.n("storedChecksum", 0) {
        return Err("Capture preview checksum does not match.".into());
    }
    let codec = scc::read_guid(chunk.get("codecId"))?;
    let bytes = if codec == [0; 16] {
        bytes
    } else if codec == scc::DEFLATE {
        tagbin::inflate(&bytes, chunk.n("decodedSize", 0) as usize)?
    } else {
        return Err("Unsupported capture preview codec.".into());
    };
    if bytes.len() as u64 != chunk.n("decodedSize", 0)
        || crc32fast::hash(&bytes) as u64 != chunk.n("decodedChecksum", 0)
    {
        return Err("Decoded capture preview checksum does not match.".into());
    }
    let reader = || image::ImageReader::with_format(Cursor::new(&bytes), image::ImageFormat::Png);
    let (w, h) = reader().into_dimensions().map_err(|e| e.to_string())?;
    if w == 0 || h == 0 || w > 4096 || h > 4096 {
        return Err("Invalid capture preview dimensions.".into());
    }
    let image = reader().decode().map_err(|e| e.to_string())?.to_rgba8();
    Ok(image::imageops::thumbnail(&image, 432, 288))
}

pub enum Event {
    Files(Vec<PathBuf>),
    Metadata(usize, Result<Metadata, String>),
    Preview(usize, Result<RgbaImage, String>),
    Indexed,
}

pub struct Loader {
    requests: Sender<usize>,
    pub events: Receiver<Event>,
}

impl Loader {
    pub fn new(folder: PathBuf, ctx: eframe::egui::Context) -> Result<Self, String> {
        let (requests, incoming) = mpsc::channel::<usize>();
        // Back pressure bounds decoded images even while the window is minimized.
        let (outgoing, events) = mpsc::sync_channel(8);
        std::thread::Builder::new()
            .name("capture-library".into())
            .spawn(move || {
                let send = |event| {
                    let sent = outgoing.send(event).is_ok();
                    ctx.request_repaint();
                    sent
                };
                let paths = storage::recent_paths(&folder);
                let mut entries = vec![None; paths.len()];
                if !send(Event::Files(paths.clone())) {
                    return;
                }
                let mut next = 0;
                loop {
                    let request = match incoming.try_recv() {
                        Ok(index) => Some(index),
                        Err(TryRecvError::Disconnected) => return,
                        Err(TryRecvError::Empty) => None,
                    };
                    if let Some(index) = request {
                        if let Some(Some(metadata)) = entries.get(index) {
                            if !send(Event::Preview(index, preview(&paths[index], metadata))) {
                                return;
                            }
                        }
                    } else if next < paths.len() {
                        let result = metadata(&paths[next]);
                        if let Ok(metadata) = &result {
                            entries[next] = Some(metadata.clone());
                        }
                        if !send(Event::Metadata(next, result)) {
                            return;
                        }
                        next += 1;
                        if next == paths.len() && !send(Event::Indexed) {
                            return;
                        }
                    } else {
                        match incoming.recv() {
                            Ok(index) => {
                                if let Some(Some(metadata)) = entries.get(index) {
                                    if !send(Event::Preview(
                                        index,
                                        preview(&paths[index], metadata),
                                    )) {
                                        return;
                                    }
                                }
                            }
                            Err(_) => return,
                        }
                    }
                }
            })
            .map_err(|e| e.to_string())?;
        Ok(Self { requests, events })
    }

    pub fn request_preview(&self, index: usize) {
        let _ = self.requests.send(index);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn saved_preview_contains_annotations_and_uses_source_application_name() {
        use crate::document::{Document, Style, Tool};
        use eframe::egui::pos2;
        let root =
            std::env::temp_dir().join(format!("capture-annotated-preview-{}", std::process::id()));
        std::fs::create_dir_all(&root).unwrap();
        let path = root.join("capture.scc");
        let fixture = include_bytes!(
            "../../../../bin/apps/modules/swagcapture/src/tests/datas/capture-all-forms.scc"
        );
        let original = scc::decode(fixture).unwrap();
        let mut doc = Document::blank(128, 96);
        doc.source_fields = original.source_fields.clone();
        let expected = doc.source_fields.as_ref().unwrap().s("sourceApplication");
        assert!(!expected.is_empty());
        let id = doc.create(Tool::Line, pos2(16., 48.), Style::for_tool(Tool::Line));
        let form = doc.forms.iter_mut().find(|f| f.id == id).unwrap();
        form.style.outline = [255, 0, 0, 255];
        form.style.thickness = 12.;
        form.style.shadow = false;
        form.draw_to(pos2(16., 48.), pos2(112., 48.), false);
        storage::save(&path, &doc).unwrap();
        let meta = metadata(&path).unwrap();
        assert_eq!(meta.title, expected);
        let image = preview(&path, &meta).unwrap();
        let pixel = image.get_pixel(image.width() / 2, image.height() / 2);
        assert!(pixel[0] > 240 && pixel[1] < 15 && pixel[2] < 15);
        std::fs::remove_file(path).unwrap();
        std::fs::remove_dir(root).unwrap();
    }

    #[test]
    fn library_preview_does_not_decode_the_document_or_background() {
        let root = std::env::temp_dir().join(format!("capture-preview-{}", std::process::id()));
        std::fs::create_dir_all(&root).unwrap();
        let path = root.join("capture.scc");
        let mut bytes = include_bytes!(
            "../../../../bin/apps/modules/swagcapture/src/tests/datas/capture-all-forms.scc"
        )
        .to_vec();
        // Corrupt the first payload while preserving the header and independent PNG.
        let size = u64::from_le_bytes(bytes[16..24].try_into().unwrap()) as usize;
        let header = tagbin::decode(&bytes[32..32 + size], "core.scc.header").unwrap();
        let offset = header.get("chunks").unwrap().items()[0].n("offset", 0) as usize;
        bytes[offset] ^= 0xff;
        std::fs::write(&path, bytes).unwrap();
        assert!(storage::load(&path).is_err());
        let meta = metadata(&path).unwrap();
        assert_eq!(meta.title, "Serialization Contract");
        assert_eq!(meta.rating, 5);
        assert!(meta.favorite);
        assert!(preview(&path, &meta).unwrap().width() > 0);
        std::fs::remove_file(path).unwrap();
        std::fs::remove_dir(root).unwrap();
    }
}
