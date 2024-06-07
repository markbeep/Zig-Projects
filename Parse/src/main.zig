const std = @import("std");
const ts = @cImport({
    @cInclude("tree_sitter/api.h");
});
const tsx = @cImport({
    @cInclude("tree-sitter-tsx.h");
});

const Language = extern struct {};

const Parser = extern struct {
    const errors = error{
        FailedParserCreation,
        FailedToSetLanguage,
        LanguageTagNotFound,
        FailedToParseString,
    };

    extern "asdasd" fn ts_parser_new() ?*Parser;
    extern fn ts_parser_delete(self: ?*Parser) void;
    extern fn ts_parser_language(self: ?*const Parser) ?*const Language;
    extern fn ts_parser_set_language(self: ?*Parser, language: ?*const Language) bool;
    extern fn ts_parser_set_included_ranges(self: ?*Parser, ranges: [*c]const ts.TSRange, count: u32) bool;
    extern fn ts_parser_included_ranges(self: ?*const Parser, count: [*c]u32) [*c]const ts.TSRange;
    extern fn ts_parser_parse(self: ?*Parser, old_tree: ?*const Tree, input: ts.TSInput) ?*Tree;
    extern fn ts_parser_parse_string(self: ?*Parser, old_tree: ?*const Tree, string: [*c]const u8, length: u32) ?*Tree;
    extern fn ts_parser_parse_string_encoding(self: ?*Parser, old_tree: ?*const Tree, string: [*c]const u8, length: u32, encoding: ts.TSInputEncoding) ?*Tree;
    extern fn ts_parser_reset(self: ?*Parser) void;
    extern fn ts_parser_set_timeout_micros(self: ?*Parser, timeout_micros: u64) void;
    extern fn ts_parser_timeout_micros(self: ?*const Parser) u64;
    extern fn ts_parser_set_cancellation_flag(self: ?*Parser, flag: [*c]const usize) void;
    extern fn ts_parser_cancellation_flag(self: ?*const Parser) [*c]const usize;
    extern fn ts_parser_set_logger(self: ?*Parser, logger: ts.TSLogger) void;
    extern fn ts_parser_logger(self: ?*const Parser) ts.TSLogger;
    extern fn ts_parser_print_dot_graphs(self: ?*Parser, fd: c_int) void;

    extern fn tree_sitter_tsx() ?*const Language;

    fn new() !*Parser {
        return ts_parser_new() orelse return errors.FailedParserCreation;
    }
    fn delete(self: *Parser) void {
        ts_parser_delete(self);
    }
    fn language(self: *Parser) *Language {
        return ts_parser_language(self);
    }
    fn setLanguage(self: *Parser, comptime language_string: []const u8) !void {
        const TaggedLanguage = struct {
            tag: []const u8,
            init: *const fn () callconv(.C) ?*const Language,
        };
        const languages = [_]TaggedLanguage{
            TaggedLanguage{ .tag = "tsx", .init = tree_sitter_tsx },
        };
        const index: ?usize = brk: {
            for (languages, 0..) |tl, i| {
                if (std.mem.eql(u8, tl.tag, language_string)) {
                    break :brk i;
                }
            }
            break :brk null;
        };

        if (index) |i| {
            if (!ts_parser_set_language(self, languages[i].init())) {
                return errors.FailedToSetLanguage;
            }
        } else {
            return errors.LanguageTagNotFound;
        }
    }
    fn parseString(self: *Parser, old_tree: ?*const Tree, string: []const u8) !*Tree {
        return ts_parser_parse_string(self, old_tree, string.ptr, @intCast(string.len)) orelse return errors.FailedToParseString;
    }
};

