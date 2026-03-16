const std = @import("std");
const package = @import("../package.zig");
const schema = @import("schema.zig");
const types = @import("../types.zig");
const wrench = @import("wrench.zig");

const Self = @This();

const PanelKey = enum(u16) {
    left = 0,
    right = 1,
};

fn panelId(key: PanelKey) types.PanelId {
    return @intFromEnum(key);
}

pub const descriptor = schema.TemplateDescriptor{
    .key = "folding_carton.simple_two_panel",
    .label = "Simple Two Panel Carton",
    .package_kind = .folding_carton,
    .numeric_params = &.{
        .{
            .key = "panel_width",
            .label = "Panel Width",
            .default_value = 40,
            .min_value = 1,
        },
        .{
            .key = "panel_height",
            .label = "Panel Height",
            .default_value = 30,
            .min_value = 1,
        },
        .{
            .key = "fold_angle_rad",
            .label = "Fold Angle",
            .default_value = std.math.pi / 2.0,
            .min_value = -std.math.pi,
            .max_value = std.math.pi,
        },
    },
};

pub const Instance = struct {
    allocator: std.mem.Allocator,
    left_segments: [4]types.PathSeg,
    right_segments: [4]types.PathSeg,
    cut_segments: [4]types.PathSeg,
    score_segments: [1]types.PathSeg,
    panels: [2]types.Panel,
    folds: [1]types.Fold,
    linework: [2]types.StyledPath2D,
    folding_carton: package.FoldingCartonModel,

    pub fn deinit(self: *Self.Instance) void {
        self.folding_carton.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn setContents(
        self: *Self.Instance,
        contents: []types.PanelContentPlacement,
    ) !void {
        try self.folding_carton.setContents(self.allocator, contents);
    }

    pub fn buildDrawing2D(
        self: *Self.Instance,
        allocator: std.mem.Allocator,
    ) !package.Drawing2DResult {
        return self.folding_carton.buildDrawing2D(allocator);
    }

    pub fn buildPreview3D(
        self: *Self.Instance,
        allocator: std.mem.Allocator,
    ) !package.Preview3DResult {
        return self.folding_carton.buildPreview3D(allocator);
    }
};

pub fn create(
    allocator: std.mem.Allocator,
    numeric_params: []const schema.NumericParamValue,
) !*Self.Instance {
    const panel_width = wrench.resolveNumericParam(numeric_params, "panel_width", 40);
    const panel_height = wrench.resolveNumericParam(numeric_params, "panel_height", 30);
    const fold_angle_rad = wrench.resolveNumericParam(
        numeric_params,
        "fold_angle_rad",
        std.math.pi / 2.0,
    );

    var instance = try allocator.create(Self.Instance);
    errdefer allocator.destroy(instance);

    instance.* = undefined;
    instance.allocator = allocator;

    buildSegments(instance, panel_width, panel_height);
    instance.panels = .{
        try types.Panel.withSurfaceBy(
            wrench.closedPath(4, &instance.left_segments),
            panelId(.left),
            .{
                .origin = .{ .x = 0, .y = 0 },
                .u_axis = .{ .x = panel_width, .y = 0 },
                .v_axis = .{ .x = 0, .y = panel_height },
            },
            .{ .x = 0, .y = 0, .z = 1 },
        ),
        try types.Panel.withSurfaceBy(
            wrench.closedPath(4, &instance.right_segments),
            panelId(.right),
            .{
                .origin = .{ .x = panel_width, .y = 0 },
                .u_axis = .{ .x = panel_width, .y = 0 },
                .v_axis = .{ .x = 0, .y = panel_height },
            },
            .{ .x = 0, .y = 0, .z = 1 },
        ),
    };
    instance.folds = .{
        wrench.fold(panelId(.left), panelId(.right), 1, 3, fold_angle_rad, .toward_inside),
    };
    instance.linework = .{
        wrench.cutPath(4, &instance.cut_segments),
        wrench.scorePath(1, &instance.score_segments),
    };
    instance.folding_carton = package.FoldingCartonModel.init(
        &instance.panels,
        &instance.folds,
        &instance.linework,
    );

    return instance;
}

fn buildSegments(instance: *Self.Instance, panel_width: f64, panel_height: f64) void {
    instance.left_segments = .{
        .{ .Line = .{ .from = .{ .x = 0, .y = 0 }, .to = .{ .x = panel_width, .y = 0 } } },
        .{ .Line = .{ .from = .{ .x = panel_width, .y = 0 }, .to = .{ .x = panel_width, .y = panel_height } } },
        .{ .Line = .{ .from = .{ .x = panel_width, .y = panel_height }, .to = .{ .x = 0, .y = panel_height } } },
        .{ .Line = .{ .from = .{ .x = 0, .y = panel_height }, .to = .{ .x = 0, .y = 0 } } },
    };
    instance.right_segments = .{
        .{ .Line = .{ .from = .{ .x = panel_width, .y = 0 }, .to = .{ .x = panel_width * 2.0, .y = 0 } } },
        .{ .Line = .{ .from = .{ .x = panel_width * 2.0, .y = 0 }, .to = .{ .x = panel_width * 2.0, .y = panel_height } } },
        .{ .Line = .{ .from = .{ .x = panel_width * 2.0, .y = panel_height }, .to = .{ .x = panel_width, .y = panel_height } } },
        .{ .Line = .{ .from = .{ .x = panel_width, .y = panel_height }, .to = .{ .x = panel_width, .y = 0 } } },
    };
    instance.cut_segments = .{
        .{ .Line = .{ .from = .{ .x = 0, .y = 0 }, .to = .{ .x = panel_width * 2.0, .y = 0 } } },
        .{ .Line = .{ .from = .{ .x = panel_width * 2.0, .y = 0 }, .to = .{ .x = panel_width * 2.0, .y = panel_height } } },
        .{ .Line = .{ .from = .{ .x = panel_width * 2.0, .y = panel_height }, .to = .{ .x = 0, .y = panel_height } } },
        .{ .Line = .{ .from = .{ .x = 0, .y = panel_height }, .to = .{ .x = 0, .y = 0 } } },
    };
    instance.score_segments = .{
        wrench.lineSegment(.{ .x = panel_width, .y = 0 }, .{ .x = panel_width, .y = panel_height }),
    };
}
