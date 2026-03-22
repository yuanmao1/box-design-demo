const std = @import("std");

const PackageKind = enum { folding_carton };
const FoldDirection = enum { toward_outside, toward_inside };
const LineRole = enum { cut, bleed, safe, fold, score, guide };
const StrokeStyle = enum { solid, dashed, dotted };
const ScaleMode = enum { independent, uniform };
const SegmentKind = enum { line, arc, bezier };

const NumericParamDef = struct {
    key: []const u8,
    label: []const u8,
    default_value: f64,
    min_value: ?f64 = null,
    max_value: ?f64 = null,
};

const SelectOptionDef = struct {
    value: []const u8,
    label: []const u8,
};

const SelectParamDef = struct {
    key: []const u8,
    label: []const u8,
    default_value: []const u8,
    options: []const SelectOptionDef,
};

const VariableDef = struct {
    name: []const u8,
    expr: []const u8,
};

const Vec2Spec = struct {
    x: f64,
    y: f64,
};

const Vec3Spec = struct {
    x: f64,
    y: f64,
    z: f64,
};

const RuntimeScalarSpec = struct {
    value: f64 = 0,
    expr: ?[]const u8 = null,
};

const RuntimeVec2Spec = struct {
    x: RuntimeScalarSpec,
    y: RuntimeScalarSpec,
};

const SurfaceFrameSpec = struct {
    origin: Vec2Spec,
    u_axis: Vec2Spec,
    v_axis: Vec2Spec,
};

const BoundsSpec = struct {
    origin: Vec2Spec,
    size: Vec2Spec,
};

const NormalizeSpec = struct {
    source_bounds: ?BoundsSpec = null,
    target_origin: RuntimeVec2Spec = .{
        .x = .{ .value = 0 },
        .y = .{ .value = 0 },
    },
    target_size: ?RuntimeVec2Spec = null,
    flip_y: bool = false,
    scale_mode: ScaleMode = .independent,
};

const PathSegmentSpec = struct {
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

const PanelSpec = struct {
    name: []const u8,
    id: u16,
    boundary: []const PathSegmentSpec,
    content_region: ?[]const PathSegmentSpec = null,
    surface_frame: ?SurfaceFrameSpec = null,
    outside_normal: ?Vec3Spec = null,
    accepts_content: bool = true,
};

const FoldSpec = struct {
    from_panel: []const u8,
    to_panel: []const u8,
    from_segment_index: u16,
    to_segment_index: u16,
    angle_rad: f64,
    angle_expr: ?[]const u8 = null,
    direction: FoldDirection,
};

const LineworkSpec = struct {
    role: LineRole,
    stroke_style: ?StrokeStyle = null,
    closed: bool = false,
    segments: []const PathSegmentSpec,
};

const InputTemplate = struct {
    key: []const u8,
    label: []const u8,
    package_kind: PackageKind = .folding_carton,
    numeric_params: []const NumericParamDef = &.{},
    select_params: []const SelectParamDef = &.{},
    variables: []const VariableDef = &.{},
    normalization: ?NormalizeSpec = null,
    panels: []const PanelSpec,
    folds: []const FoldSpec = &.{},
    linework: []const LineworkSpec = &.{},
};

// ---------------------------------------------------------------------------
// Dynamic JSON parsing helpers
// ---------------------------------------------------------------------------
// Because segment coordinates can be plain numbers OR string expressions,
// Zig's typed parseFromSlice cannot handle them directly. We parse the full
// JSON as std.json.Value and convert manually.
// ---------------------------------------------------------------------------

const JsonParseError = error{
    InvalidTemplate,
    OutOfMemory,
};

fn jsonGetString(obj: std.json.Value, key: []const u8) ?[]const u8 {
    const val = obj.object.get(key) orelse return null;
    return switch (val) {
        .string => |s| s,
        else => null,
    };
}

fn jsonGetNumber(obj: std.json.Value, key: []const u8) ?f64 {
    const val = obj.object.get(key) orelse return null;
    return switch (val) {
        .float => |f| f,
        .integer => |i| @floatFromInt(i),
        else => null,
    };
}

fn jsonGetBool(obj: std.json.Value, key: []const u8) ?bool {
    const val = obj.object.get(key) orelse return null;
    return switch (val) {
        .bool => |b| b,
        else => null,
    };
}

fn jsonGetArray(obj: std.json.Value, key: []const u8) ?std.json.Array {
    const val = obj.object.get(key) orelse return null;
    return switch (val) {
        .array => |a| a,
        else => null,
    };
}

fn jsonGetObject(obj: std.json.Value, key: []const u8) ?std.json.Value {
    const val = obj.object.get(key) orelse return null;
    return switch (val) {
        .object => val,
        else => null,
    };
}

fn jsonRequireString(obj: std.json.Value, key: []const u8, comptime context: []const u8) ![]const u8 {
    return jsonGetString(obj, key) orelse {
        return fail("{s}: missing or invalid string field \"{s}\"", .{ context, key });
    };
}

fn jsonRequireNumber(obj: std.json.Value, key: []const u8, comptime context: []const u8) !f64 {
    return jsonGetNumber(obj, key) orelse {
        return fail("{s}: missing or invalid number field \"{s}\"", .{ context, key });
    };
}

fn jsonRequireInteger(comptime T: type, obj: std.json.Value, key: []const u8, comptime context: []const u8) !T {
    const val = obj.object.get(key) orelse {
        return fail("{s}: missing field \"{s}\"", .{ context, key });
    };
    const i = switch (val) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        else => return fail("{s}: field \"{s}\" must be an integer", .{ context, key }),
    };
    return std.math.cast(T, i) orelse {
        return fail("{s}: field \"{s}\" value out of range for {s}", .{ context, key, @typeName(T) });
    };
}

/// Parse a RuntimeScalarSpec from a JSON value.
/// Accepts:
///   - number  -> .{ .value = N }
///   - string  -> .{ .expr = "..." }
///   - object  -> .{ .value = N, .expr = "..." }
fn parseRuntimeScalar(val: std.json.Value) !RuntimeScalarSpec {
    return switch (val) {
        .float => |f| .{ .value = f },
        .integer => |i| .{ .value = @floatFromInt(i) },
        .string => |s| .{ .expr = s },
        .object => .{
            .value = jsonGetNumber(val, "value") orelse 0,
            .expr = jsonGetString(val, "expr") orelse jsonGetString(val, "param"),
        },
        else => return fail("RuntimeScalarSpec: expected number, string, or object", .{}),
    };
}

/// Parse a RuntimeVec2Spec from a JSON object.
/// Each of x,y can be: number, string, or {value, expr} object.
fn parseRuntimeVec2(obj: std.json.Value, comptime context: []const u8) !RuntimeVec2Spec {
    if (obj != .object) return fail("{s}: expected object for Vec2", .{context});
    const x_val = obj.object.get("x") orelse return fail("{s}: missing x", .{context});
    const y_val = obj.object.get("y") orelse return fail("{s}: missing y", .{context});
    return .{
        .x = try parseRuntimeScalar(x_val),
        .y = try parseRuntimeScalar(y_val),
    };
}

/// Parse an optional RuntimeVec2Spec from a JSON object field.
fn parseOptionalRuntimeVec2(obj: std.json.Value, key: []const u8, comptime context: []const u8) !?RuntimeVec2Spec {
    const val = obj.object.get(key) orelse return null;
    if (val == .null) return null;
    return try parseRuntimeVec2(val, context);
}

/// Parse an optional RuntimeScalarSpec from a JSON object field.
fn parseOptionalRuntimeScalar(obj: std.json.Value, key: []const u8) !?RuntimeScalarSpec {
    const val = obj.object.get(key) orelse return null;
    if (val == .null) return null;
    return try parseRuntimeScalar(val);
}

fn parseVec2(obj: std.json.Value, comptime context: []const u8) !Vec2Spec {
    if (obj != .object) return fail("{s}: expected object for Vec2", .{context});
    return .{
        .x = jsonGetNumber(obj, "x") orelse return fail("{s}: missing x", .{context}),
        .y = jsonGetNumber(obj, "y") orelse return fail("{s}: missing y", .{context}),
    };
}

fn parseOptionalVec2(obj: std.json.Value, key: []const u8, comptime context: []const u8) !?Vec2Spec {
    const val = obj.object.get(key) orelse return null;
    if (val == .null) return null;
    return try parseVec2(val, context);
}

