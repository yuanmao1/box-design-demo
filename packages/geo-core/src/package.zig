const std = @import("std");
const types = @import("types.zig");

pub const PackageKind = enum {
    folding_carton,
    flexible_pouch,
};

pub const PreviewNodeKind = enum {
    panel,
    shell,
};

pub const PreviewTransform3D = struct {
    translation: types.Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    rotation_origin: types.Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    rotation_axis: types.Vec3 = .{ .x = 0, .y = 0, .z = 1 },
    rotation_rad: f64 = 0,
    scale: types.Vec3 = .{ .x = 1, .y = 1, .z = 1 },
};

pub const PreviewBuildError = error{
    UnknownPanelId,
    InvalidPanelEdge,
    NonLinearFoldAxis,
    ZeroLengthFoldAxis,
    MisalignedFoldAxis,
    FoldGraphCycle,
};

pub const ContentValidationError = error{
    UnknownPanelId,
    PanelRejectsContent,
    InvalidContentSize,
    ContentOutOfBounds,
    OutOfMemory,
};

pub const Drawing2DResult = struct {
    pub const Panel2D = struct {
        panel_id: types.PanelId,
        name: []const u8 = "",
        boundary: types.Path2D,
        content_region: types.Path2D,
        surface_frame: types.SurfaceFrame2D,
        accepts_content: bool,
    };

    panels: []const Panel2D = &.{},
    linework: []const types.StyledPath2D,
    contents: []const types.PanelContentPlacement = &.{},

    pub fn deinit(self: *Drawing2DResult, allocator: std.mem.Allocator) void {
        allocator.free(self.panels);
        allocator.free(self.linework);
        self.* = .{
            .panels = &.{},
            .linework = &.{},
        };
    }
};

pub const Preview3DNode = struct {
    kind: PreviewNodeKind,
    parent_index: ?u32 = null,
    panel_id: ?types.PanelId = null,
    hinge_segment_index: ?u16 = null, // Rendering hint for consumers that need an edge handle.
    boundary: ?types.Path2D = null,
    surface_frame: ?types.SurfaceFrame2D = null,
    outside_normal: ?types.Vec3 = null,
    transform: PreviewTransform3D = .{},
};

pub const Preview3DResult = struct {
    nodes: []const Preview3DNode,
    contents: []const types.PanelContentPlacement = &.{},

    pub fn deinit(self: *Preview3DResult, allocator: std.mem.Allocator) void {
        allocator.free(self.nodes);
        self.* = .{
            .nodes = &.{},
        };
    }
};

