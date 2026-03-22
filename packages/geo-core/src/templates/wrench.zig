// TODO: 后续需要补充面向 mailer_box 的“主箱体 strip + 上下 flap 附着”构造 helper

const std = @import("std");
const types = @import("../types.zig");
const schema = @import("schema.zig");

pub const RectPanelSpec = struct {
    id: types.PanelId,
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    accepts_content: bool = true,
};

pub const ScoreSegmentSpec = struct {
    from: types.Vec2,
    to: types.Vec2,
};

pub const RoundedFlapOrientation = enum {
    up,
    down,
};

pub fn resolveNumericParam(
    numeric_params: []const schema.NumericParamValue,
    key: []const u8,
    default_value: f64,
) f64 {
    for (numeric_params) |param| {
        if (std.mem.eql(u8, param.key, key)) return param.value;
    }
    return default_value;
}

pub fn resolveSelectParam(
    select_params: []const schema.SelectParamValue,
    key: []const u8,
    default_value: []const u8,
) []const u8 {
    for (select_params) |param| {
        if (std.mem.eql(u8, param.key, key)) return param.value;
    }
    return default_value;
}

pub fn rectSegments(x: f64, y: f64, width: f64, height: f64) [4]types.PathSeg {
    return .{
        .{ .Line = .{ .from = .{ .x = x, .y = y }, .to = .{ .x = x + width, .y = y } } },
        .{ .Line = .{ .from = .{ .x = x + width, .y = y }, .to = .{ .x = x + width, .y = y + height } } },
        .{ .Line = .{ .from = .{ .x = x + width, .y = y + height }, .to = .{ .x = x, .y = y + height } } },
        .{ .Line = .{ .from = .{ .x = x, .y = y + height }, .to = .{ .x = x, .y = y } } },
    };
}

pub fn closedPath(comptime N: usize, segments: *const [N]types.PathSeg) types.Path2D {
    return types.Path2D.baseBy(segments);
}

pub fn openPath(comptime N: usize, segments: *const [N]types.PathSeg) types.Path2D {
    return .{
        .closed = false,
        .segments = segments,
    };
}

pub fn cutPath(comptime N: usize, segments: *const [N]types.PathSeg) types.StyledPath2D {
    return .{
        .path = closedPath(N, segments),
        .role = .cut,
        .stroke_style = .solid,
    };
}

pub fn bleedPath(comptime N: usize, segments: *const [N]types.PathSeg) types.StyledPath2D {
    return .{
        .path = closedPath(N, segments),
        .role = .bleed,
        .stroke_style = .solid,
    };
}

pub fn safePath(comptime N: usize, segments: *const [N]types.PathSeg) types.StyledPath2D {
    return .{
        .path = closedPath(N, segments),
        .role = .safe,
        .stroke_style = .dashed,
    };
}

pub fn foldPath(comptime N: usize, segments: *const [N]types.PathSeg) types.StyledPath2D {
    return .{
        .path = openPath(N, segments),
        .role = .fold,
        .stroke_style = .dashed,
    };
}

pub fn scorePath(comptime N: usize, segments: *const [N]types.PathSeg) types.StyledPath2D {
    return foldPath(N, segments);
}

pub fn lineSegment(from: types.Vec2, to: types.Vec2) types.PathSeg {
    return .{ .Line = .{ .from = from, .to = to } };
}

pub fn scoreLine(from: types.Vec2, to: types.Vec2) [1]types.PathSeg {
    return .{lineSegment(from, to)};
}

pub fn arcSegment(
    center: types.Vec2,
    radius: f64,
    start_angle: f64,
    end_angle: f64,
    clockwise: bool,
) types.PathSeg {
    return .{
        .Arc = .{
            .center = center,
            .radius = radius,
            .startAngle = start_angle,
            .endAngle = end_angle,
            .clockwise = clockwise,
        },
    };
}

pub fn annularSectorSegments(
    center: types.Vec2,
    inner_radius: f64,
    outer_radius: f64,
    start_angle: f64,
    sweep_angle: f64,
) [4]types.PathSeg {
    const end_angle = start_angle + sweep_angle;
    const outer_start = pointOnCircle(center, outer_radius, start_angle);
    const outer_end = pointOnCircle(center, outer_radius, end_angle);
    const inner_start = pointOnCircle(center, inner_radius, start_angle);
    const inner_end = pointOnCircle(center, inner_radius, end_angle);

    return .{
        arcSegment(center, outer_radius, start_angle, end_angle, sweep_angle < 0),
        lineSegment(outer_end, inner_end),
        arcSegment(center, inner_radius, end_angle, start_angle, sweep_angle >= 0),
        lineSegment(inner_start, outer_start),
    };
}

