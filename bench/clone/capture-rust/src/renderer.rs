use crate::document::{Document, Form, ImageKind, ShapeKind, Tool};
use eframe::egui::{epaint, *};
use image::RgbaImage;
use std::{collections::HashMap, sync::Arc};

#[derive(Default)]
pub struct Renderer {
    textures: HashMap<usize, (Arc<RgbaImage>, TextureHandle)>,
    effects: HashMap<u64, (EffectKey, Arc<RgbaImage>)>,
    strokes: HashMap<u64, (crate::stroke::Key, crate::stroke::Raster)>,
}

#[derive(PartialEq)]
struct EffectKey {
    background: usize,
    background_position: [f32; 2],
    canvas_size: [u32; 2],
    bounds: [f32; 4],
    kind: ImageKind,
    strength: u32,
}

impl Renderer {
    pub fn texture(&mut self, ctx: &Context, pixels: &Arc<RgbaImage>) -> TextureId {
        let key = Arc::as_ptr(pixels) as usize;
        self.textures
            .entry(key)
            .or_insert_with(|| {
                let color = ColorImage::from_rgba_unmultiplied(
                    [pixels.width() as usize, pixels.height() as usize],
                    pixels.as_raw(),
                );
                (
                    pixels.clone(),
                    ctx.load_texture(format!("capture-{key}"), color, TextureOptions::LINEAR),
                )
            })
            .1
            .id()
    }

    pub fn clear(&mut self) {
        self.textures.clear();
        self.effects.clear();
        self.strokes.clear();
    }

    pub fn prune(&mut self) {
        self.textures
            .retain(|_, (pixels, _)| Arc::strong_count(pixels) > 1);
    }

    pub fn paint(&mut self, painter: &Painter, doc: &Document, origin: Pos2, zoom: f32) {
        let texture = self.texture(painter.ctx(), &doc.background);
        let rect = Rect::from_min_size(origin, doc.rect().size() * zoom);
        let painter = painter.with_clip_rect(rect.intersect(painter.clip_rect()));
        painter.image(
            texture,
            Rect::from_min_size(
                origin + vec2(doc.background_position[0], doc.background_position[1]) * zoom,
                vec2(
                    doc.background.width() as f32,
                    doc.background.height() as f32,
                ) * zoom,
            ),
            Rect::from_min_max(Pos2::ZERO, pos2(1., 1.)),
            Color32::WHITE,
        );
        self.effects
            .retain(|id, _| doc.forms.iter().any(|f| f.id == *id));
        self.strokes
            .retain(|id, _| doc.forms.iter().any(|f| f.id == *id));
        for form in &doc.forms {
            self.paint_form(&painter, doc, form, origin, zoom);
        }
        self.prune();
    }

    fn effect(&mut self, doc: &Document, form: &Form) -> Arc<RgbaImage> {
        let key = EffectKey {
            background: Arc::as_ptr(&doc.background) as usize,
            background_position: doc.background_position,
            canvas_size: [doc.width, doc.height],
            bounds: form.bounds,
            kind: form.style.image_kind,
            strength: form.style.strength,
        };
        if let Some((previous, image)) = self.effects.get(&form.id) {
            if *previous == key {
                return image.clone();
            }
        }
        let rect = form.rect().intersect(doc.rect());
        let x = (rect.min.x.max(0.) as u32).min(doc.width.saturating_sub(1));
        let y = (rect.min.y.max(0.) as u32).min(doc.height.saturating_sub(1));
        let w = (rect.width().max(1.) as u32).min(doc.width - x);
        let h = (rect.height().max(1.) as u32).min(doc.height - y);
        let pixels = image::imageops::crop_imm(&*doc.background_pixels(), x, y, w, h).to_image();
        let pixels = match form.style.image_kind {
            ImageKind::Blur => {
                image::imageops::blur(&pixels, form.style.strength as f32 * 0.2 + 0.1)
            }
            ImageKind::Pixelate => {
                let block = (form.style.strength / 4 + 2).max(1);
                let small = image::imageops::resize(
                    &pixels,
                    (w / block).max(1),
                    (h / block).max(1),
                    image::imageops::FilterType::Triangle,
                );
                image::imageops::resize(&small, w, h, image::imageops::FilterType::Nearest)
            }
            ImageKind::Zoom => {
                let scale = 1. + form.style.strength as f32 / 25.;
                let cw = (w as f32 / scale).max(1.) as u32;
                let ch = (h as f32 / scale).max(1.) as u32;
                let center = image::imageops::crop_imm(&pixels, (w - cw) / 2, (h - ch) / 2, cw, ch)
                    .to_image();
                image::imageops::resize(&center, w, h, image::imageops::FilterType::CatmullRom)
            }
            ImageKind::Image => pixels,
        };
        let pixels = Arc::new(pixels);
        self.effects.insert(form.id, (key, pixels.clone()));
        pixels
    }

