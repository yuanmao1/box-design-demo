const std = @import("std");
const package = @import("../package.zig");
const schema = @import("schema.zig");
const types = @import("../types.zig");
const wrench = @import("wrench.zig");

const PanelKey = enum(u16) {
    sector = 0,
};

fn panelId(key: PanelKey) types.PanelId {
    return @intFromEnum(key);
}

pub const descriptor = schema.TemplateDescriptor{
    .key = "folding_carton.sector_panel_single",
    .label = "Sector Panel",
    .package_kind = .folding_carton,
    .numeric_params = &.{
        .{ .key = "inner_radius", .label = "Inner Radius", .default_value = 12, .min_value = 0 },
        .{ .key = "outer_radius", .label = "Outer Radius", .default_value = 50, .min_value = 1 },
        .{ .key = "sweep_angle_rad", .label = "Sweep Angle", .default_value = std.math.pi / 2.0, .min_value = 0.1, .max_value = std.math.pi * 1.75 },
    },
};

pub const Instance = struct {
    allocator: std.mem.Allocator,
    segments: [4]types.PathSeg,
    panels: [1]types.Panel,
    linework: [1]types.StyledPath2D,
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
    const inner_radius = wrench.resolveNumericParam(numeric_params, "inner_radius", 12);
    const outer_radius = wrench.resolveNumericParam(numeric_params, "outer_radius", 50);
    const sweep = wrench.resolveNumericParam(numeric_params, "sweep_angle_rad", std.math.pi / 2.0);

    var instance = try allocator.create(Instance);
    errdefer allocator.destroy(instance);
    instance.* = undefined;
    instance.allocator = allocator;

    instance.panels[0] = try wrench.initPanelBySegments(
        4,
        &instance.segments,
        wrench.annularSectorSegments(.{ .x = 0, .y = 0 }, inner_radius, outer_radius, 0, sweep),
        panelId(.sector),
        .{
            .origin = .{ .x = 0, .y = 0 },
            .u_axis = .{ .x = outer_radius, .y = 0 },
            .v_axis = .{ .x = 0, .y = outer_radius },
        },
        .{ .x = 0, .y = 0, .z = 1 },
    );

    instance.linework[0] = .{
        .path = types.Path2D.baseBy(&instance.segments),
        .role = .cut,
        .stroke_style = .solid,
    };
    instance.folding_carton = package.FoldingCartonModel.init(&instance.panels, &.{}, &instance.linework);
    return instance;
}

test "sector panel supports curved boundaries and rejects edge overflow" {
    var instance = try create(std.testing.allocator, &.{});
    defer instance.deinit();

    var ok = [_]types.PanelContentPlacement{
        .{
            .id = 1,
            .panel_id = panelId(.sector),
            .content = .{ .text = .{ .text = "Arc", .font_size = 12 } },
            .transform = .{
                .position = .{ .x = 35, .y = 35 },
                .size = .{ .x = 10, .y = 10 },
                .space = .panel_uv_percent,
            },
        },
    };
    try instance.setContents(&ok);

    var overflow = [_]types.PanelContentPlacement{
        .{
            .id = 2,
            .panel_id = panelId(.sector),
            .content = .{ .text = .{ .text = "Edge", .font_size = 12 } },
            .transform = .{
                .position = .{ .x = 85, .y = 70 },
                .size = .{ .x = 18, .y = 18 },
                .rotation_rad = std.math.pi / 8.0,
                .space = .panel_uv_percent,
            },
        },
    };
    try std.testing.expectError(
        package.ContentValidationError.ContentOutOfBounds,
        instance.setContents(&overflow),
    );
}
