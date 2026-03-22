const std = @import("std");
const package = @import("package.zig");
const types = @import("types.zig");

pub const schema = @import("templates/schema.zig");

pub const folding_carton = struct {
    pub const simple_two_panel = @import("templates/simple_two_panel.zig");
    pub const mailer_box = @import("templates/mailer_box.zig");
    pub const rounded_tuck_carton = @import("templates/rounded_tuck_carton.zig");
};

pub const TemplateInstance = struct {
    ptr: *anyopaque,
    vtable: *const TemplateVTable,

    pub fn setContents(
        self: TemplateInstance,
        contents: []@import("types.zig").PanelContentPlacement,
    ) !void {
        try self.vtable.set_contents(self.ptr, contents);
    }

    pub fn deinit(self: TemplateInstance) void {
        self.vtable.deinit(self.ptr);
    }

    pub fn buildDrawing2D(
        self: TemplateInstance,
        allocator: std.mem.Allocator,
    ) !package.Drawing2DResult {
        return self.vtable.build_drawing_2d(self.ptr, allocator);
    }

    pub fn buildPreview3D(
        self: TemplateInstance,
        allocator: std.mem.Allocator,
    ) !package.Preview3DResult {
        return self.vtable.build_preview_3d(self.ptr, allocator);
    }
};

const TemplateVTable = struct {
    deinit: *const fn (ptr: *anyopaque) void,
    set_contents: *const fn (ptr: *anyopaque, contents: []types.PanelContentPlacement) anyerror!void,
    build_drawing_2d: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!package.Drawing2DResult,
    build_preview_3d: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!package.Preview3DResult,
};

fn wrapTemplateInstance(
    comptime Template: type,
    allocator: std.mem.Allocator,
    numeric_params: []const schema.NumericParamValue,
    select_params: []const schema.SelectParamValue,
) !TemplateInstance {
    const instance = try Template.create(allocator, numeric_params, select_params);
    return .{
        .ptr = instance,
        .vtable = templateVTablePtr(Template.Instance),
    };
}