fn parseVec3(obj: std.json.Value, comptime context: []const u8) !Vec3Spec {
    if (obj != .object) return fail("{s}: expected object for Vec3", .{context});
    return .{
        .x = jsonGetNumber(obj, "x") orelse return fail("{s}: missing x", .{context}),
        .y = jsonGetNumber(obj, "y") orelse return fail("{s}: missing y", .{context}),
        .z = jsonGetNumber(obj, "z") orelse return fail("{s}: missing z", .{context}),
    };
}

fn parseOptionalVec3(obj: std.json.Value, key: []const u8, comptime context: []const u8) !?Vec3Spec {
    const val = obj.object.get(key) orelse return null;
    if (val == .null) return null;
    return try parseVec3(val, context);
}

fn parseEnum(comptime E: type, val: []const u8) !E {
    inline for (std.meta.fields(E)) |field| {
        if (std.mem.eql(u8, val, field.name)) return @enumFromInt(field.value);
    }
    return fail("invalid enum value \"{s}\" for {s}", .{ val, @typeName(E) });
}

fn parseNumericParamDef(obj: std.json.Value) !NumericParamDef {
    if (obj != .object) return fail("numeric_params element: expected object", .{});
    return .{
        .key = try jsonRequireString(obj, "key", "numeric_params"),
        .label = try jsonRequireString(obj, "label", "numeric_params"),
        .default_value = try jsonRequireNumber(obj, "default_value", "numeric_params"),
        .min_value = jsonGetNumber(obj, "min_value"),
        .max_value = jsonGetNumber(obj, "max_value"),
    };
}

fn parseSelectOptionDef(obj: std.json.Value) !SelectOptionDef {
    if (obj != .object) return fail("select option: expected object", .{});
    return .{
        .value = try jsonRequireString(obj, "value", "select option"),
        .label = try jsonRequireString(obj, "label", "select option"),
    };
}

fn parseSelectParamDef(allocator: std.mem.Allocator, obj: std.json.Value) !SelectParamDef {
    if (obj != .object) return fail("select_params element: expected object", .{});
    const options_arr = jsonGetArray(obj, "options") orelse return fail("select_params: missing options", .{});
    const options = try allocator.alloc(SelectOptionDef, options_arr.items.len);
    for (options_arr.items, 0..) |item, i| {
        options[i] = try parseSelectOptionDef(item);
    }
    return .{
        .key = try jsonRequireString(obj, "key", "select_params"),
        .label = try jsonRequireString(obj, "label", "select_params"),
        .default_value = try jsonRequireString(obj, "default_value", "select_params"),
        .options = options,
    };
}

fn parseNormalization(obj: std.json.Value) !NormalizeSpec {
    if (obj != .object) return fail("normalization: expected object", .{});
    var result: NormalizeSpec = .{};

    if (jsonGetObject(obj, "source_bounds")) |sb| {
        result.source_bounds = .{
            .origin = try parseVec2(sb.object.get("origin") orelse return fail("source_bounds: missing origin", .{}), "source_bounds.origin"),
            .size = try parseVec2(sb.object.get("size") orelse return fail("source_bounds: missing size", .{}), "source_bounds.size"),
        };
    }
    if (obj.object.get("target_origin")) |to| {
        if (to != .null) {
            result.target_origin = try parseRuntimeVec2(to, "normalization.target_origin");
        }
    }
    if (obj.object.get("target_size")) |ts| {
        if (ts != .null) {
            result.target_size = try parseRuntimeVec2(ts, "normalization.target_size");
        }
    }
    result.flip_y = jsonGetBool(obj, "flip_y") orelse false;
    if (jsonGetString(obj, "scale_mode")) |sm| {
        result.scale_mode = try parseEnum(ScaleMode, sm);
    }
    return result;
}

fn parsePathSegment(obj: std.json.Value, comptime context: []const u8) !PathSegmentSpec {
    if (obj != .object) return fail("{s}: expected object for segment", .{context});
    var result: PathSegmentSpec = .{};

    if (jsonGetString(obj, "kind")) |kind_str| {
        result.kind = try parseEnum(SegmentKind, kind_str);
    }
    result.from = try parseOptionalRuntimeVec2(obj, "from", context ++ ".from");
    result.to = try parseOptionalRuntimeVec2(obj, "to", context ++ ".to");
    result.center = try parseOptionalRuntimeVec2(obj, "center", context ++ ".center");
    result.radius = try parseOptionalRuntimeScalar(obj, "radius");
    result.start_angle = try parseOptionalRuntimeScalar(obj, "start_angle");
    result.end_angle = try parseOptionalRuntimeScalar(obj, "end_angle");
    result.clockwise = jsonGetBool(obj, "clockwise") orelse false;
    result.p0 = try parseOptionalRuntimeVec2(obj, "p0", context ++ ".p0");
    result.p1 = try parseOptionalRuntimeVec2(obj, "p1", context ++ ".p1");
    result.p2 = try parseOptionalRuntimeVec2(obj, "p2", context ++ ".p2");
    result.p3 = try parseOptionalRuntimeVec2(obj, "p3", context ++ ".p3");
    return result;
}

fn parsePathSegments(allocator: std.mem.Allocator, arr: std.json.Array, comptime context: []const u8) ![]const PathSegmentSpec {
    const segments = try allocator.alloc(PathSegmentSpec, arr.items.len);
    for (arr.items, 0..) |item, i| {
        segments[i] = try parsePathSegment(item, context);
    }
    return segments;
}

fn parseSurfaceFrame(obj: std.json.Value) !SurfaceFrameSpec {
    if (obj != .object) return fail("surface_frame: expected object", .{});
    return .{
        .origin = try parseVec2(obj.object.get("origin") orelse return fail("surface_frame: missing origin", .{}), "surface_frame.origin"),
        .u_axis = try parseVec2(obj.object.get("u_axis") orelse return fail("surface_frame: missing u_axis", .{}), "surface_frame.u_axis"),
        .v_axis = try parseVec2(obj.object.get("v_axis") orelse return fail("surface_frame: missing v_axis", .{}), "surface_frame.v_axis"),
    };
}

fn parsePanel(allocator: std.mem.Allocator, obj: std.json.Value) !PanelSpec {
    if (obj != .object) return fail("panel: expected object", .{});
    const boundary_arr = jsonGetArray(obj, "boundary") orelse return fail("panel: missing boundary", .{});
    var result: PanelSpec = .{
        .name = try jsonRequireString(obj, "name", "panel"),
        .id = 0,
        .boundary = try parsePathSegments(allocator, boundary_arr, "panel.boundary"),
    };
    if (jsonGetArray(obj, "content_region")) |cr_arr| {
        result.content_region = try parsePathSegments(allocator, cr_arr, "panel.content_region");
    }
    if (obj.object.get("surface_frame")) |sf| {
        if (sf != .null) {
            result.surface_frame = try parseSurfaceFrame(sf);
        }
    }
    result.outside_normal = try parseOptionalVec3(obj, "outside_normal", "panel.outside_normal");
    result.accepts_content = jsonGetBool(obj, "accepts_content") orelse true;
    return result;
}

fn parseFold(obj: std.json.Value) !FoldSpec {
    if (obj != .object) return fail("fold: expected object", .{});
    const dir_str = try jsonRequireString(obj, "direction", "fold");
    return .{
        .from_panel = try jsonRequireString(obj, "from_panel", "fold"),
        .to_panel = try jsonRequireString(obj, "to_panel", "fold"),
        .from_segment_index = try jsonRequireInteger(u16, obj, "from_segment_index", "fold"),
        .to_segment_index = try jsonRequireInteger(u16, obj, "to_segment_index", "fold"),
        .angle_rad = try jsonRequireNumber(obj, "angle_rad", "fold"),
        .angle_expr = jsonGetString(obj, "angle_expr") orelse jsonGetString(obj, "angle_param"),
        .direction = try parseEnum(FoldDirection, dir_str),
    };
}

fn parseLinework(allocator: std.mem.Allocator, obj: std.json.Value) !LineworkSpec {
    if (obj != .object) return fail("linework: expected object", .{});
    const role_str = try jsonRequireString(obj, "role", "linework");
    const segments_arr = jsonGetArray(obj, "segments") orelse return fail("linework: missing segments", .{});
    var result: LineworkSpec = .{
        .role = try parseEnum(LineRole, role_str),
        .segments = try parsePathSegments(allocator, segments_arr, "linework.segments"),
    };
    if (jsonGetString(obj, "stroke_style")) |ss| {
        result.stroke_style = try parseEnum(StrokeStyle, ss);
    }
    result.closed = jsonGetBool(obj, "closed") orelse false;
    return result;
}