pub const FoldingCartonModel = struct {
    kind: PackageKind = .folding_carton,
    panels: []const types.Panel,
    folds: []const types.Fold,
    linework: []const types.StyledPath2D,
    contents: []const types.PanelContentPlacement = &.{},

    pub fn init(
        panels: []const types.Panel,
        folds: []const types.Fold,
        linework: []const types.StyledPath2D,
    ) FoldingCartonModel {
        return .{
            .panels = panels,
            .folds = folds,
            .linework = linework,
        };
    }

    pub fn deinit(_: *FoldingCartonModel, _: std.mem.Allocator) void {}

    pub fn setContents(
        self: *FoldingCartonModel,
        allocator: std.mem.Allocator,
        contents: []types.PanelContentPlacement,
    ) ContentValidationError!void {
        try self.prepareContents(allocator, contents);
        self.contents = contents;
    }

    pub fn buildDrawing2D(
        self: *const FoldingCartonModel,
        allocator: std.mem.Allocator,
    ) !Drawing2DResult {
        const panels = try allocator.alloc(Drawing2DResult.Panel2D, self.panels.len);
        errdefer allocator.free(panels);
        for (self.panels, 0..) |panel, index| {
            panels[index] = .{
                .panel_id = panel.id,
                .name = panel.name,
                .boundary = panel.boundary,
                .content_region = panel.content_region,
                .surface_frame = panel.surface_frame,
                .accepts_content = panel.accepts_content,
            };
        }

        const linework = try allocator.alloc(types.StyledPath2D, self.linework.len);
        errdefer {
            allocator.free(linework);
            allocator.free(panels);
        }
        std.mem.copyForwards(types.StyledPath2D, linework, self.linework);

        return .{
            .panels = panels,
            .linework = linework,
            .contents = self.contents,
        };
    }

    pub fn buildPreview3D(
        self: *const FoldingCartonModel,
        allocator: std.mem.Allocator,
    ) !Preview3DResult {
        try self.validateModel(allocator);

        const nodes = try allocator.alloc(Preview3DNode, self.panels.len);
        errdefer allocator.free(nodes);
        const visited = try allocator.alloc(bool, self.panels.len);
        defer allocator.free(visited);
        const queue = try allocator.alloc(usize, self.panels.len);
        defer allocator.free(queue);

        for (self.panels, 0..) |panel, index| {
            nodes[index] = .{
                .kind = .panel,
                .panel_id = panel.id,
                .boundary = panel.boundary,
                .surface_frame = panel.surface_frame,
                .outside_normal = panel.outside_normal,
            };
            visited[index] = false;
        }

        var head: usize = 0;
        var tail: usize = 0;
        var visited_count: usize = 0;

        while (visited_count < self.panels.len) {
            const root_index = self.choosePreviewRootIndex(visited);
            if (visited[root_index]) continue;
            visited[root_index] = true;
            visited_count += 1;
            queue[tail] = root_index;
            tail += 1;

            while (head < tail) {
                const current_index = queue[head];
                head += 1;
                const current_panel = self.panels[current_index];

                for (self.folds) |fold| {
                    const relation = self.resolveFoldRelation(current_panel.id, fold) orelse continue;
                    const child_index = try self.panelIndexById(relation.child_panel_id);
                    if (visited[child_index]) continue;

                    visited[child_index] = true;
                    visited_count += 1;
                    nodes[child_index].parent_index = @intCast(current_index);
                    nodes[child_index].hinge_segment_index = relation.child_edge.segment_index;
                    nodes[child_index].transform = try self.transformForFold(
                        relation.parent_edge,
                        relation.child_panel_id,
                        relation.angle_rad,
                        relation.direction,
                    );
                    queue[tail] = child_index;
                    tail += 1;
                }
            }
        }

        return .{
            .nodes = nodes,
            .contents = self.contents,
        };
    }

    fn validateModel(
        self: *const FoldingCartonModel,
        allocator: std.mem.Allocator,
    ) !void {
        for (self.folds) |fold| {
            try self.validateFoldAxis(fold);
        }

        const parents = try allocator.alloc(usize, self.panels.len);
        defer allocator.free(parents);
        for (parents, 0..) |*parent, index| {
            parent.* = index;
        }

        for (self.folds) |fold| {
            const left = try self.panelIndexById(fold.from_panel_id);
            const right = try self.panelIndexById(fold.to_panel_id);

            const left_root = findRoot(parents, left);
            const right_root = findRoot(parents, right);
            if (left_root == right_root) return PreviewBuildError.FoldGraphCycle;
            parents[right_root] = left_root;
        }
    }

    fn validateFoldAxis(
        self: *const FoldingCartonModel,
        fold: types.Fold,
    ) PreviewBuildError!void {
        const from_line = try self.edgeLine(fold.axis.from_edge);
        const to_line = try self.edgeLine(fold.axis.to_edge);

        if (!sameUndirectedLine(from_line, to_line)) {
            return PreviewBuildError.MisalignedFoldAxis;
        }
    }

    const ResolvedFoldRelation = struct {
        child_panel_id: types.PanelId,
        parent_edge: types.PanelEdgeRef,
        child_edge: types.PanelEdgeRef,
        angle_rad: f64,
        direction: types.FoldDirection,
    };

    fn resolveFoldRelation(
        self: *const FoldingCartonModel,
        current_panel_id: types.PanelId,
        fold: types.Fold,
    ) ?ResolvedFoldRelation {
        _ = self;

        if (fold.from_panel_id == current_panel_id) {
            return .{
                .child_panel_id = fold.to_panel_id,
                .parent_edge = fold.axis.from_edge,
                .child_edge = fold.axis.to_edge,
                .angle_rad = fold.angle_rad,
                .direction = fold.direction,
            };
        }
        if (fold.to_panel_id == current_panel_id) {
            return .{
                .child_panel_id = fold.from_panel_id,
                .parent_edge = fold.axis.to_edge,
                .child_edge = fold.axis.from_edge,
                .angle_rad = fold.angle_rad,
                .direction = invertFoldDirection(fold.direction),
            };
        }
        return null;
    }

    fn choosePreviewRootIndex(
        self: *const FoldingCartonModel,
        visited: []const bool,
    ) usize {
        var best_index: ?usize = null;
        var best_accepts_content = false;
        var best_fold_degree: usize = 0;
        var best_area: f64 = 0;

        for (self.panels, 0..) |panel, index| {
            if (visited[index]) continue;

            const accepts_content = panel.accepts_content;
            const fold_degree = self.foldDegree(panel.id);
            const area = panelFrameArea(panel);

            if (best_index == null or
                (accepts_content and !best_accepts_content) or
                (accepts_content == best_accepts_content and fold_degree > best_fold_degree) or
                (accepts_content == best_accepts_content and fold_degree == best_fold_degree and area > best_area))
            {
                best_index = index;
                best_accepts_content = accepts_content;
                best_fold_degree = fold_degree;
                best_area = area;
            }
        }

        return best_index orelse 0;
    }

    fn foldDegree(
        self: *const FoldingCartonModel,
        panel_id: types.PanelId,
    ) usize {
        var degree: usize = 0;
        for (self.folds) |fold| {
            if (fold.from_panel_id == panel_id or fold.to_panel_id == panel_id) {
                degree += 1;
            }
        }
        return degree;
    }

    fn panelIndexById(
        self: *const FoldingCartonModel,
        panel_id: types.PanelId,
    ) PreviewBuildError!usize {
        for (self.panels, 0..) |panel, index| {
            if (panel.id == panel_id) return index;
        }
        return PreviewBuildError.UnknownPanelId;
    }

    fn transformForFold(
        self: *const FoldingCartonModel,
        parent_edge: types.PanelEdgeRef,
        child_panel_id: types.PanelId,
        angle_rad: f64,
        direction: types.FoldDirection,
    ) !PreviewTransform3D {
        const axis = try self.edgeLine(parent_edge);
        const axis_vector = types.Vec3{
            .x = axis.to.x - axis.from.x,
            .y = axis.to.y - axis.from.y,
            .z = 0,
        };
        const axis_length = vec3Length(axis_vector);
        if (axis_length <= epsilon) return PreviewBuildError.ZeroLengthFoldAxis;
        const signed_angle_rad = try self.resolveFoldRotationSign(
            parent_edge.panel_id,
            child_panel_id,
            axis,
            axis_vector,
            direction,
            angle_rad,
        );

        return .{
            .rotation_origin = .{ .x = axis.from.x, .y = axis.from.y, .z = 0 },
            .rotation_axis = normalizeVec3(axis_vector, axis_length),
            .rotation_rad = signed_angle_rad,
        };
    }

    fn edgeLine(
        self: *const FoldingCartonModel,
        edge_ref: types.PanelEdgeRef,
    ) PreviewBuildError!types.LineSeg {
        const panel_index = try self.panelIndexById(edge_ref.panel_id);
        const panel = self.panels[panel_index];
        if (edge_ref.segment_index >= panel.boundary.segments.len) {
            return PreviewBuildError.InvalidPanelEdge;
        }

        return switch (panel.boundary.segments[edge_ref.segment_index]) {
            .Line => |line| line,
            else => PreviewBuildError.NonLinearFoldAxis,
        };
    }

    fn prepareContents(
        self: *const FoldingCartonModel,
        allocator: std.mem.Allocator,
        contents: []types.PanelContentPlacement,
    ) ContentValidationError!void {
        for (contents) |*content| {
            const panel = try self.panelById(content.panel_id);
            if (!panel.accepts_content) return ContentValidationError.PanelRejectsContent;
            try validatePlacementWithinPanel(allocator, panel, content.transform);
            if (content.clip_path == null) {
                content.clip_path = panel.content_region;
            }
            if (content.surface_frame == null) {
                content.surface_frame = panel.surface_frame;
            }
        }
    }

    fn panelById(
        self: *const FoldingCartonModel,
        panel_id: types.PanelId,
    ) ContentValidationError!types.Panel {
        for (self.panels) |panel| {
            if (panel.id == panel_id) return panel;
        }
        return ContentValidationError.UnknownPanelId;
    }

    fn resolveFoldRotationSign(
        self: *const FoldingCartonModel,
        parent_panel_id: types.PanelId,
        child_panel_id: types.PanelId,
        axis: types.LineSeg,
        axis_vector: types.Vec3,
        direction: types.FoldDirection,
        angle_rad: f64,
    ) PreviewBuildError!f64 {
        const parent = self.panels[try self.panelIndexById(parent_panel_id)];
        const child = self.panels[try self.panelIndexById(child_panel_id)];
        const child_center = panelCenter(child);
        const offset = types.Vec3{
            .x = child_center.x - axis.from.x,
            .y = child_center.y - axis.from.y,
            .z = 0,
        };
        const side = dotVec3(crossVec3(axis_vector, offset), parent.outside_normal);
        if (@abs(side) <= epsilon) return PreviewBuildError.MisalignedFoldAxis;

        const side_sign: f64 = if (side > 0) 1.0 else -1.0;
        const direction_sign: f64 = switch (direction) {
            .toward_outside => 1.0,
            .toward_inside => -1.0,
        };
        return angle_rad * side_sign * direction_sign;
    }
};

