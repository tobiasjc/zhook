const std = @import("std");

const allocator = std.heap.page_allocator;
const ModuleData = struct {
    root_path: []const u8,
    deps_names: []const []const u8,
};

pub fn build(b: *std.Build) void {
    // 1. define target and optimization options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 2. create lib modules
    var lib_module_datas = std.StringHashMap(ModuleData).init(allocator);
    defer lib_module_datas.deinit();

    lib_module_datas.put("git", .{ .root_path = "src/lib/git/git.zig", .deps_names = &[_][]u8{} }) catch unreachable;
    lib_module_datas.put("sql", .{ .root_path = "src/lib/sql/sql.zig", .deps_names = &[_][]u8{} }) catch unreachable;
    var lib_modules = createRootModules(lib_module_datas, b, target, optimize);
    defer lib_modules.deinit();

    // 2.1. static libs
    var lib_compile_steps = createLibCompileSteps(lib_modules, b);
    defer lib_compile_steps.deinit();

    // 3. create exe modules
    var exe_module_datas = std.StringHashMap(ModuleData).init(allocator);
    defer exe_module_datas.deinit();

    exe_module_datas.put("pre-receive", .{ .root_path = "src/pre-receive.zig", .deps_names = &[_][]const u8{"git"} }) catch unreachable;
    exe_module_datas.put("update", .{ .root_path = "src/update.zig", .deps_names = &[_][]const u8{"git"} }) catch unreachable;
    exe_module_datas.put("post-receive", .{ .root_path = "src/post-receive.zig", .deps_names = &[_][]const u8{"git"} }) catch unreachable;

    var exe_modules = createRootModules(exe_module_datas, b, target, optimize);
    defer exe_modules.deinit();

    // 3.1 link exe modules to lib dependencies
    var exe_module_datas_it = exe_module_datas.iterator();
    while (exe_module_datas_it.next()) |exe_modules_entry| {
        const exe_module_name = exe_modules_entry.key_ptr.*;
        const exe_module_data = exe_modules_entry.value_ptr.*;
        const exe_module_deps_names = exe_module_data.deps_names;

        const exe_module = exe_modules.get(exe_module_name).?;
        for (exe_module_deps_names) |exe_module_dep_name| {
            const lib_module = lib_modules.get(exe_module_dep_name).?;
            exe_module.addImport(exe_module_dep_name, lib_module);
        }
    }

    // 4. create executables
    var exe_compile_steps = createExeCompileSteps(exe_modules, b);
    defer exe_compile_steps.deinit();

    // 5. create run commands
    var run_steps = createRunSteps(exe_compile_steps, b);
    defer run_steps.deinit();

    // 6. create individual run tests
    var lib_test_steps = createTestSteps(lib_modules, b);
    defer lib_test_steps.deinit();

    var exe_test_steps = createTestSteps(exe_modules, b);
    defer exe_test_steps.deinit();

    // 7. create global run test
    _ = createAllTestStep(lib_test_steps, b);
    _ = createAllTestStep(exe_test_steps, b);
}

pub fn createRootModules(modules_data: std.StringHashMap(ModuleData), b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) std.StringHashMap(*std.Build.Module) {
    var modules = std.StringHashMap(*std.Build.Module).init(allocator);

    var modules_data_it = modules_data.iterator();
    while (modules_data_it.next()) |name_to_path_entry| {
        const name = name_to_path_entry.key_ptr.*;
        const module_data = name_to_path_entry.value_ptr.*;

        const module_root_path = module_data.root_path;
        const module = createRootModule(module_root_path, b, target, optimize);
        modules.put(name, module) catch unreachable;
    }

    return modules;
}

pub fn createRootModule(root_path: []const u8, b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    const exe_mod = b.createModule(.{
        .root_source_file = b.path(root_path),
        .target = target,
        .optimize = optimize,
    });

    return exe_mod;
}

pub fn createLibCompileSteps(root_modules: std.StringHashMap(*std.Build.Module), b: *std.Build) std.StringHashMap(*std.Build.Step.Compile) {
    var libs = std.StringHashMap(*std.Build.Step.Compile).init(allocator);

    var modules_it = root_modules.iterator();
    while (modules_it.next()) |module_entry| {
        const module_name = module_entry.key_ptr.*;
        const module = module_entry.value_ptr.*;

        const lib = createLibCompileStep(module_name, module, b);
        libs.put(module_name, lib) catch unreachable;
    }

    return libs;
}