pub fn roundedFlapSegments(
    x: f64,
    y: f64,
    width: f64,
    straight_height: f64,
    orientation: RoundedFlapOrientation,
) [4]types.PathSeg {
    const radius = width / 2.0;
    const center = switch (orientation) {
        .up => types.Vec2{ .x = x + radius, .y = y + straight_height },
        .down => types.Vec2{ .x = x + radius, .y = y - straight_height },
    };

    return switch (orientation) {
        .up => .{
            lineSegment(.{ .x = x, .y = y }, .{ .x = x + width, .y = y }),
            lineSegment(.{ .x = x + width, .y = y }, .{ .x = x + width, .y = y + straight_height }),
            arcSegment(center, radius, 0, std.math.pi, false),
            lineSegment(.{ .x = x, .y = y + straight_height }, .{ .x = x, .y = y }),
        },
        .down => .{
            lineSegment(.{ .x = x, .y = y }, .{ .x = x, .y = y - straight_height }),
            arcSegment(center, radius, std.math.pi, 0, true),
            lineSegment(.{ .x = x + width, .y = y - straight_height }, .{ .x = x + width, .y = y }),
            lineSegment(.{ .x = x + width, .y = y }, .{ .x = x, .y = y }),
        },
    };
}

pub fn horizontalScoreSpec(x: f64, y: f64, width: f64) ScoreSegmentSpec {
    return .{
        .from = .{ .x = x, .y = y },
        .to = .{ .x = x + width, .y = y },
    };
}

pub fn verticalScoreSpec(x: f64, y: f64, height: f64) ScoreSegmentSpec {
    return .{
        .from = .{ .x = x, .y = y },
        .to = .{ .x = x, .y = y + height },
    };
}

pub fn initRectPanel(
    segments_out: *[4]types.PathSeg,
    id: types.PanelId,
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    outside_normal: types.Vec3,
) !types.Panel {
    segments_out.* = rectSegments(x, y, width, height);
    return types.Panel.withSurfaceBy(
        closedPath(4, segments_out),
        id,
        .{
            .origin = .{ .x = x, .y = y },
            .u_axis = .{ .x = width, .y = 0 },
            .v_axis = .{ .x = 0, .y = height },
        },
        outside_normal,
    );
}

pub fn initPanelBySegments(
    comptime N: usize,
    segments_out: *[N]types.PathSeg,
    segments: [N]types.PathSeg,
    id: types.PanelId,
    surface_frame: types.SurfaceFrame2D,
    outside_normal: types.Vec3,
) !types.Panel {
    segments_out.* = segments;
    return types.Panel.withSurfaceBy(
        closedPath(N, segments_out),
        id,
        surface_frame,
        outside_normal,
    );
}

pub fn initRectPanelWithContentInset(
    boundary_segments_out: *[4]types.PathSeg,
    content_segments_out: *[4]types.PathSeg,
    id: types.PanelId,
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    inset: f64,
    outside_normal: types.Vec3,
) !types.Panel {
    boundary_segments_out.* = rectSegments(x, y, width, height);
    content_segments_out.* = rectSegments(
        x + inset,
        y + inset,
        width - inset * 2.0,
        height - inset * 2.0,
    );
    return types.Panel.withGeometryBy(
        closedPath(4, boundary_segments_out),
        id,
        .{
            .origin = .{ .x = x, .y = y },
            .u_axis = .{ .x = width, .y = 0 },
            .v_axis = .{ .x = 0, .y = height },
        },
        closedPath(4, content_segments_out),
        outside_normal,
    );
}

pub fn initRectPanelSet(
    comptime N: usize,
    panel_segments_out: *[N][4]types.PathSeg,
    panels_out: *[N]types.Panel,
    specs: [N]RectPanelSpec,
    outside_normal: types.Vec3,
) !void {
    for (specs, 0..) |spec, index| {
        panels_out[index] = try initRectPanel(
            &panel_segments_out[index],
            spec.id,
            spec.x,
            spec.y,
            spec.width,
            spec.height,
            outside_normal,
        );
        panels_out[index].accepts_content = spec.accepts_content;
    }
}

