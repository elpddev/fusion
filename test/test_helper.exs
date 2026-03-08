base_excludes = [:external]
env_excludes = if Node.alive?(), do: [:not_distributed], else: [:distributed]
ExUnit.start(exclude: base_excludes ++ env_excludes)