pub const FlexiblePouchModel = struct {
    kind: PackageKind = .flexible_pouch,
    outlines: []const types.Path2D,
    seams: []const types.Path2D,
    volume_profile: ?types.VolumeProfile,
    inflatedness: ?f64,
    contents: []const types.PanelContentPlacement = &.{},

    pub fn deinit(_: *FlexiblePouchModel, _: std.mem.Allocator) void {}

    pub fn buildDrawing2D(
        self: *const FlexiblePouchModel,
        allocator: std.mem.Allocator,
    ) !Drawing2DResult {
        const total_len = self.outlines.len + self.seams.len;
        const linework = try allocator.alloc(types.StyledPath2D, total_len);
        errdefer allocator.free(linework);

        for (self.outlines, 0..) |outline, index| {
            linework[index] = .{
                .path = outline,
                .role = .cut,
                .stroke_style = .solid,
            };
        }
        for (self.seams, 0..) |seam, index| {
            linework[self.outlines.len + index] = .{
                .path = seam,
                .role = .fold,
                .stroke_style = .dashed,
            };
        }

        return .{
            .panels = &.{},
            .linework = linework,
            .contents = self.contents,
        };
    }

    pub fn buildPreview3D(
        self: *const FlexiblePouchModel,
        allocator: std.mem.Allocator,
    ) !Preview3DResult {
        const node_count: usize = if (self.outlines.len == 0) 0 else 1;
        const nodes = try allocator.alloc(Preview3DNode, node_count);
        errdefer allocator.free(nodes);

        if (node_count == 1) {
            nodes[0] = .{
                .kind = .shell,
                .boundary = self.outlines[0],
            };
        }

        return .{
            .nodes = nodes,
            .contents = self.contents,
        };
    }

    pub fn setContents(
        self: *FlexiblePouchModel,
        _: std.mem.Allocator,
        contents: []types.PanelContentPlacement,
    ) ContentValidationError!void {
        for (contents) |content| {
            if (content.transform.size.x <= 0 or content.transform.size.y <= 0) {
                return ContentValidationError.InvalidContentSize;
            }
        }
        self.contents = contents;
    }
};

const epsilon = 1e-9;

fn validatePlacementWithinPanel(
    allocator: std.mem.Allocator,
    panel: types.Panel,
    transform: types.ContentTransform2D,
) ContentValidationError!void {
    if (transform.size.x <= 0 or transform.size.y <= 0) {
        return ContentValidationError.InvalidContentSize;
    }

    const quad = contentQuad(panel, transform);
    const samples = [_]types.Vec2{
        quad[0],
        quad[1],
        quad[2],
        quad[3],
        midpoint(quad[0], quad[1]),
        midpoint(quad[1], quad[2]),
        midpoint(quad[2], quad[3]),
        midpoint(quad[3], quad[0]),
        midpoint(midpoint(quad[0], quad[2]), midpoint(quad[1], quad[3])),
    };

    for (samples) |sample| {
        if (!try pathContainsPoint(allocator, panel.content_region, sample)) {
            return ContentValidationError.ContentOutOfBounds;
        }
    }

    for (0..quad.len) |index| {
        const next = (index + 1) % quad.len;
        if (try segmentIntersectsPathEdges(allocator, quad[index], quad[next], panel.content_region)) {
            return ContentValidationError.ContentOutOfBounds;
        }
    }
}