pub fn initScoreSegments(
    comptime N: usize,
    score_segments_out: *[N][1]types.PathSeg,
    specs: [N]ScoreSegmentSpec,
) void {
    for (specs, 0..) |spec, index| {
        score_segments_out[index] = scoreLine(spec.from, spec.to);
    }
}

pub fn fold(
    from_panel_id: types.PanelId,
    to_panel_id: types.PanelId,
    from_segment_index: u16,
    to_segment_index: u16,
    angle_rad: f64,
    direction: types.FoldDirection,
) types.Fold {
    return .{
        .from_panel_id = from_panel_id,
        .to_panel_id = to_panel_id,
        .axis = .{
            .from_edge = .{ .panel_id = from_panel_id, .segment_index = from_segment_index },
            .to_edge = .{ .panel_id = to_panel_id, .segment_index = to_segment_index },
        },
        .angle_rad = angle_rad,
        .direction = direction,
    };
}

pub fn initRectPanelStrip(
    comptime N: usize,
    panel_segments_out: *[N][4]types.PathSeg,
    panels_out: *[N]types.Panel,
    start_x: f64,
    y: f64,
    widths: [N]f64,
    height: f64,
    start_panel_id: types.PanelId,
    outside_normal: types.Vec3,
) !void {
    var x = start_x;

    for (widths, 0..) |width, index| {
        panels_out[index] = try initRectPanel(
            &panel_segments_out[index],
            start_panel_id + @as(types.PanelId, @intCast(index)),
            x,
            y,
            width,
            height,
            outside_normal,
        );
        x += width;
    }
}

pub fn scoreSegmentsForStrip(
    comptime N: usize,
    start_x: f64,
    y: f64,
    widths: [N]f64,
    height: f64,
) [N - 1][1]types.PathSeg {
    var segments: [N - 1][1]types.PathSeg = undefined;
    var x = start_x;

    for (widths[0 .. N - 1], 0..) |width, index| {
        x += width;
        segments[index] = scoreLine(
            .{ .x = x, .y = y },
            .{ .x = x, .y = y + height },
        );
    }

    return segments;
}

pub fn foldChainRightToLeft(
    comptime N: usize,
    start_panel_id: types.PanelId,
    angle_rad: f64,
    directions: [N]types.FoldDirection,
) [N]types.Fold {
    var folds: [N]types.Fold = undefined;
    for (directions, 0..) |direction, index| {
        const from_panel_id = start_panel_id + @as(types.PanelId, @intCast(index));
        const to_panel_id = from_panel_id + 1;
        folds[index] = fold(
            from_panel_id,
            to_panel_id,
            1,
            3,
            angle_rad,
            direction,
        );
    }
    return folds;
}

pub fn appendCutLinework(
    comptime N: usize,
    destination: []types.StyledPath2D,
    start_index: usize,
    panel_segments: *const [N][4]types.PathSeg,
) void {
    for (0..N) |index| {
        destination[start_index + index] = cutPath(4, &panel_segments[index]);
    }
}

pub fn appendScoreLinework(
    comptime N: usize,
    destination: []types.StyledPath2D,
    start_index: usize,
    score_segments: *const [N][1]types.PathSeg,
) void {
    for (0..N) |index| {
        destination[start_index + index] = foldPath(1, &score_segments[index]);
    }
}

test "wrench helpers build fold and styled paths" {
    const segments = rectSegments(0, 0, 10, 5);
    const cut = cutPath(4, &segments);
    try std.testing.expect(cut.path.closed);
    try std.testing.expectEqual(types.LineRole.cut, cut.role);

    const score_segments = scoreLine(.{ .x = 5, .y = 0 }, .{ .x = 5, .y = 5 });
    const fold_line = foldPath(1, &score_segments);
    try std.testing.expect(!fold_line.path.closed);
    try std.testing.expectEqual(types.LineRole.fold, fold_line.role);

    const hinge = fold(1, 2, 0, 2, std.math.pi / 2.0, .toward_inside);
    try std.testing.expectEqual(@as(types.PanelId, 1), hinge.from_panel_id);
    try std.testing.expectEqual(@as(u16, 2), hinge.axis.to_edge.segment_index);
}