fn parseInputTemplate(allocator: std.mem.Allocator, root: std.json.Value) !InputTemplate {
    if (root != .object) return fail("template root: expected object", .{});

    var result: InputTemplate = .{
        .key = try jsonRequireString(root, "key", "template"),
        .label = try jsonRequireString(root, "label", "template"),
        .panels = &.{},
    };

    if (jsonGetString(root, "package_kind")) |pk| {
        result.package_kind = try parseEnum(PackageKind, pk);
    }

    // numeric_params
    if (jsonGetArray(root, "numeric_params")) |np_arr| {
        const params = try allocator.alloc(NumericParamDef, np_arr.items.len);
        for (np_arr.items, 0..) |item, i| {
            params[i] = try parseNumericParamDef(item);
        }
        result.numeric_params = params;
    }

    // select_params
    if (jsonGetArray(root, "select_params")) |sp_arr| {
        const params = try allocator.alloc(SelectParamDef, sp_arr.items.len);
        for (sp_arr.items, 0..) |item, i| {
            params[i] = try parseSelectParamDef(allocator, item);
        }
        result.select_params = params;
    }

    // variables
    if (jsonGetArray(root, "variables")) |var_arr| {
        const vars = try allocator.alloc(VariableDef, var_arr.items.len);
        for (var_arr.items, 0..) |item, i| {
            if (item != .object) return fail("variables element: expected object", .{});
            vars[i] = .{
                .name = try jsonRequireString(item, "name", "variables"),
                .expr = try jsonRequireString(item, "expr", "variables"),
            };
        }
        result.variables = vars;
    }

    // normalization
    if (jsonGetObject(root, "normalization")) |norm_obj| {
        result.normalization = try parseNormalization(norm_obj);
    }

    // panels
    const panels_arr = jsonGetArray(root, "panels") orelse return fail("template: missing panels", .{});
    const panels = try allocator.alloc(PanelSpec, panels_arr.items.len);
    for (panels_arr.items, 0..) |item, i| {
        panels[i] = try parsePanel(allocator, item);
        panels[i].id = @intCast(i);
    }
    result.panels = panels;

    // folds
    if (jsonGetArray(root, "folds")) |folds_arr| {
        const folds = try allocator.alloc(FoldSpec, folds_arr.items.len);
        for (folds_arr.items, 0..) |item, i| {
            folds[i] = try parseFold(item);
        }
        result.folds = folds;
    }

    // linework
    if (jsonGetArray(root, "linework")) |lw_arr| {
        const lw = try allocator.alloc(LineworkSpec, lw_arr.items.len);
        for (lw_arr.items, 0..) |item, i| {
            lw[i] = try parseLinework(allocator, item);
        }
        result.linework = lw;
    }

    return result;
}

pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();

    _ = args.next();
    const input_path = args.next() orelse {
        printUsage();
        return error.MissingInputPath;
    };
    const output_path = args.next();

    if (std.mem.endsWith(u8, input_path, ".json")) {
        const resolved_output_path = if (output_path) |explicit_path|
            try init.gpa.dupe(u8, explicit_path)
        else
            try deriveOutputPath(init.gpa, input_path);
        defer init.gpa.free(resolved_output_path);
        try processInputFile(init, input_path, resolved_output_path);
        return;
    }

    const output_root = if (output_path) |explicit_path|
        try init.gpa.dupe(u8, explicit_path)
    else
        try deriveOutputRoot(init.gpa, input_path);
    defer init.gpa.free(output_root);

    try processInputDirectory(init, input_path, output_root);
}

fn printUsage() void {
    std.debug.print(
        "Usage: zig run packages/geo-core/tools/template_json_to_spec.zig -- <input.json|input_dir> [output.zig|output_dir]\n",
        .{},
    );
}

fn deriveOutputPath(allocator: std.mem.Allocator, input_path: []const u8) ![]u8 {
    if (replaceJsonPathSegment(allocator, input_path)) |spec_path| {
        defer allocator.free(spec_path);
        return std.fmt.allocPrint(
            allocator,
            "{s}_spec.zig",
            .{spec_path[0 .. spec_path.len - ".json".len]},
        );
    } else |_| {}

    if (std.mem.endsWith(u8, input_path, ".json")) {
        return std.fmt.allocPrint(
            allocator,
            "{s}_spec.zig",
            .{input_path[0 .. input_path.len - ".json".len]},
        );
    }

    return std.fmt.allocPrint(allocator, "{s}_spec.zig", .{input_path});
}

fn deriveOutputRoot(allocator: std.mem.Allocator, input_dir: []const u8) ![]u8 {
    if (std.mem.endsWith(u8, input_dir, "/json")) {
        return std.fmt.allocPrint(allocator, "{s}/spec", .{input_dir[0 .. input_dir.len - "/json".len]});
    }
    if (std.mem.eql(u8, input_dir, "json")) {
        return allocator.dupe(u8, "spec");
    }
    return std.fmt.allocPrint(allocator, "{s}/spec", .{input_dir});
}

fn processInputDirectory(
    init: std.process.Init,
    input_dir: []const u8,
    output_root: []const u8,
) !void {
    const json_files = try collectJsonFiles(init, input_dir);
    defer {
        for (json_files) |path| init.gpa.free(path);
        init.gpa.free(json_files);
    }

    if (json_files.len == 0) return error.NoJsonInputsFound;

    for (json_files) |input_file| {
        const relative_path = try relativeJsonPath(init.gpa, input_dir, input_file);
        defer init.gpa.free(relative_path);

        const output_path = try deriveOutputPathInRoot(init.gpa, output_root, relative_path);
        defer init.gpa.free(output_path);

        try processInputFile(init, input_file, output_path);
    }
}

fn processInputFile(init: std.process.Init, input_path: []const u8, output_path: []const u8) !void {
    const input_bytes = try readTextFile(init, input_path);
    defer init.gpa.free(input_bytes);

    var parsed = try std.json.parseFromSlice(std.json.Value, init.gpa, input_bytes, .{});
    defer parsed.deinit();

    const template = try parseInputTemplate(init.gpa, parsed.value);
    defer deinitInputTemplate(init.gpa, template);

    try validateTemplate(template);

    const rendered = try renderTemplateSpec(init.gpa, input_path, output_path, template);
    defer init.gpa.free(rendered);

    try writeTextFile(init, output_path, rendered);
    try runZigFmt(init, output_path);

    std.debug.print("Generated {s}\n", .{output_path});
}

fn deinitInputTemplate(allocator: std.mem.Allocator, template: InputTemplate) void {
    allocator.free(template.numeric_params);

    for (template.select_params) |param| {
        allocator.free(param.options);
    }
    allocator.free(template.select_params);

    allocator.free(template.variables);

    for (template.panels) |panel| {
        allocator.free(panel.boundary);
        if (panel.content_region) |content_region| allocator.free(content_region);
    }
    allocator.free(template.panels);

    allocator.free(template.folds);

    for (template.linework) |linework| {
        allocator.free(linework.segments);
    }
    allocator.free(template.linework);
}

fn collectJsonFiles(init: std.process.Init, input_dir: []const u8) ![][]u8 {
    const result = try std.process.run(init.gpa, init.io, .{
        .argv = &.{ "find", input_dir, "-type", "f", "-name", "*.json" },
    });
    defer init.gpa.free(result.stdout);
    defer init.gpa.free(result.stderr);

    switch (result.term) {
        .exited => |code| if (code != 0) return error.FindFailed,
        else => return error.FindFailed,
    }

    var files = try std.ArrayList([]u8).initCapacity(init.gpa, 8);
    errdefer {
        for (files.items) |path| init.gpa.free(path);
        files.deinit(init.gpa);
    }

    var iter = std.mem.splitScalar(u8, result.stdout, '\n');
    while (iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0) continue;
        try files.append(init.gpa, try init.gpa.dupe(u8, trimmed));
    }

    std.mem.sort([]u8, files.items, {}, lessThanString);
    return files.toOwnedSlice(init.gpa);
}

fn lessThanString(_: void, left: []u8, right: []u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn relativeJsonPath(allocator: std.mem.Allocator, root: []const u8, input_file: []const u8) ![]u8 {
    const normalized_root = if (std.mem.endsWith(u8, root, "/")) root[0 .. root.len - 1] else root;
    if (std.mem.startsWith(u8, input_file, normalized_root)) {
        var relative = input_file[normalized_root.len..];
        if (relative.len != 0 and relative[0] == '/') relative = relative[1..];
        return allocator.dupe(u8, relative);
    }
    return allocator.dupe(u8, input_file);
}

fn deriveOutputPathInRoot(
    allocator: std.mem.Allocator,
    output_root: []const u8,
    relative_json_path: []const u8,
) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{s}/{s}_spec.zig",
        .{
            output_root,
            relative_json_path[0 .. relative_json_path.len - ".json".len],
        },
    );
}

