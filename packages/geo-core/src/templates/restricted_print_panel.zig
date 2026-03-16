const std = @import("std");
const package = @import("../package.zig");
const schema = @import("schema.zig");
const types = @import("../types.zig");
const wrench = @import("wrench.zig");

const PanelKey = enum(u16) {
    printable = 0,
};

fn panelId(key: PanelKey) types.PanelId {
    return @intFromEnum(key);
}

pub const descriptor = schema.TemplateDescriptor{
    .key = "folding_carton.restricted_print_panel",
    .label = "Restricted Print Panel",
    .package_kind = .folding_carton,
    .numeric_params = &.{
        .{ .key = "panel_width", .label = "Panel Width", .default_value = 80, .min_value = 1 },
        .{ .key = "panel_height", .label = "Panel Height", .default_value = 60, .min_value = 1 },
        .{ .key = "safe_margin", .label = "Safe Margin", .default_value = 8, .min_value = 0 },
    },
};

pub const Instance = struct {
    allocator: std.mem.Allocator,
    boundary_segments: [4]types.PathSeg,
    content_segments: [4]types.PathSeg,
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
    const panel_width = wrench.resolveNumericParam(numeric_params, "panel_width", 80);
    const panel_height = wrench.resolveNumericParam(numeric_params, "panel_height", 60);
    const safe_margin = wrench.resolveNumericParam(numeric_params, "safe_margin", 8);

    var instance = try allocator.create(Instance);
    errdefer allocator.destroy(instance);
    instance.* = undefined;
    instance.allocator = allocator;

    instance.boundary_segments = wrench.rectSegments(0, 0, panel_width, panel_height);
    instance.content_segments = wrench.rectSegments(
        safe_margin,
        safe_margin,
        panel_width - safe_margin * 2.0,
        panel_height - safe_margin * 2.0,
    );

    instance.panels[0] = try types.Panel.withGeometryBy(
        types.Path2D.baseBy(&instance.boundary_segments),
        panelId(.printable),
        .{
            .origin = .{ .x = 0, .y = 0 },
            .u_axis = .{ .x = panel_width, .y = 0 },
            .v_axis = .{ .x = 0, .y = panel_height },
        },
        types.Path2D.baseBy(&instance.content_segments),
        .{ .x = 0, .y = 0, .z = 1 },
    );

    instance.linework[0] = .{
        .path = types.Path2D.baseBy(&instance.boundary_segments),
        .role = .cut,
        .stroke_style = .solid,
    };
    instance.folding_carton = package.FoldingCartonModel.init(&instance.panels, &.{}, &instance.linework);
    return instance;
}

test "restricted print panel uses content region for validation" {
    var instance = try create(std.testing.allocator, &.{});
    defer instance.deinit();

    var valid = [_]types.PanelContentPlacement{
        .{
            .id = 1,
            .panel_id = panelId(.printable),
            .content = .{ .text = .{ .text = "Safe", .font_size = 12 } },
            .transform = .{
                .position = .{ .x = 15, .y = 15 },
                .size = .{ .x = 20, .y = 20 },
                .space = .panel_uv_percent,
            },
        },
    };
    try instance.setContents(&valid);
    try std.testing.expectEqualDeep(instance.panels[0].content_region, valid[0].clip_path.?);

    var invalid = [_]types.PanelContentPlacement{
        .{
            .id = 2,
            .panel_id = panelId(.printable),
            .content = .{ .text = .{ .text = "Unsafe", .font_size = 12 } },
            .transform = .{
                .position = .{ .x = 0, .y = 0 },
                .size = .{ .x = 20, .y = 20 },
                .space = .panel_uv_percent,
            },
        },
    };
    try std.testing.expectError(
        package.ContentValidationError.ContentOutOfBounds,
        instance.setContents(&invalid),
    );
}
