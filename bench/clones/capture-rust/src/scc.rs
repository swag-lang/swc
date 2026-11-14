//! Swag Capture's SCC envelope and TagBin document profile.
use crate::{
    document::*,
    tagbin::{self, *},
};
use eframe::egui::{Rect, pos2};
use image::RgbaImage;
use std::sync::{
    Arc,
    atomic::{AtomicU64, Ordering},
};

pub(crate) const CONTAINER: [u8; 16] = [
    0x4a, 0x67, 0xac, 0xc2, 0x59, 0x30, 0x4e, 0x81, 0x81, 0xdc, 0xd1, 0x26, 0x75, 0xbc, 0x6d, 0xeb,
];
const MODEL: [u8; 16] = [
    0x6e, 0x67, 0x7e, 0xce, 0x90, 0x01, 0x44, 0xbf, 0x94, 0xcd, 0x67, 0x21, 0xbd, 0xd7, 0xc3, 0x39,
];
const BACKGROUND: [u8; 16] = [
    0x64, 0x8e, 0x64, 0xf2, 0xca, 0x4b, 0x43, 0xef, 0x80, 0x76, 0x6e, 0x0d, 0xd0, 0x52, 0x3e, 0xc5,
];
const ORIGINAL: [u8; 16] = [
    0x72, 0x06, 0xea, 0x20, 0xcd, 0x74, 0x48, 0x32, 0xaf, 0xa9, 0x0c, 0xe3, 0x3c, 0x76, 0x99, 0xcd,
];
pub(crate) const PREVIEW: [u8; 16] = [
    0x9b, 0x5e, 0x37, 0x5d, 0xe6, 0x15, 0x4a, 0x80, 0x86, 0x80, 0x6c, 0x7c, 0x37, 0xf9, 0x4c, 0xeb,
];
const TAGBIN: [u8; 16] = [
    0x4d, 0x9b, 0x85, 0xe3, 0xf2, 0xec, 0x4b, 0x30, 0x81, 0xa9, 0x4d, 0x7f, 0x6c, 0xa7, 0xfe, 0xfa,
];
const PNG: [u8; 16] = [
    0x97, 0x22, 0x20, 0x7f, 0x35, 0x61, 0x44, 0xa9, 0xbf, 0x04, 0x3c, 0x8c, 0x52, 0x38, 0xc9, 0x19,
];
pub(crate) const DEFLATE: [u8; 16] = [
    0x21, 0xbf, 0x86, 0xc9, 0x55, 0xf7, 0x4c, 0x90, 0xa4, 0x54, 0x2f, 0x07, 0x0a, 0x0f, 0x6e, 0x9b,
];
const LIMIT: usize = 256 * 1024 * 1024;

fn guid(bytes: [u8; 16]) -> Value {
    object(
        0,
        vec![field(
            "value",
            0x240256e7,
            object(
                0,
                vec![
                    field("bytes", 0x3cbf1e1d, raw_sequence(16, bytes.to_vec())),
                    field("words", 0x3d8667eb, raw_sequence(2, bytes.to_vec())),
                ],
            ),
        )],
    )
}
pub(crate) fn read_guid(value: Option<&Value>) -> Result<[u8; 16], String> {
    value
        .and_then(|v| v.get("value"))
        .and_then(|v| v.get("bytes"))
        .and_then(Value::bytes)
        .and_then(|b| b.try_into().ok())
        .ok_or_else(|| "Invalid SCC identifier.".into())
}
fn new_id() -> [u8; 16] {
    static NEXT: AtomicU64 = AtomicU64::new(0);
    let t = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let mut bytes = (t
        ^ ((std::process::id() as u128) << 64)
        ^ ((NEXT.fetch_add(1, Ordering::Relaxed) as u128) << 32))
        .to_le_bytes();
    bytes[6] = (bytes[6] & 15) | 0x40;
    bytes[8] = (bytes[8] & 63) | 0x80;
    bytes
}
fn u32_at(bytes: &[u8], at: usize) -> Result<u32, String> {
    Ok(u32::from_le_bytes(
        bytes
            .get(at..at + 4)
            .ok_or("Truncated SCC header.")?
            .try_into()
            .unwrap(),
    ))
}
fn u64_at(bytes: &[u8], at: usize) -> Result<u64, String> {
    Ok(u64::from_le_bytes(
        bytes
            .get(at..at + 8)
            .ok_or("Truncated SCC header.")?
            .try_into()
            .unwrap(),
    ))
}

