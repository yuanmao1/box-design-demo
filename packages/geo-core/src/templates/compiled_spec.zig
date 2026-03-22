const std = @import("std");
const package = @import("../package.zig");
const types = @import("../types.zig");
const schema = @import("schema.zig");
const expr = @import("../expr.zig");

pub const Vec2Spec = struct {
    x: f64,
    y: f64,
};

pub const Vec3Spec = struct {
    x: f64,
    y: f64,
    z: f64,
};

pub const SurfaceFrameSpec = struct {
    origin: Vec2Spec,
    u_axis: Vec2Spec,
    v_axis: Vec2Spec,
};

pub const SegmentKind = enum {
    line,
    arc,
    bezier,
};

pub const RuntimeScalarSpec = struct {
    value: f64 = 0,
    expr: ?[]const u8 = null,
};

pub const RuntimeVec2Spec = struct {
    x: RuntimeScalarSpec,
    y: RuntimeScalarSpec,
};

pub const PathSegmentSpec = struct {
    kind: SegmentKind = .line,
    from: ?RuntimeVec2Spec = null,
    to: ?RuntimeVec2Spec = null,
    center: ?RuntimeVec2Spec = null,
    radius: ?RuntimeScalarSpec = null,
    start_angle: ?RuntimeScalarSpec = null,
    end_angle: ?RuntimeScalarSpec = null,
    clockwise: bool = false,
    p0: ?RuntimeVec2Spec = null,
    p1: ?RuntimeVec2Spec = null,
    p2: ?RuntimeVec2Spec = null,
    p3: ?RuntimeVec2Spec = null,
};

pub const PanelSpec = struct {
    id: types.PanelId,
    name: []const u8 = "",
    boundary: []const PathSegmentSpec,
    content_region: ?[]const PathSegmentSpec = null,
    surface_frame: ?SurfaceFrameSpec = null,
    outside_normal: ?Vec3Spec = null,
    accepts_content: bool = true,
};

pub const ScaleMode = enum {
    independent,
    uniform,
};

pub const BoundsSpec = struct {
    origin: Vec2Spec,
    size: Vec2Spec,
};

pub const NormalizeSpec = struct {
    source_bounds: ?BoundsSpec = null,
    target_origin: RuntimeVec2Spec = .{
        .x = .{ .value = 0 },
        .y = .{ .value = 0 },
    },
    target_size: ?RuntimeVec2Spec = null,
    flip_y: bool = false,
    scale_mode: ScaleMode = .independent,
};

pub const FoldSpec = struct {
    from_panel_id: types.PanelId,
    to_panel_id: types.PanelId,
    from_segment_index: u16,
    to_segment_index: u16,
    angle_rad: f64,
    angle_expr: ?[]const u8 = null,
    direction: types.FoldDirection,
};

pub const LineworkSpec = struct {
    role: types.LineRole,
    stroke_style: ?types.StrokeStyle = null,
    closed: bool = false,
    segments: []const PathSegmentSpec,
};

pub const VariableDef = struct {
    name: []const u8,
    expr: []const u8,
};

pub const TemplateSpec = struct {
    key: []const u8,
    label: []const u8,
    package_kind: package.PackageKind = .folding_carton,
    numeric_params: []const schema.NumericParamDef = &.{},
    select_params: []const schema.SelectParamDef = &.{},
    variables: []const VariableDef = &.{},
    normalization: ?NormalizeSpec = null,
    panels: []const PanelSpec,
    folds: []const FoldSpec = &.{},
    linework: []const LineworkSpec = &.{},
};

/// Convenience: create a RuntimeVec2Spec from two constant f64 values.
pub fn cv2(x_val: f64, y_val: f64) RuntimeVec2Spec {
    return .{ .x = .{ .value = x_val }, .y = .{ .value = y_val } };
}

/// Convenience: create a RuntimeScalarSpec from a constant f64 value.
pub fn cs(val: f64) RuntimeScalarSpec {
    return .{ .value = val };
}

const Bounds2D = struct {
    min_x: f64,
    min_y: f64,
    max_x: f64,
    max_y: f64,

    fn width(self: Bounds2D) f64 {
        return self.max_x - self.min_x;
    }

    fn height(self: Bounds2D) f64 {
        return self.max_y - self.min_y;
    }
};

const TransformContext = struct {
    mode: enum { identity, normalized } = .identity,
    source_bounds: Bounds2D = .{
        .min_x = 0,
        .min_y = 0,
        .max_x = 0,
        .max_y = 0,
    },
    target_origin: types.Vec2 = .{ .x = 0, .y = 0 },
    scale_x: f64 = 1,
    scale_y: f64 = 1,
    flip_y: bool = false,
    scale_mode: ScaleMode = .independent,

    fn point(self: TransformContext, input_point: types.Vec2) types.Vec2 {
        if (self.mode == .identity) return input_point;

        const base_x = input_point.x - self.source_bounds.min_x;
        const base_y = if (self.flip_y)
            self.source_bounds.max_y - input_point.y
        else
            input_point.y - self.source_bounds.min_y;

        return .{
            .x = self.target_origin.x + base_x * self.scale_x,
            .y = self.target_origin.y + base_y * self.scale_y,
        };
    }

    fn vector(self: TransformContext, input_vector: types.Vec2) types.Vec2 {
        if (self.mode == .identity) return input_vector;
        return .{
            .x = input_vector.x * self.scale_x,
            .y = input_vector.y * (if (self.flip_y) -self.scale_y else self.scale_y),
        };
    }

    fn arcRadiusScale(self: TransformContext) f64 {
        if (self.mode == .identity) return 1;
        return self.scale_x;
    }
};

