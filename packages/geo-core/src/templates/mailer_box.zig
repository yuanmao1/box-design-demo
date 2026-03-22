const std = @import("std");
const package = @import("../package.zig");
const types = @import("../types.zig");
const compiled_spec = @import("compiled_spec.zig");
const cv2 = compiled_spec.cv2;

const Panel = enum(u16) {
    base = 0,
    front_wall = 1,
    back_wall = 2,
    lid = 3,
    left_wall = 4,
    right_wall = 5,
    left_dust_flap = 6,
    right_dust_flap = 7,
    lock_flap = 8,
};

fn p(key: Panel) types.PanelId {
    return @intFromEnum(key);
}

fn e(comptime expr_str: []const u8) compiled_spec.RuntimeScalarSpec {
    return .{ .expr = expr_str };
}

fn ev2(comptime x_expr: []const u8, comptime y_expr: []const u8) compiled_spec.RuntimeVec2Spec {
    return .{ .x = e(x_expr), .y = e(y_expr) };
}

fn evx(comptime x_expr: []const u8, y_val: f64) compiled_spec.RuntimeVec2Spec {
    return .{ .x = e(x_expr), .y = .{ .value = y_val } };
}

fn evy(x_val: f64, comptime y_expr: []const u8) compiled_spec.RuntimeVec2Spec {
    return .{ .x = .{ .value = x_val }, .y = e(y_expr) };
}