fn contentQuad(
    panel: types.Panel,
    transform: types.ContentTransform2D,
) [4]types.Vec2 {
    const frame = frameBasis(panel.surface_frame);

    const position = switch (transform.space) {
        .panel_uv_percent => types.Vec2{
            .x = transform.position.x / 100.0,
            .y = transform.position.y / 100.0,
        },
        .panel_local => types.Vec2{
            .x = transform.position.x / frame.u_length,
            .y = transform.position.y / frame.v_length,
        },
    };
    const size = switch (transform.space) {
        .panel_uv_percent => types.Vec2{
            .x = transform.size.x / 100.0,
            .y = transform.size.y / 100.0,
        },
        .panel_local => types.Vec2{
            .x = transform.size.x / frame.u_length,
            .y = transform.size.y / frame.v_length,
        },
    };

    const center = types.Vec2{
        .x = position.x + size.x / 2.0,
        .y = position.y + size.y / 2.0,
    };
    var local = [_]types.Vec2{
        .{ .x = position.x, .y = position.y },
        .{ .x = position.x + size.x, .y = position.y },
        .{ .x = position.x + size.x, .y = position.y + size.y },
        .{ .x = position.x, .y = position.y + size.y },
    };

    for (&local) |*point| {
        point.* = rotateAround(point.*, center, transform.rotation_rad);
    }

    return .{
        projectSurfacePoint(panel.surface_frame, local[0]),
        projectSurfacePoint(panel.surface_frame, local[1]),
        projectSurfacePoint(panel.surface_frame, local[2]),
        projectSurfacePoint(panel.surface_frame, local[3]),
    };
}

fn frameBasis(frame: types.SurfaceFrame2D) struct { u_length: f64, v_length: f64 } {
    const u_length = vec2Length(frame.u_axis);
    const v_length = vec2Length(frame.v_axis);
    return .{
        .u_length = if (u_length <= epsilon) 1.0 else u_length,
        .v_length = if (v_length <= epsilon) 1.0 else v_length,
    };
}

fn projectSurfacePoint(frame: types.SurfaceFrame2D, point: types.Vec2) types.Vec2 {
    return .{
        .x = frame.origin.x + frame.u_axis.x * point.x + frame.v_axis.x * point.y,
        .y = frame.origin.y + frame.u_axis.y * point.x + frame.v_axis.y * point.y,
    };
}

fn rotateAround(point: types.Vec2, center: types.Vec2, angle: f64) types.Vec2 {
    const dx = point.x - center.x;
    const dy = point.y - center.y;
    const sin_angle = std.math.sin(angle);
    const cos_angle = std.math.cos(angle);
    return .{
        .x = center.x + dx * cos_angle - dy * sin_angle,
        .y = center.y + dx * sin_angle + dy * cos_angle,
    };
}

fn pathContainsPoint(
    allocator: std.mem.Allocator,
    path: types.Path2D,
    point: types.Vec2,
) !bool {
    const vertices = try flattenPath(allocator, path);
    defer allocator.free(vertices);

    if (vertices.len < 3) return false;

    var inside = false;
    var j = vertices.len - 1;
    for (vertices, 0..) |vertex, i| {
        const other = vertices[j];
        if (pointOnSegment(point, other, vertex)) return true;

        const crosses = ((vertex.y > point.y) != (other.y > point.y)) and
            (point.x < (other.x - vertex.x) * (point.y - vertex.y) / ((other.y - vertex.y) + epsilon) + vertex.x);
        if (crosses) inside = !inside;
        j = i;
    }

    return inside;
}

fn segmentIntersectsPathEdges(
    allocator: std.mem.Allocator,
    from: types.Vec2,
    to: types.Vec2,
    path: types.Path2D,
) !bool {
    const vertices = try flattenPath(allocator, path);
    defer allocator.free(vertices);

    if (vertices.len < 2) return false;

    for (vertices, 0..) |start, index| {
        const finish = vertices[(index + 1) % vertices.len];
        if (sameUndirectedSegment(.{ .from = from, .to = to }, .{ .from = start, .to = finish })) continue;
        if (segmentsProperlyIntersect(from, to, start, finish)) return true;
    }

    return false;
}

fn flattenPath(
    allocator: std.mem.Allocator,
    path: types.Path2D,
) ![]types.Vec2 {
    var points: std.ArrayListUnmanaged(types.Vec2) = .{
        .items = &.{},
        .capacity = 0,
    };
    errdefer points.deinit(allocator);

    for (path.segments, 0..) |segment, index| {
        switch (segment) {
            .Line => |line| {
                if (index == 0) try points.append(allocator, line.from);
                try points.append(allocator, line.to);
            },
            .Arc => |arc| {
                const steps: usize = 16;
                const full_turn = std.math.pi * 2.0;
                const sweep = if (arc.clockwise)
                    -@mod(arc.startAngle - arc.endAngle + full_turn, full_turn)
                else
                    @mod(arc.endAngle - arc.startAngle + full_turn, full_turn);
                for (0..steps + 1) |step| {
                    if (index != 0 and step == 0) continue;
                    const t = @as(f64, @floatFromInt(step)) / @as(f64, @floatFromInt(steps));
                    const angle = arc.startAngle + sweep * t;
                    try points.append(allocator, .{
                        .x = arc.center.x + arc.radius * std.math.cos(angle),
                        .y = arc.center.y + arc.radius * std.math.sin(angle),
                    });
                }
            },
            .Bezier => |bezier| {
                const steps: usize = 16;
                for (0..steps + 1) |step| {
                    if (index != 0 and step == 0) continue;
                    const t = @as(f64, @floatFromInt(step)) / @as(f64, @floatFromInt(steps));
                    try points.append(allocator, bezierPoint(bezier, t));
                }
            },
        }
    }

    if (points.items.len > 1 and approxEqVec2(points.items[0], points.items[points.items.len - 1])) {
        _ = points.pop();
    }

    return points.toOwnedSlice(allocator);
}