fn templateVTablePtr(comptime Instance: type) *const TemplateVTable {
    return &struct {
        const value = TemplateVTable{
            .deinit = struct {
                fn call(ptr: *anyopaque) void {
                    const instance: *Instance = @ptrCast(@alignCast(ptr));
                    instance.deinit();
                }
            }.call,
            .set_contents = struct {
                fn call(ptr: *anyopaque, contents: []types.PanelContentPlacement) anyerror!void {
                    const instance: *Instance = @ptrCast(@alignCast(ptr));
                    try instance.setContents(contents);
                }
            }.call,
            .build_drawing_2d = struct {
                fn call(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!package.Drawing2DResult {
                    const instance: *Instance = @ptrCast(@alignCast(ptr));
                    return instance.buildDrawing2D(allocator);
                }
            }.call,
            .build_preview_3d = struct {
                fn call(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!package.Preview3DResult {
                    const instance: *Instance = @ptrCast(@alignCast(ptr));
                    return instance.buildPreview3D(allocator);
                }
            }.call,
        };
    }.value;
}

const declared_templates = .{
    folding_carton.simple_two_panel,
    folding_carton.mailer_box,
    folding_carton.rounded_tuck_carton,
};

const exported_template_descriptors = blk: {
    var descriptors: [declared_templates.len]schema.TemplateDescriptor = undefined;
    for (declared_templates, 0..) |Template, index| {
        descriptors[index] = Template.descriptor;
    }
    break :blk descriptors;
};

pub fn exportTemplates() []const schema.TemplateDescriptor {
    return &exported_template_descriptors;
}

pub fn createTemplate(
    allocator: std.mem.Allocator,
    key: []const u8,
    numeric_params: []const schema.NumericParamValue,
    select_params: []const schema.SelectParamValue,
) !TemplateInstance {
    inline for (declared_templates) |Template| {
        if (std.mem.eql(u8, key, Template.descriptor.key)) {
            return wrapTemplateInstance(Template, allocator, numeric_params, select_params);
        }
    }
    return error.UnknownTemplate;
}

const overlap_epsilon = 1e-6;
const curve_sample_segments = 24;

fn buildDefaultNumericParams(
    allocator: std.mem.Allocator,
    descriptor: schema.TemplateDescriptor,
) ![]schema.NumericParamValue {
    const values = try allocator.alloc(schema.NumericParamValue, descriptor.numeric_params.len);
    for (descriptor.numeric_params, 0..) |param, index| {
        values[index] = .{
            .key = param.key,
            .value = param.default_value,
        };
    }
    return values;
}

fn buildDefaultSelectParams(
    allocator: std.mem.Allocator,
    descriptor: schema.TemplateDescriptor,
) ![]schema.SelectParamValue {
    const values = try allocator.alloc(schema.SelectParamValue, descriptor.select_params.len);
    for (descriptor.select_params, 0..) |param, index| {
        values[index] = .{
            .key = param.key,
            .value = param.default_value,
        };
    }
    return values;
}

fn sampleBoundary(
    allocator: std.mem.Allocator,
    path: types.Path2D,
) ![]types.Vec2 {
    var points = try std.ArrayList(types.Vec2).initCapacity(allocator, path.segments.len * 4);
    errdefer points.deinit(allocator);

    for (path.segments, 0..) |segment, segment_index| {
        switch (segment) {
            .Line => |line| {
                if (segment_index == 0) try points.append(allocator, line.from);
                try points.append(allocator, line.to);
            },
            .Arc => |arc| {
                const start_angle = arc.startAngle;
                const end_angle = arc.endAngle;
                const full_turn = std.math.pi * 2.0;
                const sweep = if (arc.clockwise)
                    -@mod(start_angle - end_angle + full_turn, full_turn)
                else
                    @mod(end_angle - start_angle + full_turn, full_turn);

                if (segment_index == 0) {
                    try points.append(allocator, pointOnCircle(arc.center, arc.radius, start_angle));
                }

                for (1..curve_sample_segments + 1) |step| {
                    const t = @as(f64, @floatFromInt(step)) / @as(f64, @floatFromInt(curve_sample_segments));
                    const angle = start_angle + sweep * t;
                    try points.append(allocator, pointOnCircle(arc.center, arc.radius, angle));
                }
            },
            .Bezier => |bezier| {
                if (segment_index == 0) try points.append(allocator, bezier.p0);
                for (1..curve_sample_segments + 1) |step| {
                    const t = @as(f64, @floatFromInt(step)) / @as(f64, @floatFromInt(curve_sample_segments));
                    try points.append(allocator, cubicBezierPoint(bezier, t));
                }
            },
        }
    }

    if (points.items.len > 1 and approxEqVec2(points.items[0], points.items[points.items.len - 1])) {
        _ = points.pop();
    }

    return points.toOwnedSlice(allocator);
}

fn panelsOverlap(
    allocator: std.mem.Allocator,
    left: package.Drawing2DResult.Panel2D,
    right: package.Drawing2DResult.Panel2D,
) !bool {
    const left_points = try sampleBoundary(allocator, left.boundary);
    defer allocator.free(left_points);
    const right_points = try sampleBoundary(allocator, right.boundary);
    defer allocator.free(right_points);

    if (left_points.len < 3 or right_points.len < 3) return false;

    for (left_points, 0..) |left_start, left_index| {
        const left_end = left_points[(left_index + 1) % left_points.len];
        for (right_points, 0..) |right_start, right_index| {
            _ = right_start;
            const right_end = right_points[(right_index + 1) % right_points.len];
            if (segmentsProperlyIntersect(left_start, left_end, right_points[right_index], right_end)) {
                return true;
            }
        }
    }

    for (left_points) |point| {
        if (!pointOnPolygonBoundary(point, right_points) and pointInPolygon(point, right_points)) {
            return true;
        }
    }
    for (right_points) |point| {
        if (!pointOnPolygonBoundary(point, left_points) and pointInPolygon(point, left_points)) {
            return true;
        }
    }

    return false;
}

fn pathSelfIntersects(
    allocator: std.mem.Allocator,
    path: types.Path2D,
) !bool {
    const points = try sampleBoundary(allocator, path);
    defer allocator.free(points);

    if (points.len < 2) return false;

    const edge_count: usize = if (path.closed) points.len else if (points.len > 1) points.len - 1 else 0;
    if (edge_count < 2) return false;

    for (0..edge_count) |left_index| {
        const left_start = points[left_index];
        const left_end = if (path.closed) points[(left_index + 1) % points.len] else points[left_index + 1];

        for (left_index + 1..edge_count) |right_index| {
            if (segmentsAreAdjacent(path.closed, edge_count, left_index, right_index)) continue;

            const right_start = points[right_index];
            const right_end = if (path.closed) points[(right_index + 1) % points.len] else points[right_index + 1];
            if (segmentsProperlyIntersect(left_start, left_end, right_start, right_end)) return true;
        }
    }

    return false;
}

fn segmentsAreAdjacent(
    closed: bool,
    edge_count: usize,
    left_index: usize,
    right_index: usize,
) bool {
    if (left_index == right_index) return true;
    if (left_index + 1 == right_index or right_index + 1 == left_index) return true;
    if (!closed) return false;
    return (left_index == 0 and right_index + 1 == edge_count) or
        (right_index == 0 and left_index + 1 == edge_count);
}

fn roleRequiresSimpleClosedPath(role: types.LineRole) bool {
    return switch (role) {
        .cut, .bleed, .safe => true,
        .fold, .score, .guide => false,
    };
}

fn segmentsProperlyIntersect(a0: types.Vec2, a1: types.Vec2, b0: types.Vec2, b1: types.Vec2) bool {
    const o1 = orientation(a0, a1, b0);
    const o2 = orientation(a0, a1, b1);
    const o3 = orientation(b0, b1, a0);
    const o4 = orientation(b0, b1, a1);

    if (@abs(o1) <= overlap_epsilon or
        @abs(o2) <= overlap_epsilon or
        @abs(o3) <= overlap_epsilon or
        @abs(o4) <= overlap_epsilon)
    {
        return false;
    }

    return ((o1 > 0 and o2 < 0) or (o1 < 0 and o2 > 0)) and
        ((o3 > 0 and o4 < 0) or (o3 < 0 and o4 > 0));
}

fn pointInPolygon(point: types.Vec2, polygon: []const types.Vec2) bool {
    var inside = false;
    for (polygon, 0..) |current, index| {
        const next = polygon[(index + 1) % polygon.len];
        const intersects = ((current.y > point.y) != (next.y > point.y)) and
            (point.x < (next.x - current.x) * (point.y - current.y) / (next.y - current.y) + current.x);
        if (intersects) inside = !inside;
    }
    return inside;
}

fn pointOnPolygonBoundary(point: types.Vec2, polygon: []const types.Vec2) bool {
    for (polygon, 0..) |current, index| {
        const next = polygon[(index + 1) % polygon.len];
        if (pointOnSegment(point, current, next)) return true;
    }
    return false;
}

fn pointOnSegment(point: types.Vec2, start: types.Vec2, end: types.Vec2) bool {
    if (@abs(orientation(start, end, point)) > overlap_epsilon) return false;

    const min_x = @min(start.x, end.x) - overlap_epsilon;
    const max_x = @max(start.x, end.x) + overlap_epsilon;
    const min_y = @min(start.y, end.y) - overlap_epsilon;
    const max_y = @max(start.y, end.y) + overlap_epsilon;
    return point.x >= min_x and point.x <= max_x and point.y >= min_y and point.y <= max_y;
}

fn orientation(a: types.Vec2, b: types.Vec2, c: types.Vec2) f64 {
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
}

fn pointOnCircle(center: types.Vec2, radius: f64, angle: f64) types.Vec2 {
    return .{
        .x = center.x + radius * std.math.cos(angle),
        .y = center.y + radius * std.math.sin(angle),
    };
}

fn cubicBezierPoint(bezier: types.BezierSeg, t: f64) types.Vec2 {
    const mt = 1.0 - t;
    const mt2 = mt * mt;
    const mt3 = mt2 * mt;
    const t2 = t * t;
    const t3 = t2 * t;
    return .{
        .x = mt3 * bezier.p0.x +
            3.0 * mt2 * t * bezier.p1.x +
            3.0 * mt * t2 * bezier.p2.x +
            t3 * bezier.p3.x,
        .y = mt3 * bezier.p0.y +
            3.0 * mt2 * t * bezier.p1.y +
            3.0 * mt * t2 * bezier.p2.y +
            t3 * bezier.p3.y,
    };
}

fn approxEqVec2(a: types.Vec2, b: types.Vec2) bool {
    return std.math.approxEqAbs(f64, a.x, b.x, overlap_epsilon) and
        std.math.approxEqAbs(f64, a.y, b.y, overlap_epsilon);
}

test "all exported templates have non-overlapping 2d panels" {
    const descriptors = exportTemplates();

    for (descriptors) |descriptor| {
        const numeric_params = try buildDefaultNumericParams(std.testing.allocator, descriptor);
        defer std.testing.allocator.free(numeric_params);
        const select_params = try buildDefaultSelectParams(std.testing.allocator, descriptor);
        defer std.testing.allocator.free(select_params);

        const instance = try createTemplate(std.testing.allocator, descriptor.key, numeric_params, select_params);
        defer instance.deinit();

        var drawing = try instance.buildDrawing2D(std.testing.allocator);
        defer drawing.deinit(std.testing.allocator);

        for (drawing.panels, 0..) |left, left_index| {
            for (drawing.panels[left_index + 1 ..]) |right| {
                try std.testing.expect(
                    !(try panelsOverlap(std.testing.allocator, left, right)),
                );
            }
        }
    }
}

test "all exported templates have non-self-intersecting closed outlines" {
    const descriptors = exportTemplates();

    for (descriptors) |descriptor| {
        const numeric_params = try buildDefaultNumericParams(std.testing.allocator, descriptor);
        defer std.testing.allocator.free(numeric_params);
        const select_params = try buildDefaultSelectParams(std.testing.allocator, descriptor);
        defer std.testing.allocator.free(select_params);

        const instance = try createTemplate(std.testing.allocator, descriptor.key, numeric_params, select_params);
        defer instance.deinit();

        var drawing = try instance.buildDrawing2D(std.testing.allocator);
        defer drawing.deinit(std.testing.allocator);

        for (drawing.panels) |panel| {
            try std.testing.expect(!(try pathSelfIntersects(std.testing.allocator, panel.boundary)));
            try std.testing.expect(!(try pathSelfIntersects(std.testing.allocator, panel.content_region)));
        }

        for (drawing.linework) |linework| {
            if (!linework.path.closed) continue;
            if (!roleRequiresSimpleClosedPath(linework.role)) continue;
            try std.testing.expect(!(try pathSelfIntersects(std.testing.allocator, linework.path)));
        }
    }
}
