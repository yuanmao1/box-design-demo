const std = @import("std");
const package = @import("../package.zig");
const schema = @import("schema.zig");
const types = @import("../types.zig");
const wrench = @import("wrench.zig");

const Self = @This();

const PanelKey = enum(u16) {
    front = 0,
    right_side = 1,
    back = 2,
    left_side = 3,
    glue_tab = 4,
};

fn panelId(key: PanelKey) types.PanelId {
    return @intFromEnum(key);
}

pub const descriptor = schema.TemplateDescriptor{
    .key = "folding_carton.four_panel_tube",
    .label = "Four Panel Tube",
    .package_kind = .folding_carton,
    .numeric_params = &.{
        .{ .key = "front_width", .label = "Front Width", .default_value = 60, .min_value = 1 },
        .{ .key = "side_width", .label = "Side Width", .default_value = 25, .min_value = 1 },
        .{ .key = "panel_height", .label = "Panel Height", .default_value = 70, .min_value = 1 },
        .{ .key = "glue_tab_width", .label = "Glue Tab Width", .default_value = 12, .min_value = 1 },
        .{ .key = "fold_angle_rad", .label = "Fold Angle", .default_value = std.math.pi / 2.0, .min_value = -std.math.pi, .max_value = std.math.pi },
    },
};

pub const Instance = struct {
    allocator: std.mem.Allocator,
    panel_segments: [5][4]types.PathSeg,
    score_segments: [4][1]types.PathSeg,
    panels: [5]types.Panel,
    folds: [4]types.Fold,
    linework: [9]types.StyledPath2D,
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

pub fn create(
    allocator: std.mem.Allocator,
    numeric_params: []const schema.NumericParamValue,
) !*Instance {
    const front_width = wrench.resolveNumericParam(numeric_params, "front_width", 60);
    const side_width = wrench.resolveNumericParam(numeric_params, "side_width", 25);
    const panel_height = wrench.resolveNumericParam(numeric_params, "panel_height", 70);
    const glue_tab_width = wrench.resolveNumericParam(numeric_params, "glue_tab_width", 12);
    const fold_angle = wrench.resolveNumericParam(numeric_params, "fold_angle_rad", std.math.pi / 2.0);

    var instance = try allocator.create(Instance);
    errdefer allocator.destroy(instance);

    instance.* = undefined;
    instance.allocator = allocator;

    const widths = [_]f64{ front_width, side_width, front_width, side_width, glue_tab_width };
    try wrench.initRectPanelStrip(5, &instance.panel_segments, &instance.panels, 0, 0, widths, panel_height, panelId(.front), .{ .x = 0, .y = 0, .z = 1 });
    instance.panels[@intFromEnum(PanelKey.glue_tab)].accepts_content = false;

    instance.score_segments = wrench.scoreSegmentsForStrip(5, 0, 0, widths, panel_height);
    instance.folds = wrench.foldChainRightToLeft(4, panelId(.front), fold_angle, .{
        .toward_inside,
        .toward_outside,
        .toward_inside,
        .toward_outside,
    });

    wrench.appendCutLinework(5, &instance.linework, 0, &instance.panel_segments);
    wrench.appendScoreLinework(4, &instance.linework, 5, &instance.score_segments);

    instance.folding_carton = package.FoldingCartonModel.init(&instance.panels, &instance.folds, &instance.linework);
    return instance;
}

test "four panel tube builds chained preview and rejects glue tab content" {
    var instance = try create(std.testing.allocator, &.{});
    defer instance.deinit();

    var preview = try instance.buildPreview3D(std.testing.allocator);
    defer preview.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 5), preview.nodes.len);
    try std.testing.expectEqual(@as(?u32, 0), preview.nodes[1].parent_index);
    try std.testing.expectEqual(@as(?u32, 1), preview.nodes[2].parent_index);
    try std.testing.expectEqual(@as(?u32, 2), preview.nodes[3].parent_index);
    try std.testing.expectEqual(@as(?u32, 3), preview.nodes[4].parent_index);

    var contents = [_]types.PanelContentPlacement{
        .{
            .id = 1,
            .panel_id = panelId(.glue_tab),
            .content = .{ .text = .{ .text = "Nope", .font_size = 12 } },
            .transform = .{
                .position = .{ .x = 10, .y = 10 },
                .size = .{ .x = 40, .y = 40 },
                .space = .panel_uv_percent,
            },
        },
    };

    try std.testing.expectError(
        package.ContentValidationError.PanelRejectsContent,
        instance.setContents(&contents),
    );
}