fn bezierPoint(bezier: types.BezierSeg, t: f64) types.Vec2 {
    const one_minus_t = 1.0 - t;
    const a = one_minus_t * one_minus_t * one_minus_t;
    const b = 3.0 * one_minus_t * one_minus_t * t;
    const c = 3.0 * one_minus_t * t * t;
    const d = t * t * t;
    return .{
        .x = a * bezier.p0.x + b * bezier.p1.x + c * bezier.p2.x + d * bezier.p3.x,
        .y = a * bezier.p0.y + b * bezier.p1.y + c * bezier.p2.y + d * bezier.p3.y,
    };
}

fn sameUndirectedLine(a: types.LineSeg, b: types.LineSeg) bool {
    return sameUndirectedSegment(a, b);
}

fn sameUndirectedSegment(a: types.LineSeg, b: types.LineSeg) bool {
    return (approxEqVec2(a.from, b.from) and approxEqVec2(a.to, b.to)) or
        (approxEqVec2(a.from, b.to) and approxEqVec2(a.to, b.from));
}

fn midpoint(a: types.Vec2, b: types.Vec2) types.Vec2 {
    return .{
        .x = (a.x + b.x) / 2.0,
        .y = (a.y + b.y) / 2.0,
    };
}

fn pointOnSegment(point: types.Vec2, from: types.Vec2, to: types.Vec2) bool {
    const area = cross(vec2Sub(to, from), vec2Sub(point, from));
    if (@abs(area) > epsilon) return false;

    const dot_product = dot(vec2Sub(point, from), vec2Sub(point, to));
    return dot_product <= epsilon;
}

fn segmentsProperlyIntersect(a1: types.Vec2, a2: types.Vec2, b1: types.Vec2, b2: types.Vec2) bool {
    const o1 = orientation(a1, a2, b1);
    const o2 = orientation(a1, a2, b2);
    const o3 = orientation(b1, b2, a1);
    const o4 = orientation(b1, b2, a2);

    return o1 != 0 and o2 != 0 and o3 != 0 and o4 != 0 and o1 != o2 and o3 != o4;
}

fn orientation(a: types.Vec2, b: types.Vec2, c: types.Vec2) i8 {
    const value = cross(vec2Sub(b, a), vec2Sub(c, b));
    if (@abs(value) <= epsilon) return 0;
    return if (value > 0) 1 else -1;
}

fn findRoot(parents: []usize, index: usize) usize {
    var current = index;
    while (parents[current] != current) {
        parents[current] = parents[parents[current]];
        current = parents[current];
    }
    return current;
}

fn cross(a: types.Vec2, b: types.Vec2) f64 {
    return a.x * b.y - a.y * b.x;
}

fn dot(a: types.Vec2, b: types.Vec2) f64 {
    return a.x * b.x + a.y * b.y;
}

fn vec2Sub(a: types.Vec2, b: types.Vec2) types.Vec2 {
    return .{
        .x = a.x - b.x,
        .y = a.y - b.y,
    };
}

fn vec2Length(vec: types.Vec2) f64 {
    return std.math.sqrt(vec.x * vec.x + vec.y * vec.y);
}

fn approxEqVec2(a: types.Vec2, b: types.Vec2) bool {
    return std.math.approxEqAbs(f64, a.x, b.x, epsilon) and
        std.math.approxEqAbs(f64, a.y, b.y, epsilon);
}

fn vec3Length(vec: types.Vec3) f64 {
    return std.math.sqrt(vec.x * vec.x + vec.y * vec.y + vec.z * vec.z);
}

fn normalizeVec3(vec: types.Vec3, length: f64) types.Vec3 {
    return .{
        .x = vec.x / length,
        .y = vec.y / length,
        .z = vec.z / length,
    };
}

fn invertFoldDirection(direction: types.FoldDirection) types.FoldDirection {
    return switch (direction) {
        .toward_outside => .toward_inside,
        .toward_inside => .toward_outside,
    };
}

fn panelCenter(panel: types.Panel) types.Vec2 {
    return .{
        .x = panel.surface_frame.origin.x + (panel.surface_frame.u_axis.x + panel.surface_frame.v_axis.x) / 2.0,
        .y = panel.surface_frame.origin.y + (panel.surface_frame.u_axis.y + panel.surface_frame.v_axis.y) / 2.0,
    };
}

fn panelFrameArea(panel: types.Panel) f64 {
    return @abs(cross(panel.surface_frame.u_axis, panel.surface_frame.v_axis));
}

fn crossVec3(a: types.Vec3, b: types.Vec3) types.Vec3 {
    return .{
        .x = a.y * b.z - a.z * b.y,
        .y = a.z * b.x - a.x * b.z,
        .z = a.x * b.y - a.y * b.x,
    };
}

