const std = @import("std");
const package = @import("../package.zig");
const schema = @import("schema.zig");
const types = @import("../types.zig");
const wrench = @import("wrench.zig");

const PanelKey = enum(u16) {
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

fn panelId(key: PanelKey) types.PanelId {
    return @intFromEnum(key);
}

pub const descriptor = schema.TemplateDescriptor{
    .key = "folding_carton.mailer_box",
    .label = "Mailer Box",
    .package_kind = .folding_carton,
    .numeric_params = &.{
        .{ .key = "length", .label = "Length", .default_value = 95, .min_value = 1 },
        .{ .key = "width", .label = "Width", .default_value = 78, .min_value = 1 },
        .{ .key = "depth", .label = "Depth", .default_value = 28, .min_value = 1 },
        .{ .key = "lid_length", .label = "Lid Length", .default_value = 52, .min_value = 1 },
        .{ .key = "dust_flap_width", .label = "Dust Flap Width", .default_value = 18, .min_value = 1 },
        .{ .key = "front_lock_height", .label = "Front Lock Height", .default_value = 16, .min_value = 1 },
        .{ .key = "wall_angle_rad", .label = "Wall Angle", .default_value = std.math.pi / 2.0, .min_value = -std.math.pi, .max_value = std.math.pi },
        .{ .key = "lid_angle_rad", .label = "Lid Angle", .default_value = std.math.pi * 0.55, .min_value = -std.math.pi, .max_value = std.math.pi },
    },
};

pub const Instance = struct {
    allocator: std.mem.Allocator,
    panel_segments: [9][4]types.PathSeg,
    score_segments: [8][1]types.PathSeg,
    panels: [9]types.Panel,
    folds: [8]types.Fold,
    linework: [17]types.StyledPath2D,
    folding_carton: package.FoldingCartonModel,

    pub fn deinit(self: *Instance) void {
        self.folding_carton.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn setContents(self: *Instance, contents: []types.PanelContentPlacement) !void {
        try self.folding_carton.setContents(self.allocator, contents);
    }

    pub fn buildDrawing2D(self: *Instance, allocator: std.mem.Allocator) !package.Drawing2DResult {
        return self.folding_carton.buildDrawing2D(allocator);
    }

    pub fn buildPreview3D(self: *Instance, allocator: std.mem.Allocator) !package.Preview3DResult {
        return self.folding_carton.buildPreview3D(allocator);
    }
};

pub fn create(allocator: std.mem.Allocator, numeric_params: []const schema.NumericParamValue) !*Instance {
    const length = wrench.resolveNumericParam(numeric_params, "length", 95);
    const width = wrench.resolveNumericParam(numeric_params, "width", 78);
    const depth = wrench.resolveNumericParam(numeric_params, "depth", 28);
    const lid_length = wrench.resolveNumericParam(numeric_params, "lid_length", 52);
    const dust_flap_width = wrench.resolveNumericParam(numeric_params, "dust_flap_width", 18);
    const front_lock_height = wrench.resolveNumericParam(numeric_params, "front_lock_height", 16);
    const wall_angle = wrench.resolveNumericParam(numeric_params, "wall_angle_rad", std.math.pi / 2.0);
    const lid_angle = wrench.resolveNumericParam(numeric_params, "lid_angle_rad", std.math.pi * 0.55);

    var instance = try allocator.create(Instance);
    errdefer allocator.destroy(instance);
    instance.* = undefined;
    instance.allocator = allocator;

    try wrench.initRectPanelSet(
        9,
        &instance.panel_segments,
        &instance.panels,
        .{
            .{ .id = panelId(.base), .x = 0, .y = 0, .width = length, .height = width },
            .{ .id = panelId(.front_wall), .x = 0, .y = -depth, .width = length, .height = depth },
            .{ .id = panelId(.back_wall), .x = 0, .y = width, .width = length, .height = depth },
            .{ .id = panelId(.lid), .x = 0, .y = width + depth, .width = length, .height = lid_length },
            .{ .id = panelId(.left_wall), .x = -depth, .y = 0, .width = depth, .height = width },
            .{ .id = panelId(.right_wall), .x = length, .y = 0, .width = depth, .height = width },
            .{ .id = panelId(.left_dust_flap), .x = -dust_flap_width, .y = width + depth, .width = dust_flap_width, .height = lid_length },
            .{ .id = panelId(.right_dust_flap), .x = length, .y = width + depth, .width = dust_flap_width, .height = lid_length },
            .{ .id = panelId(.lock_flap), .x = 0, .y = width + depth + lid_length, .width = length, .height = front_lock_height, .accepts_content = false },
        },
        .{ .x = 0, .y = 0, .z = 1 },
    );

    instance.folds = .{
        wrench.fold(panelId(.base), panelId(.front_wall), 0, 2, wall_angle, .toward_outside),
        wrench.fold(panelId(.base), panelId(.back_wall), 2, 0, wall_angle, .toward_outside),
        wrench.fold(panelId(.base), panelId(.left_wall), 3, 1, wall_angle, .toward_outside),
        wrench.fold(panelId(.base), panelId(.right_wall), 1, 3, wall_angle, .toward_outside),
        wrench.fold(panelId(.back_wall), panelId(.lid), 2, 0, lid_angle, .toward_outside),
        wrench.fold(panelId(.lid), panelId(.left_dust_flap), 3, 1, std.math.pi / 2.0, .toward_outside),
        wrench.fold(panelId(.lid), panelId(.right_dust_flap), 1, 3, std.math.pi / 2.0, .toward_outside),
        wrench.fold(panelId(.lid), panelId(.lock_flap), 2, 0, std.math.pi / 4.0, .toward_outside),
    };

    wrench.initScoreSegments(
        8,
        &instance.score_segments,
        .{
            wrench.horizontalScoreSpec(0, 0, length),
            wrench.horizontalScoreSpec(0, width, length),
            wrench.horizontalScoreSpec(0, width + depth, length),
            wrench.horizontalScoreSpec(0, width + depth + lid_length, length),
            wrench.verticalScoreSpec(0, 0, width),
            wrench.verticalScoreSpec(length, 0, width),
            wrench.verticalScoreSpec(0, width + depth, lid_length),
            wrench.verticalScoreSpec(length, width + depth, lid_length),
        },
    );

    for (instance.panel_segments, 0..) |_, index| {
        instance.linework[index] = wrench.cutPath(4, &instance.panel_segments[index]);
    }
    for (instance.score_segments, 0..) |_, index| {
        instance.linework[9 + index] = wrench.scorePath(1, &instance.score_segments[index]);
    }

    instance.folding_carton = package.FoldingCartonModel.init(&instance.panels, &instance.folds, &instance.linework);
    return instance;
}

test "mailer box builds complex fold tree and marks lock panel non printable" {
    var instance = try create(std.testing.allocator, &.{});
    defer instance.deinit();

    var preview = try instance.buildPreview3D(std.testing.allocator);
    defer preview.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 9), preview.nodes.len);
    const lid_node = findNodeByPanelId(&preview, panelId(.lid)).?;
    const left_dust_flap_node = findNodeByPanelId(&preview, panelId(.left_dust_flap)).?;
    const right_dust_flap_node = findNodeByPanelId(&preview, panelId(.right_dust_flap)).?;
    const lock_flap_node = findNodeByPanelId(&preview, panelId(.lock_flap)).?;

    try std.testing.expectEqual(@as(?u32, 2), lid_node.parent_index);
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
            .panel_id = panelId(.lock_flap),
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
    var instance = try create(std.testing.allocator, &.{});
    defer instance.deinit();

    var preview = try instance.buildPreview3D(std.testing.allocator);
    defer preview.deinit(std.testing.allocator);

    try std.testing.expect(findNodeByPanelId(&preview, panelId(.lid)).?.node.transform.rotation_rad < 0);
    try std.testing.expect(findNodeByPanelId(&preview, panelId(.left_dust_flap)).?.node.transform.rotation_rad < 0);
    try std.testing.expect(findNodeByPanelId(&preview, panelId(.right_dust_flap)).?.node.transform.rotation_rad < 0);
    try std.testing.expect(findNodeByPanelId(&preview, panelId(.lock_flap)).?.node.transform.rotation_rad < 0);
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
