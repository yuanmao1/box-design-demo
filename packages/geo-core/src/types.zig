const std = @import("std");

pub const PanelId = u16;
pub const ContentId = u32;

pub const Vec2 = struct {
    x: f64,
    y: f64,
};

pub const Vec3 = struct {
    x: f64,
    y: f64,
    z: f64,
};

pub const Rect2D = struct {
    origin: Vec2,
    size: Vec2,
};

pub const SurfaceFrame2D = struct {
    origin: Vec2,
    u_axis: Vec2,
    v_axis: Vec2,
};

pub const LineSeg = struct {
    from: Vec2,
    to: Vec2,
};

pub const ArcSeg = struct {
    center: Vec2,
    radius: f64,
    startAngle: f64,
    endAngle: f64,
    clockwise: bool,
};

pub const BezierSeg = struct {
    p0: Vec2,
    p1: Vec2,
    p2: Vec2,
    p3: Vec2,
};

pub const PathSeg = union(enum) {
    Line: LineSeg,
    Arc: ArcSeg,
    Bezier: BezierSeg,
};

pub const Path2D = struct {
    closed: bool,
    segments: []const PathSeg,

    pub fn baseBy(segments: []const PathSeg) Path2D {
        return Path2D{
            .closed = isClosed(segments),
            .segments = segments,
        };
    }
};

pub const Panel = struct {
    pub const ValidationError = error{
        EmptyBoundary,
        BoundaryNotClosed,
        BoundaryNotContinuous,
    };

    id: PanelId,
    boundary: Path2D,
    surface_frame: SurfaceFrame2D,
    content_region: Path2D,
    outside_normal: Vec3 = .{ .x = 0, .y = 0, .z = -1 },
    accepts_content: bool = true,

    pub fn baseBy(boundary: Path2D, id: PanelId) ValidationError!Panel {
        try validateBoundary(boundary);
        const bounds = boundsForPath(boundary);
        return Panel{
            .id = id,
            .boundary = boundary,
            .surface_frame = .{
                .origin = bounds.origin,
                .u_axis = .{ .x = bounds.size.x, .y = 0 },
                .v_axis = .{ .x = 0, .y = bounds.size.y },
            },
            .content_region = boundary,
        };
    }

    pub fn withSurfaceBy(
        boundary: Path2D,
        id: PanelId,
        surface_frame: SurfaceFrame2D,
        outside_normal: Vec3,
    ) ValidationError!Panel {
        return withGeometryBy(boundary, id, surface_frame, boundary, outside_normal);
    }

    pub fn withGeometryBy(
        boundary: Path2D,
        id: PanelId,
        surface_frame: SurfaceFrame2D,
        content_region: Path2D,
        outside_normal: Vec3,
    ) ValidationError!Panel {
        try validateBoundary(boundary);
        try validateBoundary(content_region);
        return Panel{
            .id = id,
            .boundary = boundary,
            .surface_frame = surface_frame,
            .content_region = content_region,
            .outside_normal = outside_normal,
        };
    }

    pub fn validateBoundary(boundary: Path2D) ValidationError!void {
        if (boundary.segments.len == 0) return ValidationError.EmptyBoundary;
        if (!boundary.closed) return ValidationError.BoundaryNotClosed;

        var previous_end = segmentEndPoint(boundary.segments[0]);
        for (boundary.segments[1..]) |segment| {
            const current_start = segmentStartPoint(segment);
            if (!approxEqVec2(previous_end, current_start)) {
                return ValidationError.BoundaryNotContinuous;
            }
            previous_end = segmentEndPoint(segment);
        }

        const first_start = segmentStartPoint(boundary.segments[0]);
        if (!approxEqVec2(previous_end, first_start)) {
            return ValidationError.BoundaryNotContinuous;
        }
    }
};

pub const PanelEdgeRef = struct {
    panel_id: PanelId,
    segment_index: u16,
};

pub const FoldAxis = struct {
    from_edge: PanelEdgeRef,
    to_edge: PanelEdgeRef,
};

pub const FoldDirection = enum {
    toward_outside,
    toward_inside,
};

