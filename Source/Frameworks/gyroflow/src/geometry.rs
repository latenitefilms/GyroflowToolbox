//! Clip-sized FxPlug buffer geometry, following the official plugins' rotation rules.

#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct Geometry {
    pub input_rotation: f64,
    pub source_rect: (usize, usize, usize, usize),
}

pub(crate) fn is_quarter_turn(rotation: f64) -> bool {
    (rotation.rem_euclid(180.0) - 90.0).abs() < 1.0
}

pub(crate) fn for_clip(
    video_size: (usize, usize),
    mut input_rotation: f64,
    buffer_size: (usize, usize),
) -> Geometry {
    let ratio = |size: (usize, usize)| size.0 as f64 / size.1.max(1) as f64;
    // FxPlug hands us clip-sized buffers. If the host did not rotate the pixels,
    // metadata alone must not cause a second quarter turn.
    if is_quarter_turn(input_rotation)
        && video_size.0 != video_size.1
        && (ratio(buffer_size) / ratio(video_size) - 1.0).abs() < 0.01
        && (ratio(buffer_size) / ratio((video_size.1, video_size.0)) - 1.0).abs() > 0.01
    {
        input_rotation = 0.0;
    }
    let clip_size = if is_quarter_turn(input_rotation) {
        (video_size.1, video_size.0)
    } else {
        video_size
    };
    let clip_ratio = ratio(clip_size);
    let (width, height) = buffer_size;
    let (rect_width, rect_height) = if (ratio(buffer_size) - clip_ratio).abs() <= 0.1 {
        buffer_size
    } else if ratio(buffer_size) > clip_ratio {
        (
            ((height as f64 * clip_ratio).round() as usize).min(width),
            height,
        )
    } else {
        (
            width,
            ((width as f64 / clip_ratio).round() as usize).min(height),
        )
    };
    Geometry {
        input_rotation,
        source_rect: (
            (width - rect_width) / 2,
            (height - rect_height) / 2,
            rect_width,
            rect_height,
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn portrait_on_portrait_uses_the_entire_buffer() {
        for rotation in [90.0, 270.0, -90.0, 89.5] {
            for size in [(2160, 3840), (1080, 1920), (270, 480)] {
                let geometry = for_clip((3840, 2160), rotation, size);
                assert_eq!(geometry.source_rect, (0, 0, size.0, size.1));
                assert_eq!(geometry.input_rotation, rotation);
            }
        }
    }
    #[test]
    fn unrotated_buffers_do_not_receive_the_metadata_rotation_twice() {
        assert_eq!(for_clip((3840, 2160), 90.0, (960, 540)).input_rotation, 0.0);
        assert_eq!(
            for_clip((3840, 2160), 270.0, (3840, 2160)).source_rect,
            (0, 0, 3840, 2160)
        );
    }
    #[test]
    fn native_portrait_and_square_clips_keep_their_frame() {
        assert_eq!(
            for_clip((1080, 1920), 0.0, (540, 960)).source_rect,
            (0, 0, 540, 960)
        );
        assert_eq!(
            for_clip((2048, 2048), 90.0, (512, 512)).input_rotation,
            90.0
        );
    }
}