fn dotVec3(a: types.Vec3, b: types.Vec3) f64 {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

test "template model builds drawing and preview outputs" {
    const template = @import("mod.zig").folding_carton.simple_two_panel;

    var instance = try template.create(std.testing.allocator, &.{}, &.{});
    defer instance.deinit();

    var drawing = try instance.folding_carton.buildDrawing2D(std.testing.allocator);
    defer drawing.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), drawing.panels.len);
    try std.testing.expectEqual(@as(usize, 2), drawing.linework.len);

    var preview = try instance.folding_carton.buildPreview3D(std.testing.allocator);
    defer preview.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), preview.nodes.len);
    try std.testing.expectEqual(@as(?u32, null), preview.nodes[0].parent_index);
    try std.testing.expectEqual(@as(?u32, 0), preview.nodes[1].parent_index);
    try std.testing.expectApproxEqAbs(std.math.pi / 2.0, preview.nodes[1].transform.rotation_rad, 1e-9);
    try std.testing.expectApproxEqAbs(40.0, preview.nodes[1].transform.rotation_origin.x, 1e-9);
    try std.testing.expectApproxEqAbs(0.0, preview.nodes[1].transform.rotation_axis.x, 1e-9);
    try std.testing.expectApproxEqAbs(1.0, preview.nodes[1].transform.rotation_axis.y, 1e-9);
}

test "folding carton content validation rejects out of bounds percent placement" {
    const template = @import("mod.zig").folding_carton.simple_two_panel;

    var instance = try template.create(std.testing.allocator, &.{}, &.{});
    defer instance.deinit();

    var contents = [_]types.PanelContentPlacement{
        .{
            .id = 1,
            .panel_id = 0,
            .content = .{
                .text = .{
                    .text = "TooWide",
                    .font_size = 12,
                },
            },
            .transform = .{
                .position = .{ .x = 80, .y = 10 },
                .size = .{ .x = 30, .y = 20 },
                .space = .panel_uv_percent,
            },
        },
    };

    try std.testing.expectError(
        ContentValidationError.ContentOutOfBounds,
        instance.folding_carton.setContents(std.testing.allocator, &contents),
    );
}

test "folding carton content validation rejects rotated content outside panel" {
    const template = @import("mod.zig").folding_carton.simple_two_panel;

    var instance = try template.create(std.testing.allocator, &.{}, &.{});
    defer instance.deinit();

    var contents = [_]types.PanelContentPlacement{
        .{
            .id = 3,
            .panel_id = 0,
            .content = .{
                .text = .{
                    .text = "Rotate",
                    .font_size = 12,
                },
            },
            .transform = .{
                .position = .{ .x = 75, .y = 0 },
                .size = .{ .x = 25, .y = 25 },
                .rotation_rad = std.math.pi / 4.0,
                .space = .panel_uv_percent,
            },
        },
    };

    try std.testing.expectError(
        ContentValidationError.ContentOutOfBounds,
        instance.folding_carton.setContents(std.testing.allocator, &contents),
    );
}

test "folding carton content validation assigns panel clip path" {
    const template = @import("mod.zig").folding_carton.simple_two_panel;

    var instance = try template.create(std.testing.allocator, &.{}, &.{});
    defer instance.deinit();

    var contents = [_]types.PanelContentPlacement{
        .{
            .id = 2,
            .panel_id = 0,
            .content = .{
                .text = .{
                    .text = "Valid",
                    .font_size = 12,
                },
            },
            .transform = .{
                .position = .{ .x = 10, .y = 10 },
                .size = .{ .x = 30, .y = 20 },
                .space = .panel_uv_percent,
            },
        },
    };

    try instance.folding_carton.setContents(std.testing.allocator, &contents);
    try std.testing.expect(contents[0].clip_path != null);
    try std.testing.expectEqualDeep(instance.panels[0].content_region, contents[0].clip_path.?);
}

test "folding carton honors explicit content region" {
    const boundary_segments = [_]types.PathSeg{
        .{ .Line = .{ .from = .{ .x = 0, .y = 0 }, .to = .{ .x = 10, .y = 0 } } },
        .{ .Line = .{ .from = .{ .x = 10, .y = 0 }, .to = .{ .x = 10, .y = 10 } } },
        .{ .Line = .{ .from = .{ .x = 10, .y = 10 }, .to = .{ .x = 0, .y = 10 } } },
        .{ .Line = .{ .from = .{ .x = 0, .y = 10 }, .to = .{ .x = 0, .y = 0 } } },
    };
    const content_segments = [_]types.PathSeg{
        .{ .Line = .{ .from = .{ .x = 1, .y = 1 }, .to = .{ .x = 9, .y = 1 } } },
        .{ .Line = .{ .from = .{ .x = 9, .y = 1 }, .to = .{ .x = 9, .y = 9 } } },
        .{ .Line = .{ .from = .{ .x = 9, .y = 9 }, .to = .{ .x = 1, .y = 9 } } },
        .{ .Line = .{ .from = .{ .x = 1, .y = 9 }, .to = .{ .x = 1, .y = 1 } } },
    };

    var model = FoldingCartonModel.init(
        &.{
            try types.Panel.withGeometryBy(
                types.Path2D.baseBy(&boundary_segments),
                0,
                .{
                    .origin = .{ .x = 0, .y = 0 },
                    .u_axis = .{ .x = 10, .y = 0 },
                    .v_axis = .{ .x = 0, .y = 10 },
                },
                types.Path2D.baseBy(&content_segments),
                .{ .x = 0, .y = 0, .z = 1 },
            ),
        },
        &.{},
        &.{},
    );

    var contents = [_]types.PanelContentPlacement{
        .{
            .id = 7,
            .panel_id = 0,
            .content = .{
                .text = .{
                    .text = "Edge",
                    .font_size = 12,
                },
            },
            .transform = .{
                .position = .{ .x = 0, .y = 0 },
                .size = .{ .x = 20, .y = 20 },
                .space = .panel_uv_percent,
            },
        },
    };

    try std.testing.expectError(
        ContentValidationError.ContentOutOfBounds,
        model.setContents(std.testing.allocator, &contents),
    );
}