pub fn application_state(bytes: &[u8]) -> Result<Value, String> {
    if !bytes.starts_with(b"SWAGSCC\0") {
        return tagbin::decode(bytes, "gui.application-state");
    }
    let end = 32usize
        .checked_add(usize::try_from(u64_at(bytes, 16)?).map_err(|e| e.to_string())?)
        .filter(|n| *n <= bytes.len())
        .ok_or("Truncated settings header.")?;
    let header_bytes = &bytes[32..end];
    if crc32fast::hash(header_bytes) != u32_at(bytes, 24)? {
        return Err("Settings header checksum does not match.".into());
    }
    let header = tagbin::decode(header_bytes, "core.scc.header")?;
    let state_kind = [
        0x89, 0xc9, 0x8d, 0x18, 0x11, 0xdc, 0x42, 0xa0, 0x91, 0x0c, 0x4b, 0xb6, 0x4b, 0x3e, 0x27,
        0x76,
    ];
    if read_guid(header.get("containerKind"))? != state_kind {
        return Err("This SCC file does not contain application settings.".into());
    }
    let state_role = [
        0xa3, 0x7d, 0x3a, 0xf6, 0x2b, 0xa5, 0x4b, 0xc4, 0xb7, 0x96, 0x48, 0x87, 0x8f, 0xd0, 0x9f,
        0xe4,
    ];
    for chunk in header
        .get("chunks")
        .ok_or("Missing settings chunks.")?
        .items()
    {
        if read_guid(chunk.get("roleId"))? != state_role {
            continue;
        }
        let start = usize::try_from(chunk.n("offset", 0)).map_err(|e| e.to_string())?;
        let length = usize::try_from(chunk.n("storedSize", 0)).map_err(|e| e.to_string())?;
        let end = start
            .checked_add(length)
            .filter(|n| *n <= bytes.len())
            .ok_or("Truncated settings chunk.")?;
        let stored = &bytes[start..end];
        if crc32fast::hash(stored) as u64 != chunk.n("storedChecksum", 0) {
            return Err("Settings chunk checksum does not match.".into());
        }
        let codec = read_guid(chunk.get("codecId"))?;
        let data = if codec == [0; 16] {
            stored.to_vec()
        } else if codec == DEFLATE {
            inflate(stored, chunk.n("decodedSize", 0) as usize)?
        } else {
            return Err("Unsupported settings codec.".into());
        };
        if crc32fast::hash(&data) as u64 != chunk.n("decodedChecksum", 0) {
            return Err("Decoded settings checksum does not match.".into());
        }
        return tagbin::decode(&data, "gui.application-state");
    }
    Err("Missing application settings.".into())
}