pub fn defineTemplate(comptime template_spec: TemplateSpec) type {
    validateTemplateSpec(template_spec);

    return struct {
        pub const descriptor = schema.TemplateDescriptor{
            .key = template_spec.key,
            .label = template_spec.label,
            .package_kind = .folding_carton,
            .numeric_params = template_spec.numeric_params,
            .select_params = template_spec.select_params,
        };
        pub const spec = template_spec;

        pub const Instance = struct {
            allocator: std.mem.Allocator,
            panel_boundary_segments: [countPanelBoundarySegments(template_spec)]types.PathSeg,
            panel_content_segments: [countPanelContentSegments(template_spec)]types.PathSeg,
            panels: [template_spec.panels.len]types.Panel,
            folds: [template_spec.folds.len]types.Fold,
            linework_segments: [countLineworkSegments(template_spec)]types.PathSeg,
            linework: [template_spec.linework.len]types.StyledPath2D,
            folding_carton: package.FoldingCartonModel,

            pub fn deinit(self: *Instance) void {
                self.folding_carton.deinit(self.allocator);
                self.allocator.destroy(self);
            }

            pub fn setContents(self: *Instance, contents: []types.PanelContentPlacement) !void {
                try self.folding_carton.setContents(self.allocator, contents);
            }

            pub fn buildDrawing2D(
                self: *Instance,
                allocator: std.mem.Allocator,
            ) !package.Drawing2DResult {
                return self.folding_carton.buildDrawing2D(allocator);
            }

            pub fn buildPreview3D(
                self: *Instance,
                allocator: std.mem.Allocator,
            ) !package.Preview3DResult {
                return self.folding_carton.buildPreview3D(allocator);
            }
        };

        pub fn create(
            allocator: std.mem.Allocator,
            numeric_params: []const schema.NumericParamValue,
            select_params: []const schema.SelectParamValue,
        ) !*Instance {
            _ = select_params;

            // Resolve variables in declaration order (each can reference params + earlier vars)
            var resolved_vars: [template_spec.variables.len]f64 = undefined;
            inline for (template_spec.variables, 0..) |_, i| {
                const partial = ExprResolver{
                    .numeric_params = numeric_params,
                    .param_defs = template_spec.numeric_params,
                    .var_defs = template_spec.variables[0..i],
                    .resolved_vars = resolved_vars[0..i],
                };
                resolved_vars[i] = try partial.resolveScalar(.{ .expr = template_spec.variables[i].expr });
            }

            const resolve = ExprResolver{
                .numeric_params = numeric_params,
                .param_defs = template_spec.numeric_params,
                .var_defs = template_spec.variables,
                .resolved_vars = &resolved_vars,
            };
            const transform = try resolveTransform(template_spec, resolve);

            const instance = try allocator.create(Instance);
            errdefer allocator.destroy(instance);
            instance.* = undefined;
            instance.allocator = allocator;

            try buildPanelSegments(template_spec, resolve, transform, &instance.panel_boundary_segments);
            try buildContentSegments(template_spec, resolve, transform, &instance.panel_content_segments);
            try buildPanels(
                template_spec,
                transform,
                &instance.panel_boundary_segments,
                &instance.panel_content_segments,
                &instance.panels,
            );
            try buildFolds(template_spec, resolve, &instance.folds);
            try buildLineworkSegments(template_spec, resolve, transform, &instance.linework_segments);
            buildLinework(template_spec, &instance.linework_segments, &instance.linework);

            instance.folding_carton = package.FoldingCartonModel.init(
                &instance.panels,
                &instance.folds,
                &instance.linework,
            );
            return instance;
        }
    };
}

// ── Resolver bridging ────────────────────────────────────────────────

const ExprResolver = struct {
    numeric_params: []const schema.NumericParamValue,
    param_defs: []const schema.NumericParamDef,
    var_defs: []const VariableDef,
    resolved_vars: []const f64,

    fn lookupName(self: *const ExprResolver, name: []const u8) ?f64 {
        for (self.var_defs, 0..) |vd, i| {
            if (std.mem.eql(u8, vd.name, name)) return self.resolved_vars[i];
        }
        for (self.numeric_params) |param| {
            if (std.mem.eql(u8, param.key, name)) return param.value;
        }
        for (self.param_defs) |param_def| {
            if (std.mem.eql(u8, param_def.key, name)) return param_def.default_value;
        }
        return null;
    }

    fn toExprResolver(self: *const ExprResolver) expr.Resolver {
        return .{
            .context = @ptrCast(self),
            .resolve_fn = @ptrCast(&lookupName),
        };
    }

    fn resolveScalar(self: *const ExprResolver, scalar: RuntimeScalarSpec) !f64 {
        if (scalar.expr) |expr_str| {
            return expr.evaluate(expr_str, self.toExprResolver()) catch return error.InvalidExpression;
        }
        return scalar.value;
    }

    fn resolveVec2(self: *const ExprResolver, vec: RuntimeVec2Spec) !types.Vec2 {
        return .{
            .x = try self.resolveScalar(vec.x),
            .y = try self.resolveScalar(vec.y),
        };
    }
};

// ── Validation ───────────────────────────────────────────────────────

fn validateTemplateSpec(comptime template_spec: TemplateSpec) void {
    @setEvalBranchQuota(200000);
    if (template_spec.package_kind != .folding_carton) {
        @compileError(std.fmt.comptimePrint(
            "compiled_spec only supports package_kind=.folding_carton, got .{s}",
            .{@tagName(template_spec.package_kind)},
        ));
    }

    inline for (template_spec.numeric_params, 0..) |param, index| {
        inline for (template_spec.numeric_params[index + 1 ..]) |other_param| {
            if (std.mem.eql(u8, param.key, other_param.key)) {
                @compileError(std.fmt.comptimePrint(
                    "duplicate numeric param key \"{s}\" in template spec",
                    .{param.key},
                ));
            }
        }
    }

    // Validate variables
    inline for (template_spec.variables, 0..) |var_def, var_index| {
        // Variable name must not collide with numeric params
        inline for (template_spec.numeric_params) |param| {
            if (std.mem.eql(u8, var_def.name, param.key)) {
                @compileError(std.fmt.comptimePrint(
                    "variable \"{s}\" collides with numeric param of the same name",
                    .{var_def.name},
                ));
            }
        }
        // Variable name must not collide with other variables
        inline for (template_spec.variables[var_index + 1 ..]) |other_var| {
            if (std.mem.eql(u8, var_def.name, other_var.name)) {
                @compileError(std.fmt.comptimePrint(
                    "duplicate variable name \"{s}\"",
                    .{var_def.name},
                ));
            }
        }
        // Variable expr can reference params and earlier variables
        const identifiers = expr.extractIdentifiers(var_def.expr);
        inline for (identifiers) |name| {
            validateReferencedName(template_spec, template_spec.variables[0..var_index], name, std.fmt.comptimePrint(
                "variables[{d}] (\"{s}\")",
                .{ var_index, var_def.name },
            ));
        }
    }

    if (template_spec.panels.len == 0) {
        @compileError("template spec must declare at least one panel");
    }

    if (template_spec.normalization) |normalization| {
        if (normalization.target_size) |target_size| {
            validateRuntimeScalar(template_spec, target_size.x, "normalization.target_size.x");
            validateRuntimeScalar(template_spec, target_size.y, "normalization.target_size.y");
        }
        validateRuntimeScalar(template_spec, normalization.target_origin.x, "normalization.target_origin.x");
        validateRuntimeScalar(template_spec, normalization.target_origin.y, "normalization.target_origin.y");
    }

    inline for (template_spec.panels, 0..) |panel_spec, panel_index| {
        if (panel_spec.boundary.len == 0) {
            @compileError(std.fmt.comptimePrint(
                "panel {d} has an empty boundary",
                .{panel_index},
            ));
        }

        inline for (panel_spec.boundary, 0..) |segment, segment_index| {
            validatePathSegment(template_spec, segment, std.fmt.comptimePrint(
                "panels[{d}].boundary[{d}]",
                .{ panel_index, segment_index },
            ));
        }

        if (panel_spec.content_region) |content_region| {
            if (content_region.len == 0) {
                @compileError(std.fmt.comptimePrint(
                    "panel {d} has an empty content_region",
                    .{panel_index},
                ));
            }

            inline for (content_region, 0..) |segment, segment_index| {
                validatePathSegment(template_spec, segment, std.fmt.comptimePrint(
                    "panels[{d}].content_region[{d}]",
                    .{ panel_index, segment_index },
                ));
            }
        }

        inline for (template_spec.panels[panel_index + 1 ..]) |other_panel| {
            if (other_panel.id == panel_spec.id) {
                @compileError(std.fmt.comptimePrint(
                    "duplicate panel id {d} in template spec",
                    .{panel_spec.id},
                ));
            }
        }
    }

    inline for (template_spec.folds, 0..) |fold_spec, fold_index| {
        if (!hasPanelId(template_spec, fold_spec.from_panel_id)) {
            @compileError(std.fmt.comptimePrint(
                "fold {d} references missing from_panel_id {d}",
                .{ fold_index, fold_spec.from_panel_id },
            ));
        }
        if (!hasPanelId(template_spec, fold_spec.to_panel_id)) {
            @compileError(std.fmt.comptimePrint(
                "fold {d} references missing to_panel_id {d}",
                .{ fold_index, fold_spec.to_panel_id },
            ));
        }

        if (foldSpecSegmentLen(template_spec, fold_spec.from_panel_id) <= fold_spec.from_segment_index) {
            @compileError(std.fmt.comptimePrint(
                "fold {d} uses from_segment_index {d} outside panel {d} boundary",
                .{ fold_index, fold_spec.from_segment_index, fold_spec.from_panel_id },
            ));
        }
        if (foldSpecSegmentLen(template_spec, fold_spec.to_panel_id) <= fold_spec.to_segment_index) {
            @compileError(std.fmt.comptimePrint(
                "fold {d} uses to_segment_index {d} outside panel {d} boundary",
                .{ fold_index, fold_spec.to_segment_index, fold_spec.to_panel_id },
            ));
        }

        if (fold_spec.angle_expr) |angle_expr_str| {
            validateExprIdentifiers(template_spec, angle_expr_str, std.fmt.comptimePrint(
                "folds[{d}].angle_expr",
                .{fold_index},
            ));
        }
    }

    inline for (template_spec.linework, 0..) |line_spec, line_index| {
        if (line_spec.segments.len == 0) {
            @compileError(std.fmt.comptimePrint(
                "linework {d} has no segments",
                .{line_index},
            ));
        }

        inline for (line_spec.segments, 0..) |segment, segment_index| {
            validatePathSegment(template_spec, segment, std.fmt.comptimePrint(
                "linework[{d}].segments[{d}]",
                .{ line_index, segment_index },
            ));
        }
    }
}

