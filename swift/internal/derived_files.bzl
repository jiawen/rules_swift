# Copyright 2018 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Factory functions for declaring derived files and directories."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load(":utils.bzl", "owner_relative_path")

def _default_path(ctx, add_target_name_to_output_path, basename):
    if add_target_name_to_output_path:
        target_name = ctx.label.name
        return paths.join(target_name, basename)
    else:
        return basename

def _declare_file(actions, add_target_name_to_output_path, target_name, basename):
    if add_target_name_to_output_path:
        return actions.declare_file(paths.join(target_name, basename))
    else:
        return actions.declare_file(basename)

def _declare_directory(actions, add_target_name_to_output_path, target_name, directory):
    if add_target_name_to_output_path:
        return actions.declare_directory("{}_{}".format(target_name, directory))
    else:
        return actions.declare_directory(directory)

def _ast(actions, add_target_name_to_output_path, target_name, src):
    """Declares a file for an ast file during compilation.

    Args:
        actions: The context's actions object.
        add_target_name_to_output_path: Add target_name in output path. More info at SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT description.
        target_name: The name of the target being built.
        src: A `File` representing the source file being compiled.

    Returns:
        The declared `File` where the given src's AST will be dumped to.
    """
    dirname, basename = _intermediate_frontend_file_path(target_name, src)
    return _declare_file(
        actions,
        add_target_name_to_output_path,
        target_name,
        paths.join(dirname, "{}.ast".format(basename)),
    )

def _autolink_flags(actions, add_target_name_to_output_path, target_name):
    """Declares the response file into which autolink flags will be extracted.

    Args:
        actions: The context's actions object.
        add_target_name_to_output_path: Add target_name in output path. More info at SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT description.
        target_name: The name of the target being built.

    Returns:
        The declared `File`.
    """
    return _declare_file(
        actions,
        add_target_name_to_output_path,
        target_name,
        "{}.autolink".format(target_name),
    )

def _executable(actions, add_target_name_to_output_path, target_name):
    """Declares a file for the executable created by a binary or test rule.

    Args:
        actions: The context's actions object.
        add_target_name_to_output_path: Add target_name in output path. More info at SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT description.
        target_name: The name of the target being built.

    Returns:
        The declared `File`.
    """
    return _declare_file(
        actions,
        add_target_name_to_output_path,
        target_name,
        target_name,
    )

def _indexstore_directory(actions, add_target_name_to_output_path, target_name):
    """Declares a directory in which the compiler's indexstore will be written.

    Args:
        actions: The context's actions object.
        add_target_name_to_output_path: Add target_name in output path. More info at SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT description.
        target_name: The name of the target being built.

    Returns:
        The declared `File`.
    """
    return _declare_directory(
        actions,
        add_target_name_to_output_path,
        target_name,
        "{}.indexstore".format(target_name),
    )

def _intermediate_bc_file(actions, add_target_name_to_output_path, target_name, src):
    """Declares a file for an intermediate llvm bc file during compilation.

    Args:
        actions: The context's actions object.
        add_target_name_to_output_path: Add target_name in output path. More info at SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT description.
        target_name: The name of the target being built.
        src: A `File` representing the source file being compiled.

    Returns:
        The declared `File`.
    """
    dirname, basename = _intermediate_frontend_file_path(target_name, src)
    return _declare_file(
        actions,
        add_target_name_to_output_path,
        target_name,
        paths.join(dirname, "{}.bc".format(basename)),
    )

def _intermediate_frontend_file_path(target_name, src):
    """Returns the path to the directory for intermediate compile outputs.

    This is a helper function and is not exported in the `derived_files` module.

    Args:
        target_name: The name of hte target being built.
        src: A `File` representing the source file whose intermediate frontend
            artifacts path should be returned.

    Returns:
        The path to the directory where intermediate artifacts for the given
        target and source file should be stored.
    """
    objs_dir = "{}_objs".format(target_name)

    owner_rel_path = owner_relative_path(src).replace(" ", "__SPACE__")
    safe_name = paths.basename(owner_rel_path)

    return paths.join(objs_dir, paths.dirname(owner_rel_path)), safe_name