fn replaceJsonPathSegment(allocator: std.mem.Allocator, input_path: []const u8) ![]u8 {
    if (std.mem.indexOf(u8, input_path, "/json/")) |index| {
        return std.fmt.allocPrint(
            allocator,
            "{s}/spec/{s}",
            .{
                input_path[0..index],
                input_path[index + "/json/".len ..],
            },
        );
    }
    if (std.mem.startsWith(u8, input_path, "json/")) {
        return std.fmt.allocPrint(allocator, "spec/{s}", .{input_path["json/".len..]});
    }
    return error.NoJsonPathSegment;
}

fn readTextFile(init: std.process.Init, path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(path)) {
        var file = try std.Io.Dir.openFileAbsolute(init.io, path, .{});
        defer file.close(init.io);
        var reader_buffer: [4096]u8 = undefined;
        var reader = file.reader(init.io, &reader_buffer);
        return reader.interface.allocRemaining(init.gpa, .limited(16 * 1024 * 1024));
    }

    return std.Io.Dir.cwd().readFileAlloc(
        init.io,
        path,
        init.gpa,
        .limited(16 * 1024 * 1024),
    );
}

fn writeTextFile(init: std.process.Init, path: []const u8, bytes: []const u8) !void {
    try ensureParentDir(init, path);

    if (std.fs.path.isAbsolute(path)) {
        var file = try std.Io.Dir.createFileAbsolute(init.io, path, .{});
        defer file.close(init.io);
        try file.writeStreamingAll(init.io, bytes);
        return;
    }

    try std.Io.Dir.cwd().writeFile(init.io, .{
        .sub_path = path,
        .data = bytes,
    });
}

fn ensureParentDir(init: std.process.Init, path: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse return;
    if (parent.len == 0) return;

    const result = try std.process.run(init.gpa, init.io, .{
        .argv = &.{ "mkdir", "-p", parent },
    });
    defer init.gpa.free(result.stdout);
    defer init.gpa.free(result.stderr);

    switch (result.term) {
        .exited => |code| if (code != 0) return error.MkdirFailed,
        else => return error.MkdirFailed,
    }
}

fn runZigFmt(init: std.process.Init, path: []const u8) !void {
    const result = try std.process.run(init.gpa, init.io, .{
        .argv = &.{ "zig", "fmt", path },
    });
    defer init.gpa.free(result.stdout);
    defer init.gpa.free(result.stderr);

    switch (result.term) {
        .exited => |code| if (code != 0) {
            if (result.stderr.len != 0) std.debug.print("{s}", .{result.stderr});
            return error.ZigFmtFailed;
        },
        else => return error.ZigFmtFailed,
    }
}

fn validateTemplate(template: InputTemplate) !void {
    if (template.package_kind != .folding_carton) {
        return fail(
            "template.package_kind must be folding_carton, got {s}",
            .{@tagName(template.package_kind)},
        );
    }

    if (template.panels.len == 0) {
        return fail("template.panels must not be empty", .{});
    }

    for (template.numeric_params, 0..) |param, index| {
        for (template.numeric_params[index + 1 ..]) |other_param| {
            if (std.mem.eql(u8, param.key, other_param.key)) {
                return fail("template.numeric_params has duplicate key \"{s}\"", .{param.key});
            }
        }
    }
    for (template.select_params, 0..) |param, index| {
        if (param.options.len == 0) {
            return fail("template.select_params[{d}].options must not be empty", .{index});
        }
        var has_default = false;
        for (param.options) |option| {
            if (std.mem.eql(u8, option.value, param.default_value)) has_default = true;
        }
        if (!has_default) {
            return fail("template.select_params[{d}].default_value must match one option", .{index});
        }
        for (template.select_params[index + 1 ..]) |other_param| {
            if (std.mem.eql(u8, param.key, other_param.key)) {
                return fail("template.select_params has duplicate key \"{s}\"", .{param.key});
            }
        }
        for (template.numeric_params) |numeric_param| {
            if (std.mem.eql(u8, param.key, numeric_param.key)) {
                return fail("template params re-use key \"{s}\" across numeric/select", .{param.key});
            }
        }
    }

    for (template.variables, 0..) |variable, var_index| {
        // Variable names must not collide with numeric_params keys
        for (template.numeric_params) |numeric_param| {
            if (std.mem.eql(u8, variable.name, numeric_param.key)) {
                return fail("template.variables[{d}].name \"{s}\" collides with numeric param key", .{ var_index, variable.name });
            }
        }
        // Variable names must be unique
        for (template.variables[var_index + 1 ..]) |other_var| {
            if (std.mem.eql(u8, variable.name, other_var.name)) {
                return fail("template.variables has duplicate name \"{s}\"", .{variable.name});
            }
        }
        // Variable expressions must reference valid params or earlier variables.
        // For simple single-key expressions (no operators), verify the key exists.
        try validateVariableExpr(template, variable.expr, var_index);
    }

    if (template.normalization) |normalization| {
        try validateRuntimeScalar(template, normalization.target_origin.x, "template.normalization.target_origin.x");
        try validateRuntimeScalar(template, normalization.target_origin.y, "template.normalization.target_origin.y");
        if (normalization.target_size) |target_size| {
            try validateRuntimeScalar(template, target_size.x, "template.normalization.target_size.x");
            try validateRuntimeScalar(template, target_size.y, "template.normalization.target_size.y");
        }
        if (normalization.source_bounds) |source_bounds| {
            if (source_bounds.size.x <= 0 or source_bounds.size.y <= 0) {
                return fail("template.normalization.source_bounds.size must be positive", .{});
            }
        }
    }

    for (template.panels, 0..) |panel, panel_index| {
        if (panel.boundary.len == 0) {
            return fail("template.panels[{d}].boundary must not be empty", .{panel_index});
        }

        if (panel.content_region) |content_region| {
            if (content_region.len == 0) {
                return fail("template.panels[{d}].content_region must not be empty", .{panel_index});
            }
            for (content_region, 0..) |segment, segment_index| {
                try validateSegment(segment, "template.panels[{d}].content_region[{d}]", .{
                    panel_index,
                    segment_index,
                });
            }
        }

        for (panel.boundary, 0..) |segment, segment_index| {
            try validateSegment(segment, "template.panels[{d}].boundary[{d}]", .{
                panel_index,
                segment_index,
            });
        }

        for (template.panels[panel_index + 1 ..]) |other_panel| {
            if (std.mem.eql(u8, other_panel.name, panel.name)) {
                return fail("template.panels has duplicate name \"{s}\"", .{panel.name});
            }
        }
        if (!isValidPanelName(panel.name)) {
            return fail("template.panels[{d}].name \"{s}\" must be a valid Zig identifier", .{ panel_index, panel.name });
        }
    }

    for (template.folds, 0..) |fold, fold_index| {
        const from_panel = findPanelByName(template, fold.from_panel) orelse {
            return fail(
                "template.folds[{d}].from_panel references missing panel \"{s}\"",
                .{ fold_index, fold.from_panel },
            );
        };
        const to_panel = findPanelByName(template, fold.to_panel) orelse {
            return fail(
                "template.folds[{d}].to_panel references missing panel \"{s}\"",
                .{ fold_index, fold.to_panel },
            );
        };

        if (fold.from_segment_index >= from_panel.boundary.len) {
            return fail(
                "template.folds[{d}].from_segment_index {d} is outside panel \"{s}\" boundary",
                .{ fold_index, fold.from_segment_index, fold.from_panel },
            );
        }
        if (fold.to_segment_index >= to_panel.boundary.len) {
            return fail(
                "template.folds[{d}].to_segment_index {d} is outside panel \"{s}\" boundary",
                .{ fold_index, fold.to_segment_index, fold.to_panel },
            );
        }
        if (fold.angle_expr) |expr_str| {
            try validateExprKey(template, expr_str, "template.folds[{d}].angle_expr", .{fold_index});
        }
    }

    for (template.linework, 0..) |linework, line_index| {
        if (linework.segments.len == 0) {
            return fail("template.linework[{d}].segments must not be empty", .{line_index});
        }
        for (linework.segments, 0..) |segment, segment_index| {
            try validateSegment(segment, "template.linework[{d}].segments[{d}]", .{
                line_index,
                segment_index,
            });
        }
    }
}