pub const Fold = struct {
    from_panel_id: PanelId,
    to_panel_id: PanelId,
    axis: FoldAxis,
    angle_rad: f64,
    direction: FoldDirection = .toward_outside,
};

pub const StrokeStyle = enum {
    solid,
    dashed,
    dotted,
};

pub const LineRole = enum {
    cut,
    score,
    guide,
};

pub const StyledPath2D = struct {
    path: Path2D,
    role: LineRole,
    stroke_style: StrokeStyle = .solid,
};

pub const VolumeProfile = struct {
    outline: Path2D,
    depth_axis: Vec3 = .{ .x = 0, .y = 0, .z = 1 },
};

pub const ContentKind = enum {
    image,
    text,
    shape,
    qr_code,
    barcode,
    vector_path,
};

pub const SurfaceContent = union(ContentKind) {
    image: struct {
        source: []const u8,
        focal_point: Vec2 = .{ .x = 50, .y = 50 },
    },
    text: struct {
        text: []const u8,
        font_key: ?[]const u8 = null,
        font_size: f64,
        color_hex: []const u8 = "#000000",
    },
    shape: struct {
        fill_svg_path: []const u8,
    },
    qr_code: struct {
        payload: []const u8,
    },
    barcode: struct {
        payload: []const u8,
    },
    vector_path: struct {
        path: Path2D,
    },
};

pub const ContentTransformSpace = enum {
    panel_local,
    panel_uv_percent,
};

pub const ContentTransform2D = struct {
    position: Vec2,
    size: Vec2,
    rotation_rad: f64 = 0,
    space: ContentTransformSpace = .panel_local,
};

pub const PanelContentPlacement = struct {
    id: ContentId,
    panel_id: PanelId,
    content: SurfaceContent,
    transform: ContentTransform2D,
    clip_path: ?Path2D = null,
    surface_frame: ?SurfaceFrame2D = null,
    z_index: i32 = 0,
};

fn isClosed(segments: []const PathSeg) bool {
    if (segments.len == 0) return false;

    const start = segmentStartPoint(segments[0]);
    const end = segmentEndPoint(segments[segments.len - 1]);

    return approxEqVec2(start, end);
}

fn segmentStartPoint(segment: PathSeg) Vec2 {
    return switch (segment) {
        .Line => |line| line.from,
        .Arc => |arc| pointOnArc(arc, arc.startAngle),
        .Bezier => |bezier| bezier.p0,
    };
}

fn segmentEndPoint(segment: PathSeg) Vec2 {
    return switch (segment) {
        .Line => |line| line.to,
        .Arc => |arc| pointOnArc(arc, arc.endAngle),
        .Bezier => |bezier| bezier.p3,
    };
}

fn pointOnArc(arc: ArcSeg, angle: f64) Vec2 {
    return .{
        .x = arc.center.x + arc.radius * std.math.cos(angle),
        .y = arc.center.y + arc.radius * std.math.sin(angle),
    };
}

fn approxEqVec2(a: Vec2, b: Vec2) bool {
    return approxEq(a.x, b.x) and approxEq(a.y, b.y);
}

fn approxEq(a: f64, b: f64) bool {
    return std.math.approxEqAbs(f64, a, b, 1e-9);
}

fn boundsForPath(path: Path2D) Rect2D {
    var min_x = std.math.inf(f64);
    var min_y = std.math.inf(f64);
    var max_x = -std.math.inf(f64);
    var max_y = -std.math.inf(f64);

    for (path.segments) |segment| {
        switch (segment) {
            .Line => |line| {
                includePoint(&min_x, &min_y, &max_x, &max_y, line.from);
                includePoint(&min_x, &min_y, &max_x, &max_y, line.to);
            },
            .Arc => |arc| {
                includePoint(&min_x, &min_y, &max_x, &max_y, .{
                    .x = arc.center.x - arc.radius,
                    .y = arc.center.y - arc.radius,
                });
                includePoint(&min_x, &min_y, &max_x, &max_y, .{
                    .x = arc.center.x + arc.radius,
                    .y = arc.center.y + arc.radius,
                });
            },
            .Bezier => |bezier| {
                includePoint(&min_x, &min_y, &max_x, &max_y, bezier.p0);
                includePoint(&min_x, &min_y, &max_x, &max_y, bezier.p1);
                includePoint(&min_x, &min_y, &max_x, &max_y, bezier.p2);
                includePoint(&min_x, &min_y, &max_x, &max_y, bezier.p3);
            },
        }
    }

    return .{
        .origin = .{ .x = min_x, .y = min_y },
        .size = .{ .x = max_x - min_x, .y = max_y - min_y },
    };
}