fn validateRuntimeScalar(
    comptime template_spec: TemplateSpec,
    scalar: RuntimeScalarSpec,
    comptime field_name: []const u8,
) void {
    if (scalar.expr) |expr_str| {
        validateExprIdentifiers(template_spec, expr_str, field_name);
    }
}

fn validateRuntimeVec2(
    comptime template_spec: TemplateSpec,
    vec: RuntimeVec2Spec,
    comptime field_name: []const u8,
) void {
    validateRuntimeScalar(template_spec, vec.x, field_name ++ ".x");
    validateRuntimeScalar(template_spec, vec.y, field_name ++ ".y");
}

fn validateExprIdentifiers(
    comptime template_spec: TemplateSpec,
    comptime expr_str: []const u8,
    comptime field_name: []const u8,
) void {
    const identifiers = expr.extractIdentifiers(expr_str);
    inline for (identifiers) |name| {
        validateReferencedName(template_spec, template_spec.variables, name, field_name);
    }
}

fn validateReferencedName(
    comptime template_spec: TemplateSpec,
    comptime visible_vars: []const VariableDef,
    comptime name: []const u8,
    comptime field_name: []const u8,
) void {
    inline for (template_spec.numeric_params) |param| {
        if (std.mem.eql(u8, param.key, name)) return;
    }
    inline for (visible_vars) |vd| {
        if (std.mem.eql(u8, vd.name, name)) return;
    }

    @compileError(std.fmt.comptimePrint(
        "{s} references unknown identifier \"{s}\"",
        .{ field_name, name },
    ));
}

fn validatePathSegment(comptime template_spec: TemplateSpec, comptime segment: PathSegmentSpec, comptime field_name: []const u8) void {
    switch (segment.kind) {
        .line => {
            if (segment.from == null or segment.to == null) {
                @compileError(std.fmt.comptimePrint(
                    "{s} must provide from/to for a line segment",
                    .{field_name},
                ));
            }
            validateRuntimeVec2(template_spec, segment.from.?, field_name ++ ".from");
            validateRuntimeVec2(template_spec, segment.to.?, field_name ++ ".to");
        },
        .arc => {
            if (segment.center == null or
                segment.radius == null or
                segment.start_angle == null or
                segment.end_angle == null)
            {
                @compileError(std.fmt.comptimePrint(
                    "{s} must provide center/radius/start_angle/end_angle for an arc segment",
                    .{field_name},
                ));
            }
            validateRuntimeVec2(template_spec, segment.center.?, field_name ++ ".center");
            validateRuntimeScalar(template_spec, segment.radius.?, field_name ++ ".radius");
            validateRuntimeScalar(template_spec, segment.start_angle.?, field_name ++ ".start_angle");
            validateRuntimeScalar(template_spec, segment.end_angle.?, field_name ++ ".end_angle");
        },
        .bezier => {
            if (segment.p0 == null or segment.p1 == null or segment.p2 == null or segment.p3 == null) {
                @compileError(std.fmt.comptimePrint(
                    "{s} must provide p0/p1/p2/p3 for a bezier segment",
                    .{field_name},
                ));
            }
            validateRuntimeVec2(template_spec, segment.p0.?, field_name ++ ".p0");
            validateRuntimeVec2(template_spec, segment.p1.?, field_name ++ ".p1");
            validateRuntimeVec2(template_spec, segment.p2.?, field_name ++ ".p2");
            validateRuntimeVec2(template_spec, segment.p3.?, field_name ++ ".p3");
        },
    }
}

fn hasPanelId(comptime template_spec: TemplateSpec, target_panel_id: types.PanelId) bool {
    inline for (template_spec.panels) |panel_spec| {
        if (panel_spec.id == target_panel_id) return true;
    }
    return false;
}

fn foldSpecSegmentLen(comptime template_spec: TemplateSpec, target_panel_id: types.PanelId) usize {
    inline for (template_spec.panels) |panel_spec| {
        if (panel_spec.id == target_panel_id) return panel_spec.boundary.len;
    }
    return 0;
}

fn countPanelBoundarySegments(comptime template_spec: TemplateSpec) usize {
    var total: usize = 0;
    inline for (template_spec.panels) |panel_spec| {
        total += panel_spec.boundary.len;
    }
    return total;
}

fn countPanelContentSegments(comptime template_spec: TemplateSpec) usize {
    var total: usize = 0;
    inline for (template_spec.panels) |panel_spec| {
        if (panel_spec.content_region) |content_region| {
            total += content_region.len;
        }
    }
    return total;
}

fn countLineworkSegments(comptime template_spec: TemplateSpec) usize {
    var total: usize = 0;
    inline for (template_spec.linework) |line_spec| {
        total += line_spec.segments.len;
    }
    return total;
}

// ── Transform resolution ─────────────────────────────────────────────