fn validateRuntimeScalar(
    template: InputTemplate,
    scalar: RuntimeScalarSpec,
    comptime fmt: []const u8,
) !void {
    if (scalar.expr) |expr_str| {
        try validateExprKey(template, expr_str, fmt, .{});
    }
}

/// Validate that an expression string references known param keys.
/// For simple single-key expressions (no operators), verify the key exists.
/// For complex expressions (containing operators/spaces), skip validation
/// since the expression evaluator will handle them at runtime.
fn validateExprKey(
    template: InputTemplate,
    expr_str: []const u8,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    // If the expression contains spaces, operators, or parentheses, it is
    // a complex expression that we cannot validate statically here.
    for (expr_str) |c| {
        if (c == ' ' or c == '+' or c == '-' or c == '*' or c == '/' or c == '(' or c == ')') return;
    }
    // Simple single-key expression: validate it is a known numeric param or variable.
    for (template.numeric_params) |param| {
        if (std.mem.eql(u8, param.key, expr_str)) return;
    }
    for (template.variables) |variable| {
        if (std.mem.eql(u8, variable.name, expr_str)) return;
    }

    const prefix = try std.fmt.allocPrint(std.heap.smp_allocator, fmt, args);
    defer std.heap.smp_allocator.free(prefix);
    return fail("{s} references missing numeric param or variable \"{s}\"", .{ prefix, expr_str });
}

/// Validate that a variable expression references known numeric params or
/// earlier variables (those with index < current_index).
/// For complex expressions (containing operators/spaces), skip validation.
fn validateVariableExpr(template: InputTemplate, expr_str: []const u8, current_index: usize) !void {
    // Complex expressions with operators are validated at runtime.
    for (expr_str) |c| {
        if (c == ' ' or c == '+' or c == '-' or c == '*' or c == '/' or c == '(' or c == ')') return;
    }
    // Check numeric params
    for (template.numeric_params) |param| {
        if (std.mem.eql(u8, param.key, expr_str)) return;
    }
    // Check earlier variables (defined before current_index)
    for (template.variables[0..current_index]) |earlier_var| {
        if (std.mem.eql(u8, earlier_var.name, expr_str)) return;
    }
    return fail("template.variables[{d}].expr references unknown identifier \"{s}\"", .{ current_index, expr_str });
}

fn validateSegment(segment: PathSegmentSpec, comptime fmt: []const u8, args: anytype) !void {
    const prefix = try std.fmt.allocPrint(std.heap.smp_allocator, fmt, args);
    defer std.heap.smp_allocator.free(prefix);

    switch (segment.kind) {
        .line => {
            if (segment.from == null or segment.to == null) {
                return fail("{s} must provide from/to", .{prefix});
            }
        },
        .arc => {
            if (segment.center == null or
                segment.radius == null or
                segment.start_angle == null or
                segment.end_angle == null)
            {
                return fail("{s} must provide center/radius/start_angle/end_angle", .{prefix});
            }
            // Only validate positive radius for constant values without expressions
            const radius = segment.radius.?;
            if (radius.expr == null and radius.value <= 0) {
                return fail("{s} radius must be positive", .{prefix});
            }
        },
        .bezier => {
            if (segment.p0 == null or segment.p1 == null or segment.p2 == null or segment.p3 == null) {
                return fail("{s} must provide p0/p1/p2/p3", .{prefix});
            }
        },
    }
}

fn findPanelByName(template: InputTemplate, panel_name: []const u8) ?PanelSpec {
    for (template.panels) |panel| {
        if (std.mem.eql(u8, panel.name, panel_name)) return panel;
    }
    return null;
}

fn isValidPanelName(name: []const u8) bool {
    if (name.len == 0) return false;
    if (!isIdentStart(name[0])) return false;
    for (name[1..]) |ch| {
        if (!isIdentCont(ch)) return false;
    }
    return true;
}

fn isIdentStart(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or ch == '_';
}

fn isIdentCont(ch: u8) bool {
    return isIdentStart(ch) or (ch >= '0' and ch <= '9');
}

fn fail(comptime fmt: []const u8, args: anytype) error{InvalidTemplate} {
    std.debug.print(fmt ++ "\n", args);
    return error.InvalidTemplate;
}

fn renderTemplateSpec(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    output_path: []const u8,
    template: InputTemplate,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const import_path = try deriveCompiledSpecImportPath(allocator, output_path);
    defer allocator.free(import_path);

    try out.writer.writeAll("// Generated from ");
    try writeQuotedString(&out.writer, source_path);
    try out.writer.writeAll(" by packages/geo-core/tools/template_json_to_spec.zig.\n");
    try out.writer.writeAll("// Edit the JSON source, then regenerate this file.\n");
    try out.writer.writeAll("const compiled_spec = @import(");
    try writeQuotedString(&out.writer, import_path);
    try out.writer.writeAll(");\n");
    try out.writer.writeAll("const cv2 = compiled_spec.cv2;\n");
    try out.writer.writeAll("const cs = compiled_spec.cs;\n\n");
    try renderPanelEnum(&out.writer, template);
    try out.writer.writeAll("\n");
    try out.writer.writeAll("pub const spec: compiled_spec.TemplateSpec = .{\n");
    try writeFieldString(&out.writer, 1, "key", template.key);
    try writeFieldString(&out.writer, 1, "label", template.label);

    if (template.numeric_params.len != 0) {
        try out.writer.writeAll("    .numeric_params = &.{\n");
        for (template.numeric_params) |param| {
            try renderNumericParam(&out.writer, 2, param);
        }
        try out.writer.writeAll("    },\n");
    }
    if (template.select_params.len != 0) {
        try out.writer.writeAll("    .select_params = &.{\n");
        for (template.select_params) |param| {
            try renderSelectParam(&out.writer, 2, param);
        }
        try out.writer.writeAll("    },\n");
    }

    if (template.variables.len != 0) {
        try out.writer.writeAll("    .variables = &.{\n");
        for (template.variables) |variable| {
            try renderVariable(&out.writer, 2, variable);
        }
        try out.writer.writeAll("    },\n");
    }

    if (template.normalization) |normalization| {
        try renderNormalization(&out.writer, 1, normalization);
    }

    try out.writer.writeAll("    .panels = &.{\n");
    for (template.panels) |panel| {
        try renderPanel(&out.writer, 2, panel);
    }
    try out.writer.writeAll("    },\n");

    if (template.folds.len != 0) {
        try out.writer.writeAll("    .folds = &.{\n");
        for (template.folds) |fold| {
            try renderFold(&out.writer, 2, fold);
        }
        try out.writer.writeAll("    },\n");
    }

    if (template.linework.len != 0) {
        try out.writer.writeAll("    .linework = &.{\n");
        for (template.linework) |linework| {
            try renderLinework(&out.writer, 2, linework);
        }
        try out.writer.writeAll("    },\n");
    }

    try out.writer.writeAll("};\n");
    return out.toOwnedSlice();
}

fn deriveCompiledSpecImportPath(allocator: std.mem.Allocator, output_path: []const u8) ![]u8 {
    const marker = "src/templates/";
    const marker_index = std.mem.indexOf(u8, output_path, marker) orelse return allocator.dupe(u8, "../compiled_spec.zig");
    const relative_output_path = output_path[marker_index + marker.len ..];
    const output_dir = std.fs.path.dirname(relative_output_path) orelse return allocator.dupe(u8, "compiled_spec.zig");

    if (output_dir.len == 0 or std.mem.eql(u8, output_dir, ".")) {
        return allocator.dupe(u8, "compiled_spec.zig");
    }

    var depth: usize = 0;
    var iter = std.mem.splitScalar(u8, output_dir, '/');
    while (iter.next()) |segment| {
        if (segment.len == 0 or std.mem.eql(u8, segment, ".")) continue;
        depth += 1;
    }

    var prefix = std.ArrayList(u8).empty;
    for (0..depth) |_| {
        try prefix.appendSlice(allocator, "../");
    }
    defer prefix.deinit(allocator);
    try prefix.appendSlice(allocator, "compiled_spec.zig");
    return prefix.toOwnedSlice(allocator);
}