test "wrench helpers build strips chains and linework" {
    const widths = [_]f64{ 10, 6, 10 };
    var panel_segments: [3][4]types.PathSeg = undefined;
    var panels: [3]types.Panel = undefined;
    try initRectPanelStrip(3, &panel_segments, &panels, 2, 4, widths, 8, 5, .{ .x = 0, .y = 0, .z = 1 });
    try std.testing.expectEqual(@as(types.PanelId, 5), panels[0].id);
    try std.testing.expectEqual(@as(types.PanelId, 7), panels[2].id);

    const scores = scoreSegmentsForStrip(3, 2, 4, widths, 8);
    try std.testing.expectEqual(@as(f64, 12), scores[0][0].Line.from.x);
    try std.testing.expectEqual(@as(f64, 18), scores[1][0].Line.from.x);

    const folds = foldChainRightToLeft(2, 5, std.math.pi / 2.0, .{ .toward_inside, .toward_outside });
    try std.testing.expectEqual(@as(types.PanelId, 5), folds[0].from_panel_id);
    try std.testing.expectEqual(@as(types.PanelId, 7), folds[1].to_panel_id);

    var linework: [5]types.StyledPath2D = undefined;
    appendCutLinework(3, &linework, 0, &panel_segments);
    appendScoreLinework(2, &linework, 3, &scores);
    try std.testing.expectEqual(types.LineRole.cut, linework[0].role);
    try std.testing.expectEqual(types.LineRole.fold, linework[4].role);
    try std.testing.expectApproxEqAbs(@as(f64, 2), linework[0].path.segments[0].Line.from.x, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 12), linework[3].path.segments[0].Line.from.x, 1e-9);
}

test "wrench helpers initialize panel and score specs" {
    var panel_segments: [2][4]types.PathSeg = undefined;
    var panels: [2]types.Panel = undefined;
    try initRectPanelSet(
        2,
        &panel_segments,
        &panels,
        .{
            .{ .id = 10, .x = 0, .y = 0, .width = 12, .height = 8 },
            .{ .id = 11, .x = 12, .y = 0, .width = 4, .height = 8, .accepts_content = false },
        },
        .{ .x = 0, .y = 0, .z = 1 },
    );
    try std.testing.expectEqual(@as(types.PanelId, 10), panels[0].id);
    try std.testing.expect(!panels[1].accepts_content);

    var score_segments: [2][1]types.PathSeg = undefined;
    initScoreSegments(
        2,
        &score_segments,
        .{
            horizontalScoreSpec(0, 4, 16),
            verticalScoreSpec(12, 0, 8),
        },
    );
    try std.testing.expectEqual(@as(f64, 16), score_segments[0][0].Line.to.x);
    try std.testing.expectEqual(@as(f64, 8), score_segments[1][0].Line.to.y);
}

test "wrench helpers build annular sector and rounded flap segments" {
    const sector = annularSectorSegments(.{ .x = 0, .y = 0 }, 10, 24, 0, std.math.pi / 2.0);
    try std.testing.expect(sector[0] == .Arc);
    try std.testing.expect(sector[2] == .Arc);
    try std.testing.expectApproxEqAbs(@as(f64, 24), sector[0].Arc.radius, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 10), sector[2].Arc.radius, 1e-9);

    const flap = roundedFlapSegments(0, 0, 20, 8, .up);
    try std.testing.expect(flap[2] == .Arc);
    try std.testing.expectApproxEqAbs(std.math.pi, flap[2].Arc.endAngle, 1e-9);

    var stored: [4]types.PathSeg = undefined;
    const panel = try initPanelBySegments(
        4,
        &stored,
        flap,
        42,
        .{
            .origin = .{ .x = 0, .y = 0 },
            .u_axis = .{ .x = 20, .y = 0 },
            .v_axis = .{ .x = 0, .y = 18 },
        },
        .{ .x = 0, .y = 0, .z = 1 },
    );
    try std.testing.expectEqual(@as(types.PanelId, 42), panel.id);
}

fn pointOnCircle(center: types.Vec2, radius: f64, angle: f64) types.Vec2 {
    return .{
        .x = center.x + std.math.cos(angle) * radius,
        .y = center.y + std.math.sin(angle) * radius,
    };
}