fn includePoint(
    min_x: *f64,
    min_y: *f64,
    max_x: *f64,
    max_y: *f64,
    point: Vec2,
) void {
    min_x.* = @min(min_x.*, point.x);
    min_y.* = @min(min_y.*, point.y);
    max_x.* = @max(max_x.*, point.x);
    max_y.* = @max(max_y.*, point.y);
}

test "Path2D.baseBy infers closed for connected polygon" {
    const segments = [_]PathSeg{
        .{ .Line = .{ .from = .{ .x = 0, .y = 0 }, .to = .{ .x = 10, .y = 0 } } },
        .{ .Line = .{ .from = .{ .x = 10, .y = 0 }, .to = .{ .x = 10, .y = 5 } } },
        .{ .Line = .{ .from = .{ .x = 10, .y = 5 }, .to = .{ .x = 0, .y = 5 } } },
        .{ .Line = .{ .from = .{ .x = 0, .y = 5 }, .to = .{ .x = 0, .y = 0 } } },
    };

    const path = Path2D.baseBy(&segments);

    try std.testing.expect(path.closed);
    try std.testing.expectEqual(@as(usize, 4), path.segments.len);
}

test "Panel.baseBy accepts closed continuous boundary" {
    const segments = [_]PathSeg{
        .{ .Line = .{ .from = .{ .x = 0, .y = 0 }, .to = .{ .x = 10, .y = 0 } } },
        .{ .Line = .{ .from = .{ .x = 10, .y = 0 }, .to = .{ .x = 10, .y = 5 } } },
        .{ .Line = .{ .from = .{ .x = 10, .y = 5 }, .to = .{ .x = 0, .y = 5 } } },
        .{ .Line = .{ .from = .{ .x = 0, .y = 5 }, .to = .{ .x = 0, .y = 0 } } },
    };

    const panel = try Panel.baseBy(Path2D.baseBy(&segments), 7);

    try std.testing.expectEqual(@as(PanelId, 7), panel.id);
}

test "Panel.baseBy rejects non-closed boundary" {
    const segments = [_]PathSeg{
        .{ .Line = .{ .from = .{ .x = 0, .y = 0 }, .to = .{ .x = 10, .y = 0 } } },
        .{ .Line = .{ .from = .{ .x = 10, .y = 0 }, .to = .{ .x = 10, .y = 5 } } },
        .{ .Line = .{ .from = .{ .x = 10, .y = 5 }, .to = .{ .x = 0, .y = 5 } } },
    };

    try std.testing.expectError(
        Panel.ValidationError.BoundaryNotClosed,
        Panel.baseBy(Path2D.baseBy(&segments), 1),
    );
}

test "Panel.baseBy rejects discontinuous boundary" {
    const segments = [_]PathSeg{
        .{ .Line = .{ .from = .{ .x = 0, .y = 0 }, .to = .{ .x = 10, .y = 0 } } },
        .{ .Line = .{ .from = .{ .x = 10, .y = 0 }, .to = .{ .x = 10, .y = 5 } } },
        .{ .Line = .{ .from = .{ .x = 20, .y = 5 }, .to = .{ .x = 0, .y = 5 } } },
        .{ .Line = .{ .from = .{ .x = 0, .y = 5 }, .to = .{ .x = 0, .y = 0 } } },
    };

    const boundary = Path2D{
        .closed = true,
        .segments = &segments,
    };

    try std.testing.expectError(
        Panel.ValidationError.BoundaryNotContinuous,
        Panel.baseBy(boundary, 2),
    );
}