    pub fn paint_form(
        &mut self,
        painter: &Painter,
        doc: &Document,
        form: &Form,
        origin: Pos2,
        zoom: f32,
    ) {
        let center = form.rect().center();
        let angle = form.style.rotation.to_radians();
        let (s, c) = angle.sin_cos();
        let transform = |p: Pos2| {
            let d = p - center;
            origin + (center.to_vec2() + vec2(d.x * c - d.y * s, d.x * s + d.y * c)) * zoom
        };
        let opacity = form.style.opacity / 100.;
        let color = |rgba: [u8; 4]| {
            Color32::from_rgba_unmultiplied(
                rgba[0],
                rgba[1],
                rgba[2],
                (rgba[3] as f32 * opacity) as u8,
            )
        };
        let fill = color(form.style.fill);
        let outline = color(form.style.outline);
        let rect = form.rect();
        let center_screen = transform(center);
        let screen_rect = Rect::from_center_size(center_screen, rect.size() * zoom);
        let poly = |points: Vec<Pos2>, closed: bool, filled: bool, stroke: Stroke| {
            if points.len() < 2 {
                return;
            }
            let points: Vec<_> = points.into_iter().map(transform).collect();
            if form.style.shadow
                && form.tool != Tool::Highlight
                && form.tool != Tool::PixelSelection
            {
                let offset = vec2(2., 2.) * zoom;
                let shadow: Vec<_> = points.iter().map(|p| *p + offset).collect();
                painter.add(epaint::PathShape {
                    points: shadow,
                    closed,
                    fill: if filled {
                        Color32::from_black_alpha((55. * opacity) as u8)
                    } else {
                        Color32::TRANSPARENT
                    },
                    stroke: Stroke::new(
                        stroke.width + zoom,
                        Color32::from_black_alpha((40. * opacity) as u8),
                    )
                    .into(),
                });
            }
            painter.add(epaint::PathShape {
                points,
                closed,
                fill: if filled { fill } else { Color32::TRANSPARENT },
                stroke: stroke.into(),
            });
        };
        match form.tool {
            Tool::Shape | Tool::PixelSelection => {
                let points = match form.style.shape {
                    ShapeKind::Ellipse if form.tool != Tool::PixelSelection => (0..64)
                        .map(|i| {
                            let a = i as f32 * std::f32::consts::TAU / 64.;
                            center + vec2(a.cos() * rect.width() / 2., a.sin() * rect.height() / 2.)
                        })
                        .collect(),
                    ShapeKind::Rounded if form.tool != Tool::PixelSelection => {
                        let r = form
                            .style
                            .radius
                            .min(rect.width() / 2.)
                            .min(rect.height() / 2.);
                        let mut points = vec![];
                        for (corner, start) in [
                            (rect.right_top() + vec2(-r, r), -std::f32::consts::FRAC_PI_2),
                            (rect.right_bottom() + vec2(-r, -r), 0.),
                            (
                                rect.left_bottom() + vec2(r, -r),
                                std::f32::consts::FRAC_PI_2,
                            ),
                            (rect.left_top() + vec2(r, r), std::f32::consts::PI),
                        ] {
                            for i in 0..9 {
                                let a = start + i as f32 * std::f32::consts::FRAC_PI_2 / 8.;
                                points.push(corner + Vec2::angled(a) * r);
                            }
                        }
                        points
                    }
                    _ => vec![
                        rect.left_top(),
                        rect.right_top(),
                        rect.right_bottom(),
                        rect.left_bottom(),
                    ],
                };
                poly(
                    points,
                    true,
                    form.style.filled && form.tool != Tool::PixelSelection,
                    if form.tool == Tool::PixelSelection {
                        Stroke::new(1.0_f32, Color32::from_rgb(253, 223, 27))
                    } else {
                        Stroke::new(form.style.thickness * zoom, outline)
                    },
                );
            }
            Tool::Polygon => {
                let points = if form.points.len() > 2 {
                    form.points.iter().map(|p| pos2(p[0], p[1])).collect()
                } else {
                    vec![
                        pos2(center.x, rect.min.y),
                        rect.right_bottom(),
                        rect.left_bottom(),
                    ]
                };
                poly(
                    points,
                    true,
                    form.style.filled,
                    Stroke::new(form.style.thickness * zoom, outline),
                );
            }
            Tool::Arrow | Tool::Line | Tool::Draw | Tool::Highlight => {
                let density = zoom * painter.ctx().pixels_per_point();
                let key = crate::stroke::Key::new(form, density);
                if self
                    .strokes
                    .get(&form.id)
                    .is_none_or(|(previous, _)| *previous != key)
                {
                    if let Some(raster) = crate::stroke::rasterize(form, density) {
                        self.strokes.insert(form.id, (key, raster));
                    } else {
                        self.strokes.remove(&form.id);
                    }
                }
                if let Some((_, raster)) = self.strokes.get(&form.id) {
                    let pixels = raster.pixels.clone();
                    let rect = raster.rect;
                    let texture = self.texture(painter.ctx(), &pixels);
                    let mut mesh = Mesh::with_texture(texture);
                    for (point, uv) in [
                        (rect.left_top(), pos2(0., 0.)),
                        (rect.right_top(), pos2(1., 0.)),
                        (rect.right_bottom(), pos2(1., 1.)),
                        (rect.left_bottom(), pos2(0., 1.)),
                    ] {
                        mesh.vertices.push(epaint::Vertex {
                            pos: transform(point),
                            uv,
                            color: Color32::WHITE,
                        });
                    }
                    mesh.indices = vec![0, 1, 2, 0, 2, 3];
                    painter.add(mesh);
                }
            }
            Tool::Text | Tool::Callout | Tool::Step => {
                if form.tool == Tool::Step {
                    painter.circle(
                        center_screen,
                        screen_rect.width().min(screen_rect.height()) / 2.,
                        fill,
                        Stroke::new(form.style.thickness * zoom, outline),
                    );
                }
                if form.tool == Tool::Callout {
                    let tail = vec![
                        pos2(rect.min.x + rect.width() * 0.25, rect.max.y - 2.),
                        pos2(form.tail[0], form.tail[1]),
                        pos2(rect.min.x + rect.width() * 0.5, rect.max.y - 2.),
                    ];
                    painter.add(Shape::convex_polygon(
                        tail.into_iter().map(transform).collect(),
                        fill,
                        Stroke::new(form.style.thickness * zoom, outline),
                    ));
                    painter.rect_filled(
                        screen_rect,
                        (form.style.radius * zoom).min(255.) as u8,
                        fill,
                    );
                    painter.rect_stroke(
                        screen_rect,
                        (form.style.radius * zoom).min(255.) as u8,
                        Stroke::new(form.style.thickness * zoom, outline),
                        StrokeKind::Middle,
                    );
                }
                let text = if form.tool == Tool::Step {
                    if form.style.numbering == 0 {
                        form.step.to_string()
                    } else {
                        char::from_u32(
                            if form.style.numbering == 1 { 65 } else { 97 }
                                + form.step.saturating_sub(1) % 26,
                        )
                        .unwrap()
                        .to_string()
                    }
                } else {
                    form.text.clone()
                };
                let family = crate::theme::font_key(
                    &form.style.font_name,
                    form.style.bold,
                    form.style.italic,
                );
                let font_size = if form.tool == Tool::Step {
                    rect.height().min(rect.width()) * 0.55
                } else {
                    form.style.font_size * (1. + form.style.scale / 100.)
                } * zoom;
                let text_color = if form.tool == Tool::Text {
                    fill
                } else if form.tool == Tool::Callout {
                    color(form.style.text_color)
                } else {
                    outline
                };
                let font = FontId::new(font_size, FontFamily::Name(family.into()));
                let lines: Vec<_> = text
                    .split('\n')
                    .map(|line| painter.layout_no_wrap(line.into(), font.clone(), text_color))
                    .collect();
                let spacing = form.style.line_spacing * zoom;
                let heights: Vec<_> = lines
                    .iter()
                    .map(|g| {
                        if g.mesh_bounds.is_positive() {
                            g.mesh_bounds.height()
                        } else {
                            font_size * 0.7
                        }
                    })
                    .collect();
                let height: f32 =
                    heights.iter().sum::<f32>() + spacing * lines.len().saturating_sub(1) as f32;
                let pad = if form.tool == Tool::Callout {
                    form.style.radius * 0.5 + form.style.thickness
                } else {
                    form.style.thickness
                };
                let box_rect = screen_rect.shrink(pad * zoom);
                let mut y = match form.style.align_v {
                    0 => box_rect.top(),
                    1 => box_rect.bottom() - height,
                    _ => box_rect.center().y - height / 2.,
                };
                let paint_text = |position: Pos2, galley: Arc<Galley>, ink: Color32| {
                    let delta = position - center_screen;
                    let rotated =
                        center_screen + vec2(delta.x * c - delta.y * s, delta.x * s + delta.y * c);
                    let mut shape = epaint::TextShape::new(rotated, galley, ink);
                    shape.override_text_color = Some(ink);
                    shape.angle = angle;
                    painter.add(shape);
                };
                for (galley, height) in lines.iter().zip(heights) {
                    let bound = galley.mesh_bounds;
                    let x = match form.style.align_h {
                        0 => box_rect.left(),
                        1 => box_rect.right() - bound.width(),
                        _ => box_rect.center().x - bound.width() / 2.,
                    };
                    let position = pos2(x - bound.left(), y - bound.top());
                    let border = if form.tool == Tool::Text {
                        form.style.thickness * zoom
                    } else {
                        0.
                    };
                    if form.style.shadow && form.tool == Tool::Text {
                        for ring in (1..=6).rev() {
                            for i in 0..12 {
                                let shift = Vec2::angled(i as f32 * std::f32::consts::TAU / 12.)
                                    * (border + ring as f32 * zoom);
                                paint_text(
                                    position + vec2(2., 2.) * zoom + shift,
                                    galley.clone(),
                                    Color32::from_black_alpha((5. * opacity) as u8),
                                );
                            }
                        }
                    }
                    if border > 0. {
                        for i in 0..24 {
                            paint_text(
                                position
                                    + Vec2::angled(i as f32 * std::f32::consts::TAU / 24.) * border,
                                galley.clone(),
                                outline,
                            );
                        }
                    }
                    if form.style.bold_size > 0. {
                        for i in 0..12 {
                            paint_text(
                                position
                                    + Vec2::angled(i as f32 * std::f32::consts::TAU / 12.)
                                        * form.style.bold_size
                                        * zoom,
                                galley.clone(),
                                text_color,
                            );
                        }
                    }
                    paint_text(position, galley.clone(), text_color);
                    y += height + spacing;
                }
            }
            Tool::Image => {
                let pixels = if form.style.image_kind == ImageKind::Image {
                    form.image.clone()
                } else {
                    Some(self.effect(doc, form))
                };
                if let Some(pixels) = pixels {
                    let texture = self.texture(painter.ctx(), &pixels);
                    let mut mesh = Mesh::with_texture(texture);
                    for (p, uv) in [
                        (rect.left_top(), pos2(0., 0.)),
                        (rect.right_top(), pos2(1., 0.)),
                        (rect.right_bottom(), pos2(1., 1.)),
                        (rect.left_bottom(), pos2(0., 1.)),
                    ] {
                        mesh.vertices.push(epaint::Vertex {
                            pos: transform(p),
                            uv,
                            color: Color32::from_white_alpha((opacity * 255.) as u8),
                        });
                    }
                    mesh.indices = vec![0, 1, 2, 0, 2, 3];
                    painter.add(mesh);
                }
            }
            Tool::Select => {}
        }
    }
}

