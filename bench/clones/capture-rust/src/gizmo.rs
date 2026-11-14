use crate::document::{Form, Tool};
use eframe::egui::*;

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Handle {
    Edge(usize),
    Rotate,
    Point(usize),
    Control,
    Tail,
}

pub fn anchors(r: Rect) -> [Pos2; 8] {
    [
        r.left_top(),
        r.center_top(),
        r.right_top(),
        r.left_center(),
        r.right_center(),
        r.left_bottom(),
        r.center_bottom(),
        r.right_bottom(),
    ]
}

pub fn rotate(v: Vec2, degrees: f32) -> Vec2 {
    let (s, c) = degrees.to_radians().sin_cos();
    vec2(v.x * c - v.y * s, v.x * s + v.y * c)
}

pub fn handles(form: &Form, zoom: f32) -> Vec<(Handle, Pos2)> {
    if matches!(form.tool, Tool::Arrow | Tool::Line | Tool::Polygon) {
        let mut points: Vec<_> = form
            .points
            .iter()
            .enumerate()
            .map(|(i, p)| (Handle::Point(i), pos2(p[0], p[1])))
            .collect();
        if form.style.bezier && matches!(form.tool, Tool::Arrow | Tool::Line) {
            points.push((Handle::Control, pos2(form.control[0], form.control[1])));
        }
        return points;
    }
    let rect = form.rect();
    let mut points: Vec<_> = anchors(rect)
        .into_iter()
        .enumerate()
        .map(|(i, p)| (Handle::Edge(i), p))
        .collect();
    if matches!(
        form.tool,
        Tool::Shape | Tool::Text | Tool::Image | Tool::Callout
    ) {
        points.push((Handle::Rotate, rect.center_top() - vec2(0., 26. / zoom)));
    }
    if form.tool == Tool::Callout {
        points.push((Handle::Tail, pos2(form.tail[0], form.tail[1])));
    }
    for (_, point) in &mut points {
        *point = rect.center() + rotate(*point - rect.center(), form.style.rotation);
    }
    points
}

pub fn resize(rect: Rect, anchor: usize, delta: Vec2, angle: f32, constrain: bool) -> Rect {
    let mut delta = rotate(delta, -angle);
    if constrain && matches!(anchor, 0 | 2 | 5 | 7) {
        let sign = if matches!(anchor, 0 | 7) { 1. } else { -1. };
        if delta.x.abs() > delta.y.abs() {
            delta.y = sign * delta.x;
        } else {
            delta.x = sign * delta.y;
        }
    }
    let mut local = Rect::from_center_size(Pos2::ZERO, rect.size());
    if matches!(anchor, 0 | 3 | 5) {
        local.min.x = (local.min.x + delta.x).min(local.max.x - 2.);
    }
    if matches!(anchor, 0 | 1 | 2) {
        local.min.y = (local.min.y + delta.y).min(local.max.y - 2.);
    }
    if matches!(anchor, 2 | 4 | 7) {
        local.max.x = (local.max.x + delta.x).max(local.min.x + 2.);
    }
    if matches!(anchor, 5 | 6 | 7) {
        local.max.y = (local.max.y + delta.y).max(local.min.y + 2.);
    }
    Rect::from_center_size(
        rect.center() + rotate(local.center().to_vec2(), angle),
        local.size(),
    )
}

pub fn paint(painter: &Painter, form: &Form, origin: Pos2, zoom: f32, ink: Color32) {
    let screen = |p: Pos2| origin + p.to_vec2() * zoom;
    let rect = form.rect();
    if !matches!(form.tool, Tool::Arrow | Tool::Line | Tool::Polygon) {
        let points = vec![
            rect.left_top(),
            rect.right_top(),
            rect.right_bottom(),
            rect.left_bottom(),
            rect.left_top(),
        ];
        painter.add(Shape::line(
            points
                .into_iter()
                .map(|p| screen(rect.center() + rotate(p - rect.center(), form.style.rotation)))
                .collect(),
            Stroke::new(1.0_f32, ink),
        ));
    }
    for (handle, point) in handles(form, zoom) {
        let pos = screen(point);
        if handle == Handle::Rotate {
            let top = screen(
                rect.center() + rotate(rect.center_top() - rect.center(), form.style.rotation),
            );
            painter.line_segment([top, pos], Stroke::new(1.0_f32, ink));
        }
        if handle == Handle::Control && form.points.len() >= 2 {
            for p in &form.points[..2] {
                painter.line_segment(
                    [screen(pos2(p[0], p[1])), pos],
                    Stroke::new(1.0_f32, ink.gamma_multiply(0.45)),
                );
            }
        }
        painter.circle(pos, 4., Color32::WHITE, Stroke::new(1.0_f32, ink));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn resize_matches_swag_anchor_contract() {
        let r = Rect::from_min_size(pos2(100., 100.), vec2(50., 40.));
        assert_eq!(
            resize(r, 0, vec2(10., 5.), 0., false),
            Rect::from_min_size(pos2(110., 105.), vec2(40., 35.))
        );
        assert_eq!(
            resize(r, 7, vec2(10., 4.), 0., true),
            Rect::from_min_size(pos2(100., 100.), vec2(60., 50.))
        );
        assert_eq!(
            resize(r, 2, vec2(10., 4.), 0., true),
            Rect::from_min_size(pos2(100., 90.), vec2(60., 50.))
        );
        assert_eq!(
            resize(r, 1, vec2(0., 100.), 0., false),
            Rect::from_min_size(pos2(100., 138.), vec2(50., 2.))
        );
    }
    #[test]
    fn rotated_resize_keeps_the_opposite_side_fixed() {
        let r = Rect::from_center_size(pos2(100., 100.), vec2(80., 40.));
        let changed = resize(r, 4, vec2(0., 20.), 90., false);
        assert!((changed.width() - 100.).abs() < 0.001);
        assert!((changed.center() - pos2(100., 110.)).length() < 0.001);
    }
}