test "fold validation rejects misaligned hinge edges" {
    const left_segments = [_]types.PathSeg{
        .{ .Line = .{ .from = .{ .x = 0, .y = 0 }, .to = .{ .x = 10, .y = 0 } } },
        .{ .Line = .{ .from = .{ .x = 10, .y = 0 }, .to = .{ .x = 10, .y = 10 } } },
        .{ .Line = .{ .from = .{ .x = 10, .y = 10 }, .to = .{ .x = 0, .y = 10 } } },
        .{ .Line = .{ .from = .{ .x = 0, .y = 10 }, .to = .{ .x = 0, .y = 0 } } },
    };
    const right_segments = [_]types.PathSeg{
        .{ .Line = .{ .from = .{ .x = 11, .y = 0 }, .to = .{ .x = 21, .y = 0 } } },
        .{ .Line = .{ .from = .{ .x = 21, .y = 0 }, .to = .{ .x = 21, .y = 10 } } },
        .{ .Line = .{ .from = .{ .x = 21, .y = 10 }, .to = .{ .x = 11, .y = 10 } } },
        .{ .Line = .{ .from = .{ .x = 11, .y = 10 }, .to = .{ .x = 11, .y = 0 } } },
    };

    var model = FoldingCartonModel.init(
        &.{
            try types.Panel.withSurfaceBy(
                types.Path2D.baseBy(&left_segments),
                0,
                .{
                    .origin = .{ .x = 0, .y = 0 },
                    .u_axis = .{ .x = 10, .y = 0 },
                    .v_axis = .{ .x = 0, .y = 10 },
                },
                .{ .x = 0, .y = 0, .z = 1 },
            ),
            try types.Panel.withSurfaceBy(
                types.Path2D.baseBy(&right_segments),
                1,
                .{
                    .origin = .{ .x = 11, .y = 0 },
                    .u_axis = .{ .x = 10, .y = 0 },
                    .v_axis = .{ .x = 0, .y = 10 },
                },
                .{ .x = 0, .y = 0, .z = 1 },
            ),
        },
        &.{
            .{
                .from_panel_id = 0,
                .to_panel_id = 1,
                .axis = .{
                    .from_edge = .{ .panel_id = 0, .segment_index = 1 },
                    .to_edge = .{ .panel_id = 1, .segment_index = 3 },
                },
                .angle_rad = std.math.pi / 2.0,
            },
        },
        &.{},
    );

    try std.testing.expectError(
        PreviewBuildError.MisalignedFoldAxis,
        model.buildPreview3D(std.testing.allocator),
    );
}

test "fold direction derives opposite signed rotations for inside versus outside folds" {
    const base_segments = [_]types.PathSeg{
        .{ .Line = .{ .from = .{ .x = 0, .y = 0 }, .to = .{ .x = 10, .y = 0 } } },
        .{ .Line = .{ .from = .{ .x = 10, .y = 0 }, .to = .{ .x = 10, .y = 10 } } },
        .{ .Line = .{ .from = .{ .x = 10, .y = 10 }, .to = .{ .x = 0, .y = 10 } } },
        .{ .Line = .{ .from = .{ .x = 0, .y = 10 }, .to = .{ .x = 0, .y = 0 } } },
    };
    const child_segments = [_]types.PathSeg{
        .{ .Line = .{ .from = .{ .x = 0, .y = 10 }, .to = .{ .x = 10, .y = 10 } } },
        .{ .Line = .{ .from = .{ .x = 10, .y = 10 }, .to = .{ .x = 10, .y = 20 } } },
        .{ .Line = .{ .from = .{ .x = 10, .y = 20 }, .to = .{ .x = 0, .y = 20 } } },
        .{ .Line = .{ .from = .{ .x = 0, .y = 20 }, .to = .{ .x = 0, .y = 10 } } },
    };

    const panels = [_]types.Panel{
        try types.Panel.withSurfaceBy(
            types.Path2D.baseBy(&base_segments),
            0,
            .{ .origin = .{ .x = 0, .y = 0 }, .u_axis = .{ .x = 10, .y = 0 }, .v_axis = .{ .x = 0, .y = 10 } },
            .{ .x = 0, .y = 0, .z = 1 },
        ),
        try types.Panel.withSurfaceBy(
            types.Path2D.baseBy(&child_segments),
            1,
            .{ .origin = .{ .x = 0, .y = 10 }, .u_axis = .{ .x = 10, .y = 0 }, .v_axis = .{ .x = 0, .y = 10 } },
            .{ .x = 0, .y = 0, .z = 1 },
        ),
    };

    var outside_model = FoldingCartonModel.init(
        &panels,
        &.{
            .{
                .from_panel_id = 0,
                .to_panel_id = 1,
                .axis = .{
                    .from_edge = .{ .panel_id = 0, .segment_index = 2 },
                    .to_edge = .{ .panel_id = 1, .segment_index = 0 },
                },
                .angle_rad = std.math.pi / 3.0,
                .direction = .toward_outside,
            },
        },
        &.{},
    );
    var outside_preview = try outside_model.buildPreview3D(std.testing.allocator);
    defer outside_preview.deinit(std.testing.allocator);

    var inside_model = FoldingCartonModel.init(
        &panels,
        &.{
            .{
                .from_panel_id = 0,
                .to_panel_id = 1,
                .axis = .{
                    .from_edge = .{ .panel_id = 0, .segment_index = 2 },
                    .to_edge = .{ .panel_id = 1, .segment_index = 0 },
                },
                .angle_rad = std.math.pi / 3.0,
                .direction = .toward_inside,
            },
        },
        &.{},
    );
    var inside_preview = try inside_model.buildPreview3D(std.testing.allocator);
    defer inside_preview.deinit(std.testing.allocator);

    try std.testing.expectApproxEqAbs(std.math.pi / 3.0, @abs(outside_preview.nodes[1].transform.rotation_rad), 1e-9);
    try std.testing.expectApproxEqAbs(std.math.pi / 3.0, @abs(inside_preview.nodes[1].transform.rotation_rad), 1e-9);
    try std.testing.expectApproxEqAbs(
        outside_preview.nodes[1].transform.rotation_rad,
        -inside_preview.nodes[1].transform.rotation_rad,
        1e-9,
    );
}