fn resolveTransform(
    comptime template_spec: TemplateSpec,
    resolve: ExprResolver,
) !TransformContext {
    const normalization = template_spec.normalization orelse return .{};

    const source_bounds = normalization.source_bounds orelse computeTemplateBounds(template_spec);
    if (source_bounds.size.x <= 0 or source_bounds.size.y <= 0) return error.InvalidNormalizationBounds;

    const target_origin = types.Vec2{
        .x = try resolve.resolveScalar(normalization.target_origin.x),
        .y = try resolve.resolveScalar(normalization.target_origin.y),
    };

    const target_size = if (normalization.target_size) |target_size_spec|
        types.Vec2{
            .x = try resolve.resolveScalar(target_size_spec.x),
            .y = try resolve.resolveScalar(target_size_spec.y),
        }
    else
        types.Vec2{ .x = source_bounds.size.x, .y = source_bounds.size.y };

    if (target_size.x <= 0 or target_size.y <= 0) return error.InvalidNormalizationTargetSize;

    var scale_x = target_size.x / source_bounds.size.x;
    var scale_y = target_size.y / source_bounds.size.y;
    if (normalization.scale_mode == .uniform) {
        const uniform_scale = @min(scale_x, scale_y);
        scale_x = uniform_scale;
        scale_y = uniform_scale;
    }

    return .{
        .mode = .normalized,
        .source_bounds = .{
            .min_x = source_bounds.origin.x,
            .min_y = source_bounds.origin.y,
            .max_x = source_bounds.origin.x + source_bounds.size.x,
            .max_y = source_bounds.origin.y + source_bounds.size.y,
        },
        .target_origin = target_origin,
        .scale_x = scale_x,
        .scale_y = scale_y,
        .flip_y = normalization.flip_y,
        .scale_mode = normalization.scale_mode,
    };
}

fn computeTemplateBounds(comptime template_spec: TemplateSpec) BoundsSpec {
    var min_x = std.math.inf(f64);
    var min_y = std.math.inf(f64);
    var max_x = -std.math.inf(f64);
    var max_y = -std.math.inf(f64);

    inline for (template_spec.panels) |panel| {
        inline for (panel.boundary) |segment| {
            includeSpecSegmentBounds(&min_x, &min_y, &max_x, &max_y, segment);
        }
        if (panel.content_region) |content_region| {
            inline for (content_region) |segment| {
                includeSpecSegmentBounds(&min_x, &min_y, &max_x, &max_y, segment);
            }
        }
    }
    inline for (template_spec.linework) |linework| {
        inline for (linework.segments) |segment| {
            includeSpecSegmentBounds(&min_x, &min_y, &max_x, &max_y, segment);
        }
    }

    return .{
        .origin = .{ .x = min_x, .y = min_y },
        .size = .{ .x = max_x - min_x, .y = max_y - min_y },
    };
}

fn specScalarValue(scalar: RuntimeScalarSpec) f64 {
    return scalar.value;
}

fn specVec2Value(vec: RuntimeVec2Spec) Vec2Spec {
    return .{ .x = specScalarValue(vec.x), .y = specScalarValue(vec.y) };
}

fn includeSpecSegmentBounds(
    min_x: *f64,
    min_y: *f64,
    max_x: *f64,
    max_y: *f64,
    segment: PathSegmentSpec,
) void {
    switch (segment.kind) {
        .line => {
            includeSpecPoint(min_x, min_y, max_x, max_y, specVec2Value(segment.from.?));
            includeSpecPoint(min_x, min_y, max_x, max_y, specVec2Value(segment.to.?));
        },
        .arc => {
            const center = specVec2Value(segment.center.?);
            const radius = specScalarValue(segment.radius.?);
            includeArcBounds(
                min_x,
                min_y,
                max_x,
                max_y,
                center,
                radius,
                specScalarValue(segment.start_angle.?),
                specScalarValue(segment.end_angle.?),
                segment.clockwise,
            );
        },
        .bezier => {
            includeSpecPoint(min_x, min_y, max_x, max_y, specVec2Value(segment.p0.?));
            includeSpecPoint(min_x, min_y, max_x, max_y, specVec2Value(segment.p1.?));
            includeSpecPoint(min_x, min_y, max_x, max_y, specVec2Value(segment.p2.?));
            includeSpecPoint(min_x, min_y, max_x, max_y, specVec2Value(segment.p3.?));
        },
    }
}

fn includeArcBounds(
    min_x: *f64,
    min_y: *f64,
    max_x: *f64,
    max_y: *f64,
    center: Vec2Spec,
    radius: f64,
    start_angle: f64,
    end_angle: f64,
    clockwise: bool,
) void {
    includeSpecPoint(min_x, min_y, max_x, max_y, pointOnCircleSpec(center, radius, start_angle));
    includeSpecPoint(min_x, min_y, max_x, max_y, pointOnCircleSpec(center, radius, end_angle));

    inline for ([_]f64{ 0, std.math.pi / 2.0, std.math.pi, std.math.pi * 1.5 }) |angle| {
        if (angleOnArc(angle, start_angle, end_angle, clockwise)) {
            includeSpecPoint(min_x, min_y, max_x, max_y, pointOnCircleSpec(center, radius, angle));
        }
    }
}

fn angleOnArc(angle: f64, start_angle: f64, end_angle: f64, clockwise: bool) bool {
    const full_turn = std.math.pi * 2.0;
    const normalized_angle = normalizeAngle(angle);
    const normalized_start = normalizeAngle(start_angle);
    const normalized_end = normalizeAngle(end_angle);

    if (!clockwise) {
        const sweep = @mod(normalized_end - normalized_start + full_turn, full_turn);
        const delta = @mod(normalized_angle - normalized_start + full_turn, full_turn);
        return delta <= sweep + 1e-9;
    }

    const sweep = @mod(normalized_start - normalized_end + full_turn, full_turn);
    const delta = @mod(normalized_start - normalized_angle + full_turn, full_turn);
    return delta <= sweep + 1e-9;
}

fn normalizeAngle(angle: f64) f64 {
    const full_turn = std.math.pi * 2.0;
    return @mod(angle + full_turn, full_turn);
}

fn pointOnCircleSpec(center: Vec2Spec, radius: f64, angle: f64) Vec2Spec {
    return .{
        .x = center.x + std.math.cos(angle) * radius,
        .y = center.y + std.math.sin(angle) * radius,
    };
}

// ── Build functions ──────────────────────────────────────────────────

fn buildPanelSegments(
    comptime template_spec: TemplateSpec,
    resolve: ExprResolver,
    transform: TransformContext,
    destination: *[countPanelBoundarySegments(template_spec)]types.PathSeg,
) !void {
    var cursor: usize = 0;
    inline for (template_spec.panels) |panel_spec| {
        inline for (panel_spec.boundary) |segment_spec| {
            destination[cursor] = try pathSegmentFromSpec(segment_spec, resolve, transform);
            cursor += 1;
        }
    }
}

fn buildContentSegments(
    comptime template_spec: TemplateSpec,
    resolve: ExprResolver,
    transform: TransformContext,
    destination: *[countPanelContentSegments(template_spec)]types.PathSeg,
) !void {
    var cursor: usize = 0;
    inline for (template_spec.panels) |panel_spec| {
        if (panel_spec.content_region) |content_region| {
            inline for (content_region) |segment_spec| {
                destination[cursor] = try pathSegmentFromSpec(segment_spec, resolve, transform);
                cursor += 1;
            }
        }
    }
}