fn renderNumericParam(writer: *std.Io.Writer, indent_level: usize, param: NumericParamDef) !void {
    const indent = indentation(indent_level);
    const inner = indentation(indent_level + 1);

    try writer.print("{s}.{{\n", .{indent});
    try writer.print("{s}.key = ", .{inner});
    try writeQuotedString(writer, param.key);
    try writer.writeAll(",\n");
    try writer.print("{s}.label = ", .{inner});
    try writeQuotedString(writer, param.label);
    try writer.writeAll(",\n");
    try writer.print("{s}.default_value = {},\n", .{ inner, param.default_value });
    if (param.min_value) |min_value| {
        try writer.print("{s}.min_value = {},\n", .{ inner, min_value });
    }
    if (param.max_value) |max_value| {
        try writer.print("{s}.max_value = {},\n", .{ inner, max_value });
    }
    try writer.print("{s}}},\n", .{indent});
}

fn renderSelectParam(writer: *std.Io.Writer, indent_level: usize, param: SelectParamDef) !void {
    const indent = indentation(indent_level);
    const inner = indentation(indent_level + 1);

    try writer.print("{s}.{{\n", .{indent});
    try writer.print("{s}.key = ", .{inner});
    try writeQuotedString(writer, param.key);
    try writer.writeAll(",\n");
    try writer.print("{s}.label = ", .{inner});
    try writeQuotedString(writer, param.label);
    try writer.writeAll(",\n");
    try writer.print("{s}.default_value = ", .{inner});
    try writeQuotedString(writer, param.default_value);
    try writer.writeAll(",\n");
    try writer.print("{s}.options = &.{{\n", .{inner});
    for (param.options) |option| {
        try writer.print("{s}.{{ .value = ", .{indentation(indent_level + 2)});
        try writeQuotedString(writer, option.value);
        try writer.writeAll(", .label = ");
        try writeQuotedString(writer, option.label);
        try writer.writeAll(" },\n");
    }
    try writer.print("{s}}},\n", .{inner});
    try writer.print("{s}}},\n", .{indent});
}

fn renderVariable(writer: *std.Io.Writer, indent_level: usize, variable: VariableDef) !void {
    const indent = indentation(indent_level);
    try writer.print("{s}.{{ .name = ", .{indent});
    try writeQuotedString(writer, variable.name);
    try writer.writeAll(", .expr = ");
    try writeQuotedString(writer, variable.expr);
    try writer.writeAll(" },\n");
}

fn renderNormalization(writer: *std.Io.Writer, indent_level: usize, normalization: NormalizeSpec) !void {
    const indent = indentation(indent_level);
    const inner = indentation(indent_level + 1);

    try writer.print("{s}.normalization = .{{\n", .{indent});
    if (normalization.source_bounds) |source_bounds| {
        try writer.print("{s}.source_bounds = .{{\n", .{inner});
        try writer.print("{s}.origin = ", .{indentation(indent_level + 2)});
        try writePlainVec2(writer, source_bounds.origin);
        try writer.writeAll(",\n");
        try writer.print("{s}.size = ", .{indentation(indent_level + 2)});
        try writePlainVec2(writer, source_bounds.size);
        try writer.writeAll(",\n");
        try writer.print("{s}}},\n", .{inner});
    }

    if (!runtimeVec2IsDefaultOrigin(normalization.target_origin)) {
        try writer.print("{s}.target_origin = ", .{inner});
        try writeRuntimeVec2(writer, normalization.target_origin);
        try writer.writeAll(",\n");
    }

    if (normalization.target_size) |target_size| {
        try writer.print("{s}.target_size = ", .{inner});
        try writeRuntimeVec2(writer, target_size);
        try writer.writeAll(",\n");
    }

    if (normalization.flip_y) {
        try writer.print("{s}.flip_y = true,\n", .{inner});
    }
    if (normalization.scale_mode != .independent) {
        try writer.print("{s}.scale_mode = .{s},\n", .{ inner, @tagName(normalization.scale_mode) });
    }

    try writer.print("{s}}},\n", .{indent});
}

fn renderPanelEnum(writer: *std.Io.Writer, template: InputTemplate) !void {
    try writer.writeAll("const Panel = enum(u16) {\n");
    for (template.panels) |panel| {
        try writer.print("    {s} = {},\n", .{ panel.name, panel.id });
    }
    try writer.writeAll("};\n\n");
    try writer.writeAll("fn p(key: Panel) u16 {\n");
    try writer.writeAll("    return @intFromEnum(key);\n");
    try writer.writeAll("}\n");
}

fn renderPanel(writer: *std.Io.Writer, indent_level: usize, panel: PanelSpec) !void {
    const indent = indentation(indent_level);
    const inner = indentation(indent_level + 1);

    try writer.print("{s}.{{\n", .{indent});
    try writer.print("{s}.id = p(.{s}),\n", .{ inner, panel.name });
    try writer.print("{s}.name = \"{s}\",\n", .{ inner, panel.name });

    if (panel.surface_frame) |surface_frame| {
        try writer.print("{s}.surface_frame = .{{\n", .{inner});
        try writer.print("{s}.origin = ", .{indentation(indent_level + 2)});
        try writePlainVec2(writer, surface_frame.origin);
        try writer.writeAll(",\n");
        try writer.print("{s}.u_axis = ", .{indentation(indent_level + 2)});
        try writePlainVec2(writer, surface_frame.u_axis);
        try writer.writeAll(",\n");
        try writer.print("{s}.v_axis = ", .{indentation(indent_level + 2)});
        try writePlainVec2(writer, surface_frame.v_axis);
        try writer.writeAll(",\n");
        try writer.print("{s}}},\n", .{inner});
    }

    if (panel.content_region) |content_region| {
        try writer.print("{s}.content_region = &.{{\n", .{inner});
        for (content_region) |segment| {
            try writer.print("{s}", .{indentation(indent_level + 2)});
            try writeSegment(writer, indent_level + 2, segment);
            try writer.writeAll(",\n");
        }
        try writer.print("{s}}},\n", .{inner});
    }

    if (panel.outside_normal) |outside_normal| {
        try writer.print("{s}.outside_normal = ", .{inner});
        try writeVec3(writer, outside_normal);
        try writer.writeAll(",\n");
    }

    if (!panel.accepts_content) {
        try writer.print("{s}.accepts_content = false,\n", .{inner});
    }

    try writer.print("{s}.boundary = &.{{\n", .{inner});
    for (panel.boundary) |segment| {
        try writer.print("{s}", .{indentation(indent_level + 2)});
        try writeSegment(writer, indent_level + 2, segment);
        try writer.writeAll(",\n");
    }
    try writer.print("{s}}},\n", .{inner});
    try writer.print("{s}}},\n", .{indent});
}

fn renderFold(writer: *std.Io.Writer, indent_level: usize, fold: FoldSpec) !void {
    const indent = indentation(indent_level);
    const inner = indentation(indent_level + 1);

    try writer.print("{s}.{{\n", .{indent});
    try writer.print("{s}.from_panel_id = p(.{s}),\n", .{ inner, fold.from_panel });
    try writer.print("{s}.to_panel_id = p(.{s}),\n", .{ inner, fold.to_panel });
    try writer.print("{s}.from_segment_index = {},\n", .{ inner, fold.from_segment_index });
    try writer.print("{s}.to_segment_index = {},\n", .{ inner, fold.to_segment_index });
    try writer.print("{s}.angle_rad = {},\n", .{ inner, fold.angle_rad });
    if (fold.angle_expr) |angle_expr| {
        try writer.print("{s}.angle_expr = ", .{inner});
        try writeQuotedString(writer, angle_expr);
        try writer.writeAll(",\n");
    }
    try writer.print("{s}.direction = .{s},\n", .{ inner, @tagName(fold.direction) });
    try writer.print("{s}}},\n", .{indent});
}

fn renderLinework(writer: *std.Io.Writer, indent_level: usize, linework: LineworkSpec) !void {
    const indent = indentation(indent_level);
    const inner = indentation(indent_level + 1);

    try writer.print("{s}.{{\n", .{indent});
    try writer.print("{s}.role = .{s},\n", .{ inner, @tagName(linework.role) });
    if (linework.stroke_style) |stroke_style| {
        try writer.print("{s}.stroke_style = .{s},\n", .{ inner, @tagName(stroke_style) });
    }
    if (linework.closed) {
        try writer.print("{s}.closed = true,\n", .{inner});
    }
    try writer.print("{s}.segments = &.{{\n", .{inner});
    for (linework.segments) |segment| {
        try writer.print("{s}", .{indentation(indent_level + 2)});
        try writeSegment(writer, indent_level + 2, segment);
        try writer.writeAll(",\n");
    }
    try writer.print("{s}}},\n", .{inner});
    try writer.print("{s}}},\n", .{indent});
}