pub fn createLibCompileStep(name: []const u8, root_module: *std.Build.Module, b: *std.Build) *std.Build.Step.Compile {
    const lib_step = b.addLibrary(.{
        .linkage = .static,
        .name = name,
        .root_module = root_module,
    });
    b.installArtifact(lib_step);

    return lib_step;
}

pub fn createExeCompileSteps(root_modules: std.StringHashMap(*std.Build.Module), b: *std.Build) std.StringHashMap(*std.Build.Step.Compile) {
    var exe_steps = std.StringHashMap(*std.Build.Step.Compile).init(allocator);

    var modules_it = root_modules.iterator();
    while (modules_it.next()) |module_entry| {
        const module_name = module_entry.key_ptr.*;
        const module = module_entry.value_ptr.*;

        const exe_step = createExeCompileStep(module_name, module, b);
        exe_steps.put(module_name, exe_step) catch unreachable;
    }

    return exe_steps;
}

pub fn createExeCompileStep(name: []const u8, root_module: *std.Build.Module, b: *std.Build) *std.Build.Step.Compile {
    const exe_step = b.addExecutable(.{
        .name = name,
        .root_module = root_module,
    });
    b.installArtifact(exe_step);

    return exe_step;
}

pub fn createRunSteps(exe_steps: std.StringHashMap(*std.Build.Step.Compile), b: *std.Build) std.StringHashMap(*std.Build.Step.Run) {
    var run_steps = std.StringHashMap(*std.Build.Step.Run).init(allocator);

    var exe_steps_it = exe_steps.iterator();
    while (exe_steps_it.next()) |exe_step_entry| {
        const name = exe_step_entry.key_ptr.*;
        const exe_step = exe_step_entry.value_ptr.*;

        const run_cmd_name = std.mem.concat(allocator, u8, &[_][]const u8{ "run-", name }) catch unreachable;
        const run_description = std.mem.concat(allocator, u8, &[_][]const u8{ "Run the executable ", name }) catch unreachable;
        const run_step = createRunStep(run_cmd_name, run_description, exe_step, b);
        run_steps.put(name, run_step) catch unreachable;
    }

    return run_steps;
}

pub fn createRunStep(run_cmd_name: []const u8, run_description: []const u8, exe_step: *std.Build.Step.Compile, b: *std.Build) *std.Build.Step.Run {
    const run_step = b.addRunArtifact(exe_step);
    run_step.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_step.addArgs(args);
    }
    const run_cmd = b.step(run_cmd_name, run_description);
    run_cmd.dependOn(&run_step.step);

    return run_step;
}

pub fn createAllTestStep(compile_steps: std.StringHashMap(*std.Build.Step.Compile), b: *std.Build) *std.Build.Step {
    const test_cmd = if (b.top_level_steps.contains("test")) &b.top_level_steps.get("test").?.step else b.step("test", "Test all modules");

    var compile_steps_vit = compile_steps.valueIterator();
    while (compile_steps_vit.next()) |compile_step_pt| {
        const compile_step = compile_step_pt.*;
        const compile_run_step = b.addRunArtifact(compile_step);
        test_cmd.dependOn(&compile_run_step.step);
    }

    return test_cmd;
}

pub fn createTestSteps(root_modules: std.StringHashMap(*std.Build.Module), b: *std.Build) std.StringHashMap(*std.Build.Step.Compile) {
    var test_steps = std.StringHashMap(*std.Build.Step.Compile).init(allocator);

    var root_modules_it = root_modules.iterator();
    while (root_modules_it.next()) |root_module_entry| {
        const name = root_module_entry.key_ptr.*;
        const root_module = root_module_entry.value_ptr.*;

        const test_cmd_name = std.mem.concat(allocator, u8, &[_][]const u8{ "test-", name }) catch unreachable;
        const test_description = std.mem.concat(allocator, u8, &[_][]const u8{ "Test the module ", name }) catch unreachable;
        const test_step = createTestStep(test_cmd_name, test_description, root_module, b);
        test_steps.put(name, test_step) catch unreachable;
    }

    return test_steps;
}

pub fn createTestStep(test_cmd_name: []const u8, test_description: []const u8, root_module: *std.Build.Module, b: *std.Build) *std.Build.Step.Compile {
    const test_step = b.addTest(.{
        .root_module = root_module,
    });
    const test_run_step = b.addRunArtifact(test_step);
    const test_cmd = b.step(test_cmd_name, test_description);
    test_cmd.dependOn(&test_run_step.step);

    return test_step;
}