fn buildPanels(
    comptime template_spec: TemplateSpec,
    transform: TransformContext,
    boundary_segments: *const [countPanelBoundarySegments(template_spec)]types.PathSeg,
    content_segments: *const [countPanelContentSegments(template_spec)]types.PathSeg,
    panels_out: *[template_spec.panels.len]types.Panel,
) !void {
    var boundary_cursor: usize = 0;
    var content_cursor: usize = 0;

    inline for (template_spec.panels, 0..) |panel_spec, panel_index| {
        const boundary_len = panel_spec.boundary.len;
        const boundary_path = types.Path2D.baseBy(
            boundary_segments[boundary_cursor .. boundary_cursor + boundary_len],
        );
        boundary_cursor += boundary_len;

        const content_region_path = if (panel_spec.content_region) |content_region| blk: {
            const content_len = content_region.len;
            const path = types.Path2D.baseBy(
                content_segments[content_cursor .. content_cursor + content_len],
            );
            content_cursor += content_len;
            break :blk path;
        } else boundary_path;

        var panel = try types.Panel.withGeometryBy(
            boundary_path,
            panel_spec.id,
            resolveSurfaceFrame(panel_spec, boundary_path, transform),
            content_region_path,
            resolveOutsideNormal(panel_spec),
        );
        panel.accepts_content = panel_spec.accepts_content;
        panel.name = panel_spec.name;
        panels_out[panel_index] = panel;
    }
}

fn buildFolds(
    comptime template_spec: TemplateSpec,
    resolve: ExprResolver,
    folds_out: *[template_spec.folds.len]types.Fold,
) !void {
    inline for (template_spec.folds, 0..) |fold_spec, fold_index| {
        folds_out[fold_index] = .{
            .from_panel_id = fold_spec.from_panel_id,
            .to_panel_id = fold_spec.to_panel_id,
            .axis = .{
                .from_edge = .{
                    .panel_id = fold_spec.from_panel_id,
                    .segment_index = fold_spec.from_segment_index,
                },
                .to_edge = .{
                    .panel_id = fold_spec.to_panel_id,
                    .segment_index = fold_spec.to_segment_index,
                },
            },
            .angle_rad = try resolveFoldAngle(resolve, fold_spec),
            .direction = fold_spec.direction,
        };
    }
}

fn buildLineworkSegments(
    comptime template_spec: TemplateSpec,
    resolve: ExprResolver,
    transform: TransformContext,
    destination: *[countLineworkSegments(template_spec)]types.PathSeg,
) !void {
    var cursor: usize = 0;
    inline for (template_spec.linework) |line_spec| {
        inline for (line_spec.segments) |segment_spec| {
            destination[cursor] = try pathSegmentFromSpec(segment_spec, resolve, transform);
            cursor += 1;
        }
    }
}

fn buildLinework(
    comptime template_spec: TemplateSpec,
    segments: *const [countLineworkSegments(template_spec)]types.PathSeg,
    linework_out: *[template_spec.linework.len]types.StyledPath2D,
) void {
    var cursor: usize = 0;
    inline for (template_spec.linework, 0..) |line_spec, line_index| {
        const segment_len = line_spec.segments.len;
        linework_out[line_index] = .{
            .path = .{
                .closed = line_spec.closed,
                .segments = segments[cursor .. cursor + segment_len],
            },
            .role = line_spec.role,
            .stroke_style = line_spec.stroke_style orelse defaultStrokeStyle(line_spec.role),
        };
        cursor += segment_len;
    }
}

fn resolveFoldAngle(
    resolve: ExprResolver,
    fold_spec: FoldSpec,
) !f64 {
    if (fold_spec.angle_expr) |angle_expr_str| {
        return resolve.resolveScalar(.{ .expr = angle_expr_str });
    }
    return fold_spec.angle_rad;
}

fn pathSegmentFromSpec(segment: PathSegmentSpec, resolve: ExprResolver, transform: TransformContext) !types.PathSeg {
    return switch (segment.kind) {
        .line => .{
            .Line = .{
                .from = transform.point(try resolve.resolveVec2(segment.from.?)),
                .to = transform.point(try resolve.resolveVec2(segment.to.?)),
            },
        },
        .bezier => .{
            .Bezier = .{
                .p0 = transform.point(try resolve.resolveVec2(segment.p0.?)),
                .p1 = transform.point(try resolve.resolveVec2(segment.p1.?)),
                .p2 = transform.point(try resolve.resolveVec2(segment.p2.?)),
                .p3 = transform.point(try resolve.resolveVec2(segment.p3.?)),
            },
        },
        .arc => try arcSegmentFromSpec(segment, resolve, transform),
    };
}

fn arcSegmentFromSpec(segment: PathSegmentSpec, resolve: ExprResolver, transform: TransformContext) !types.PathSeg {
    const center = try resolve.resolveVec2(segment.center.?);
    const radius = try resolve.resolveScalar(segment.radius.?);
    const start_angle = try resolve.resolveScalar(segment.start_angle.?);
    const end_angle = try resolve.resolveScalar(segment.end_angle.?);

    if (transform.mode == .normalized and transform.scale_mode == .independent) {
        if (!std.math.approxEqAbs(f64, transform.scale_x, transform.scale_y, 1e-9)) {
            return error.NonUniformArcScale;
        }
    }

    const transformed_center = transform.point(center);
    const transformed_start = transform.point(pointOnCircle(center, radius, start_angle));
    const transformed_end = transform.point(pointOnCircle(center, radius, end_angle));
    const clockwise = if (transform.mode == .normalized and transform.flip_y)
        !segment.clockwise
    else
        segment.clockwise;

    return .{
        .Arc = .{
            .center = transformed_center,
            .radius = radius * transform.arcRadiusScale(),
            .startAngle = std.math.atan2(
                transformed_start.y - transformed_center.y,
                transformed_start.x - transformed_center.x,
            ),
            .endAngle = std.math.atan2(
                transformed_end.y - transformed_center.y,
                transformed_end.x - transformed_center.x,
            ),
            .clockwise = clockwise,
        },
    };
}

fn resolveSurfaceFrame(
    panel_spec: PanelSpec,
    boundary_path: types.Path2D,
    transform: TransformContext,
) types.SurfaceFrame2D {
    if (panel_spec.surface_frame) |surface_frame| {
        return .{
            .origin = transform.point(vec2FromSpec(surface_frame.origin)),
            .u_axis = transform.vector(vec2FromSpec(surface_frame.u_axis)),
            .v_axis = transform.vector(vec2FromSpec(surface_frame.v_axis)),
        };
    }

    return defaultSurfaceFrame(boundary_path);
}

fn resolveOutsideNormal(panel_spec: PanelSpec) types.Vec3 {
    if (panel_spec.outside_normal) |outside_normal| {
        return vec3FromSpec(outside_normal);
    }

    return .{ .x = 0, .y = 0, .z = 1 };
}