fn writeFieldString(writer: *std.Io.Writer, indent_level: usize, name: []const u8, value: []const u8) !void {
    try writer.print("{s}.{s} = ", .{ indentation(indent_level), name });
    try writeQuotedString(writer, value);
    try writer.writeAll(",\n");
}

fn writeQuotedString(writer: *std.Io.Writer, value: []const u8) !void {
    var json_writer: std.json.Stringify = .{
        .writer = writer,
        .options = .{},
    };
    try json_writer.write(value);
}

fn writeRuntimeScalar(writer: *std.Io.Writer, scalar: RuntimeScalarSpec) !void {
    // Use cs() shorthand for constant-only scalars
    if (scalar.expr == null) {
        try writer.print("cs({})", .{scalar.value});
        return;
    }
    try writer.writeAll(".{");
    var wrote_field = false;
    if (scalar.value != 0) {
        try writer.print(" .value = {}", .{scalar.value});
        wrote_field = true;
    }
    if (scalar.expr) |expr_str| {
        if (wrote_field) try writer.writeAll(",");
        try writer.writeAll(" .expr = ");
        try writeQuotedString(writer, expr_str);
        wrote_field = true;
    }
    if (wrote_field) {
        try writer.writeAll(" }");
    } else {
        try writer.writeAll("}");
    }
}

/// Write a RuntimeVec2Spec. Uses cv2(x,y) shorthand when both components are
/// constant values, otherwise uses full struct syntax.
fn writeRuntimeVec2(writer: *std.Io.Writer, vec: RuntimeVec2Spec) !void {
    if (vec.x.expr == null and vec.y.expr == null) {
        try writer.print("cv2({}, {})", .{ vec.x.value, vec.y.value });
        return;
    }
    try writer.writeAll(".{ .x = ");
    try writeRuntimeScalar(writer, vec.x);
    try writer.writeAll(", .y = ");
    try writeRuntimeScalar(writer, vec.y);
    try writer.writeAll(" }");
}

fn writeSegment(writer: *std.Io.Writer, indent_level: usize, segment: PathSegmentSpec) !void {
    switch (segment.kind) {
        .line => {
            try writer.writeAll(".{ .from = ");
            try writeRuntimeVec2(writer, segment.from.?);
            try writer.writeAll(", .to = ");
            try writeRuntimeVec2(writer, segment.to.?);
            try writer.writeAll(" }");
        },
        .arc => {
            const indent = indentation(indent_level);
            const inner = indentation(indent_level + 1);
            try writer.writeAll(".{\n");
            try writer.print("{s}.kind = .arc,\n", .{inner});
            try writer.print("{s}.center = ", .{inner});
            try writeRuntimeVec2(writer, segment.center.?);
            try writer.writeAll(",\n");
            try writer.print("{s}.radius = ", .{inner});
            try writeRuntimeScalar(writer, segment.radius.?);
            try writer.writeAll(",\n");
            try writer.print("{s}.start_angle = ", .{inner});
            try writeRuntimeScalar(writer, segment.start_angle.?);
            try writer.writeAll(",\n");
            try writer.print("{s}.end_angle = ", .{inner});
            try writeRuntimeScalar(writer, segment.end_angle.?);
            try writer.writeAll(",\n");
            if (segment.clockwise) {
                try writer.print("{s}.clockwise = true,\n", .{inner});
            }
            try writer.print("{s}}}", .{indent});
        },
        .bezier => {
            const indent = indentation(indent_level);
            const inner = indentation(indent_level + 1);
            try writer.writeAll(".{\n");
            try writer.print("{s}.kind = .bezier,\n", .{inner});
            try writer.print("{s}.p0 = ", .{inner});
            try writeRuntimeVec2(writer, segment.p0.?);
            try writer.writeAll(",\n");
            try writer.print("{s}.p1 = ", .{inner});
            try writeRuntimeVec2(writer, segment.p1.?);
            try writer.writeAll(",\n");
            try writer.print("{s}.p2 = ", .{inner});
            try writeRuntimeVec2(writer, segment.p2.?);
            try writer.writeAll(",\n");
            try writer.print("{s}.p3 = ", .{inner});
            try writeRuntimeVec2(writer, segment.p3.?);
            try writer.writeAll(",\n");
            try writer.print("{s}}}", .{indent});
        },
    }
}

/// Write a plain Vec2Spec (used for BoundsSpec and SurfaceFrameSpec which
/// do not support expressions).
fn writePlainVec2(writer: *std.Io.Writer, vec: Vec2Spec) !void {
    try writer.print(".{{ .x = {}, .y = {} }}", .{ vec.x, vec.y });
}

fn writeVec3(writer: *std.Io.Writer, vec: Vec3Spec) !void {
    try writer.print(".{{ .x = {}, .y = {}, .z = {} }}", .{ vec.x, vec.y, vec.z });
}

fn runtimeVec2IsDefaultOrigin(value: RuntimeVec2Spec) bool {
    return runtimeScalarIsDefaultZero(value.x) and runtimeScalarIsDefaultZero(value.y);
}

fn runtimeScalarIsDefaultZero(value: RuntimeScalarSpec) bool {
    return value.expr == null and value.value == 0;
}

fn indentation(level: usize) []const u8 {
    return switch (level) {
        0 => "",
        1 => "    ",
        2 => "        ",
        3 => "            ",
        4 => "                ",
        5 => "                    ",
        6 => "                        ",
        7 => "                            ",
        8 => "                                ",
        else => unreachable,
    };
}

test "deriveOutputPath maps json source tree to spec tree" {
    const output = try deriveOutputPath(std.testing.allocator, "a/data/json/template.json");
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("a/data/spec/template_spec.zig", output);
}

test "deriveOutputRoot maps json directory to spec directory" {
    const output = try deriveOutputRoot(std.testing.allocator, "a/data/json");
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("a/data/spec", output);
}

test "deriveOutputPathInRoot preserves relative layout" {
    const output = try deriveOutputPathInRoot(std.testing.allocator, "a/data/spec", "nested/template.json");
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("a/data/spec/nested/template_spec.zig", output);
}

test "validateTemplate accepts arcs, bezier, normalization, and runtime expressions" {
    const template = InputTemplate{
        .key = "folding_carton.test",
        .label = "Test",
        .numeric_params = &.{
            .{ .key = "target_width", .label = "Target Width", .default_value = 100 },
            .{ .key = "fold_angle_rad", .label = "Fold Angle", .default_value = std.math.pi / 2.0 },
        },
        .normalization = .{
            .target_size = .{
                .x = .{ .expr = "target_width" },
                .y = .{ .value = 60 },
            },
        },
        .panels = &.{
            .{
                .name = "left",
                .id = 0,
                .boundary = &.{
                    .{ .from = .{ .x = .{ .value = 0 }, .y = .{ .value = 0 } }, .to = .{ .x = .{ .value = 1 }, .y = .{ .value = 0 } } },
                    .{
                        .kind = .arc,
                        .center = .{ .x = .{ .value = 1 }, .y = .{ .value = 0.5 } },
                        .radius = .{ .value = 0.5 },
                        .start_angle = .{ .value = -std.math.pi / 2.0 },
                        .end_angle = .{ .value = std.math.pi / 2.0 },
                    },
                    .{ .from = .{ .x = .{ .value = 1 }, .y = .{ .value = 1 } }, .to = .{ .x = .{ .value = 0 }, .y = .{ .value = 1 } } },
                    .{ .from = .{ .x = .{ .value = 0 }, .y = .{ .value = 1 } }, .to = .{ .x = .{ .value = 0 }, .y = .{ .value = 0 } } },
                },
            },
            .{
                .name = "right",
                .id = 1,
                .boundary = &.{
                    .{ .from = .{ .x = .{ .value = 1 }, .y = .{ .value = 0 } }, .to = .{ .x = .{ .value = 2 }, .y = .{ .value = 0 } } },
                    .{ .from = .{ .x = .{ .value = 2 }, .y = .{ .value = 0 } }, .to = .{ .x = .{ .value = 2 }, .y = .{ .value = 1 } } },
                    .{ .from = .{ .x = .{ .value = 2 }, .y = .{ .value = 1 } }, .to = .{ .x = .{ .value = 1 }, .y = .{ .value = 1 } } },
                    .{ .from = .{ .x = .{ .value = 1 }, .y = .{ .value = 1 } }, .to = .{ .x = .{ .value = 1 }, .y = .{ .value = 0 } } },
                },
            },
        },
        .folds = &.{
            .{
                .from_panel = "left",
                .to_panel = "right",
                .from_segment_index = 0,
                .to_segment_index = 3,
                .angle_rad = 0,
                .angle_expr = "fold_angle_rad",
                .direction = .toward_inside,
            },
        },
        .linework = &.{
            .{
                .role = .guide,
                .segments = &.{
                    .{
                        .kind = .bezier,
                        .p0 = .{ .x = .{ .value = 0 }, .y = .{ .value = 0.5 } },
                        .p1 = .{ .x = .{ .value = 0.4 }, .y = .{ .value = 0.1 } },
                        .p2 = .{ .x = .{ .value = 1.6 }, .y = .{ .value = 0.9 } },
                        .p3 = .{ .x = .{ .value = 2 }, .y = .{ .value = 0.5 } },
                    },
                },
            },
        },
    };

    try validateTemplate(template);
}