const TreeCursor = struct {
    extern fn ts_tree_cursor_new(node: Node) TreeCursor;
    extern fn ts_tree_cursor_delete(self: [*c]TreeCursor) void;
    extern fn ts_tree_cursor_reset(self: [*c]TreeCursor, node: Node) void;
    extern fn ts_tree_cursor_reset_to(dst: [*c]TreeCursor, src: [*c]const TreeCursor) void;
    extern fn ts_tree_cursor_current_node(self: [*c]const TreeCursor) Node;
    extern fn ts_tree_cursor_current_field_name(self: [*c]const TreeCursor) [*c]const u8;
    extern fn ts_tree_cursor_current_field_id(self: [*c]const TreeCursor) ts.TSFieldId;
    extern fn ts_tree_cursor_goto_parent(self: [*c]TreeCursor) bool;
    extern fn ts_tree_cursor_goto_next_sibling(self: [*c]TreeCursor) bool;
    extern fn ts_tree_cursor_goto_previous_sibling(self: [*c]TreeCursor) bool;
    extern fn ts_tree_cursor_goto_first_child(self: [*c]TreeCursor) bool;
    extern fn ts_tree_cursor_goto_last_child(self: [*c]TreeCursor) bool;
    extern fn ts_tree_cursor_goto_descendant(self: [*c]TreeCursor, goal_descendant_index: u32) void;
    extern fn ts_tree_cursor_current_descendant_index(self: [*c]const TreeCursor) u32;
    extern fn ts_tree_cursor_current_depth(self: [*c]const TreeCursor) u32;
    extern fn ts_tree_cursor_goto_first_child_for_byte(self: [*c]TreeCursor, goal_byte: u32) i64;
    extern fn ts_tree_cursor_goto_first_child_for_point(self: [*c]TreeCursor, goal_point: ts.TSPoint) i64;
    extern fn ts_tree_cursor_copy(cursor: [*c]const TreeCursor) TreeCursor;
};

const Tree = extern struct {
    extern fn ts_tree_copy(self: ?*const Tree) ?*Tree;
    extern fn ts_tree_delete(self: ?*Tree) void;
    extern fn ts_tree_root_node(self: ?*const Tree) Node;
    extern fn ts_tree_root_node_with_offset(self: ?*const Tree, offset_bytes: u32, offset_extent: ts.TSPoint) Node;
    extern fn ts_tree_language(self: ?*const Tree) ?*const Language;
    extern fn ts_tree_included_ranges(self: ?*const Tree, length: [*c]u32) [*c]ts.TSRange;
    extern fn ts_tree_edit(self: ?*Tree, edit: [*c]const ts.TSInputEdit) void;
    extern fn ts_tree_get_changed_ranges(old_tree: ?*const Tree, new_tree: ?*const Tree, length: [*c]u32) [*c]ts.TSRange;
    extern fn ts_tree_print_dot_graph(self: ?*const Tree, file_descriptor: c_int) void;

    fn delete(self: ?*Tree) void {
        ts_tree_delete(self);
    }
    fn rootNode(self: ?*Tree) Node {
        return ts_tree_root_node(self);
    }
};