fn defaultStrokeStyle(role: types.LineRole) types.StrokeStyle {
    return switch (role) {
        .cut => .solid,
        .bleed => .solid,
        .safe => .dashed,
        .fold => .dashed,
        .score => .dashed,
        .guide => .dotted,
    };
}

fn defaultSurfaceFrame(boundary_path: types.Path2D) types.SurfaceFrame2D {
    var min_x = std.math.inf(f64);
    var min_y = std.math.inf(f64);
    var max_x = -std.math.inf(f64);
    var max_y = -std.math.inf(f64);

    for (boundary_path.segments) |segment| {
        switch (segment) {
            .Line => |line| {
                includePoint(&min_x, &min_y, &max_x, &max_y, line.from);
                includePoint(&min_x, &min_y, &max_x, &max_y, line.to);
            },
            .Arc => |arc| includeRuntimeArcBounds(&min_x, &min_y, &max_x, &max_y, arc),
            .Bezier => |bezier| {
                includePoint(&min_x, &min_y, &max_x, &max_y, bezier.p0);
                includePoint(&min_x, &min_y, &max_x, &max_y, bezier.p1);
                includePoint(&min_x, &min_y, &max_x, &max_y, bezier.p2);
                includePoint(&min_x, &min_y, &max_x, &max_y, bezier.p3);
            },
        }
    }

    return .{
        .origin = .{ .x = min_x, .y = min_y },
        .u_axis = .{ .x = max_x - min_x, .y = 0 },
        .v_axis = .{ .x = 0, .y = max_y - min_y },
    };
}

fn includeRuntimeArcBounds(
    min_x: *f64,
    min_y: *f64,
    max_x: *f64,
    max_y: *f64,
    arc: types.ArcSeg,
) void {
    includePoint(min_x, min_y, max_x, max_y, pointOnCircle(arc.center, arc.radius, arc.startAngle));
    includePoint(min_x, min_y, max_x, max_y, pointOnCircle(arc.center, arc.radius, arc.endAngle));

    inline for ([_]f64{ 0, std.math.pi / 2.0, std.math.pi, std.math.pi * 1.5 }) |angle| {
        if (angleOnArc(angle, arc.startAngle, arc.endAngle, arc.clockwise)) {
            includePoint(min_x, min_y, max_x, max_y, pointOnCircle(arc.center, arc.radius, angle));
        }
    }
}

fn includePoint(
    min_x: *f64,
    min_y: *f64,
    max_x: *f64,
    max_y: *f64,
    point_val: types.Vec2,
) void {
    min_x.* = @min(min_x.*, point_val.x);
    min_y.* = @min(min_y.*, point_val.y);
    max_x.* = @max(max_x.*, point_val.x);
    max_y.* = @max(max_y.*, point_val.y);
}

fn includeSpecPoint(
    min_x: *f64,
    min_y: *f64,
    max_x: *f64,
    max_y: *f64,
    point_val: Vec2Spec,
) void {
    min_x.* = @min(min_x.*, point_val.x);
    min_y.* = @min(min_y.*, point_val.y);
    max_x.* = @max(max_x.*, point_val.x);
    max_y.* = @max(max_y.*, point_val.y);
}

fn pointOnCircle(center: types.Vec2, radius: f64, angle: f64) types.Vec2 {
    return .{
        .x = center.x + std.math.cos(angle) * radius,
        .y = center.y + std.math.sin(angle) * radius,
    };
}

fn vec2FromSpec(value: Vec2Spec) types.Vec2 {
    return .{ .x = value.x, .y = value.y };
}

fn vec3FromSpec(value: Vec3Spec) types.Vec3 {
    return .{ .x = value.x, .y = value.y, .z = value.z };
}

// ── Tests ────────────────────────────────────────────────────────────

test "compiled_spec builds fixed geometry template from comptime data" {
    const Template = defineTemplate(.{
        .key = "folding_carton.inline_spec_test",
        .label = "Inline Spec Test",
        .panels = &.{
            .{
                .id = 0,
                .boundary = &.{
                    .{ .from = cv2(0, 0), .to = cv2(20, 0) },
                    .{ .from = cv2(20, 0), .to = cv2(20, 10) },
                    .{ .from = cv2(20, 10), .to = cv2(0, 10) },
                    .{ .from = cv2(0, 10), .to = cv2(0, 0) },
                },
            },
        },
        .linework = &.{
            .{
                .role = .cut,
                .closed = true,
                .segments = &.{
                    .{ .from = cv2(0, 0), .to = cv2(20, 0) },
                    .{ .from = cv2(20, 0), .to = cv2(20, 10) },
                    .{ .from = cv2(20, 10), .to = cv2(0, 10) },
                    .{ .from = cv2(0, 10), .to = cv2(0, 0) },
                },
            },
        },
    });

    var instance = try Template.create(std.testing.allocator, &.{}, &.{});
    defer instance.deinit();

    var drawing = try instance.buildDrawing2D(std.testing.allocator);
    defer drawing.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("folding_carton.inline_spec_test", Template.descriptor.key);
    try std.testing.expectEqual(@as(usize, 1), drawing.linework.len);
    try std.testing.expect(drawing.linework[0].path.closed);
}

test "compiled_spec normalizes relative coordinates and resolves runtime params" {
    const Template = defineTemplate(.{
        .key = "folding_carton.normalized_test",
        .label = "Normalized Test",
        .numeric_params = &.{
            .{ .key = "target_width", .label = "Target Width", .default_value = 120, .min_value = 1 },
            .{ .key = "target_height", .label = "Target Height", .default_value = 60, .min_value = 1 },
            .{ .key = "fold_angle_rad", .label = "Fold Angle", .default_value = std.math.pi / 2.0, .min_value = -std.math.pi, .max_value = std.math.pi },
        },
        .normalization = .{
            .target_size = .{
                .x = .{ .expr = "target_width" },
                .y = .{ .expr = "target_height" },
            },
        },
        .panels = &.{
            .{
                .id = 0,
                .boundary = &.{
                    .{ .from = cv2(0, 0), .to = cv2(1, 0) },
                    .{ .from = cv2(1, 0), .to = cv2(1, 1) },
                    .{ .from = cv2(1, 1), .to = cv2(0, 1) },
                    .{ .from = cv2(0, 1), .to = cv2(0, 0) },
                },
            },
            .{
                .id = 1,
                .boundary = &.{
                    .{ .from = cv2(1, 0), .to = cv2(2, 0) },
                    .{ .from = cv2(2, 0), .to = cv2(2, 1) },
                    .{ .from = cv2(2, 1), .to = cv2(1, 1) },
                    .{ .from = cv2(1, 1), .to = cv2(1, 0) },
                },
            },
        },
        .folds = &.{
            .{
                .from_panel_id = 0,
                .to_panel_id = 1,
                .from_segment_index = 1,
                .to_segment_index = 3,
                .angle_rad = 0,
                .angle_expr = "fold_angle_rad",
                .direction = .toward_inside,
            },
        },
    });

    var instance = try Template.create(std.testing.allocator, &.{
        .{ .key = "target_width", .value = 200 },
        .{ .key = "target_height", .value = 80 },
        .{ .key = "fold_angle_rad", .value = std.math.pi / 3.0 },
    }, &.{});
    defer instance.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 100), instance.panels[0].surface_frame.u_axis.x, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 80), instance.panels[0].surface_frame.v_axis.y, 1e-9);
    try std.testing.expectApproxEqAbs(std.math.pi / 3.0, instance.folds[0].angle_rad, 1e-9);
}

