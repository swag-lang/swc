//! Capture line silhouettes: shared by the canvas, previews and image export.
use crate::document::{Form, Style};
use eframe::egui::{Pos2, Rect, Vec2, vec2};
use image::RgbaImage;
use resvg::tiny_skia as sk;
use std::sync::Arc;

#[derive(PartialEq)]
pub struct Key {
    style: Style,
    points: Vec<[f32; 2]>,
    control: [f32; 2],
    density: f32,
}

impl Key {
    pub fn new(form: &Form, density: f32) -> Self {
        Self {
            style: form.style.clone(),
            points: form.points.clone(),
            control: form.control,
            density,
        }
    }
}

pub struct Raster {
    pub pixels: Arc<RgbaImage>,
    pub rect: Rect,
}

// The cap coordinates and shaft setbacks follow pixel/painter/drawpath.swg.
pub fn cap_points(p: Pos2, direction: Vec2, width: f32, kind: u32, scale: f32) -> Vec<Vec<Pos2>> {
    let half = width * 0.5;
    let n = vec2(-direction.y, direction.x) * half;
    match kind {
        1 => vec![vec![p + n, p - n, p + direction * half]],
        3 => vec![vec![
            p + n,
            p - n,
            p - n + direction * half,
            p + n + direction * half,
        ]],
        4 => vec![vec![
            p - direction * width * scale + n * scale,
            p - direction * width * scale - n * scale,
            p,
        ]],
        5 => {
            let neck = p - direction * width * scale;
            let back = neck - direction * (scale * 4.);
            // One concave ring prevents an antialiased seam along the shared axis.
            vec![vec![back + n * scale, neck, back - n * scale, p]]
        }
        6 => {
            let d = direction * half * scale;
            let n = n * scale;
            vec![vec![p - d + n, p - d - n, p + d - n, p + d + n]]
        }
        2 | 7 => {
            let radius = half * if kind == 7 { scale } else { 1. };
            vec![
                (0..64)
                    .map(|i| p + Vec2::angled(i as f32 * std::f32::consts::TAU / 64.) * radius)
                    .collect(),
            ]
        }
        _ => vec![],
    }
}

fn setback(width: f32, kind: u32, scale: f32) -> f32 {
    match kind {
        4 => width * 0.5 * scale,
        5 => width * 0.7 * scale,
        6 => (width * 0.5 * scale - 1.).max(0.),
        7 => {
            let r = width * 0.5 * scale;
            (r - (r * 0.2).max(1.)).max(0.)
        }
        _ => 0.,
    }
}

fn slice_path(points: &[Pos2], start: f32, end: f32) -> Vec<Pos2> {
    let mut result = Vec::new();
    let mut distance = 0.;
    for pair in points.windows(2) {
        let length = pair[0].distance(pair[1]);
        if length > 0.0001 && distance + length > start && distance < end {
            let a = pair[0].lerp(pair[1], ((start - distance) / length).clamp(0., 1.));
            let b = pair[0].lerp(pair[1], ((end - distance) / length).clamp(0., 1.));
            if result.last() != Some(&a) {
                result.push(a);
            }
            result.push(b);
        }
        distance += length;
    }
    result
}

fn path(points: &[Pos2], closed: bool) -> Option<sk::Path> {
    let first = points.first()?;
    let mut builder = sk::PathBuilder::new();
    builder.move_to(first.x, first.y);
    for p in &points[1..] {
        builder.line_to(p.x, p.y);
    }
    if closed {
        builder.close();
    }
    builder.finish()
}

