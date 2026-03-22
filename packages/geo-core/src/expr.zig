const std = @import("std");

pub const EvalError = error{
    InvalidExpression,
    UnresolvedIdentifier,
    DivisionByZero,
    UnexpectedToken,
};

pub const Resolver = struct {
    context: *const anyopaque,
    resolve_fn: *const fn (context: *const anyopaque, name: []const u8) ?f64,

    pub fn resolve(self: Resolver, name: []const u8) ?f64 {
        return self.resolve_fn(self.context, name);
    }

    /// Create a Resolver from a simple function pointer (no context needed).
    pub fn fromFn(comptime func: fn (name: []const u8) ?f64) Resolver {
        const S = struct {
            var dummy: u8 = 0;
            fn wrapper(_: *const anyopaque, name: []const u8) ?f64 {
                return func(name);
            }
        };
        return .{
            .context = @ptrCast(&S.dummy),
            .resolve_fn = S.wrapper,
        };
    }
};

pub fn evaluate(expr_str: []const u8, resolver: Resolver) EvalError!f64 {
    var parser = Parser{ .source = expr_str, .resolver = resolver };
    const result = try parser.parseExpr();
    parser.skipWhitespace();
    if (parser.pos < parser.source.len) return error.UnexpectedToken;
    return result;
}

pub fn extractIdentifiers(comptime expr_str: []const u8) []const []const u8 {
    comptime {
        var identifiers: []const []const u8 = &.{};
        var i: usize = 0;
        while (i < expr_str.len) {
            if (isIdentStart(expr_str[i])) {
                const start = i;
                while (i < expr_str.len and isIdentCont(expr_str[i])) : (i += 1) {}
                const name = expr_str[start..i];
                var found = false;
                for (identifiers) |existing| {
                    if (std.mem.eql(u8, existing, name)) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    identifiers = identifiers ++ .{name};
                }
            } else {
                i += 1;
            }
        }
        return identifiers;
    }
}

const Parser = struct {
    source: []const u8,
    pos: usize = 0,
    resolver: Resolver,

    fn parseExpr(self: *Parser) EvalError!f64 {
        var result = try self.parseTerm();
        while (true) {
            self.skipWhitespace();
            if (self.pos >= self.source.len) break;
            const ch = self.source[self.pos];
            if (ch == '+') {
                self.pos += 1;
                result += try self.parseTerm();
            } else if (ch == '-') {
                self.pos += 1;
                result -= try self.parseTerm();
            } else break;
        }
        return result;
    }

    fn parseTerm(self: *Parser) EvalError!f64 {
        var result = try self.parseUnary();
        while (true) {
            self.skipWhitespace();
            if (self.pos >= self.source.len) break;
            const ch = self.source[self.pos];
            if (ch == '*') {
                self.pos += 1;
                result *= try self.parseUnary();
            } else if (ch == '/') {
                self.pos += 1;
                const divisor = try self.parseUnary();
                if (divisor == 0) return error.DivisionByZero;
                result /= divisor;
            } else break;
        }
        return result;
    }

    fn parseUnary(self: *Parser) EvalError!f64 {
        self.skipWhitespace();
        if (self.pos < self.source.len and self.source[self.pos] == '-') {
            self.pos += 1;
            return -(try self.parseUnary());
        }
        if (self.pos < self.source.len and self.source[self.pos] == '+') {
            self.pos += 1;
            return try self.parseUnary();
        }
        return try self.parseAtom();
    }

    fn parseAtom(self: *Parser) EvalError!f64 {
        self.skipWhitespace();
        if (self.pos >= self.source.len) return error.InvalidExpression;

        const ch = self.source[self.pos];

        if (ch == '(') {
            self.pos += 1;
            const result = try self.parseExpr();
            self.skipWhitespace();
            if (self.pos >= self.source.len or self.source[self.pos] != ')') {
                return error.InvalidExpression;
            }
            self.pos += 1;
            return result;
        }

        if (isDigit(ch) or ch == '.') {
            return self.parseNumber();
        }

        if (isIdentStart(ch)) {
            return self.parseIdentifier();
        }

        return error.UnexpectedToken;
    }

    fn parseNumber(self: *Parser) EvalError!f64 {
        const start = self.pos;
        var has_dot = false;
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (isDigit(c)) {
                self.pos += 1;
            } else if (c == '.' and !has_dot) {
                has_dot = true;
                self.pos += 1;
            } else break;
        }
        if (self.pos == start) return error.InvalidExpression;
        return std.fmt.parseFloat(f64, self.source[start..self.pos]) catch return error.InvalidExpression;
    }

    fn parseIdentifier(self: *Parser) EvalError!f64 {
        const start = self.pos;
        while (self.pos < self.source.len and isIdentCont(self.source[self.pos])) {
            self.pos += 1;
        }
        const name = self.source[start..self.pos];
        return self.resolver.resolve(name) orelse error.UnresolvedIdentifier;
    }

    fn skipWhitespace(self: *Parser) void {
        while (self.pos < self.source.len and (self.source[self.pos] == ' ' or self.source[self.pos] == '\t')) {
            self.pos += 1;
        }
    }
};