test "compiled_spec supports arc and bezier segments" {
    const Template = defineTemplate(.{
        .key = "folding_carton.curve_test",
        .label = "Curve Test",
        .panels = &.{
            .{
                .id = 0,
                .boundary = &.{
                    .{ .from = cv2(0, 0), .to = cv2(20, 0) },
                    .{
                        .kind = .arc,
                        .center = cv2(20, 10),
                        .radius = cs(10),
                        .start_angle = cs(-std.math.pi / 2.0),
                        .end_angle = cs(std.math.pi / 2.0),
                    },
                    .{ .from = cv2(20, 20), .to = cv2(0, 20) },
                    .{ .from = cv2(0, 20), .to = cv2(0, 0) },
                },
            },
        },
        .linework = &.{
            .{
                .role = .guide,
                .segments = &.{
                    .{
                        .kind = .bezier,
                        .p0 = cv2(0, 10),
                        .p1 = cv2(8, 0),
                        .p2 = cv2(12, 20),
                        .p3 = cv2(20, 10),
                    },
                },
            },
        },
    });

    var instance = try Template.create(std.testing.allocator, &.{}, &.{});
    defer instance.deinit();

    try std.testing.expect(instance.panels[0].boundary.segments[1] == .Arc);
    try std.testing.expect(instance.linework[0].path.segments[0] == .Bezier);
}

test "compiled_spec resolves parametric coordinate expressions" {
    const Template = defineTemplate(.{
        .key = "folding_carton.parametric_test",
        .label = "Parametric Test",
        .numeric_params = &.{
            .{ .key = "length", .label = "Length", .default_value = 95, .min_value = 1 },
            .{ .key = "width", .label = "Width", .default_value = 78, .min_value = 1 },
            .{ .key = "depth", .label = "Depth", .default_value = 28, .min_value = 1 },
        },
        .panels = &.{
            .{
                .id = 0,
                .boundary = &.{
                    .{ .from = cv2(0, 0), .to = .{ .x = .{ .expr = "length" }, .y = .{ .value = 0 } } },
                    .{ .from = .{ .x = .{ .expr = "length" }, .y = .{ .value = 0 } }, .to = .{ .x = .{ .expr = "length" }, .y = .{ .expr = "width" } } },
                    .{ .from = .{ .x = .{ .expr = "length" }, .y = .{ .expr = "width" } }, .to = .{ .x = .{ .value = 0 }, .y = .{ .expr = "width" } } },
                    .{ .from = .{ .x = .{ .value = 0 }, .y = .{ .expr = "width" } }, .to = cv2(0, 0) },
                },
            },
            .{
                .id = 1,
                .boundary = &.{
                    .{ .from = .{ .x = .{ .value = 0 }, .y = .{ .expr = "width" } }, .to = .{ .x = .{ .expr = "length" }, .y = .{ .expr = "width" } } },
                    .{ .from = .{ .x = .{ .expr = "length" }, .y = .{ .expr = "width" } }, .to = .{ .x = .{ .expr = "length" }, .y = .{ .expr = "width + depth" } } },
                    .{ .from = .{ .x = .{ .expr = "length" }, .y = .{ .expr = "width + depth" } }, .to = .{ .x = .{ .value = 0 }, .y = .{ .expr = "width + depth" } } },
                    .{ .from = .{ .x = .{ .value = 0 }, .y = .{ .expr = "width + depth" } }, .to = .{ .x = .{ .value = 0 }, .y = .{ .expr = "width" } } },
                },
            },
        },
        .folds = &.{
            .{
                .from_panel_id = 0,
                .to_panel_id = 1,
                .from_segment_index = 2,
                .to_segment_index = 0,
                .angle_rad = std.math.pi / 2.0,
                .direction = .toward_outside,
            },
        },
    });

    var instance = try Template.create(std.testing.allocator, &.{
        .{ .key = "length", .value = 100 },
        .{ .key = "width", .value = 80 },
        .{ .key = "depth", .value = 30 },
    }, &.{});
    defer instance.deinit();

    // Panel 0: base (0,0)-(100,80)
    try std.testing.expectApproxEqAbs(@as(f64, 100), instance.panels[0].surface_frame.u_axis.x, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 80), instance.panels[0].surface_frame.v_axis.y, 1e-9);

    // Panel 1: wall (0,80)-(100,110) — width + depth = 110
    try std.testing.expectApproxEqAbs(@as(f64, 100), instance.panels[1].surface_frame.u_axis.x, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 30), instance.panels[1].surface_frame.v_axis.y, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 80), instance.panels[1].surface_frame.origin.y, 1e-9);
}