pub fn decode(bytes: &[u8]) -> Result<Document, String> {
    if bytes.len() > LIMIT
        || !bytes.starts_with(b"SWAGSCC\0")
        || u32_at(bytes, 8)? != 1
        || u32_at(bytes, 12)? != 0
        || u32_at(bytes, 28)? != 0
    {
        return Err("Unsupported SCC envelope.".into());
    }
    let size = usize::try_from(u64_at(bytes, 16)?).map_err(|e| e.to_string())?;
    let header_end = 32usize
        .checked_add(size)
        .filter(|n| *n <= bytes.len())
        .ok_or("Truncated SCC header.")?;
    let header_bytes = &bytes[32..header_end];
    if crc32fast::hash(header_bytes) != u32_at(bytes, 24)? {
        return Err("SCC header checksum does not match.".into());
    }
    let header = tagbin::decode(header_bytes, "core.scc.header")?;
    if read_guid(header.get("containerKind"))? != CONTAINER {
        return Err("This SCC file is not a capture.".into());
    }
    if header.n("declaredFileSize", 0) != bytes.len() as u64 {
        return Err("SCC file length does not match.".into());
    }
    let manifest = header.get("manifest").ok_or("Missing SCC manifest.")?;
    if manifest.n("profileVersion", 0) > 1 {
        return Err("Unsupported capture profile version.".into());
    }
    let mut model = None;
    let mut background = None;
    let mut original = None;
    let mut previous_end = header_end;
    for chunk in header.get("chunks").ok_or("Missing SCC chunks.")?.items() {
        let offset = usize::try_from(chunk.n("offset", 0)).map_err(|e| e.to_string())?;
        let size = usize::try_from(chunk.n("storedSize", 0)).map_err(|e| e.to_string())?;
        let end = offset
            .checked_add(size)
            .filter(|n| *n <= bytes.len())
            .ok_or("Truncated SCC chunk.")?;
        if offset < previous_end {
            return Err("SCC chunks overlap.".into());
        }
        previous_end = end;
        let stored = &bytes[offset..end];
        if crc32fast::hash(stored) as u64 != chunk.n("storedChecksum", 0) {
            return Err("SCC chunk checksum does not match.".into());
        }
        let role = read_guid(chunk.get("roleId"))?;
        if ![MODEL, BACKGROUND, ORIGINAL].contains(&role) {
            continue;
        }
        let codec = read_guid(chunk.get("codecId"))?;
        let decoded_size = usize::try_from(chunk.n("decodedSize", 0)).map_err(|e| e.to_string())?;
        let decoded = if codec == [0; 16] {
            if decoded_size != stored.len() {
                return Err("SCC stored size does not match.".into());
            }
            stored.to_vec()
        } else if codec == DEFLATE {
            inflate(stored, decoded_size)?
        } else {
            return Err("Unsupported SCC codec.".into());
        };
        if crc32fast::hash(&decoded) as u64 != chunk.n("decodedChecksum", 0) {
            return Err("SCC decoded checksum does not match.".into());
        }
        if role == MODEL {
            model = Some(tagbin::decode(&decoded, "swag.capture.document")?);
        } else {
            let image = decode_image(&tagbin::decode(&decoded, "pixel.image")?)?;
            if role == BACKGROUND {
                background = Some(image);
            } else {
                original = Some(image);
            }
        }
    }
    let mut model = model.ok_or("Missing capture document.")?;
    let (width, height) = (model.n("width", 0), model.n("height", 0));
    if width == 0
        || height == 0
        || width > 32768
        || height > 32768
        || width * height > 64 * 1024 * 1024
    {
        return Err("Invalid capture canvas dimensions.".into());
    }
    let mut doc = Document::from_image(
        background.unwrap_or_else(|| RgbaImage::new(width as u32, height as u32)),
        "Screen",
    );
    doc.width = width as u32;
    doc.height = height as u32;
    if let Some(position) = model.get("backImagePos").and_then(Value::bytes) {
        if position.len() != 8 {
            return Err("Invalid capture background position.".into());
        }
        doc.background_position = std::array::from_fn(|i| {
            f32::from_le_bytes(position[i * 4..i * 4 + 4].try_into().unwrap())
        });
        if !doc.background_position.iter().all(|n| n.is_finite()) {
            return Err("Invalid capture background position.".into());
        }
    }
    if let Some(image) = original {
        doc.original = Arc::new(image);
    }
    doc.title = model.s("title");
    doc.favorite = model.n("favorite", 0) != 0;
    doc.rating = model.n("rating", 0).min(5) as u8;
    doc.tags = model
        .get("tags")
        .map(|v| {
            v.items()
                .iter()
                .filter_map(Value::string)
                .collect::<Vec<_>>()
                .join(", ")
        })
        .unwrap_or_default();
    doc.next_step = model.n("nextStepIndex", 1) as u32;
    doc.next_group = model.n("nextGroupId", 1);
    for value in model
        .get("forms")
        .ok_or("Missing capture objects.")?
        .items()
    {
        let Value::Interface { key, value } = value else {
            return Err("Invalid capture object.".into());
        };
        doc.forms.push(decode_form(doc.next_id, key, value)?);
        doc.next_id += 1;
    }
    model.set("forms", FORMS, sequence(vec![]));
    doc.source_fields = Some(Arc::new(model));
    Ok(doc)
}

fn decode_image(value: &Value) -> Result<RgbaImage, String> {
    let w = value.n("width", 0) as u32;
    let h = value.n("height", 0) as u32;
    if w == 0 || h == 0 || w > 32768 || h > 32768 || w as u64 * h as u64 > 64 * 1024 * 1024 {
        return Err("Invalid SCC image dimensions.".into());
    }
    let format = value.n("pixelFormat", 1);
    let channels = match format {
        0 | 2 => 3,
        1 | 3 => 4,
        5 => 1,
        6 => 2,
        _ => return Err("Unsupported SCC pixel format.".into()),
    };
    let pixels = value
        .get("pixels")
        .and_then(Value::bytes)
        .ok_or("Missing SCC image pixels.")?;
    let stride = w as usize * channels;
    if pixels.len() != stride * h as usize
        || value.n("rowStride", 0) as usize != stride
        || value.n("byteCount", 0) as usize != pixels.len()
    {
        return Err("Invalid SCC pixel buffer length.".into());
    }
    let mut image = RgbaImage::new(w, h);
    for (x, y, pixel) in image.enumerate_pixels_mut() {
        let i = (h as usize - 1 - y as usize) * stride + x as usize * channels;
        let p = &pixels[i..i + channels];
        let mut rgba = match format {
            0 => [p[2], p[1], p[0], 255],
            1 => [p[2], p[1], p[0], p[3]],
            2 => [p[0], p[1], p[2], 255],
            3 => [p[0], p[1], p[2], p[3]],
            5 => [p[0], p[0], p[0], 255],
            _ => [p[0], p[0], p[0], p[1]],
        };
        if value.n("alphaMode", 0) == 1 && rgba[3] > 0 {
            for c in 0..3 {
                rgba[c] = ((rgba[c] as u32 * 255) / rgba[3] as u32).min(255) as u8;
            }
        }
        *pixel = image::Rgba(rgba);
    }
    Ok(image)
}

