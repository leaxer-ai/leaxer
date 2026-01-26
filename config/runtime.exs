import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# Helper function to get the default user directory based on OS
defmodule RuntimeHelpers do
  def default_user_dir do
    case :os.type() do
      {:unix, :darwin} ->
        Path.expand("~/Documents/Leaxer")

      {:unix, _} ->
        xdg_data = System.get_env("XDG_DATA_HOME") || Path.expand("~/.local/share")
        Path.join(xdg_data, "Leaxer")

      {:win32, _} ->
        user_profile = System.get_env("USERPROFILE") || Path.expand("~")
        Path.join([user_profile, "Documents", "Leaxer"])
    end
  end

  def user_dir do
    System.get_env("LEAXER_USER_DIR") || default_user_dir()
  end

  def config_path do
    Path.join(user_dir(), "config.json")
  end

  def network_exposure_enabled? do
    # Environment variable override takes precedence
    if System.get_env("LEAXER_BIND_ALL_INTERFACES") == "true" do
      true
    else
      # Otherwise, check config.json
      case File.read(config_path()) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, config} -> config["network_exposure_enabled"] == true
            _ -> false
          end

        _ ->
          false
      end
    end
  end
end

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/leaxer_core start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :leaxer_core, LeaxerCoreWeb.Endpoint, server: true
end

# Secret key base and signing salt configuration for all environments
# These secrets should be provided via environment variables
# In test environment, use default secrets for convenience
secret_key_base =
  System.get_env("SECRET_KEY_BASE") ||
    if config_env() == :test do
      "test_secret_key_base_at_least_64_bytes_long_for_testing_purposes_only_do_not_use_in_production"
    else
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """
    end

signing_salt =
  System.get_env("SIGNING_SALT") ||
    if config_env() == :test do
      "test_signing_salt_for_testing"
    else
      raise """
      environment variable SIGNING_SALT is missing.
      You can generate one by calling: mix phx.gen.secret
      """
    end

# Configure endpoint with secrets from environment
config :leaxer_core, LeaxerCoreWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))],
  secret_key_base: secret_key_base,
  live_view: [signing_salt: signing_salt]

# Configure dynamic TAESD path based on user's models directory
# This uses LeaxerCore.Paths.models_dir() which resolves to ~/Documents/Leaxer/models
# We must use compile-time path resolution here since Paths module uses Application config
taesd_path =
  case System.get_env("LEAXER_TAESD_PATH") do
    nil ->
      # Default path: ~/Documents/Leaxer/models/taesd/taesd_decoder.safetensors
      Path.join([
        RuntimeHelpers.user_dir(),
        "models",
        "taesd",
        "taesd_decoder.safetensors"
      ])

    path ->
      path
  end

config :leaxer_core, LeaxerCore.Workers.StableDiffusionServer, taesd_path: taesd_path

# Check if network exposure is enabled (from config.json or env var)
network_exposure_enabled = RuntimeHelpers.network_exposure_enabled?()

# CORS configuration for all environments
# In development, this uses sensible defaults for common dev server ports
# In production, set CORS_ORIGINS env var to a comma-separated list of allowed origins
# Example: CORS_ORIGINS="https://app.example.com,https://admin.example.com"
#
# When network exposure is enabled, allow private network IP ranges
cors_origins =
  case {System.get_env("CORS_ORIGINS"), config_env(), network_exposure_enabled} do
    # Explicit CORS_ORIGINS always wins
    {origins, _, _} when is_binary(origins) and origins != "" ->
      origins
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    # Production without explicit CORS_ORIGINS and no network exposure
    {_, :prod, false} ->
      []

    # Network exposure enabled - allow all origins (private networks validated by browser)
    # This is safe because:
    # 1. Network exposure must be explicitly enabled by the user
    # 2. The server only binds to LAN, not the public internet
    # 3. CORS is primarily a browser security feature for cross-origin requests
    {_, _, true} ->
      # Use regex to match any origin when network exposure is enabled
      [~r/.*/]

    # Development/test defaults - common dev server ports
    {_, _, false} ->
      port = String.to_integer(System.get_env("PORT", "4000"))
      ui_port = String.to_integer(System.get_env("UI_PORT", "5173"))

      # Include common dev ports: Vite (5173), custom (8888), CRA (3000), Tauri, etc.
      [
        "http://localhost:#{port}",
        "http://localhost:#{ui_port}",
        "http://127.0.0.1:#{port}",
        "http://127.0.0.1:#{ui_port}",
        "http://localhost:8888",
        "http://127.0.0.1:8888",
        "http://localhost:3000",
        "http://127.0.0.1:3000",
        "http://tauri.localhost",
        "https://tauri.localhost",
        "tauri://localhost"
      ]
  end

config :cors_plug,
  origin: cors_origins,
  methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
  headers: [
    "Authorization",
    "Content-Type",
    "Accept",
    "Origin",
    "User-Agent",
    "DNT",
    "Cache-Control",
    "X-Mx-ReqToken",
    "Keep-Alive",
    "X-Requested-With",
    "If-Modified-Since",
    "X-CSRF-Token"
  ]

# For development environment, override IP binding when network exposure is enabled
if config_env() == :dev and network_exposure_enabled do
  config :leaxer_core, LeaxerCoreWeb.Endpoint,
    http: [
      ip: {0, 0, 0, 0},
      thousand_island_options: [
        read_timeout: 300_000
      ]
    ]
end

if config_env() == :prod do
  host = System.get_env("PHX_HOST") || "example.com"

  config :leaxer_core, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # Default to localhost for security.
  # Bind to all interfaces when:
  # 1. LEAXER_BIND_ALL_INTERFACES=true env var is set (for Docker, k8s, etc.)
  # 2. network_exposure_enabled is true in config.json (user enabled LAN access)
  ip_binding =
    if network_exposure_enabled do
      {0, 0, 0, 0}
    else
      {127, 0, 0, 1}
    end

  config :leaxer_core, LeaxerCoreWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # By default, bind to localhost only for security.
      # Set LEAXER_BIND_ALL_INTERFACES=true or enable network exposure in settings
      # to bind to all interfaces.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: ip_binding,
      # Increase timeouts for long-running WebSocket connections during image generation
      thousand_island_options: [
        read_timeout: 300_000
      ]
    ]

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :leaxer_core, LeaxerCoreWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :leaxer_core, LeaxerCoreWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