test "compiled_spec resolves variables as derived values" {
    const Template = defineTemplate(.{
        .key = "folding_carton.variables_test",
        .label = "Variables Test",
        .numeric_params = &.{
            .{ .key = "length", .label = "Length", .default_value = 95, .min_value = 1 },
            .{ .key = "width", .label = "Width", .default_value = 78, .min_value = 1 },
            .{ .key = "depth", .label = "Depth", .default_value = 28, .min_value = 1 },
            .{ .key = "lid_length", .label = "Lid Length", .default_value = 52, .min_value = 1 },
        },
        .variables = &.{
            .{ .name = "y1", .expr = "width" },
            .{ .name = "y2", .expr = "width + depth" },
            .{ .name = "y3", .expr = "y2 + lid_length" },
        },
        .panels = &.{
            .{
                .id = 0,
                .boundary = &.{
                    .{ .from = cv2(0, 0), .to = .{ .x = .{ .expr = "length" }, .y = .{ .value = 0 } } },
                    .{ .from = .{ .x = .{ .expr = "length" }, .y = .{ .value = 0 } }, .to = .{ .x = .{ .expr = "length" }, .y = .{ .expr = "y1" } } },
                    .{ .from = .{ .x = .{ .expr = "length" }, .y = .{ .expr = "y1" } }, .to = .{ .x = .{ .value = 0 }, .y = .{ .expr = "y1" } } },
                    .{ .from = .{ .x = .{ .value = 0 }, .y = .{ .expr = "y1" } }, .to = cv2(0, 0) },
                },
            },
            .{
                .id = 1,
                .boundary = &.{
                    .{ .from = .{ .x = .{ .value = 0 }, .y = .{ .expr = "y1" } }, .to = .{ .x = .{ .expr = "length" }, .y = .{ .expr = "y1" } } },
                    .{ .from = .{ .x = .{ .expr = "length" }, .y = .{ .expr = "y1" } }, .to = .{ .x = .{ .expr = "length" }, .y = .{ .expr = "y2" } } },
                    .{ .from = .{ .x = .{ .expr = "length" }, .y = .{ .expr = "y2" } }, .to = .{ .x = .{ .value = 0 }, .y = .{ .expr = "y2" } } },
                    .{ .from = .{ .x = .{ .value = 0 }, .y = .{ .expr = "y2" } }, .to = .{ .x = .{ .value = 0 }, .y = .{ .expr = "y1" } } },
                },
            },
            .{
                .id = 2,
                .boundary = &.{
                    .{ .from = .{ .x = .{ .value = 0 }, .y = .{ .expr = "y2" } }, .to = .{ .x = .{ .expr = "length" }, .y = .{ .expr = "y2" } } },
                    .{ .from = .{ .x = .{ .expr = "length" }, .y = .{ .expr = "y2" } }, .to = .{ .x = .{ .expr = "length" }, .y = .{ .expr = "y3" } } },
                    .{ .from = .{ .x = .{ .expr = "length" }, .y = .{ .expr = "y3" } }, .to = .{ .x = .{ .value = 0 }, .y = .{ .expr = "y3" } } },
                    .{ .from = .{ .x = .{ .value = 0 }, .y = .{ .expr = "y3" } }, .to = .{ .x = .{ .value = 0 }, .y = .{ .expr = "y2" } } },
                },
            },
        },
        .folds = &.{
            .{
                .from_panel_id = 0,
                .to_panel_id = 1,
                .from_segment_index = 2,
                .to_segment_index = 0,
                .angle_rad = std.math.pi / 2.0,
                .direction = .toward_outside,
            },
            .{
                .from_panel_id = 1,
                .to_panel_id = 2,
                .from_segment_index = 2,
                .to_segment_index = 0,
                .angle_rad = std.math.pi / 2.0,
                .direction = .toward_outside,
            },
        },
    });

    // Use default params: length=95, width=78, depth=28, lid_length=52
    var instance = try Template.create(std.testing.allocator, &.{}, &.{});
    defer instance.deinit();

    // Panel 0: base (0,0)-(95,78) — y1 = width = 78
    try std.testing.expectApproxEqAbs(@as(f64, 95), instance.panels[0].surface_frame.u_axis.x, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 78), instance.panels[0].surface_frame.v_axis.y, 1e-9);

    // Panel 1: wall (0,78)-(95,106) — y2 = width + depth = 106
    try std.testing.expectApproxEqAbs(@as(f64, 78), instance.panels[1].surface_frame.origin.y, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 28), instance.panels[1].surface_frame.v_axis.y, 1e-9);

    // Panel 2: lid (0,106)-(95,158) — y3 = y2 + lid_length = 106 + 52 = 158
    try std.testing.expectApproxEqAbs(@as(f64, 106), instance.panels[2].surface_frame.origin.y, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 52), instance.panels[2].surface_frame.v_axis.y, 1e-9);

    // Verify with custom params
    var instance2 = try Template.create(std.testing.allocator, &.{
        .{ .key = "length", .value = 100 },
        .{ .key = "width", .value = 50 },
        .{ .key = "depth", .value = 20 },
        .{ .key = "lid_length", .value = 40 },
    }, &.{});
    defer instance2.deinit();

    // y1=50, y2=70, y3=110
    try std.testing.expectApproxEqAbs(@as(f64, 50), instance2.panels[0].surface_frame.v_axis.y, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 50), instance2.panels[1].surface_frame.origin.y, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 20), instance2.panels[1].surface_frame.v_axis.y, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 70), instance2.panels[2].surface_frame.origin.y, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 40), instance2.panels[2].surface_frame.v_axis.y, 1e-9);
}

test "compiled_spec resolves expressions with multiply and divide in arc radius" {
    // Panel: left edge 0..size, top/bottom horizontal, right side is an arc.
    // Arc center at (size, size/2), radius = size/2, goes from -pi/2 to pi/2.
    // So arc starts at (size, 0) and ends at (size, size) — boundary is continuous.
    const Template = defineTemplate(.{
        .key = "folding_carton.expr_arc_test",
        .label = "Expr Arc Test",
        .numeric_params = &.{
            .{ .key = "size", .label = "Size", .default_value = 40, .min_value = 1 },
        },
        .variables = &.{
            .{ .name = "half", .expr = "size / 2" },
        },
        .panels = &.{
            .{
                .id = 0,
                .boundary = &.{
                    .{ .from = cv2(0, 0), .to = .{ .x = .{ .expr = "size" }, .y = .{ .value = 0 } } },
                    .{
                        .kind = .arc,
                        .center = .{ .x = .{ .expr = "size" }, .y = .{ .expr = "half" } },
                        .radius = .{ .expr = "half" },
                        .start_angle = cs(-std.math.pi / 2.0),
                        .end_angle = cs(std.math.pi / 2.0),
                    },
                    .{ .from = .{ .x = .{ .expr = "size" }, .y = .{ .expr = "size" } }, .to = .{ .x = .{ .value = 0 }, .y = .{ .expr = "size" } } },
                    .{ .from = .{ .x = .{ .value = 0 }, .y = .{ .expr = "size" } }, .to = cv2(0, 0) },
                },
            },
        },
    });

    var instance = try Template.create(std.testing.allocator, &.{
        .{ .key = "size", .value = 60 },
    }, &.{});
    defer instance.deinit();

    // half = 30. Arc centered at (60, 30) with radius 30
    const arc = instance.panel_boundary_segments[1].Arc;
    try std.testing.expectApproxEqAbs(@as(f64, 60), arc.center.x, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 30), arc.center.y, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 30), arc.radius, 1e-9);
}

test "compiled_spec variables can be used in fold angle_expr" {
    const Template = defineTemplate(.{
        .key = "folding_carton.var_fold_test",
        .label = "Var Fold Test",
        .numeric_params = &.{
            .{ .key = "open_ratio", .label = "Open Ratio", .default_value = 0.5, .min_value = 0, .max_value = 1 },
        },
        .variables = &.{
            .{ .name = "lid_angle", .expr = "open_ratio * 3.14159" },
        },
        .panels = &.{
            .{
                .id = 0,
                .boundary = &.{
                    .{ .from = cv2(0, 0), .to = cv2(40, 0) },
                    .{ .from = cv2(40, 0), .to = cv2(40, 30) },
                    .{ .from = cv2(40, 30), .to = cv2(0, 30) },
                    .{ .from = cv2(0, 30), .to = cv2(0, 0) },
                },
            },
            .{
                .id = 1,
                .boundary = &.{
                    .{ .from = cv2(0, 30), .to = cv2(40, 30) },
                    .{ .from = cv2(40, 30), .to = cv2(40, 60) },
                    .{ .from = cv2(40, 60), .to = cv2(0, 60) },
                    .{ .from = cv2(0, 60), .to = cv2(0, 30) },
                },
            },
        },
        .folds = &.{
            .{
                .from_panel_id = 0,
                .to_panel_id = 1,
                .from_segment_index = 2,
                .to_segment_index = 0,
                .angle_rad = 0,
                .angle_expr = "lid_angle",
                .direction = .toward_outside,
            },
        },
    });

    var instance = try Template.create(std.testing.allocator, &.{
        .{ .key = "open_ratio", .value = 0.5 },
    }, &.{});
    defer instance.deinit();

    // lid_angle = 0.5 * 3.14159 ≈ pi/2
    try std.testing.expectApproxEqAbs(0.5 * 3.14159, instance.folds[0].angle_rad, 1e-4);
}