const Node = extern struct {
    context: [4]u32,
    id: ?*const anyopaque,
    tree: ?*const Tree,

    extern fn ts_node_type(self: Node) [*c]const u8;
    extern fn ts_node_symbol(self: Node) ts.TSSymbol;
    extern fn ts_node_language(self: Node) ?*const Language;
    extern fn ts_node_grammar_type(self: Node) [*c]const u8;
    extern fn ts_node_grammar_symbol(self: Node) ts.TSSymbol;
    extern fn ts_node_start_byte(self: Node) u32;
    extern fn ts_node_start_point(self: Node) ts.TSPoint;
    extern fn ts_node_end_byte(self: Node) u32;
    extern fn ts_node_end_point(self: Node) ts.TSPoint;
    extern fn ts_node_string(self: Node) [*c]u8;
    extern fn ts_node_is_null(self: Node) bool;
    extern fn ts_node_is_named(self: Node) bool;
    extern fn ts_node_is_missing(self: Node) bool;
    extern fn ts_node_is_extra(self: Node) bool;
    extern fn ts_node_has_changes(self: Node) bool;
    extern fn ts_node_has_error(self: Node) bool;
    extern fn ts_node_is_error(self: Node) bool;
    extern fn ts_node_parse_state(self: Node) ts.TSStateId;
    extern fn ts_node_next_parse_state(self: Node) ts.TSStateId;
    extern fn ts_node_parent(self: Node) Node;
    extern fn ts_node_child_containing_descendant(self: Node, descendant: Node) Node;
    extern fn ts_node_child(self: Node, child_index: u32) Node;
    extern fn ts_node_field_name_for_child(self: Node, child_index: u32) [*c]const u8;
    extern fn ts_node_child_count(self: Node) u32;
    extern fn ts_node_named_child(self: Node, child_index: u32) Node;
    extern fn ts_node_named_child_count(self: Node) u32;
    extern fn ts_node_child_by_field_name(self: Node, name: [*c]const u8, name_length: u32) Node;
    extern fn ts_node_child_by_field_id(self: Node, field_id: ts.TSFieldId) Node;
    extern fn ts_node_next_sibling(self: Node) Node;
    extern fn ts_node_prev_sibling(self: Node) Node;
    extern fn ts_node_next_named_sibling(self: Node) Node;
    extern fn ts_node_prev_named_sibling(self: Node) Node;
    extern fn ts_node_first_child_for_byte(self: Node, byte: u32) Node;
    extern fn ts_node_first_named_child_for_byte(self: Node, byte: u32) Node;
    extern fn ts_node_descendant_count(self: Node) u32;
    extern fn ts_node_descendant_for_byte_range(self: Node, start: u32, end: u32) Node;
    extern fn ts_node_descendant_for_point_range(self: Node, start: ts.TSPoint, end: ts.TSPoint) Node;
    extern fn ts_node_named_descendant_for_byte_range(self: Node, start: u32, end: u32) Node;
    extern fn ts_node_named_descendant_for_point_range(self: Node, start: ts.TSPoint, end: ts.TSPoint) Node;
    extern fn ts_node_edit(self: [*c]Node, edit: [*c]const ts.TSInputEdit) void;
    extern fn ts_node_eq(self: Node, other: Node) bool;

    fn init(node: Tree) Node {
        return Node{
            .context = node.context,
            .id = node.id,
            .tree = node.tree,
        };
    }
    fn childCount(self: Node) u32 {
        return self.ts_node_child_count();
    }
    fn string(self: Node) []const u8 {
        const str = ts_node_string(self);
        return std.mem.span(str);
    }

    // fn getType(self: Node) []const u8 {
    //     return std.mem.span(void); // TODO
    // }
};

pub fn main() !void {
    const parser = try Parser.new();
    defer parser.delete();
    try parser.setLanguage("tsx");

    const source_code = "const a = 1;";
    const tree = try parser.parseString(null, source_code);
    defer tree.delete();

    const root_node = tree.rootNode();
    std.debug.print("↳ {s}", .{root_node.string()});
    // printTree(root_node, 0);

    // const n = Node.init(root_node);
    // std.debug.print("\nNODE COUNT = {}\n", .{n.childCount()});
}

fn compareNodeType(comptime tag: []const u8, node: ts.TSNode) bool {
    const node_type = ts.ts_node_type(node);
    return std.mem.eql(u8, tag, node_type[0..tag.len]);
}

fn printTree(node: ts.TSNode, level: usize) void {
    // spacing
    std.debug.print("\n", .{});
    for (0..level) |_| {
        std.debug.print("  ", .{});
    }
    std.debug.print("↳ ", .{});

    const node_string = ts.ts_node_string(node);
    std.debug.print("{s} named={}", .{ node_string, ts.ts_node_is_named(node) });

    const child_count = ts.ts_node_child_count(node);
    for (0..child_count) |i| {
        const child_node = ts.ts_node_child(node, @intCast(i));
        printTree(child_node, level + 1);
    }
}