fn isDigit(ch: u8) bool {
    return ch >= '0' and ch <= '9';
}

fn isIdentStart(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or ch == '_';
}

fn isIdentCont(ch: u8) bool {
    return isIdentStart(ch) or isDigit(ch);
}

fn testResolverFn(name: []const u8) ?f64 {
    const table = .{
        .{ "width", 78.0 },
        .{ "length", 95.0 },
        .{ "depth", 28.0 },
        .{ "lid_length", 52.0 },
        .{ "margin", 5.0 },
    };
    inline for (table) |entry| {
        if (std.mem.eql(u8, name, entry[0])) return entry[1];
    }
    return null;
}

const testResolver = Resolver.fromFn(testResolverFn);

test "evaluate pure numbers" {
    try std.testing.expectApproxEqAbs(@as(f64, 42), try evaluate("42", testResolver), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), try evaluate("3.14", testResolver), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), try evaluate(".5", testResolver), 1e-9);
}

test "evaluate arithmetic" {
    try std.testing.expectApproxEqAbs(@as(f64, 11), try evaluate("3 + 4 * 2", testResolver), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 14), try evaluate("(3 + 4) * 2", testResolver), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 5), try evaluate("10 / 2", testResolver), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 1), try evaluate("7 - 3 * 2", testResolver), 1e-9);
}

test "evaluate unary negation" {
    try std.testing.expectApproxEqAbs(@as(f64, -5), try evaluate("-5", testResolver), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, -7), try evaluate("-(3 + 4)", testResolver), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, -28), try evaluate("-depth", testResolver), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 3), try evaluate("--3", testResolver), 1e-9);
}

test "evaluate identifiers" {
    try std.testing.expectApproxEqAbs(@as(f64, 78), try evaluate("width", testResolver), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 95), try evaluate("length", testResolver), 1e-9);
}

test "evaluate compound expressions with identifiers" {
    try std.testing.expectApproxEqAbs(@as(f64, 106), try evaluate("width + depth", testResolver), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 158), try evaluate("width + depth + lid_length", testResolver), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 134), try evaluate("width + depth * 2", testResolver), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 53), try evaluate("(width + depth) / 2", testResolver), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 47.5), try evaluate("(length - margin * 2) / 2 + margin", testResolver), 1e-9);
}

test "evaluate whitespace handling" {
    try std.testing.expectApproxEqAbs(@as(f64, 106), try evaluate("  width  +  depth  ", testResolver), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 78), try evaluate(" width ", testResolver), 1e-9);
}

test "evaluate errors" {
    try std.testing.expectError(error.UnresolvedIdentifier, evaluate("unknown", testResolver));
    try std.testing.expectError(error.DivisionByZero, evaluate("1 / 0", testResolver));
    try std.testing.expectError(error.InvalidExpression, evaluate("(3 + 4", testResolver));
    try std.testing.expectError(error.InvalidExpression, evaluate("", testResolver));
    try std.testing.expectError(error.InvalidExpression, evaluate("3 + + +", testResolver));
}

test "extractIdentifiers returns unique identifiers" {
    const ids = comptime extractIdentifiers("width + depth * 2 + width");
    try std.testing.expectEqual(@as(usize, 2), ids.len);
    try std.testing.expectEqualStrings("width", ids[0]);
    try std.testing.expectEqualStrings("depth", ids[1]);
}

test "extractIdentifiers handles numbers only" {
    const ids = comptime extractIdentifiers("3 + 4 * 2");
    try std.testing.expectEqual(@as(usize, 0), ids.len);
}

test "extractIdentifiers handles complex expression" {
    const ids = comptime extractIdentifiers("(length - margin * 2) / depth");
    try std.testing.expectEqual(@as(usize, 3), ids.len);
    try std.testing.expectEqualStrings("length", ids[0]);
    try std.testing.expectEqualStrings("margin", ids[1]);
    try std.testing.expectEqualStrings("depth", ids[2]);
}
