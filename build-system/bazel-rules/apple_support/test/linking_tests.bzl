"""Tests for linking behavior."""

load(
    "//test/rules:action_command_line_test.bzl",
    "make_action_command_line_test_rule",
)

default_test = make_action_command_line_test_rule()

disable_objc_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "-objc_link_flag",
        ],
    },
)

dsym_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:apple_generate_dsym": True,
    },
)

def linking_test_suite(name):
    default_test(
        name = "{}_default_apple_link_test".format(name),
        tags = [name],
        expected_argv = [
            "-Xlinker",
            "-objc_abi_version",
            "-Xlinker",
            "2",
            "-ObjC",
        ],
        not_expected_argv = [
            "-g",
            "DSYM_HINT_LINKED_BINARY",
        ],
        mnemonic = "ObjcLink",
        target_under_test = "//test/test_data:macos_binary",
    )

    disable_objc_test(
        name = "{}_disable_objc_apple_link_test".format(name),
        tags = [name],
        expected_argv = [
            "-Xlinker",
            "-objc_abi_version",
            "-Xlinker",
            "2",
        ],
        not_expected_argv = ["-ObjC"],
        mnemonic = "ObjcLink",
        target_under_test = "//test/test_data:macos_binary",
    )

    dsym_test(
        name = "{}_generate_dsym_test".format(name),
        tags = [name],
        expected_argv = [
            "-g",
            "DSYM_HINT_LINKED_BINARY",
        ],
        mnemonic = "ObjcLink",
        target_under_test = "//test/test_data:macos_binary",
    )