fn encode_image(image: &RgbaImage) -> Value {
    let mut pixels = vec![];
    for row in image.rows().rev() {
        for pixel in row {
            pixels.extend_from_slice(&pixel.0);
        }
    }
    object(
        0,
        vec![
            field("pixels", BYTES, raw_sequence(pixels.len(), pixels)),
            field("metadata", 0xbe2fc4e2, sequence(vec![])),
            field("byteCount", U64, long(image.as_raw().len() as u64)),
            field("width", I32, integer(image.width())),
            field("height", I32, integer(image.height())),
            field("rowStride", I32, integer(image.width() * 4)),
            field("pixelFormat", U8, byte(3)),
            field("alphaMode", U8, byte(0)),
            field("bitsPerPixel", U8, byte(32)),
            field("bytesPerPixel", U8, byte(4)),
        ],
    )
}

fn color(value: Option<&Value>, fallback: [u8; 4]) -> [u8; 4] {
    if let Some(bytes) = value.and_then(Value::bytes) {
        if bytes.len() >= 4 {
            return [bytes[2], bytes[1], bytes[0], bytes[3]];
        }
    }
    fallback
}
fn color_value(color: [u8; 4]) -> Value {
    let bgra = [color[2], color[1], color[0], color[3]];
    Value::Raw(bgra.into_iter().chain(bgra).collect())
}
fn base_of(value: &Value) -> &Value {
    value.get("base").unwrap_or(value)
}

pub(crate) fn decode_form(id: u64, key: &str, source: &Value) -> Result<Form, String> {
    let tool = match key {
        "swag.capture.form.shape" => Tool::Shape,
        "swag.capture.form.line" => Tool::Line,
        "swag.capture.form.arrow" => Tool::Arrow,
        "swag.capture.form.polygon" => Tool::Polygon,
        "swag.capture.form.draw" => Tool::Draw,
        "swag.capture.form.text" => Tool::Text,
        "swag.capture.form.step" => Tool::Step,
        "swag.capture.form.image" => Tool::Image,
        "swag.capture.form.callout" => Tool::Callout,
        _ => return Err(format!("Unsupported capture object {key}.")),
    };
    let value = source.get("line").unwrap_or(source);
    let base = base_of(value);
    let style = Style {
        fill: color(base.get("backColor"), [232, 8, 8, 255]),
        outline: color(base.get("borderColor"), [255; 4]),
        thickness: base.f("borderSize", 5.),
        opacity: base.n("alpha", 100) as f32,
        rotation: base.f("rotate", 0.),
        shadow: base.n("paintShadow", 1) != 0,
        font_size: value.f("fontSize", 48.),
        radius: value.f("roundSize", 10.),
        shape: match value.n("kind", 0) {
            1 => ShapeKind::Rectangle,
            2 => ShapeKind::Rounded,
            _ => ShapeKind::Ellipse,
        },
        image_kind: match value.n("kind", 0) {
            1 => ImageKind::Blur,
            2 => ImageKind::Pixelate,
            3 => ImageKind::Zoom,
            _ => ImageKind::Image,
        },
        strength: value.n("strength", 50) as u32,
        arrow_size: value.f("endSize", 3.),
        bold: value.n("fontStyle", 0) & 1 != 0,
        italic: value.n("fontStyle", 0) & 2 != 0,
        filled: color(base.get("backColor"), [232, 8, 8, 255])[3] != 0,
        font_name: {
            let name = value.s("fontName");
            if name.is_empty() {
                "Inter".into()
            } else {
                name
            }
        },
        align_h: value.n("alignHorz", 2) as u32,
        align_v: value.n("alignVert", 2) as u32,
        line_spacing: value.f("lineSpacing", 14.),
        bold_size: value.f("boldSize", 0.),
        scale: base.f("scale", 0.),
        join: base.n("joinStyle", 2) as u32,
        dash: base.n("dashStyle", 0) as u32,
        bezier: base.n("bezier", 0) != 0,
        begin_cap: value.n("beginCap", 2) as u32,
        end_cap: value.n("endCap", if tool == Tool::Arrow { 4 } else { 2 }) as u32,
        start_size: value.f("startSize", 4.),
        line_outline: value.f("outlineSize", 0.),
        line_outline_color: color(value.get("outlineColor"), [0, 0, 0, 255]),
        numbering: value.n("typeIndex", 0) as u32,
        text_color: color(value.get("textColor"), [255; 4]),
        ..Style::default()
    };
    let mut form = Form::new(
        id,
        tool,
        pos2(
            base.n("x", 0) as u32 as i32 as f32,
            base.n("y", 0) as u32 as i32 as f32,
        ),
        style,
        value.n("index", 1) as u32,
    );
    form.bounds[2] = base.n("w", 32) as f32;
    form.bounds[3] = base.n("h", 32) as f32;
    form.text = value.s("text");
    form.control = [
        value.f("xa", 0.) + value.f("xc", 10.),
        value.f("ya", 0.) + value.f("yc", 10.),
    ];
    form.tail = [
        value.f("tailX", form.bounds[0]),
        value.f("tailY", form.bounds[1] + form.bounds[3] + 10.),
    ];
    if base.n("subKind", 0) == 1 {
        form.tool = Tool::Highlight;
    }
    if let Some(bytes) = base.get("groups").and_then(Value::bytes) {
        if bytes.len() % 8 != 0 {
            return Err("Invalid capture group list.".into());
        }
        form.groups = bytes
            .chunks_exact(8)
            .map(|b| u64::from_le_bytes(b.try_into().unwrap()))
            .collect();
    }
    if matches!(tool, Tool::Arrow | Tool::Line) {
        form.points = vec![
            [value.f("xa", 0.), value.f("ya", 0.)],
            [value.f("xb", 32.), value.f("yb", 32.)],
        ];
    } else if let Some(bytes) = value.get("points").and_then(Value::bytes) {
        if bytes.len() % 8 != 0 {
            return Err("Invalid capture point list.".into());
        }
        form.points = bytes
            .chunks_exact(8)
            .map(|b| {
                [
                    f32::from_le_bytes(b[..4].try_into().unwrap()),
                    f32::from_le_bytes(b[4..].try_into().unwrap()),
                ]
            })
            .collect();
    }
    if matches!(tool, Tool::Arrow | Tool::Line | Tool::Polygon | Tool::Draw)
        && !form.points.is_empty()
    {
        let r = Rect::from_points(
            &form
                .points
                .iter()
                .map(|p| pos2(p[0], p[1]))
                .collect::<Vec<_>>(),
        );
        form.bounds = [r.min.x, r.min.y, r.width().max(1.), r.height().max(1.)];
    }
    if tool == Tool::Image {
        if let Some(value) = value.get("image") {
            if value.n("width", 0) > 0 {
                form.image = Some(Arc::new(decode_image(value)?));
            }
        }
    }
    form.source_fields = Some(Arc::new(source.clone()));
    Ok(form)
}

