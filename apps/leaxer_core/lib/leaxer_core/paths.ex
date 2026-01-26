defmodule LeaxerCore.Paths do
  @moduledoc """
  Manages user data directory paths for Leaxer.

  By default, user data is stored in `~/Documents/Leaxer/`. This can be
  overridden by setting the `LEAXER_USER_DIR` environment variable.

  ## Directory Structure

      ~/Documents/Leaxer/
      ├── custom_nodes/     # Custom node plugins (.ex files)
      ├── models/           # ML models (Stable Diffusion, LLMs, etc.)
      ├── workflows/        # Saved workflows (.json files)
      ├── chats/            # Saved chat sessions (.chat files)
      ├── outputs/          # Generated images and files
      └── config.json       # User configuration

  ## Custom Nodes

  To install a custom node:
  1. Create an Elixir module that `use LeaxerCore.Nodes.Behaviour`
  2. Place the `.ex` file in the `custom_nodes/` directory
  3. Restart Leaxer

  Example custom node structure:
      ~/Documents/Leaxer/custom_nodes/
      ├── my_custom_node.ex
      └── leaxer-community-pack/
          ├── image_effects.ex
          └── text_utils.ex
  """

  @doc """
  Returns the base user data directory.

  Can be overridden via the `LEAXER_USER_DIR` environment variable.
  """
  def user_data_dir do
    path = System.get_env("LEAXER_USER_DIR") || default_user_dir()
    # Normalize path to use consistent forward slashes (required for Path.wildcard on Windows)
    Path.expand(path)
  end

  @doc """
  Returns the default user data directory based on the operating system.
  """
  def default_user_dir do
    case :os.type() do
      {:unix, :darwin} ->
        # macOS: ~/Documents/Leaxer
        Path.expand("~/Documents/Leaxer")

      {:unix, _} ->
        # Linux: prefer XDG spec, fallback to ~/.local/share/Leaxer
        xdg_data = System.get_env("XDG_DATA_HOME") || Path.expand("~/.local/share")
        Path.join(xdg_data, "Leaxer")

      {:win32, _} ->
        # Windows: ~/Documents/Leaxer
        user_profile = System.get_env("USERPROFILE") || Path.expand("~")
        Path.join([user_profile, "Documents", "Leaxer"])
    end
  end

  @doc """
  Returns the directory for custom node plugins.
  """
  def custom_nodes_dir do
    Path.join(user_data_dir(), "custom_nodes")
  end

  @doc """
  Returns the directory for ML models.
  """
  def models_dir do
    Path.join(user_data_dir(), "models")
  end

  @doc """
  Returns the directory for saved workflows.
  """
  def workflows_dir do
    Path.join(user_data_dir(), "workflows")
  end

  @doc """
  Returns the directory for generated outputs (permanent saves).
  """
  def outputs_dir do
    Path.join(user_data_dir(), "outputs")
  end

  @doc """
  Returns the directory for user-uploaded input images.
  """
  def inputs_dir do
    Path.join(user_data_dir(), "inputs")
  end

  @doc """
  Returns the directory for temporary preview images.
  This directory is cleaned up on application startup.
  """
  def tmp_dir do
    Path.join(user_data_dir(), "tmp")
  end

  @doc """
  Returns the directory for saved chat sessions.
  """
  def chats_dir do
    Path.join(user_data_dir(), "chats")
  end

  @doc """
  Returns the path to the user configuration file.
  """
  def config_file do
    Path.join(user_data_dir(), "config.json")
  end

  @doc """
  Creates all required user directories if they don't exist.
  Also creates a README file on first run.
  Cleans up the tmp directory on startup.
  """
  def ensure_directories! do
    directories = [
      user_data_dir(),
      custom_nodes_dir(),
      models_dir(),
      workflows_dir(),
      chats_dir(),
      outputs_dir(),
      inputs_dir(),
      tmp_dir()
    ]

    Enum.each(directories, &File.mkdir_p!/1)

    # Clean up tmp directory on startup
    cleanup_tmp_dir()

    # Create README on first run
    readme_path = Path.join(user_data_dir(), "README.md")

    unless File.exists?(readme_path) do
      File.write!(readme_path, readme_content())
    end

    # Create example custom node on first run
    example_path = Path.join(custom_nodes_dir(), "example_node.ex.example")

    unless File.exists?(example_path) do
      File.write!(example_path, example_node_content())
    end

    :ok
  end

  @doc """
  Returns all paths as a map. Useful for API responses.
  """
  def all_paths do
    %{
      user_data_dir: user_data_dir(),
      custom_nodes_dir: custom_nodes_dir(),
      models_dir: models_dir(),
      workflows_dir: workflows_dir(),
      chats_dir: chats_dir(),
      outputs_dir: outputs_dir(),
      inputs_dir: inputs_dir(),
      tmp_dir: tmp_dir(),
      config_file: config_file()
    }
  end

  @doc """
  Cleans up the tmp directory by removing all files.
  """
  def cleanup_tmp_dir do
    tmp = tmp_dir()

    case File.ls(tmp) do
      {:ok, files} ->
        Enum.each(files, fn file ->
          path = Path.join(tmp, file)
          File.rm(path)
        end)

      {:error, _} ->
        :ok
    end
  end

  @doc """
  Opens the specified directory in the system file explorer.
  """
  def open_in_explorer(path) do
    case :os.type() do
      {:unix, :darwin} -> System.cmd("open", [path])
      {:win32, _} -> System.cmd("explorer", [path])
      {:unix, _} -> System.cmd("xdg-open", [path])
    end
  end

  # Private helpers

  defp readme_content do
    """
    # Leaxer User Directory

    This directory contains your custom nodes, models, workflows, and generated outputs.

    ## Directory Structure

    - `custom_nodes/` - Install custom node plugins here
    - `models/` - Store ML models (Stable Diffusion, LLMs, etc.)
    - `workflows/` - Save and load your workflows
    - `outputs/` - Generated images and files

    ## Installing Custom Nodes

    ### Via Git

    ```bash
    cd custom_nodes
    git clone https://github.com/username/leaxer-plugin-name.git
    ```

    ### Via Single File

    ```bash
    curl -o custom_nodes/my_node.ex https://example.com/my_node.ex
    ```

    After adding custom nodes, restart Leaxer to load them.

    ## Creating Custom Nodes

    See `custom_nodes/example_node.ex.example` for a template.

    A custom node must:
    1. `use LeaxerCore.Nodes.Behaviour`
    2. Implement `input_spec/0`, `output_spec/0`, and `process/2`
    3. Optionally override `type/0`, `label/0`, `category/0`, `description/0`

    ## Environment Variable

    You can override this directory location by setting:

    ```bash
    export LEAXER_USER_DIR=/path/to/your/leaxer/data
    ```
    """
  end

  defp example_node_content do
    """
    # Example Custom Node for Leaxer
    #
    # Rename this file to example_node.ex (remove .example) to enable it.
    # Then restart Leaxer.

    defmodule CustomNodes.ExampleUppercase do
      @moduledoc \"\"\"
      An example custom node that converts text to uppercase.
      \"\"\"
      use LeaxerCore.Nodes.Behaviour

      @impl true
      def type, do: "ExampleUppercase"

      @impl true
      def label, do: "Uppercase"

      @impl true
      def category, do: "Custom"

      @impl true
      def description, do: "Converts input text to uppercase"

      @impl true
      def input_spec do
        %{
          text: %{type: :string, label: "Text", default: "", multiline: true}
        }
      end

      @impl true
      def output_spec do
        %{
          result: %{type: :string, label: "Result"}
        }
      end

      @impl true
      def process(inputs, config) do
        text = inputs["text"] || config["text"] || ""
        {:ok, %{"result" => String.upcase(text)}}
      end
    end
    """
  end
end