test "renderTemplateSpec emits new schema fields with cv2/cs syntax" {
    const template = InputTemplate{
        .key = "folding_carton.test",
        .label = "Test",
        .numeric_params = &.{
            .{ .key = "target_width", .label = "Target Width", .default_value = 100, .min_value = 1 },
        },
        .select_params = &.{
            .{
                .key = "fold_pattern",
                .label = "Fold Pattern",
                .default_value = "alternating",
                .options = &.{
                    .{ .value = "alternating", .label = "Alternating" },
                    .{ .value = "all_outside", .label = "All Outside" },
                },
            },
        },
        .normalization = .{
            .target_size = .{
                .x = .{ .expr = "target_width" },
                .y = .{ .value = 60 },
            },
            .flip_y = true,
            .scale_mode = .uniform,
        },
        .panels = &.{
            .{
                .name = "lid",
                .id = 0,
                .boundary = &.{
                    .{ .from = .{ .x = .{ .value = 0 }, .y = .{ .value = 0 } }, .to = .{ .x = .{ .value = 1 }, .y = .{ .value = 0 } } },
                    .{
                        .kind = .arc,
                        .center = .{ .x = .{ .value = 1 }, .y = .{ .value = 0.5 } },
                        .radius = .{ .value = 0.5 },
                        .start_angle = .{ .value = -std.math.pi / 2.0 },
                        .end_angle = .{ .value = std.math.pi / 2.0 },
                    },
                    .{ .from = .{ .x = .{ .value = 1 }, .y = .{ .value = 1 } }, .to = .{ .x = .{ .value = 0 }, .y = .{ .value = 1 } } },
                    .{ .from = .{ .x = .{ .value = 0 }, .y = .{ .value = 1 } }, .to = .{ .x = .{ .value = 0 }, .y = .{ .value = 0 } } },
                },
            },
        },
        .folds = &.{
            .{
                .from_panel = "lid",
                .to_panel = "lid",
                .from_segment_index = 0,
                .to_segment_index = 0,
                .angle_rad = 0,
                .angle_expr = "target_width",
                .direction = .toward_inside,
            },
        },
        .linework = &.{
            .{
                .role = .guide,
                .segments = &.{
                    .{
                        .kind = .bezier,
                        .p0 = .{ .x = .{ .value = 0 }, .y = .{ .value = 0.5 } },
                        .p1 = .{ .x = .{ .value = 0.4 }, .y = .{ .value = 0.1 } },
                        .p2 = .{ .x = .{ .value = 0.6 }, .y = .{ .value = 0.9 } },
                        .p3 = .{ .x = .{ .value = 1 }, .y = .{ .value = 0.5 } },
                    },
                },
            },
        },
    };

    const rendered = try renderTemplateSpec(std.testing.allocator, "test.json", "packages/geo-core/src/templates/data/spec/test_spec.zig", template);
    defer std.testing.allocator.free(rendered);

    try std.testing.expect(std.mem.containsAtLeast(u8, rendered, 1, "const cv2 = compiled_spec.cv2;"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rendered, 1, "const cs = compiled_spec.cs;"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rendered, 1, "const Panel = enum(u16) {"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rendered, 1, "fn p(key: Panel) u16 {"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rendered, 1, ".numeric_params = &.{"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rendered, 1, ".select_params = &.{"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rendered, 1, ".normalization = .{"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rendered, 1, ".angle_expr = \"target_width\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rendered, 1, ".kind = .arc"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rendered, 1, ".kind = .bezier"));
    // Verify cv2() shorthand is used for constant coordinates
    try std.testing.expect(std.mem.containsAtLeast(u8, rendered, 1, "cv2("));
    // Verify RuntimeScalarSpec syntax for radius
    try std.testing.expect(std.mem.containsAtLeast(u8, rendered, 1, ".radius = cs("));
    // Verify expression syntax in normalization
    try std.testing.expect(std.mem.containsAtLeast(u8, rendered, 1, ".expr = \"target_width\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rendered, 1, ".id = p(.lid)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rendered, 1, ".from_panel_id = p(.lid)"));
}

test "renderTemplateSpec emits expression syntax for parametric coordinates" {
    const template = InputTemplate{
        .key = "folding_carton.expr_test",
        .label = "Expression Test",
        .numeric_params = &.{
            .{ .key = "width", .label = "Width", .default_value = 100 },
            .{ .key = "height", .label = "Height", .default_value = 50 },
        },
        .panels = &.{
            .{
                .name = "body",
                .id = 0,
                .boundary = &.{
                    // Mix of constant and expression coordinates
                    .{
                        .from = .{ .x = .{ .value = 0 }, .y = .{ .value = 0 } },
                        .to = .{ .x = .{ .expr = "width" }, .y = .{ .value = 0 } },
                    },
                    .{
                        .from = .{ .x = .{ .expr = "width" }, .y = .{ .value = 0 } },
                        .to = .{ .x = .{ .expr = "width" }, .y = .{ .expr = "height" } },
                    },
                    .{
                        .from = .{ .x = .{ .expr = "width" }, .y = .{ .expr = "height" } },
                        .to = .{ .x = .{ .value = 0 }, .y = .{ .expr = "height" } },
                    },
                    .{
                        .from = .{ .x = .{ .value = 0 }, .y = .{ .expr = "height" } },
                        .to = .{ .x = .{ .value = 0 }, .y = .{ .value = 0 } },
                    },
                },
            },
        },
    };

    const rendered = try renderTemplateSpec(std.testing.allocator, "test.json", "packages/geo-core/src/templates/test_spec.zig", template);
    defer std.testing.allocator.free(rendered);

    // cv2(0, 0) for all-constant
    try std.testing.expect(std.mem.containsAtLeast(u8, rendered, 1, "cv2("));
    // Mixed expr: full struct syntax
    try std.testing.expect(std.mem.containsAtLeast(u8, rendered, 1, ".expr = \"width\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rendered, 1, ".expr = \"height\""));
}

test "renderTemplateSpec emits variables block" {
    const template = InputTemplate{
        .key = "folding_carton.vars_test",
        .label = "Variables Test",
        .numeric_params = &.{
            .{ .key = "width", .label = "Width", .default_value = 78 },
            .{ .key = "depth", .label = "Depth", .default_value = 28 },
        },
        .variables = &.{
            .{ .name = "y1", .expr = "width" },
            .{ .name = "y2", .expr = "width + depth" },
        },
        .panels = &.{
            .{
                .name = "body",
                .id = 0,
                .boundary = &.{
                    .{
                        .from = .{ .x = .{ .value = 0 }, .y = .{ .value = 0 } },
                        .to = .{ .x = .{ .value = 10 }, .y = .{ .value = 0 } },
                    },
                    .{
                        .from = .{ .x = .{ .value = 10 }, .y = .{ .value = 0 } },
                        .to = .{ .x = .{ .value = 10 }, .y = .{ .value = 10 } },
                    },
                    .{
                        .from = .{ .x = .{ .value = 10 }, .y = .{ .value = 10 } },
                        .to = .{ .x = .{ .value = 0 }, .y = .{ .value = 10 } },
                    },
                    .{
                        .from = .{ .x = .{ .value = 0 }, .y = .{ .value = 10 } },
                        .to = .{ .x = .{ .value = 0 }, .y = .{ .value = 0 } },
                    },
                },
            },
        },
    };

    const rendered = try renderTemplateSpec(std.testing.allocator, "test.json", "packages/geo-core/src/templates/test_spec.zig", template);
    defer std.testing.allocator.free(rendered);

    try std.testing.expect(std.mem.containsAtLeast(u8, rendered, 1, ".variables = &.{"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rendered, 1, ".name = \"y1\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rendered, 1, ".expr = \"width\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rendered, 1, ".name = \"y2\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rendered, 1, ".expr = \"width + depth\""));
}