const Generated = compiled_spec.defineTemplate(.{
    .key = "folding_carton.mailer_box",
    .label = "Mailer Box",
    .thickness = 1.5,
    .numeric_params = &.{
        .{ .key = "length", .label = "Length", .default_value = 95, .min_value = 1 },
        .{ .key = "width", .label = "Width", .default_value = 78, .min_value = 1 },
        .{ .key = "depth", .label = "Depth", .default_value = 28, .min_value = 1 },
        .{ .key = "wall_angle_rad", .label = "Wall Angle", .default_value = std.math.pi / 2.0, .min_value = -std.math.pi, .max_value = std.math.pi },
        .{ .key = "lid_angle_rad", .label = "Lid Angle", .default_value = std.math.pi * 0.55, .min_value = -std.math.pi, .max_value = std.math.pi },
    },
    .variables = &.{
        // Derived dimensions from length/width/depth
        .{ .name = "lid_length", .expr = "width * 0.67" },
        .{ .name = "dust_flap_width", .expr = "depth * 0.65" },
        .{ .name = "lock_height", .expr = "depth * 0.57" },
        // Y-axis key lines (bottom to top)
        .{ .name = "y0", .expr = "-depth" },
        .{ .name = "y1", .expr = "0" },
        .{ .name = "y2", .expr = "width" },
        .{ .name = "y3", .expr = "width + depth" },
        .{ .name = "y4", .expr = "y3 + lid_length" },
        .{ .name = "y5", .expr = "y4 + lock_height" },
        // X-axis key lines
        .{ .name = "x0", .expr = "-depth" },
        .{ .name = "x2", .expr = "length" },
        .{ .name = "x3", .expr = "length + depth" },
        // Dust flap X edges
        .{ .name = "dx0", .expr = "-dust_flap_width" },
        .{ .name = "dx1", .expr = "length + dust_flap_width" },
    },
    .panels = &.{
        .{
            .id = p(.base), .name = "base",
            .boundary = &.{
                .{ .from = evy(0, "y1"), .to = ev2("x2", "y1") },
                .{ .from = ev2("x2", "y1"), .to = ev2("x2", "y2") },
                .{ .from = ev2("x2", "y2"), .to = evy(0, "y2") },
                .{ .from = evy(0, "y2"), .to = evy(0, "y1") },
            },
        },
        .{
            .id = p(.front_wall), .name = "front_wall",
            .boundary = &.{
                .{ .from = evy(0, "y0"), .to = ev2("x2", "y0") },
                .{ .from = ev2("x2", "y0"), .to = ev2("x2", "y1") },
                .{ .from = ev2("x2", "y1"), .to = evy(0, "y1") },
                .{ .from = evy(0, "y1"), .to = evy(0, "y0") },
            },
        },
        .{
            .id = p(.back_wall), .name = "back_wall",
            .boundary = &.{
                .{ .from = evy(0, "y2"), .to = ev2("x2", "y2") },
                .{ .from = ev2("x2", "y2"), .to = ev2("x2", "y3") },
                .{ .from = ev2("x2", "y3"), .to = evy(0, "y3") },
                .{ .from = evy(0, "y3"), .to = evy(0, "y2") },
            },
        },
        .{
            .id = p(.lid), .name = "lid",
            .boundary = &.{
                .{ .from = evy(0, "y3"), .to = ev2("x2", "y3") },
                .{ .from = ev2("x2", "y3"), .to = ev2("x2", "y4") },
                .{ .from = ev2("x2", "y4"), .to = evy(0, "y4") },
                .{ .from = evy(0, "y4"), .to = evy(0, "y3") },
            },
        },
        .{
            .id = p(.left_wall), .name = "left_wall",
            .boundary = &.{
                .{ .from = ev2("x0", "y1"), .to = evy(0, "y1") },
                .{ .from = evy(0, "y1"), .to = evy(0, "y2") },
                .{ .from = evy(0, "y2"), .to = ev2("x0", "y2") },
                .{ .from = ev2("x0", "y2"), .to = ev2("x0", "y1") },
            },
        },
        .{
            .id = p(.right_wall), .name = "right_wall",
            .boundary = &.{
                .{ .from = ev2("x2", "y1"), .to = ev2("x3", "y1") },
                .{ .from = ev2("x3", "y1"), .to = ev2("x3", "y2") },
                .{ .from = ev2("x3", "y2"), .to = ev2("x2", "y2") },
                .{ .from = ev2("x2", "y2"), .to = ev2("x2", "y1") },
            },
        },
        .{
            .id = p(.left_dust_flap), .name = "left_dust_flap",
            .boundary = &.{
                .{ .from = ev2("dx0", "y3"), .to = evy(0, "y3") },
                .{ .from = evy(0, "y3"), .to = evy(0, "y4") },
                .{ .from = evy(0, "y4"), .to = ev2("dx0", "y4") },
                .{ .from = ev2("dx0", "y4"), .to = ev2("dx0", "y3") },
            },
        },
        .{
            .id = p(.right_dust_flap), .name = "right_dust_flap",
            .boundary = &.{
                .{ .from = ev2("x2", "y3"), .to = ev2("dx1", "y3") },
                .{ .from = ev2("dx1", "y3"), .to = ev2("dx1", "y4") },
                .{ .from = ev2("dx1", "y4"), .to = ev2("x2", "y4") },
                .{ .from = ev2("x2", "y4"), .to = ev2("x2", "y3") },
            },
        },
        .{
            .id = p(.lock_flap), .name = "lock_flap",
            .accepts_content = false,
            .boundary = &.{
                .{ .from = evy(0, "y4"), .to = ev2("x2", "y4") },
                .{ .from = ev2("x2", "y4"), .to = ev2("x2", "y5") },
                .{ .from = ev2("x2", "y5"), .to = evy(0, "y5") },
                .{ .from = evy(0, "y5"), .to = evy(0, "y4") },
            },
        },
    },
    .folds = &.{
        // base → front_wall
        .{ .from_panel_id = p(.base), .to_panel_id = p(.front_wall), .from_segment_index = 0, .to_segment_index = 2, .angle_rad = 0, .angle_expr = "wall_angle_rad", .direction = .toward_outside },
        // base → back_wall
        .{ .from_panel_id = p(.base), .to_panel_id = p(.back_wall), .from_segment_index = 2, .to_segment_index = 0, .angle_rad = 0, .angle_expr = "wall_angle_rad", .direction = .toward_outside },
        // base → left_wall
        .{ .from_panel_id = p(.base), .to_panel_id = p(.left_wall), .from_segment_index = 3, .to_segment_index = 1, .angle_rad = 0, .angle_expr = "wall_angle_rad", .direction = .toward_outside },
        // base → right_wall
        .{ .from_panel_id = p(.base), .to_panel_id = p(.right_wall), .from_segment_index = 1, .to_segment_index = 3, .angle_rad = 0, .angle_expr = "wall_angle_rad", .direction = .toward_outside },
        // back_wall → lid
        .{ .from_panel_id = p(.back_wall), .to_panel_id = p(.lid), .from_segment_index = 2, .to_segment_index = 0, .angle_rad = 0, .angle_expr = "lid_angle_rad", .direction = .toward_outside },
        // lid → left_dust_flap
        .{ .from_panel_id = p(.lid), .to_panel_id = p(.left_dust_flap), .from_segment_index = 3, .to_segment_index = 1, .angle_rad = std.math.pi / 2.0, .direction = .toward_outside },
        // lid → right_dust_flap
        .{ .from_panel_id = p(.lid), .to_panel_id = p(.right_dust_flap), .from_segment_index = 1, .to_segment_index = 3, .angle_rad = std.math.pi / 2.0, .direction = .toward_outside },
        // lid → lock_flap
        .{ .from_panel_id = p(.lid), .to_panel_id = p(.lock_flap), .from_segment_index = 2, .to_segment_index = 0, .angle_rad = std.math.pi / 4.0, .direction = .toward_outside },
    },
    .linework = &.{
        // Horizontal score lines
        .{ .role = .score, .segments = &.{.{ .from = evy(0, "y1"), .to = ev2("x2", "y1") }} },
        .{ .role = .score, .segments = &.{.{ .from = evy(0, "y2"), .to = ev2("x2", "y2") }} },
        .{ .role = .score, .segments = &.{.{ .from = evy(0, "y3"), .to = ev2("x2", "y3") }} },
        .{ .role = .score, .segments = &.{.{ .from = evy(0, "y4"), .to = ev2("x2", "y4") }} },
        // Vertical score lines (base area)
        .{ .role = .score, .segments = &.{.{ .from = evy(0, "y1"), .to = evy(0, "y2") }} },
        .{ .role = .score, .segments = &.{.{ .from = ev2("x2", "y1"), .to = ev2("x2", "y2") }} },
        // Vertical score lines (lid area)
        .{ .role = .score, .segments = &.{.{ .from = evy(0, "y3"), .to = evy(0, "y4") }} },
        .{ .role = .score, .segments = &.{.{ .from = ev2("x2", "y3"), .to = ev2("x2", "y4") }} },
    },
});