fn encode_form(form: &Form) -> Value {
    let mut source = form
        .source_fields
        .as_deref()
        .cloned()
        .unwrap_or_else(|| object(0, vec![]));
    let mut value = source
        .get("line")
        .cloned()
        .unwrap_or_else(|| source.clone());
    let mut base = value
        .get("base")
        .cloned()
        .unwrap_or_else(|| object(0, vec![]));
    for (i, k) in ["x", "y", "w", "h"].iter().enumerate() {
        base.set(k, I32, integer(form.bounds[i] as i32 as u32));
    }
    base.set("borderSize", F32, float(form.style.thickness));
    base.set("rotate", F32, float(form.style.rotation));
    base.set("scale", F32, float(form.style.scale));
    base.set("joinStyle", I32, integer(form.style.join));
    base.set("dashStyle", I32, integer(form.style.dash));
    base.set("bezier", BOOL, byte(form.style.bezier as u8));
    base.set("alpha", U8, byte(form.style.opacity.clamp(0., 100.) as u8));
    base.set("paintShadow", BOOL, byte(form.style.shadow as u8));
    let mut fill = form.style.fill;
    if !form.style.filled && matches!(form.tool, Tool::Shape | Tool::Polygon) {
        fill[3] = 0;
    }
    base.set("backColor", 0xfdbe5e47, color_value(fill));
    base.set("borderColor", 0xfdbe5e47, color_value(form.style.outline));
    base.set(
        "groups",
        0x247f2738,
        raw_sequence(
            form.groups.len(),
            form.groups.iter().flat_map(|n| n.to_le_bytes()).collect(),
        ),
    );
    base.set(
        "subKind",
        I32,
        integer(if form.tool == Tool::Highlight {
            1
        } else if form.tool == Tool::PixelSelection {
            2
        } else {
            base.n("subKind", 0) as u32
        }),
    );
    value.set("base", 0x498ba3f9, base);
    let key = match form.tool {
        Tool::Shape | Tool::PixelSelection => {
            value.set(
                "kind",
                I32,
                integer(match form.style.shape {
                    ShapeKind::Ellipse => 0,
                    ShapeKind::Rectangle => 1,
                    ShapeKind::Rounded => 2,
                }),
            );
            value.set("roundSize", F32, float(form.style.radius));
            "shape"
        }
        Tool::Arrow | Tool::Line => {
            value.set("beginCap", I32, integer(form.style.begin_cap));
            value.set("endCap", I32, integer(form.style.end_cap));
            value.set("startSize", F32, float(form.style.start_size));
            value.set("outlineSize", F32, float(form.style.line_outline));
            value.set(
                "outlineColor",
                0xfdbe5e47,
                color_value(form.style.line_outline_color),
            );
            let a = form
                .points
                .first()
                .copied()
                .unwrap_or([form.bounds[0], form.bounds[1]]);
            let b = form.points.last().copied().unwrap_or(a);
            value.set("xc", F32, float(form.control[0] - a[0]));
            value.set("yc", F32, float(form.control[1] - a[1]));
            for (k, n) in [
                ("xa", a[0]),
                ("ya", a[1]),
                ("xb", b[0]),
                ("yb", b[1]),
                ("endSize", form.style.arrow_size),
            ] {
                value.set(k, F32, float(n));
            }
            if form.tool == Tool::Arrow {
                source.set("line", 0xe54e0783, value);
                value = source;
                "arrow"
            } else {
                "line"
            }
        }
        Tool::Polygon | Tool::Draw | Tool::Highlight => {
            value.set(
                "points",
                0x992d14e6,
                raw_sequence(
                    form.points.len(),
                    form.points
                        .iter()
                        .flatten()
                        .flat_map(|n| n.to_le_bytes())
                        .collect(),
                ),
            );
            if form.tool == Tool::Polygon {
                "polygon"
            } else {
                "draw"
            }
        }
        Tool::Text | Tool::Callout => {
            value.set("fontName", STRING, text(&form.style.font_name));
            value.set("alignHorz", I32, integer(form.style.align_h));
            value.set("alignVert", I32, integer(form.style.align_v));
            value.set("lineSpacing", F32, float(form.style.line_spacing));
            value.set("boldSize", F32, float(form.style.bold_size));
            value.set("text", STRING, text(&form.text));
            value.set("fontSize", F32, float(form.style.font_size));
            value.set(
                "fontStyle",
                I32,
                integer(form.style.bold as u32 | ((form.style.italic as u32) << 1)),
            );
            if form.tool == Tool::Callout {
                value.set("tailX", F32, float(form.tail[0]));
                value.set("tailY", F32, float(form.tail[1]));
                value.set("textColor", 0xfdbe5e47, color_value(form.style.text_color));
                value.set("roundSize", F32, float(form.style.radius));
                "callout"
            } else {
                "text"
            }
        }
        Tool::Step => {
            value.set("index", U32, integer(form.step));
            value.set("typeIndex", I32, integer(form.style.numbering));
            value.set(
                "kind",
                I32,
                integer(match form.style.shape {
                    ShapeKind::Ellipse => 0,
                    ShapeKind::Rectangle => 1,
                    ShapeKind::Rounded => 2,
                }),
            );
            "step"
        }
        Tool::Image => {
            if let Some(image) = &form.image {
                value.set("image", 0x5ed512f1, encode_image(image));
            }
            value.set(
                "kind",
                I32,
                integer(match form.style.image_kind {
                    ImageKind::Image => 0,
                    ImageKind::Blur => 1,
                    ImageKind::Pixelate => 2,
                    ImageKind::Zoom => 3,
                }),
            );
            value.set("strength", I32, integer(form.style.strength));
            "image"
        }
        Tool::Select => "shape",
    };
    Value::Interface {
        key: format!("swag.capture.form.{key}"),
        value: Box::new(value),
    }
}