pub fn hit(form: &Form, point: Pos2, tolerance: f32) -> bool {
    let points = form.path_points();
    let s = &form.style;
    let distance = |a: Pos2, b: Pos2| {
        let d = b - a;
        let t = ((point - a).dot(d) / d.length_sq().max(0.001)).clamp(0., 1.);
        point.distance(a + d * t)
    };
    if points
        .windows(2)
        .any(|p| distance(p[0], p[1]) <= tolerance + s.thickness * 0.5 + s.line_outline)
    {
        return true;
    }
    let first = points.windows(2).find(|p| p[0] != p[1]);
    let last = points.windows(2).rev().find(|p| p[0] != p[1]);
    let (Some(first), Some(last)) = (first, last) else {
        return false;
    };
    for (p, direction, kind, scale) in [
        (
            points[0],
            (first[0] - first[1]).normalized(),
            s.begin_cap,
            s.start_size,
        ),
        (
            *points.last().unwrap(),
            (last[1] - last[0]).normalized(),
            s.end_cap,
            s.arrow_size,
        ),
    ] {
        for ring in cap_points(p, direction, s.thickness, kind, scale) {
            let mut inside = false;
            for i in 0..ring.len() {
                let a = ring[i];
                let b = ring[(i + 1) % ring.len()];
                if distance(a, b) <= tolerance + s.line_outline {
                    return true;
                }
                if (a.y > point.y) != (b.y > point.y)
                    && point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x
                {
                    inside = !inside;
                }
            }
            if inside {
                return true;
            }
        }
    }
    false
}