// The exporter consumes the same tessellated document as the native renderer. It
// does not capture the desktop or include selection handles, chrome, or zoom.
pub fn export(doc: &Document) -> Result<RgbaImage, String> {
    render_image(doc, doc.width, doc.height)
}

pub fn preview(doc: &Document) -> Result<RgbaImage, String> {
    let scale = (341. / doc.width as f32)
        .min(256. / doc.height as f32)
        .min(1.);
    render_image(
        doc,
        (doc.width as f32 * scale).round().max(1.) as u32,
        (doc.height as f32 * scale).round().max(1.) as u32,
    )
}

fn render_image(doc: &Document, width: u32, height: u32) -> Result<RgbaImage, String> {
    if doc.width == 0 || doc.height == 0 || doc.width > 8192 || doc.height > 8192 {
        return Err("Invalid export dimensions.".into());
    }
    let ctx = Context::default();
    ctx.set_fonts(crate::theme::fonts_for(
        doc.forms.iter().map(|f| f.style.font_name.as_str()),
    ));
    let mut renderer = Renderer::default();
    let mut raster = Rasterizer::default();
    let mut output = RgbaImage::new(width, height);
    let zoom = (width as f32 / doc.width as f32).min(height as f32 / doc.height as f32);
    for _ in 0..2 {
        let input = RawInput {
            screen_rect: Some(Rect::from_min_size(
                Pos2::ZERO,
                vec2(width as f32, height as f32),
            )),
            ..Default::default()
        };
        let frame = ctx.run(input, |ctx| {
            let painter = ctx.layer_painter(LayerId::background());
            renderer.paint(&painter, doc, Pos2::ZERO, zoom);
        });
        let shapes = ctx.tessellate(frame.shapes, 1.);
        output = raster.render(width, height, &shapes, &frame.textures_delta)?;
    }
    Ok(output)
}