pub fn encode(doc: &Document) -> Result<Vec<u8>, String> {
    let mut model = doc
        .source_fields
        .as_deref()
        .cloned()
        .unwrap_or_else(|| object(1, vec![]));
    for (key, n) in [
        ("width", doc.width),
        ("height", doc.height),
        ("widthOrg", doc.original.width()),
        ("heightOrg", doc.original.height()),
    ] {
        model.set(key, I32, integer(n));
    }
    model.set(
        "forms",
        FORMS,
        sequence(doc.forms.iter().map(encode_form).collect()),
    );
    model.set("title", STRING, text(&doc.title));
    model.set(
        "backImagePos",
        0x5550945e,
        Value::Raw(
            doc.background_position
                .iter()
                .flat_map(|n| n.to_le_bytes())
                .collect(),
        ),
    );
    model.set("favorite", BOOL, byte(doc.favorite as u8));
    model.set("rating", U8, byte(doc.rating));
    model.set(
        "tags",
        STRINGS,
        sequence(
            doc.tags
                .split(',')
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(text)
                .collect(),
        ),
    );
    model.set("nextStepIndex", U32, integer(doc.next_step));
    model.set("nextGroupId", U64, long(doc.next_group));
    if model.get("sourceKind").is_none() {
        model.set(
            "sourceKind",
            I32,
            integer(match doc.source.as_str() {
                "Screen" => 1,
                "Image File" => 2,
                "Clipboard" => 3,
                _ => 4,
            }),
        );
    }
    let mut metadata = object(1, vec![]);
    if let Value::Object { fields, .. } = &model {
        for f in fields {
            if [
                "width",
                "height",
                "linkedImage",
                "linkedUpToDate",
                "sourceKind",
                "capturedAt",
                "sourceApplication",
                "sourceExecutable",
                "sourceWindowTitle",
                "sourceWindowClass",
                "favorite",
                "rating",
            ]
            .contains(&f.key.as_str())
            {
                metadata.set(&f.key, f.kind, f.value.clone());
            }
        }
    }
    let profile = tagbin::encode("swag.capture.library-metadata", &metadata);
    let preview = crate::renderer::preview(doc)?;
    let payloads = [
        (
            MODEL,
            TAGBIN,
            tagbin::encode("swag.capture.document", &model),
            3u32,
            true,
        ),
        (
            BACKGROUND,
            TAGBIN,
            tagbin::encode("pixel.image", &encode_image(&doc.background)),
            1,
            true,
        ),
        (
            ORIGINAL,
            TAGBIN,
            tagbin::encode("pixel.image", &encode_image(&doc.original)),
            0,
            true,
        ),
        (PREVIEW, PNG, crate::storage::png(&preview)?, 4, false),
    ];
    let mut chunks = vec![];
    let mut stored_chunks = vec![];
    for (role, kind, bytes, flags, compress) in payloads {
        let stored = if compress {
            deflate(&bytes)?
        } else {
            bytes.clone()
        };
        chunks.push(object(
            0,
            vec![
                field("id", GUID, guid(new_id())),
                field("typeId", GUID, guid(kind)),
                field("roleId", GUID, guid(role)),
                field(
                    "codecId",
                    GUID,
                    guid(if compress { DEFLATE } else { [0; 16] }),
                ),
                field("schemaVersion", U32, integer(1)),
                field("flags", U32, integer(flags)),
                field("offset", U64, long(0)),
                field("storedSize", U64, long(stored.len() as u64)),
                field("decodedSize", U64, long(bytes.len() as u64)),
                field("storedChecksum", U32, integer(crc32fast::hash(&stored))),
                field("decodedChecksum", U32, integer(crc32fast::hash(&bytes))),
            ],
        ));
        stored_chunks.push(stored);
    }
    let entry = object(
        0,
        vec![
            field("id", GUID, guid(new_id())),
            field("kind", I32, integer(1)),
            field("name", STRING, text(&doc.title)),
            field("primaryChunk", GUID, chunks[0].get("id").unwrap().clone()),
            field(
                "variantChunks",
                0x145cf4df,
                sequence(
                    chunks
                        .iter()
                        .skip(1)
                        .map(|c| c.get("id").unwrap().clone())
                        .collect(),
                ),
            ),
        ],
    );
    let manifest = object(
        0,
        vec![
            field("version", U32, integer(1)),
            field("profileVersion", U32, integer(1)),
            field("name", STRING, text(&doc.title)),
            field("tags", STRINGS, model.get("tags").unwrap().clone()),
            field("entries", 0x1db9d4fa, sequence(vec![entry])),
            field("profileData", BYTES, raw_sequence(profile.len(), profile)),
        ],
    );
    let mut header = object(
        1,
        vec![
            field("containerKind", GUID, guid(CONTAINER)),
            field("containerId", GUID, guid(new_id())),
            field("generation", U64, long(1)),
            field("declaredFileSize", U64, long(0)),
            field("manifest", 0x573aa3b4, manifest),
            field("chunks", 0xe6963e89, sequence(chunks.clone())),
        ],
    );
    let preliminary = tagbin::encode("core.scc.header", &header);
    let mut position = (32 + preliminary.len() + 7) & !7;
    for (chunk, bytes) in chunks.iter_mut().zip(&stored_chunks) {
        chunk.set("offset", U64, long(position as u64));
        position = (position + bytes.len() + 7) & !7;
    }
    let final_size =
        chunks.last().unwrap().n("offset", 0) as usize + stored_chunks.last().unwrap().len();
    header.set("declaredFileSize", U64, long(final_size as u64));
    header.set("chunks", 0xe6963e89, sequence(chunks.clone()));
    let encoded = tagbin::encode("core.scc.header", &header);
    if encoded.len() != preliminary.len() {
        return Err("SCC header size changed while assigning offsets.".into());
    }
    let mut output = b"SWAGSCC\0".to_vec();
    output.extend_from_slice(&1u32.to_le_bytes());
    output.extend_from_slice(&0u32.to_le_bytes());
    output.extend_from_slice(&(encoded.len() as u64).to_le_bytes());
    output.extend_from_slice(&crc32fast::hash(&encoded).to_le_bytes());
    output.extend_from_slice(&0u32.to_le_bytes());
    output.extend(encoded);
    for (chunk, bytes) in chunks.iter().zip(stored_chunks) {
        output.resize(chunk.n("offset", 0) as usize, 0);
        output.extend(bytes);
    }
    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;
    const FIXTURE: &[u8] = include_bytes!(
        "../../../../bin/apps/modules/swagcapture/src/tests/datas/capture-all-forms.scc"
    );
    #[test]
    fn capture_without_a_background_keeps_a_transparent_canvas() {
        let mut bytes = encode(&Document::blank(48, 32)).unwrap();
        let size = u64_at(&bytes, 16).unwrap() as usize;
        let mut header = tagbin::decode(&bytes[32..32 + size], "core.scc.header").unwrap();
        let mut chunks = header.get("chunks").unwrap().items().to_vec();
        for chunk in &mut chunks {
            if read_guid(chunk.get("roleId")).unwrap() == BACKGROUND {
                chunk.set("roleId", GUID, guid([0; 16]));
            }
        }
        header.set("chunks", 0xe6963e89, sequence(chunks));
        let encoded = tagbin::encode("core.scc.header", &header);
        assert_eq!(encoded.len(), size);
        bytes[32..32 + size].copy_from_slice(&encoded);
        bytes[24..28].copy_from_slice(&crc32fast::hash(&encoded).to_le_bytes());
        let doc = decode(&bytes).unwrap();
        assert_eq!((doc.width, doc.height), (48, 32));
        assert!(doc.background.pixels().all(|pixel| pixel.0 == [0; 4]));
    }
    #[test]
    fn shifted_background_survives_loading_cropping_and_saving() {
        let mut doc = Document::blank(128, 96);
        doc.width = 100;
        doc.height = 60;
        doc.background_position = [-12., 8.];
        let mut loaded = decode(&encode(&doc).unwrap()).unwrap();
        assert_eq!(loaded.background_position, [-12., 8.]);
        assert_eq!(loaded.background.dimensions(), (128, 96));
        assert_eq!(loaded.background_pixels().get_pixel(0, 0).0, [0; 4]);
        assert_eq!(loaded.background_pixels().get_pixel(0, 8).0, [255; 4]);
        loaded.crop(Rect::from_min_size(
            pos2(10., 10.),
            eframe::egui::vec2(30., 20.),
        ));
        let cropped = decode(&encode(&loaded).unwrap()).unwrap();
        assert_eq!((cropped.width, cropped.height), (30, 20));
        assert_eq!(cropped.background_position, [-22., -2.]);
        assert_eq!(cropped.background, doc.background);
    }
    #[test]
    fn imports_the_original_swag_contract_fixture() {
        let doc = decode(FIXTURE).unwrap();
        assert_eq!((doc.width, doc.height), (128, 96));
        assert_eq!(doc.forms.len(), 9);
        assert_eq!(doc.title, "Serialization Contract");
        assert!(doc.favorite);
        assert_eq!(doc.rating, 5);
        assert_eq!(doc.background.get_pixel(0, 0).0, [25, 156, 244, 255]);
        assert_eq!(doc.original.get_pixel(0, 0).0, [96, 196, 71, 255]);
        assert_eq!(doc.forms[0].bounds, [2., 3., 20., 18.]);
        assert_eq!(doc.forms[0].style.radius, 17.);
        assert_eq!(doc.forms[1].points, vec![[5., 7.], [91., 33.]]);
        assert_eq!(doc.forms[5].text, "fixture text");
        assert_eq!(doc.forms[5].style.font_size, 27.);
        assert_eq!(doc.forms[6].step, 7);
        assert_eq!(doc.forms[7].image.as_ref().unwrap().dimensions(), (3, 2));
    }
    #[test]
    fn scc_round_trip_retains_extended_source_fields() {
        let doc = decode(FIXTURE).unwrap();
        let bytes = encode(&doc).unwrap();
        let loaded = decode(&bytes).unwrap();
        assert_eq!(loaded.background, doc.background);
        assert_eq!(loaded.original, doc.original);
        assert_eq!(loaded.forms.len(), 9);
        assert_eq!(
            loaded.forms[1].source_fields.as_ref().unwrap().f("xc", 0.),
            38.
        );
        assert_eq!(
            loaded.forms[5]
                .source_fields
                .as_ref()
                .unwrap()
                .s("fontName"),
            "Arial"
        );
        assert_eq!(loaded.forms[7].image, doc.forms[7].image);
    }
    #[test]
    fn damaged_headers_and_payloads_fail_before_import() {
        let mut bytes = FIXTURE.to_vec();
        bytes[100] ^= 1;
        assert!(decode(&bytes).is_err());
        let mut bytes = FIXTURE.to_vec();
        bytes[5000] ^= 1;
        assert!(decode(&bytes).is_err());
        assert!(decode(&FIXTURE[..100]).is_err());
    }
}