pub fn rasterize(form: &Form, density: f32) -> Option<Raster> {
    let points = form.path_points();
    if points.len() < 2 || points.iter().any(|p| !p.x.is_finite() || !p.y.is_finite()) {
        return None;
    }
    let s = &form.style;
    let width = s.thickness.clamp(0., 1000.);
    if width == 0. {
        return None;
    }
    let length: f32 = points.windows(2).map(|p| p[0].distance(p[1])).sum();
    if length <= 0.0001 {
        return None;
    }
    let first_dir = points
        .windows(2)
        .find_map(|p| (p[0] != p[1]).then(|| (p[0] - p[1]).normalized()))?;
    let last_dir = points
        .windows(2)
        .rev()
        .find_map(|p| (p[0] != p[1]).then(|| (p[1] - p[0]).normalized()))?;
    let caps: Vec<_> = cap_points(points[0], first_dir, width, s.begin_cap, s.start_size)
        .into_iter()
        .chain(cap_points(
            *points.last()?,
            last_dir,
            width,
            s.end_cap,
            s.arrow_size,
        ))
        .collect();
    let start = setback(width, s.begin_cap, s.start_size).min(length);
    let end = (length - setback(width, s.end_cap, s.arrow_size)).max(start);
    let mut shafts = Vec::new();
    if s.dash == 0 {
        shafts.push(slice_path(&points, start, end));
    } else {
        let pattern: &[f32] = match s.dash {
            3 => &[2., 1.],
            4 => &[2., 1., 1., 1.],
            _ => &[1., 1.],
        };
        let mut at = start;
        let mut index = 0;
        while at < end {
            let span =
                pattern[index % pattern.len()] * width * if index % 2 == 0 { 1. } else { 0.25 };
            if index % 2 == 0 {
                shafts.push(slice_path(&points, at, (at + span).min(end)));
            }
            at += span.max(0.01);
            index += 1;
        }
    }
    let mut bounds = Rect::from_points(&points);
    for ring in &caps {
        bounds = bounds.union(Rect::from_points(ring));
    }
    bounds = bounds
        .expand(width * 0.5 + s.line_outline.clamp(0., 100.) + if s.shadow { 10. } else { 2. });
    let density = density
        .clamp(0.25, 8.)
        .min(4096. / bounds.width().max(bounds.height()));
    let w = (bounds.width() * density).ceil().max(1.) as u32;
    let h = (bounds.height() * density).ceil().max(1.) as u32;
    let transform = sk::Transform::from_row(
        density,
        0.,
        0.,
        density,
        -bounds.min.x * density,
        -bounds.min.y * density,
    );
    let draw = |outline: f32| -> Option<sk::Pixmap> {
        let mut mask = sk::Pixmap::new(w, h)?;
        let mut paint = sk::Paint::default();
        paint.set_color_rgba8(255, 255, 255, 255);
        let stroke = sk::Stroke {
            width: width + 2. * outline,
            line_cap: sk::LineCap::Butt,
            line_join: match s.join {
                1 => sk::LineJoin::Bevel,
                3 | 4 => sk::LineJoin::Miter,
                _ => sk::LineJoin::Round,
            },
            ..Default::default()
        };
        for points in &shafts {
            if let Some(p) = path(points, false) {
                mask.stroke_path(&p, &paint, &stroke, transform, None);
            }
        }
        for ring in &caps {
            if let Some(p) = path(ring, true) {
                mask.fill_path(&p, &paint, sk::FillRule::Winding, transform, None);
                if outline > 0. {
                    mask.stroke_path(
                        &p,
                        &paint,
                        &sk::Stroke {
                            width: 2. * outline,
                            line_join: sk::LineJoin::Miter,
                            ..Default::default()
                        },
                        transform,
                        None,
                    );
                }
            }
        }
        Some(mask)
    };
    let ink = draw(0.)?;
    let border = draw(s.line_outline.clamp(0., 100.))?;
    let shadow = if s.shadow {
        let mask = image::GrayImage::from_fn(w, h, |x, y| {
            image::Luma([border.pixel(x, y).unwrap().alpha()])
        });
        Some(image::imageops::blur(&mask, (2. * density).max(0.1)))
    } else {
        None
    };
    let pixels = RgbaImage::from_fn(w, h, |x, y| {
        let mut rgba = [0f32; 4];
        let mut over = |color: [u8; 4], coverage: f32| {
            let a = color[3] as f32 / 255. * coverage;
            for c in 0..3 {
                rgba[c] = color[c] as f32 * a + rgba[c] * (1. - a);
            }
            rgba[3] = a + rgba[3] * (1. - a);
        };
        if let Some(shadow) = &shadow {
            let offset = (2. * density).round() as u32;
            if x >= offset && y >= offset {
                over(
                    [0, 0, 0, 64],
                    shadow.get_pixel(x - offset, y - offset).0[0] as f32 / 255.,
                );
            }
        }
        let a = ink.pixel(x, y).unwrap().alpha() as f32 / 255.;
        let b = border.pixel(x, y).unwrap().alpha() as f32 / 255.;
        if s.line_outline > 0. {
            over(s.line_outline_color, b);
        }
        over(s.outline, a);
        let alpha = rgba[3];
        image::Rgba([
            if alpha > 0. {
                (rgba[0] / alpha).round() as u8
            } else {
                0
            },
            if alpha > 0. {
                (rgba[1] / alpha).round() as u8
            } else {
                0
            },
            if alpha > 0. {
                (rgba[2] / alpha).round() as u8
            } else {
                0
            },
            (alpha * s.opacity.clamp(0., 100.) * 2.55).round() as u8,
        ])
    });
    Some(Raster {
        pixels: Arc::new(pixels),
        rect: Rect::from_min_size(bounds.min, vec2(w as f32 / density, h as f32 / density)),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::document::Tool;
    use eframe::egui::pos2;
    #[test]
    fn arrow_caps_follow_swag_dimensions_and_terminate_at_tip() {
        let cap = cap_points(pos2(100., 50.), Vec2::X, 10., 4, 4.);
        assert_eq!(
            Rect::from_points(&cap[0]),
            Rect::from_min_max(pos2(60., 30.), pos2(100., 70.))
        );
        let mut f = Form::new(
            1,
            Tool::Arrow,
            pos2(20., 50.),
            Style::for_tool(Tool::Arrow),
            1,
        );
        f.style.thickness = 10.;
        f.style.shadow = false;
        f.draw_to(pos2(20., 50.), pos2(100., 50.), false);
        let raster = rasterize(&f, 1.).unwrap();
        let at = |x: f32, y: f32| {
            raster
                .pixels
                .get_pixel(
                    (x - raster.rect.min.x) as u32,
                    (y - raster.rect.min.y) as u32,
                )
                .0
        };
        assert!(at(80., 45.)[3] > 240);
        assert_eq!(at(104., 50.)[3], 0);
        assert!(
            f.hit(pos2(62., 33.), 1.),
            "The visible arrowhead must be selectable away from the shaft"
        );
        assert!(!f.hit(pos2(90., 30.), 1.));
        f.style.end_cap = 5;
        let alternative = rasterize(&f, 1.).unwrap();
        for x in 65..95 {
            let pixel = alternative.pixels.get_pixel(
                (x as f32 - alternative.rect.min.x) as u32,
                (50. - alternative.rect.min.y) as u32,
            );
            assert_eq!(
                pixel[3], 255,
                "The two halves of Arrow 2 must have no internal seam"
            );
        }
        f.style.opacity = 50.;
        let translucent = rasterize(&f, 1.).unwrap();
        assert!(
            translucent.pixels.pixels().all(|p| p[3] <= 128),
            "Shaft/cap overlap must not multiply opacity"
        );
    }
}
