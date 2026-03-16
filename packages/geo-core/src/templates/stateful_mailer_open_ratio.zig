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
};

fn panelId(key: PanelKey) types.PanelId {
    return @intFromEnum(key);
}

pub const descriptor = schema.TemplateDescriptor{
    .key = "folding_carton.stateful_mailer_open_ratio",
    .label = "Stateful Mailer Open Ratio",
    .package_kind = .folding_carton,
    .numeric_params = &.{
        .{ .key = "length", .label = "Length", .default_value = 95, .min_value = 1 },
        .{ .key = "width", .label = "Width", .default_value = 78, .min_value = 1 },
        .{ .key = "depth", .label = "Depth", .default_value = 28, .min_value = 1 },
        .{ .key = "open_ratio", .label = "Open Ratio", .default_value = 0.5, .min_value = 0, .max_value = 1 },
    },
};

pub const Instance = struct {
    allocator: std.mem.Allocator,
    panel_segments: [4][4]types.PathSeg,
    score_segments: [3][1]types.PathSeg,
    panels: [4]types.Panel,
    folds: [3]types.Fold,
    linework: [7]types.StyledPath2D,
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
    const open_ratio = std.math.clamp(wrench.resolveNumericParam(numeric_params, "open_ratio", 0.5), 0, 1);
    const lid_angle = open_ratio * (std.math.pi * 0.8);

    var instance = try allocator.create(Instance);
    errdefer allocator.destroy(instance);
    instance.* = undefined;
    instance.allocator = allocator;

    try wrench.initRectPanelSet(
        4,
        &instance.panel_segments,
        &instance.panels,
        .{
            .{ .id = panelId(.base), .x = 0, .y = 0, .width = length, .height = width },
            .{ .id = panelId(.front_wall), .x = 0, .y = -depth, .width = length, .height = depth },
            .{ .id = panelId(.back_wall), .x = 0, .y = width, .width = length, .height = depth },
            .{ .id = panelId(.lid), .x = 0, .y = width + depth, .width = length, .height = width },
        },
        .{ .x = 0, .y = 0, .z = 1 },
    );

    instance.folds = .{
        wrench.fold(panelId(.base), panelId(.front_wall), 0, 2, std.math.pi / 2.0, .toward_outside),
        wrench.fold(panelId(.base), panelId(.back_wall), 2, 0, std.math.pi / 2.0, .toward_outside),
        wrench.fold(panelId(.back_wall), panelId(.lid), 2, 0, lid_angle, .toward_inside),
    };

    wrench.initScoreSegments(
        3,
        &instance.score_segments,
        .{
            wrench.horizontalScoreSpec(0, 0, length),
            wrench.horizontalScoreSpec(0, width, length),
            wrench.horizontalScoreSpec(0, width + depth, length),
        },
    );

    wrench.appendCutLinework(4, &instance.linework, 0, &instance.panel_segments);
    wrench.appendScoreLinework(3, &instance.linework, 4, &instance.score_segments);

    instance.folding_carton = package.FoldingCartonModel.init(&instance.panels, &instance.folds, &instance.linework);
    return instance;
}

test "stateful mailer maps open ratio to lid fold angle" {
    var instance = try create(std.testing.allocator, &.{ .{ .key = "open_ratio", .value = 0.75 } });
    defer instance.deinit();

    var preview = try instance.buildPreview3D(std.testing.allocator);
    defer preview.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), preview.nodes.len);
    try std.testing.expectEqual(panelId(.lid), preview.nodes[3].panel_id.?);
    try std.testing.expectEqual(@as(?u32, 2), preview.nodes[3].parent_index);
    try std.testing.expectApproxEqAbs(std.math.pi * 0.6, @abs(preview.nodes[3].transform.rotation_rad), 1e-9);
    try std.testing.expect(preview.nodes[3].transform.rotation_rad > 0);
}