#[derive(Default)]
pub struct Rasterizer {
    textures: HashMap<TextureId, ColorImage>,
}

impl Rasterizer {
    pub fn render(
        &mut self,
        width: u32,
        height: u32,
        shapes: &[epaint::ClippedPrimitive],
        delta: &epaint::textures::TexturesDelta,
    ) -> Result<RgbaImage, String> {
        for (id, delta) in &delta.set {
            let ImageData::Color(image) = &delta.image;
            if let Some([x, y]) = delta.pos {
                let target = self
                    .textures
                    .get_mut(id)
                    .ok_or("Missing partial texture.")?;
                for row in 0..image.height() {
                    let dst = (y + row) * target.width() + x;
                    target.pixels[dst..dst + image.width()].copy_from_slice(
                        &image.pixels[row * image.width()..(row + 1) * image.width()],
                    );
                }
            } else {
                self.textures.insert(*id, (**image).clone());
            }
        }
        let mut pixels = vec![[0u8; 4]; width as usize * height as usize];
        for primitive in shapes {
            let epaint::Primitive::Mesh(mesh) = &primitive.primitive else {
                return Err("Unsupported paint callback.".into());
            };
            let texture = self
                .textures
                .get(&mesh.texture_id)
                .ok_or("Missing export texture.")?;
            let clip = primitive.clip_rect.intersect(Rect::from_min_size(
                Pos2::ZERO,
                vec2(width as f32, height as f32),
            ));
            for tri in mesh.indices.chunks_exact(3) {
                let a = mesh.vertices[tri[0] as usize];
                let b = mesh.vertices[tri[1] as usize];
                let c = mesh.vertices[tri[2] as usize];
                let fixed = |p: Pos2| {
                    [
                        (p.x as f64 * 256.).round() as i64,
                        (p.y as f64 * 256.).round() as i64,
                    ]
                };
                let edge = |a: [i64; 2], b: [i64; 2], p: [i64; 2]| {
                    (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])
                };
                let fa = fixed(a.pos);
                let fb = fixed(b.pos);
                let fc = fixed(c.pos);
                let area = edge(fa, fb, fc);
                if area == 0 {
                    continue;
                }
                let bounds = Rect::from_points(&[a.pos, b.pos, c.pos]).intersect(clip);
                for y in (bounds.min.y.floor().max(0.) as u32)
                    ..(bounds.max.y.ceil().min(height as f32) as u32)
                {
                    for x in (bounds.min.x.floor().max(0.) as u32)
                        ..(bounds.max.x.ceil().min(width as f32) as u32)
                    {
                        let sample = [x as i64 * 256 + 128, y as i64 * 256 + 128];
                        let p = pos2(x as f32 + 0.5, y as f32 + 0.5);
                        if !clip.contains(p) {
                            continue;
                        }
                        let ea = edge(fb, fc, sample) * area.signum();
                        let eb = edge(fc, fa, sample) * area.signum();
                        let ec = edge(fa, fb, sample) * area.signum();
                        let top_left = |u: [i64; 2], v: [i64; 2]| {
                            let dx = (v[0] - u[0]) * area.signum();
                            let dy = (v[1] - u[1]) * area.signum();
                            dy < 0 || (dy == 0 && dx > 0)
                        };
                        if ea < 0
                            || eb < 0
                            || ec < 0
                            || (ea == 0 && !top_left(fb, fc))
                            || (eb == 0 && !top_left(fc, fa))
                            || (ec == 0 && !top_left(fa, fb))
                        {
                            continue;
                        }
                        let wa = ea as f32 / area.abs() as f32;
                        let wb = eb as f32 / area.abs() as f32;
                        let wc = ec as f32 / area.abs() as f32;
                        let uv = a.uv.to_vec2() * wa + b.uv.to_vec2() * wb + c.uv.to_vec2() * wc;
                        let tx = (uv.x * texture.width() as f32 - 0.5)
                            .clamp(0., texture.width() as f32 - 1.);
                        let ty = (uv.y * texture.height() as f32 - 0.5)
                            .clamp(0., texture.height() as f32 - 1.);
                        let x0 = tx as usize;
                        let y0 = ty as usize;
                        let x1 = (x0 + 1).min(texture.width() - 1);
                        let y1 = (y0 + 1).min(texture.height() - 1);
                        let sx = tx.fract();
                        let sy = ty.fract();
                        let texels = [
                            texture[(x0, y0)],
                            texture[(x1, y0)],
                            texture[(x0, y1)],
                            texture[(x1, y1)],
                        ];
                        let weights = [
                            (1. - sx) * (1. - sy),
                            sx * (1. - sy),
                            (1. - sx) * sy,
                            sx * sy,
                        ];
                        let mut src = [0.; 4];
                        for channel in 0..4 {
                            let t: f32 =
                                (0..4).map(|i| texels[i][channel] as f32 * weights[i]).sum();
                            let v = a.color[channel] as f32 * wa
                                + b.color[channel] as f32 * wb
                                + c.color[channel] as f32 * wc;
                            src[channel] = t * v / 255.;
                        }
                        let dst = &mut pixels[y as usize * width as usize + x as usize];
                        for channel in 0..4 {
                            dst[channel] = (src[channel]
                                + dst[channel] as f32 * (1. - src[3] / 255.))
                                .round()
                                .clamp(0., 255.) as u8;
                        }
                    }
                }
            }
        }
        for id in &delta.free {
            self.textures.remove(id);
        }
        let mut output = RgbaImage::new(width, height);
        for (dst, src) in output.pixels_mut().zip(pixels) {
            let color = Color32::from_rgba_premultiplied(src[0], src[1], src[2], src[3]);
            *dst = image::Rgba(color.to_srgba_unmultiplied());
        }
        Ok(output)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn export_preserves_opaque_background_and_annotation() {
        let mut doc = Document::blank(64, 64);
        let mut style = crate::document::Style::default();
        style.filled = true;
        style.shape = ShapeKind::Rectangle;
        style.shadow = false;
        doc.create(Tool::Shape, pos2(16., 16.), style);
        doc.forms[0].draw_to(pos2(16., 16.), pos2(48., 48.), false);
        let image = export(&doc).unwrap();
        assert_eq!(image.get_pixel(2, 2).0, [255; 4]);
        assert_eq!(image.get_pixel(32, 32).0, [232, 8, 8, 255]);
    }
}