def _intermediate_object_file(actions, add_target_name_to_output_path, target_name, src):
    """Declares a file for an intermediate object file during compilation.

    These files are produced when the compiler is invoked with multiple frontend
    invocations (i.e., whole module optimization disabled); in that case, there
    is a `.o` file produced for each source file, rather than a single `.o` for
    the entire module.

    Args:
        actions: The context's actions object.
        add_target_name_to_output_path: Add target_name in output path. More info at SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT description.
        target_name: The name of the target being built.
        src: A `File` representing the source file being compiled.

    Returns:
        The declared `File`.
    """
    dirname, basename = _intermediate_frontend_file_path(target_name, src)
    return _declare_file(
        actions,
        add_target_name_to_output_path,
        target_name,
        paths.join(dirname, "{}.o".format(basename)),
    )

def _module_map(actions, add_target_name_to_output_path, target_name):
    """Declares the module map for a target.

    These module maps are used when generating a Swift-compatible module map for
    a C/Objective-C target, and also when generating the module map for the
    generated header of a Swift target.

    Args:
        actions: The context's actions object.
        add_target_name_to_output_path: Add target_name in output path. More info at SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT description.
        target_name: The name of the target being built.

    Returns:
        The declared `File`.
    """
    return _declare_file(
        actions,
        add_target_name_to_output_path,
        target_name,
        "{}.swift.modulemap".format(target_name),
    )

def _modulewrap_object(actions, add_target_name_to_output_path, target_name):
    """Declares the object file used to wrap Swift modules for ELF binaries.

    Args:
        actions: The context's actions object.
        add_target_name_to_output_path: Add target_name in output path. More info at SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT description.
        target_name: The name of the target being built.

    Returns:
        The declared `File`.
    """
    return _declare_file(
        actions,
        add_target_name_to_output_path,
        target_name,
        "{}.modulewrap.o".format(target_name),
    )

def _declare_validated_generated_header(actions, add_target_name_to_output_path, target_name, generated_header_name):
    """Validates and declares the explicitly named generated header.

    If the file does not have a `.h` extension, the build will fail.

    Args:
        actions: The context's `actions` object.
        add_target_name_to_output_path: Add target_name in output path. More info at SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT description.
        target_name: Executable target name.
        generated_header_name: The desired name of the generated header.

    Returns:
        A `File` that should be used as the output for the generated header.
    """
    extension = paths.split_extension(generated_header_name)[1]
    if extension != ".h":
        fail(
            "The generated header for a Swift module must have a '.h' " +
            "extension (got '{}').".format(generated_header_name),
        )

    return _declare_file(
        actions,
        add_target_name_to_output_path,
        target_name,
        generated_header_name,
    )

def _precompiled_module(actions, add_target_name_to_output_path, target_name):
    """Declares the precompiled module for a C/Objective-C target.

    Args:
        actions: The context's actions object.
        add_target_name_to_output_path: Add target_name in output path. More info at SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT description.
        target_name: The name of the target.

    Returns:
        The declared `File`.
    """
    return _declare_file(
        actions,
        add_target_name_to_output_path,
        target_name,
        "{}.swift.pcm".format(target_name),
    )

def _reexport_modules_src(actions, target_name):
    """Declares a source file used to re-export other Swift modules.

    Args:
        actions: The context's actions object.
        target_name: The name of the target being built.

    Returns:
        The declared `File`.
    """

    return actions.declare_file("{}_exports.swift".format(target_name))

def _static_archive(actions, add_target_name_to_output_path, alwayslink, link_name, target_name):
    """Declares a file for the static archive created by a compilation rule.

    Args:
        actions: The context's actions object.
        add_target_name_to_output_path: Add target_name in output path. More info at SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT description.
        alwayslink: Indicates whether the object files in the library should
            always be always be linked into any binaries that depend on it, even
            if some contain no symbols referenced by the binary.
        link_name: The name of the library being built, without a `lib` prefix
            or file extension.
        target_name: The name of the target being built.

    Returns:
        The declared `File`.
    """
    extension = "lo" if alwayslink else "a"
    return _declare_file(
        actions,
        add_target_name_to_output_path,
        target_name,
        "lib{}.{}".format(link_name, extension),
    )

