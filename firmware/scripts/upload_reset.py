Import("env")


def connect_under_reset(source, target, env):
    # Configure reset after the target is selected, before programming starts.
    flags = list(env["UPLOADERFLAGS"])
    flags[-2:-2] = [
        "-c", "adapter speed 100",
        "-c", "reset_config srst_only srst_nogate connect_assert_srst",
    ]
    env.Replace(UPLOADERFLAGS=flags)


env.AddPreAction("upload", connect_under_reset)