test "fold sign stays stable when parent and child traversal is reversed" {
    const left_segments = [_]types.PathSeg{
        .{ .Line = .{ .from = .{ .x = 0, .y = 0 }, .to = .{ .x = 10, .y = 0 } } },
        .{ .Line = .{ .from = .{ .x = 10, .y = 0 }, .to = .{ .x = 10, .y = 10 } } },
        .{ .Line = .{ .from = .{ .x = 10, .y = 10 }, .to = .{ .x = 0, .y = 10 } } },
        .{ .Line = .{ .from = .{ .x = 0, .y = 10 }, .to = .{ .x = 0, .y = 0 } } },
    };
    const right_segments = [_]types.PathSeg{
        .{ .Line = .{ .from = .{ .x = 10, .y = 0 }, .to = .{ .x = 20, .y = 0 } } },
        .{ .Line = .{ .from = .{ .x = 20, .y = 0 }, .to = .{ .x = 20, .y = 10 } } },
        .{ .Line = .{ .from = .{ .x = 20, .y = 10 }, .to = .{ .x = 10, .y = 10 } } },
        .{ .Line = .{ .from = .{ .x = 10, .y = 10 }, .to = .{ .x = 10, .y = 0 } } },
    };
    const panels = [_]types.Panel{
        try types.Panel.withSurfaceBy(
            types.Path2D.baseBy(&left_segments),
            0,
            .{ .origin = .{ .x = 0, .y = 0 }, .u_axis = .{ .x = 10, .y = 0 }, .v_axis = .{ .x = 0, .y = 10 } },
            .{ .x = 0, .y = 0, .z = 1 },
        ),
        try types.Panel.withSurfaceBy(
            types.Path2D.baseBy(&right_segments),
            1,
            .{ .origin = .{ .x = 10, .y = 0 }, .u_axis = .{ .x = 10, .y = 0 }, .v_axis = .{ .x = 0, .y = 10 } },
            .{ .x = 0, .y = 0, .z = 1 },
        ),
    };

    var left_root_model = FoldingCartonModel.init(
        &panels,
        &.{
            .{
                .from_panel_id = 0,
                .to_panel_id = 1,
                .axis = .{
                    .from_edge = .{ .panel_id = 0, .segment_index = 1 },
                    .to_edge = .{ .panel_id = 1, .segment_index = 3 },
                },
                .angle_rad = std.math.pi / 2.0,
                .direction = .toward_inside,
            },
        },
        &.{},
    );
    var left_root_preview = try left_root_model.buildPreview3D(std.testing.allocator);
    defer left_root_preview.deinit(std.testing.allocator);

    var reversed_model = FoldingCartonModel.init(
        &.{ panels[1], panels[0] },
        &.{
            .{
                .from_panel_id = 0,
                .to_panel_id = 1,
                .axis = .{
                    .from_edge = .{ .panel_id = 0, .segment_index = 1 },
                    .to_edge = .{ .panel_id = 1, .segment_index = 3 },
                },
                .angle_rad = std.math.pi / 2.0,
                .direction = .toward_inside,
            },
        },
        &.{},
    );
    var reversed_preview = try reversed_model.buildPreview3D(std.testing.allocator);
    defer reversed_preview.deinit(std.testing.allocator);

    const right_child_rotation = if (left_root_preview.nodes[1].panel_id.? == 1) left_root_preview.nodes[1].transform.rotation_rad else left_root_preview.nodes[0].transform.rotation_rad;
    const left_child_rotation = if (reversed_preview.nodes[1].panel_id.? == 0) reversed_preview.nodes[1].transform.rotation_rad else reversed_preview.nodes[0].transform.rotation_rad;

    try std.testing.expectApproxEqAbs(std.math.pi / 2.0, @abs(right_child_rotation), 1e-9);
    try std.testing.expectApproxEqAbs(std.math.pi / 2.0, @abs(left_child_rotation), 1e-9);
    try std.testing.expectApproxEqAbs(right_child_rotation, -left_child_rotation, 1e-9);
}

test "template registry exports descriptors and creates instances" {
    const templates = @import("mod.zig");

    const descriptors = templates.exportTemplates();
    try std.testing.expect(descriptors.len >= 1);
    try std.testing.expectEqualStrings(
        "folding_carton.simple_two_panel",
        descriptors[0].key,
    );

    var instance = try templates.createTemplate(
        std.testing.allocator,
        descriptors[0].key,
        &.{
            .{ .key = "panel_width", .value = 55 },
            .{ .key = "panel_height", .value = 20 },
        },
        &.{},
    );
    defer instance.deinit();

    var preview = try instance.buildPreview3D(std.testing.allocator);
    defer preview.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), preview.nodes.len);
    try std.testing.expectApproxEqAbs(55.0, preview.nodes[1].transform.rotation_origin.x, 1e-9);
}