def _swiftc_output_file_map(actions, add_target_name_to_output_path, target_name):
    """Declares a file for the output file map for a compilation action.

    This JSON-formatted output map file allows us to supply our own paths and
    filenames for the intermediate artifacts produced by multiple frontend
    invocations, rather than using the temporary defaults.

    Args:
        actions: The context's actions object.
        add_target_name_to_output_path: Add target_name in output path. More info at SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT description.
        target_name: The name of the target being built.

    Returns:
        The declared `File`.
    """
    return _declare_file(
        actions,
        add_target_name_to_output_path,
        target_name,
        "{}.output_file_map.json".format(target_name),
    )

def _swiftc_derived_output_file_map(actions, add_target_name_to_output_path, target_name):
    """Declares a file for the output file map for a swiftmodule only action.

    This JSON-formatted output map file allows us to supply our own paths and
    filenames for the intermediate artifacts produced by multiple frontend
    invocations, rather than using the temporary defaults.

    Args:
        actions: The context's actions object.
        add_target_name_to_output_path: Add target_name in output path. More info at SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT description.
        target_name: The name of the target being built.

    Returns:
        The declared `File`.
    """
    return _declare_file(
        actions,
        add_target_name_to_output_path,
        target_name,
        "{}.derived_output_file_map.json".format(target_name),
    )

def _swiftdoc(actions, add_target_name_to_output_path, target_name, module_name):
    """Declares a file for the Swift doc file created by a compilation rule.

    Args:
        actions: The context's actions object.
        add_target_name_to_output_path: Add target_name in output path. More info at SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT description.
        target_name: The name of the target being built.
        module_name: The name of the module being built.

    Returns:
        The declared `File`.
    """
    return _declare_file(
        actions,
        add_target_name_to_output_path,
        target_name,
        "{}.swiftdoc".format(module_name),
    )

def _swiftinterface(actions, add_target_name_to_output_path, target_name, module_name):
    """Declares a file for the Swift interface created by a compilation rule.

    Args:
        actions: The context's actions object.
        add_target_name_to_output_path: Add target_name in output path. More info at SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT description.
        target_name: The name of the target being built.
        module_name: The name of the module being built.

    Returns:
        The declared `File`.
    """
    return _declare_file(
        actions,
        add_target_name_to_output_path,
        target_name,
        "{}.swiftinterface".format(module_name),
    )

def _private_swiftinterface(actions, add_target_name_to_output_path, target_name, module_name):
    """Declares a file for the private Swift interface created by a compilation rule.

    Args:
        actions: The context's actions object.
        add_target_name_to_output_path: Add target_name in output path. More info at SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT description.
        target_name: The name of the target being built.
        module_name: The name of the module being built.

    Returns:
        The declared `File`.
    """
    return _declare_file(
        actions,
        add_target_name_to_output_path,
        target_name,
        "{}.private.swiftinterface".format(module_name),
    )

def _swiftmodule(actions, add_target_name_to_output_path, target_name, module_name):
    """Declares a file for the Swift module created by a compilation rule.

    Args:
        actions: The context's actions object.
        add_target_name_to_output_path: Add target_name in output path. More info at SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT description.
        target_name: The name of the target being built.
        module_name: The name of the module being built.

    Returns:
        The declared `File`.
    """
    return _declare_file(
        actions,
        add_target_name_to_output_path,
        target_name,
        "{}.swiftmodule".format(module_name),
    )

def _swiftsourceinfo(actions, add_target_name_to_output_path, target_name, module_name):
    """Declares a file for the Swift sourceinfo created by a compilation rule.

    Args:
        actions: The context's actions object.
        add_target_name_to_output_path: Add target_name in output path. More info at SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT description.
        target_name: The name of the target being built.
        module_name: The name of the module being built.

    Returns:
        The declared `File`.
    """
    return _declare_file(
        actions,
        add_target_name_to_output_path,
        target_name,
        "{}.swiftsourceinfo".format(module_name),
    )

def _symbol_graph_directory(actions, target_name):
    """Declares a directory for symbol graphs extracted from a Swift module.

    Args:
        actions: The context's actions object.
        target_name: The name of the target being built.

    Returns:
        The declared `File`.
    """
    return actions.declare_directory("{}.symbolgraphs".format(target_name))

