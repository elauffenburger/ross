const std = @import("std");

pub fn Exclude(T: type, exclude: anytype) type {
    // Make sure T is a struct.
    switch (@typeInfo(T)) {
        .@"struct" => {},
        else => @compileError(std.fmt.comptimePrint("T must be a struct but was {any}", .{@TypeOf(T)})),
    }
    const t = @typeInfo(T).@"struct";

    // Make sure exclude is a tuple of strings.
    switch (@typeInfo(@TypeOf(exclude))) {
        .@"struct" => |s| {
            if (!s.is_tuple) {
                @compileError("exclude must be a tuple of strings");
            }
        },
        else => @compileError(std.fmt.comptimePrint("exclude must be a tuple of strings but was {any}", .{@TypeOf(exclude)})),
    }
    const excl = @typeInfo(@TypeOf(exclude)).@"struct";

    // Copy over fields that aren't defined in exclude.
    var fields: [t.fields.len - excl.fields.len]std.builtin.Type.StructField = undefined;
    var field_i = 0;
    fields_loop: for (t.fields) |f| {
        for (exclude) |exclude_field_name| {
            if (std.mem.eql(u8, f.name, exclude_field_name)) {
                continue :fields_loop;
            }
        }

        fields[field_i] = f;
        field_i += 1;
    }

    return @Type(.{
        .@"struct" = std.builtin.Type.Struct{
            .is_tuple = false,
            .layout = .auto,
            .backing_integer = null,
            .decls = &[0]std.builtin.Type.Declaration{},
            .fields = &fields,
        },
    });
}

pub fn And(T: type, @"and": type) type {
    // Make sure T is a struct.
    switch (@typeInfo(T)) {
        .@"struct" => {},
        else => @compileError(std.fmt.comptimePrint("T must be a struct but was {any}", .{@TypeOf(T)})),
    }
    const t = @typeInfo(T).@"struct";

    // Make sure and is a struct with just fields.
    switch (@typeInfo(@"and")) {
        .@"struct" => |s| {
            if (s.decls.len != 0) {
                @compileError("and must contain only fields");
            }
        },
        else => @compileError(std.fmt.comptimePrint("and must be a struct but was {any}", .{@TypeOf(@"and")})),
    }
    const a = @typeInfo(@"and").@"struct";

    // Init fields with T's fields.
    var fields: [t.fields.len + a.fields.len]std.builtin.Type.StructField = undefined;
    std.mem.copyForwards(std.builtin.Type.StructField, &fields, t.fields);

    // Add fields from and to the fields from T.
    for (a.fields, 0..a.fields.len) |f, i| {
        // Make sure T doesn't already contain a field with the same name.
        for (t.fields) |a_f| {
            if (std.mem.eql(u8, f.name, a_f.name)) {
                @compileError(std.fmt.comptimePrint("T already contains a field named {s}", .{a_f.name}));
            }
        }

        fields[t.fields.len + i] = f;
    }

    return @Type(.{
        .@"struct" = std.builtin.Type.Struct{
            .is_tuple = false,
            .layout = .auto,
            .backing_integer = null,
            .decls = &[0]std.builtin.Type.Declaration{},
            .fields = &fields,
        },
    });
}
