# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :leaxer_core,
  generators: [timestamp_type: :utc_datetime],
  # Path to bundled tools (libvips, etc.) - relative to project root
  tools_dir: Path.expand("../tools", __DIR__)

# Configure the Queue
config :leaxer_core, LeaxerCore.Queue, batching_enabled: true

# Configure the SD Server Pool
# pool_size: Number of sd-server instances to run in parallel
# base_port: Starting port number (instances use base_port, base_port+1, ...)
config :leaxer_core, LeaxerCore.Workers.SDServerPool,
  pool_size: 1,
  base_port: 1234

# Configure individual SD Server instances
# taesd_enabled: Use Tiny AutoEncoder for 2x faster decode (lower quality)
# vae_on_cpu: Move VAE to RAM, keep UNet on GPU (saves VRAM)
# vae_tiling: Process VAE in tiles to handle large images without OOM
# Note: taesd_path is resolved dynamically at runtime via LeaxerCore.Paths
config :leaxer_core, LeaxerCore.Workers.StableDiffusionServer,
  taesd_enabled: false,
  vae_on_cpu: false,
  vae_tiling: true

# Configure the endpoint
config :leaxer_core, LeaxerCoreWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: LeaxerCoreWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: LeaxerCore.PubSub

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  leaxer_core: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../apps/leaxer_core/assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  leaxer_core: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("../apps/leaxer_core", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

# Sample configuration:
#
#     config :logger, :default_handler,
#       level: :info
#
#     config :logger, :default_formatter,
#       format: "$date $time [$level] $metadata$message\n",
#       metadata: [:user_id]
#