def _vfsoverlay(actions, add_target_name_to_output_path, target_name):
    """Declares a file for the VFS overlay for a compilation action.

    The VFS overlay is YAML-formatted file that allows us to place the
    `.swiftmodule` files for all dependencies into a single virtual search
    path, independent of the actual file system layout.

    Args:
        actions: The context's actions object.
        add_target_name_to_output_path: Add target_name in output path. More info at SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT description.
        target_name: The name of the target being built.

    Returns:
        The declared `File`.
    """
    return _declare_file(
        actions,
        add_target_name_to_output_path,
        target_name,
        "{}.vfsoverlay.yaml".format(target_name),
    )

def _whole_module_object_file(actions, add_target_name_to_output_path, target_name):
    """Declares a file for object files created with whole module optimization.

    This is the output of a compile action when whole module optimization is
    enabled, which means that the driver produces a single frontend invocation
    that compiles all the source files at once.

    Args:
        actions: The context's actions object.
        add_target_name_to_output_path: Add target_name in output path. More info at SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT description.
        target_name: The name of the target being built.

    Returns:
        The declared `File`.
    """
    return _declare_file(
        actions,
        add_target_name_to_output_path,
        target_name,
        "{}.o".format(target_name),
    )

def _swift_const_values_file(actions, target_name):
    """Declares a file for the Swift const values.

    Args:
        actions: The context's actions object.
        target_name: The name of the target being built.

    Returns:
        The declared `File`.
    """
    return actions.declare_file("{}.swiftconstvalues".format(target_name))

def _intermediate_swift_const_values_file(actions, target_name, src):
    """Declares a file for an intermediate Swift const values file during compilation.

    These files are produced when the compiler is invoked with multiple frontend
    invocations (i.e., whole module optimization disabled); in that case, there
    is a `.swiftconstvalues` file produced for each source file, rather than a single
    `.swiftconstvalues` for the entire module.

    Args:
        actions: The context's actions object.
        target_name: The name of the target being built.
        src: A `File` representing the source file being compiled.

    Returns:
        The declared `File`.
    """
    dirname, basename = _intermediate_frontend_file_path(target_name, src)
    return actions.declare_file(
        paths.join(dirname, "{}.swiftconstvalues".format(basename)),
    )

def _xctest_runner_script(actions, add_target_name_to_output_path, target_name):
    """Declares a file for the script that runs an `.xctest` bundle on Darwin.

    Args:
        actions: The context's actions object.
        add_target_name_to_output_path: Add target_name in output path. More info at SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT description.
        target_name: The name of the target being built.

    Returns:
        The declared `File`.
    """
    return _declare_file(
        actions,
        add_target_name_to_output_path,
        target_name,
        "{}.test-runner.sh".format(target_name),
    )

derived_files = struct(
    ast = _ast,
    autolink_flags = _autolink_flags,
    executable = _executable,
    indexstore_directory = _indexstore_directory,
    intermediate_bc_file = _intermediate_bc_file,
    intermediate_object_file = _intermediate_object_file,
    intermediate_swift_const_values_file = _intermediate_swift_const_values_file,
    module_map = _module_map,
    modulewrap_object = _modulewrap_object,
    path = _default_path,
    precompiled_module = _precompiled_module,
    private_swiftinterface = _private_swiftinterface,
    reexport_modules_src = _reexport_modules_src,
    static_archive = _static_archive,
    swiftc_output_file_map = _swiftc_output_file_map,
    swiftc_derived_output_file_map = _swiftc_derived_output_file_map,
    swiftdoc = _swiftdoc,
    swiftinterface = _swiftinterface,
    swiftmodule = _swiftmodule,
    swiftsourceinfo = _swiftsourceinfo,
    symbol_graph_directory = _symbol_graph_directory,
    vfsoverlay = _vfsoverlay,
    whole_module_object_file = _whole_module_object_file,
    swift_const_values_file = _swift_const_values_file,
    xctest_runner_script = _xctest_runner_script,
    generated_header = _declare_validated_generated_header,
)