pub const descriptor = Generated.descriptor;
pub const Instance = Generated.Instance;

pub fn create(
    allocator: std.mem.Allocator,
    numeric_params: []const @import("schema.zig").NumericParamValue,
    select_params: []const @import("schema.zig").SelectParamValue,
) !*Instance {
    return Generated.create(allocator, numeric_params, select_params);
}

// ── Tests ────────────────────────────────────────────────────────────

test "mailer box builds complex fold tree and marks lock panel non printable" {
    var instance = try create(std.testing.allocator, &.{}, &.{});
    defer instance.deinit();

    var preview = try instance.buildPreview3D(std.testing.allocator);
    defer preview.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 9), preview.nodes.len);
    const lid_node = findNodeByPanelId(&preview, p(.lid)).?;
    const left_dust_flap_node = findNodeByPanelId(&preview, p(.left_dust_flap)).?;
    const right_dust_flap_node = findNodeByPanelId(&preview, p(.right_dust_flap)).?;
    const lock_flap_node = findNodeByPanelId(&preview, p(.lock_flap)).?;

    const back_wall_node = findNodeByPanelId(&preview, p(.back_wall)).?;
    try std.testing.expectEqual(@as(?u32, back_wall_node.index), lid_node.parent_index);
    try std.testing.expectEqual(lid_node.index, left_dust_flap_node.parent_index.?);
    try std.testing.expectEqual(lid_node.index, right_dust_flap_node.parent_index.?);
    try std.testing.expectEqual(lid_node.index, lock_flap_node.parent_index.?);
    try std.testing.expectApproxEqAbs(std.math.pi * 0.55, @abs(lid_node.node.transform.rotation_rad), 1e-9);
    try std.testing.expect(lid_node.node.transform.rotation_rad < 0);
    try std.testing.expect(left_dust_flap_node.node.transform.rotation_rad < 0);
    try std.testing.expect(right_dust_flap_node.node.transform.rotation_rad < 0);
    try std.testing.expect(lock_flap_node.node.transform.rotation_rad < 0);

    var contents = [_]types.PanelContentPlacement{
        .{
            .id = 1,
            .panel_id = p(.lock_flap),
            .content = .{ .text = .{ .text = "Lock", .font_size = 12 } },
            .transform = .{
                .position = .{ .x = 10, .y = 10 },
                .size = .{ .x = 30, .y = 30 },
                .space = .panel_uv_percent,
            },
        },
    };
    try std.testing.expectError(
        package.ContentValidationError.PanelRejectsContent,
        instance.setContents(&contents),
    );
}

test "mailer box lid family keeps stable negative fold sign" {
    var instance = try create(std.testing.allocator, &.{}, &.{});
    defer instance.deinit();

    var preview = try instance.buildPreview3D(std.testing.allocator);
    defer preview.deinit(std.testing.allocator);

    try std.testing.expect(findNodeByPanelId(&preview, p(.lid)).?.node.transform.rotation_rad < 0);
    try std.testing.expect(findNodeByPanelId(&preview, p(.left_dust_flap)).?.node.transform.rotation_rad < 0);
    try std.testing.expect(findNodeByPanelId(&preview, p(.right_dust_flap)).?.node.transform.rotation_rad < 0);
    try std.testing.expect(findNodeByPanelId(&preview, p(.lock_flap)).?.node.transform.rotation_rad < 0);
}

const PreviewNodeLookup = struct {
    index: u32,
    node: *const package.Preview3DNode,
    parent_index: ?u32,
};

fn findNodeByPanelId(preview: *const package.Preview3DResult, target_panel_id: types.PanelId) ?PreviewNodeLookup {
    for (preview.nodes, 0..) |*node, index| {
        if (node.panel_id != null and node.panel_id.? == target_panel_id) {
            return .{
                .index = @intCast(index),
                .node = node,
                .parent_index = node.parent_index,
            };
        }
    }
    return null;
}
