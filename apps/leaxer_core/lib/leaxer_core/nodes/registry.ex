defmodule LeaxerCore.Nodes.Registry do
  @moduledoc """
  Dynamic registry for node types using ETS for O(1) lookup performance.

  This module manages both built-in nodes (compiled with the application) and
  custom nodes (loaded dynamically from the user's custom_nodes directory).

  ## Architecture

  - Uses an ETS table for fast concurrent reads
  - Built-in nodes are registered at startup
  - Custom nodes are loaded from `~/Documents/Leaxer/custom_nodes/`
  - Hot-reloading of custom nodes is disabled in production to prevent atom exhaustion

  ## Atom Table Safety

  Elixir/Erlang atoms are **not garbage collected**. The atom table has a default
  limit of ~1 million atoms. Repeatedly calling `Code.compile_file/1` on modified
  files would eventually crash the VM with "no more index entries in atom_tab".

  To prevent this:
  - **Production**: Hot-reload is disabled. Requires application restart for changes.
  - **Development**: Hot-reload uses code purging to remove old module versions,
    minimizing new atom creation when the same modules are reloaded.

  Configure via: `config :leaxer_core, LeaxerCore.Nodes.Registry, hot_reload: true`

  ## Supervision

  - **Restart**: Permanent (always restarted)
  - **Strategy**: Part of main supervision tree with `:one_for_one`
  - **ETS Table**: `:leaxer_node_registry` with `read_concurrency: true`

  ## Failure Modes

  - **Crash during init**: ETS table creation fails, supervisor restarts process.
  - **Crash after init**: ETS table survives (owned by supervisor), data preserved.
    On restart, built-in nodes re-registered, custom nodes reloaded.
  - **Custom node compilation error**: Logged and skipped, other nodes unaffected.

  ## State Recovery

  The ETS table is created with `:named_table` and `:public` access. On restart,
  the table is recreated and all nodes re-registered. This is safe because node
  registrations are deterministic (same modules always register same types).

  ## Usage

      # Get a node module by type
      LeaxerCore.Nodes.Registry.get_module("MathOp")
      #=> LeaxerCore.Nodes.Math.MathOp

      # List all registered nodes with metadata
      LeaxerCore.Nodes.Registry.list_all_with_metadata()
      #=> [%{type: "MathOp", label: "Math", ...}, ...]

  ## ETS Concurrency Model

  **Table**: `:leaxer_node_registry`

  **Configuration**: `:set`, `:public`, `:named_table`, `read_concurrency: true`

  ### Access Pattern

  - **Readers**: Runtime executing nodes, frontend fetching node list (high frequency)
  - **Writers**: GenServer during init and custom node reload (startup only)

  ### Concurrency Guarantees

  - **Read safety**: Multiple processes can lookup nodes simultaneously. Graph
    execution and frontend requests do not block each other.
  - **Write safety**: All registrations go through GenServer callbacks. Writes
    only occur at startup (`init/1`) and during manual reload (`reload_custom_nodes/0`).
  - **Startup isolation**: Built-in nodes are registered before the application
    accepts requests, so readers never see partial registration state.

  ### Operations

  | Operation | Access | Frequency | Notes |
  |-----------|--------|-----------|-------|
  | `get_module/1` | Read | High | During every node execution |
  | `get_metadata/1` | Read | Medium | Frontend node info requests |
  | `list_all_with_metadata/0` | Read | Low | Frontend node menu (uses tab2list) |
  | `stats/0` | Read | Low | Diagnostic (uses tab2list) |
  | `register_builtin_nodes/0` | Write | Once | At startup only |
  | `load_custom_nodes/0` | Write | Rare | At startup and manual reload |
  | `reload_custom_nodes/0` | Write | Rare | User-triggered via API (dev only) |

  ### Multi-Key Design

  Each node type is stored as a separate key (`{type, module, source}`). This
  enables O(1) lookups by type. The `tab2list/1` operations scan all keys but
  are only used for infrequent operations like building the frontend menu.
  """

  use GenServer
  require Logger

  @table_name :leaxer_node_registry

  # Built-in node modules (compiled with the application)
  # Categories are alphabetically sorted, and nodes within each category are also alphabetically sorted
  @builtin_modules %{
    # Dataset (Batch prompt management and list operations)
    "ListFromText" => LeaxerCore.Nodes.Dataset.ListFromText,
    # Detailer (Object detection, segmentation, and enhancement)
    "DetailerForEach" => LeaxerCore.Nodes.Detailer.DetailerForEach,
    "DetectObjects" => LeaxerCore.Nodes.Detailer.DetectObjects,
    "GroundingDinoLoader" => LeaxerCore.Nodes.Detailer.GroundingDinoLoader,
    "MaskToSEGS" => LeaxerCore.Nodes.Detailer.MaskToSEGS,
    "SAMLoader" => LeaxerCore.Nodes.Detailer.SAMLoader,
    "SAMSegment" => LeaxerCore.Nodes.Detailer.SAMSegment,
    "SEGSCombine" => LeaxerCore.Nodes.Detailer.SEGSCombine,
    "SEGSFilter" => LeaxerCore.Nodes.Detailer.SEGSFilter,
    "SEGSPreview" => LeaxerCore.Nodes.Detailer.SEGSPreview,
    "SEGSToMask" => LeaxerCore.Nodes.Detailer.SEGSToMask,
    "ListLength" => LeaxerCore.Nodes.Dataset.ListLength,
    "LoadTextFile" => LeaxerCore.Nodes.Dataset.LoadTextFile,
    "PromptBuilder" => LeaxerCore.Nodes.Dataset.PromptBuilder,
    "RandomLineFromList" => LeaxerCore.Nodes.Dataset.RandomLineFromList,
    "RoundRobin" => LeaxerCore.Nodes.Dataset.RoundRobin,
    "TagSelector" => LeaxerCore.Nodes.Dataset.TagSelector,
    "WildcardProcessor" => LeaxerCore.Nodes.Dataset.WildcardProcessor,
    # Diffusion (Stable Diffusion image generation)
    "CacheSettings" => LeaxerCore.Nodes.Inference.CacheSettings,
    "ChromaSettings" => LeaxerCore.Nodes.Inference.ChromaSettings,
    "FluxKontext" => LeaxerCore.Nodes.Inference.FluxKontext,
    "GenerateImage" => LeaxerCore.Nodes.Inference.GenerateImage,
    "GenerateVideo" => LeaxerCore.Nodes.Inference.GenerateVideo,
    "LoadControlNet" => LeaxerCore.Nodes.Inference.LoadControlNet,
    "LoadLoRA" => LeaxerCore.Nodes.Inference.LoadLoRA,
    "LoadPhotoMaker" => LeaxerCore.Nodes.Inference.LoadPhotoMaker,
    "LoadTextEncoders" => LeaxerCore.Nodes.Inference.LoadTextEncoders,
    "LoadVAE" => LeaxerCore.Nodes.Inference.LoadVAE,
    "LoadModel" => LeaxerCore.Nodes.Inference.LoadModel,
    "PreviewImage" => LeaxerCore.Nodes.Inference.PreviewImage,
    "QwenImageEdit" => LeaxerCore.Nodes.Inference.QwenImageEdit,
    "QwenImageGenerate" => LeaxerCore.Nodes.Inference.QwenImageGenerate,
    "SamplerSettings" => LeaxerCore.Nodes.Inference.SamplerSettings,
    "SaveImage" => LeaxerCore.Nodes.Inference.SaveImage,
    "StackLoRA" => LeaxerCore.Nodes.Inference.StackLoRA,
    "ZImageGenerate" => LeaxerCore.Nodes.Inference.ZImageGenerate,
    "OvisImageGenerate" => LeaxerCore.Nodes.Inference.OvisImageGenerate,
    # LLM (Large Language Model text generation)
    "LLMGenerate" => LeaxerCore.Nodes.LLM.Generate,
    "LLMPromptEnhance" => LeaxerCore.Nodes.LLM.PromptEnhance,
    "LoadLLM" => LeaxerCore.Nodes.LLM.LoadLLM,
    # Image (Image processing and manipulation)
    "AddBorder" => LeaxerCore.Nodes.Image.AddBorder,
    "AdjustColors" => LeaxerCore.Nodes.Image.AdjustColors,
    "BlendImages" => LeaxerCore.Nodes.Image.BlendImages,
    "CropImage" => LeaxerCore.Nodes.Image.CropImage,
    "FlipImage" => LeaxerCore.Nodes.Image.FlipImage,
    "CompareImage" => LeaxerCore.Nodes.Image.CompareImage,
    "ImageGrid" => LeaxerCore.Nodes.Image.ImageGrid,
    "ImageInfo" => LeaxerCore.Nodes.Image.ImageInfo,
    "ResizeImage" => LeaxerCore.Nodes.Image.ResizeImage,
    "RotateImage" => LeaxerCore.Nodes.Image.RotateImage,
    "SDUpscaler" => LeaxerCore.Nodes.Image.SDUpscaler,
    "SharpenImage" => LeaxerCore.Nodes.Image.SharpenImage,
    "SocialCrop" => LeaxerCore.Nodes.Image.SocialCrop,
    "UpscaleImage" => LeaxerCore.Nodes.Image.UpscaleImage,
    "WatermarkImage" => LeaxerCore.Nodes.Image.WatermarkImage,
    # IO (Input/Output operations)
    "BatchRename" => LeaxerCore.Nodes.IO.BatchRename,
    "DirectoryList" => LeaxerCore.Nodes.IO.DirectoryList,
    "FilePath" => LeaxerCore.Nodes.IO.FilePath,
    "LoadImage" => LeaxerCore.Nodes.IO.LoadImage,
    "SaveTextFile" => LeaxerCore.Nodes.IO.SaveTextFile,
    # Logic (Boolean operations and conditionals)
    "And" => LeaxerCore.Nodes.Logic.And,
    "Arithmetic" => LeaxerCore.Nodes.Logic.Arithmetic,
    "BooleanLogic" => LeaxerCore.Nodes.Logic.BooleanLogic,
    "Compare" => LeaxerCore.Nodes.Logic.Compare,
    "IfElse" => LeaxerCore.Nodes.Logic.IfElse,
    "Not" => LeaxerCore.Nodes.Logic.Not,
    "Or" => LeaxerCore.Nodes.Logic.Or,
    "Switch" => LeaxerCore.Nodes.Logic.Switch,
    # Math (Numerical operations)
    "Abs" => LeaxerCore.Nodes.Math.Abs,
    "Ceil" => LeaxerCore.Nodes.Math.Ceil,
    "Clamp" => LeaxerCore.Nodes.Math.Clamp,
    "Floor" => LeaxerCore.Nodes.Math.Floor,
    "MapRange" => LeaxerCore.Nodes.Math.MapRange,
    "MathOp" => LeaxerCore.Nodes.Math.MathOp,
    "Max" => LeaxerCore.Nodes.Math.Max,
    "Min" => LeaxerCore.Nodes.Math.Min,
    "OneMinus" => LeaxerCore.Nodes.Math.OneMinus,
    "Round" => LeaxerCore.Nodes.Math.Round,
    # Primitives (Basic input values)
    "BigInt" => LeaxerCore.Nodes.Primitives.BigInt,
    "Boolean" => LeaxerCore.Nodes.Primitives.Boolean,
    "Float" => LeaxerCore.Nodes.Primitives.Float,
    "Integer" => LeaxerCore.Nodes.Primitives.Integer,
    "String" => LeaxerCore.Nodes.Primitives.String,
    # Text (String manipulation)
    "Concat" => LeaxerCore.Nodes.Utility.Concat,
    "ConcatenateAdvanced" => LeaxerCore.Nodes.Utility.ConcatenateAdvanced,
    "Contains" => LeaxerCore.Nodes.Utility.Contains,
    "RegexExtract" => LeaxerCore.Nodes.Utility.RegexExtract,
    "RegexMatch" => LeaxerCore.Nodes.Utility.RegexMatch,
    "RegexReplace" => LeaxerCore.Nodes.Utility.RegexReplace,
    "StringReplace" => LeaxerCore.Nodes.Utility.StringReplace,
    "Substring" => LeaxerCore.Nodes.Utility.Substring,
    "Trim" => LeaxerCore.Nodes.Utility.Trim,
    # Utility (Miscellaneous utilities)
    "Counter" => LeaxerCore.Nodes.Utility.Counter,
    "DateTimeStamp" => LeaxerCore.Nodes.Utility.DateTimeStamp,
    "FormatString" => LeaxerCore.Nodes.Utility.FormatString,
    "GroupToggle" => LeaxerCore.Nodes.Utility.GroupToggle,
    "Label" => LeaxerCore.Nodes.Utility.Label,
    "Note" => LeaxerCore.Nodes.Utility.Note,
    "PreviewText" => LeaxerCore.Nodes.Utility.PreviewText,
    "RandomInt" => LeaxerCore.Nodes.Utility.RandomInt,
    "RandomSeed" => LeaxerCore.Nodes.Utility.RandomSeed,
    "Reroute" => LeaxerCore.Nodes.Utility.Reroute
  }

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the module for a given node type.
  Returns nil if the type is not registered.
  """
  def get_module(type) when is_binary(type) do
    case :ets.lookup(@table_name, type) do
      [{^type, module, _source}] -> module
      [] -> nil
    end
  end

  @doc """
  Lists all registered node types.
  """
  def list_types do
    :ets.tab2list(@table_name)
    |> Enum.map(fn {type, _module, _source} -> type end)
    |> Enum.sort()
  end

  @doc """
  Lists all registered nodes with their full metadata.
  This is the main API used by the frontend.
  """
  def list_all_with_metadata do
    :ets.tab2list(@table_name)
    |> Enum.map(fn {type, module, source} ->
      get_node_metadata(type, module, source)
    end)
    |> Enum.sort_by(& &1.type)
  end

  @doc """
  Gets metadata for a specific node type.
  """
  def get_metadata(type) when is_binary(type) do
    case :ets.lookup(@table_name, type) do
      [{^type, module, source}] -> {:ok, get_node_metadata(type, module, source)}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Gets the spec for a specific node type.
  Returns the spec directly or nil if not found.
  """
  def get_spec(type) when is_binary(type) do
    case :ets.lookup(@table_name, type) do
      [{^type, module, source}] -> get_node_metadata(type, module, source)
      [] -> nil
    end
  end

  @doc """
  Reloads all custom nodes from the custom_nodes directory.

  This function is disabled in production to prevent atom table exhaustion.
  In Elixir/Erlang, atoms are never garbage collected, so repeatedly reloading
  modules would eventually crash the VM.

  To enable hot-reload in development:

      config :leaxer_core, LeaxerCore.Nodes.Registry, hot_reload: true

  Returns:
  - `{:ok, count}` - Number of custom nodes loaded
  - `{:error, :hot_reload_disabled}` - Hot-reload is disabled in config
  """
  def reload_custom_nodes do
    if hot_reload_enabled?() do
      GenServer.call(__MODULE__, :reload_custom_nodes)
    else
      Logger.warning(
        "Custom node hot-reload is disabled. " <>
          "Set `config :leaxer_core, LeaxerCore.Nodes.Registry, hot_reload: true` to enable."
      )

      {:error, :hot_reload_disabled}
    end
  end

  @doc """
  Returns whether hot-reload is enabled.
  Defaults to false in production for safety.
  """
  def hot_reload_enabled? do
    config = Application.get_env(:leaxer_core, __MODULE__, [])
    Keyword.get(config, :hot_reload, false)
  end

  @doc """
  Returns statistics about registered nodes.
  """
  def stats do
    all = :ets.tab2list(@table_name)
    builtin = Enum.count(all, fn {_, _, source} -> source == :builtin end)
    custom = Enum.count(all, fn {_, _, source} -> source == :custom end)

    %{
      total: length(all),
      builtin: builtin,
      custom: custom
    }
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table with concurrent read access
    :ets.new(@table_name, [
      :named_table,
      :set,
      :public,
      read_concurrency: true
    ])

    # Register all nodes
    register_builtin_nodes()
    custom_modules = load_custom_nodes()

    # Track loaded custom modules for safe purging on reload
    {:ok, %{custom_modules: custom_modules}}
  end

  @impl true
  def handle_call(:reload_custom_nodes, _from, state) do
    # Get previously loaded custom modules for purging
    old_modules = Map.get(state, :custom_modules, [])

    # Purge old module versions to prevent atom table growth
    # This removes the old code from memory. If the same module name is
    # recompiled, it reuses the existing atom instead of creating a new one.
    purge_modules(old_modules)

    # Remove existing custom nodes from registry
    :ets.tab2list(@table_name)
    |> Enum.filter(fn {_, _, source} -> source == :custom end)
    |> Enum.each(fn {type, _, _} -> :ets.delete(@table_name, type) end)

    # Reload custom nodes and track new modules
    new_modules = load_custom_nodes()
    count = length(new_modules)

    {:reply, {:ok, count}, %{state | custom_modules: new_modules}}
  end

  # Purge old module versions to free memory and allow safe recompilation.
  # When a module with the same name is recompiled, the existing atom is reused.
  defp purge_modules(modules) do
    Enum.each(modules, fn module ->
      # Delete old code first, then purge
      # :code.delete removes the current version, making it "old"
      # :code.purge removes the old version if no process is using it
      case :code.delete(module) do
        true ->
          :code.purge(module)
          Logger.debug("Purged module: #{inspect(module)}")

        false ->
          # Module wasn't loaded or already deleted
          :ok
      end
    end)
  end

  # Private Functions

  defp register_builtin_nodes do
    Enum.each(@builtin_modules, fn {type, module} ->
      :ets.insert(@table_name, {type, module, :builtin})
    end)

    Logger.info("Registered #{map_size(@builtin_modules)} built-in nodes")
  end

  # Returns a list of loaded module atoms for tracking (used for purging on reload)
  defp load_custom_nodes do
    custom_dir = LeaxerCore.Paths.custom_nodes_dir()

    if File.dir?(custom_dir) do
      # Find all .ex files (ignore .ex.example files)
      files =
        custom_dir
        |> Path.join("**/*.ex")
        |> Path.wildcard()
        |> Enum.reject(&String.ends_with?(&1, ".example"))

      loaded_modules =
        files
        |> Enum.flat_map(&load_custom_node_file/1)

      if length(loaded_modules) > 0 do
        Logger.info("Loaded #{length(loaded_modules)} custom node(s) from #{custom_dir}")
      end

      loaded_modules
    else
      Logger.debug("Custom nodes directory not found: #{custom_dir}")
      []
    end
  end

  # Returns list of module atoms loaded from this file
  defp load_custom_node_file(path) do
    try do
      # Compile the file
      compiled = Code.compile_file(path)

      # Find modules that implement the behaviour
      valid_modules =
        Enum.filter(compiled, fn {module, _bytecode} ->
          implements_behaviour?(module)
        end)

      # Register each valid module and collect module atoms
      Enum.map(valid_modules, fn {module, _bytecode} ->
        type = get_node_type(module)
        :ets.insert(@table_name, {type, module, :custom})
        Logger.info("Loaded custom node: #{type} from #{Path.basename(path)}")
        module
      end)
    rescue
      e ->
        Logger.error("Failed to load custom node #{path}: #{Exception.message(e)}")
        []
    end
  end

  defp implements_behaviour?(module) do
    # Check if module implements LeaxerCore.Nodes.Behaviour
    behaviours =
      try do
        module.__info__(:attributes)
        |> Keyword.get(:behaviour, [])
      rescue
        # UndefinedFunctionError: module not loaded/invalid
        UndefinedFunctionError -> []
      end

    LeaxerCore.Nodes.Behaviour in behaviours
  end

  defp get_node_type(module) do
    # Try to call type/0, fallback to module name
    if function_exported?(module, :type, 0) do
      module.type()
    else
      module |> Module.split() |> List.last()
    end
  end

  defp get_node_metadata(type, module, source) do
    # Get metadata with fallbacks for modules that don't implement all callbacks
    raw_category = safe_call(module, :category, "Uncategorized")
    category = LeaxerCore.Nodes.Behaviour.normalize_category(raw_category)
    category_path = LeaxerCore.Nodes.Behaviour.parse_category(category)

    %{
      type: type,
      label: safe_call(module, :label, type),
      category: category,
      category_path: category_path,
      description: safe_call(module, :description, ""),
      input_spec: get_normalized_input_spec(module),
      output_spec: get_normalized_output_spec(module),
      config_spec: get_normalized_config_spec(module),
      default_config: safe_call(module, :default_config, %{}),
      ui_component: safe_call(module, :ui_component, :auto),
      source: source
    }
  end

  defp get_normalized_input_spec(module) do
    raw_spec = safe_call(module, :input_spec, %{})
    LeaxerCore.Nodes.Behaviour.normalize_input_spec(raw_spec)
  end

  defp get_normalized_output_spec(module) do
    raw_spec = safe_call(module, :output_spec, %{})
    LeaxerCore.Nodes.Behaviour.normalize_output_spec(raw_spec)
  end

  defp get_normalized_config_spec(module) do
    raw_spec = safe_call(module, :config_spec, %{})
    LeaxerCore.Nodes.Behaviour.normalize_input_spec(raw_spec)
  end

  defp safe_call(module, function, default) do
    # Ensure module is loaded before checking function_exported?
    Code.ensure_loaded(module)

    if function_exported?(module, function, 0) do
      try do
        apply(module, function, [])
      rescue
        # RuntimeError or FunctionClauseError from malformed node implementation
        RuntimeError -> default
        FunctionClauseError -> default
      end
    else
      default
    end
  end
end
