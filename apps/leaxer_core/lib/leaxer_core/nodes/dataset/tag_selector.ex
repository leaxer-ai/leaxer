defmodule LeaxerCore.Nodes.Dataset.TagSelector do
  @moduledoc """
  Dictionary-style tag lookup based on trigger words.

  Ported from isekai-comfy-node's IsekaiTagSelector.
  Outputs preset tags based on a trigger word using dictionary-style matching.

  Supports two formats:
  1. TOML/INI style:
     [TriggerWord]
     tags, separated, by, commas

  2. Legacy style:
     TriggerWord: tags, separated, by, commas

  Matching is case-insensitive.

  ## Examples

      iex> presets = "[Batman]\\ndark, knight\\n\\n[Superman]\\nhero, cape"
      iex> TagSelector.process(%{"trigger_word" => "batman", "presets" => presets}, %{})
      {:ok, %{"selected_tags" => "dark, knight"}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  @impl true
  def type, do: "TagSelector"

  @impl true
  def label, do: "Tag Selector"

  @impl true
  def category, do: "Data/Prompt"

  @impl true
  def description,
    do: "Select preset tags based on trigger word (character names, styles, etc.)"

  @impl true
  def input_spec do
    default_presets = """
    [Superman]
    movie, superhero, dc, comic, blue, red

    [Batman]
    dark, knight, gotham, rich, black

    [Wonder Woman]
    amazon, warrior, princess, tiara
    """

    %{
      trigger_word: %{
        type: :string,
        label: "TRIGGER WORD",
        default: "",
        description: "String to search for in presets"
      },
      presets: %{
        type: :string,
        label: "PRESETS",
        default: default_presets,
        multiline: true,
        description: "TOML/INI format sections or legacy colon format"
      },
      default_value: %{
        type: :string,
        label: "DEFAULT VALUE",
        default: "",
        optional: true,
        description: "Fallback value if trigger not found"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      selected_tags: %{
        type: :string,
        label: "SELECTED TAGS"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    trigger_word = inputs["trigger_word"] || config["trigger_word"] || ""
    presets = inputs["presets"] || config["presets"] || ""
    default_value = inputs["default_value"] || config["default_value"] || ""

    # Clean and normalize the trigger word
    search_key = trigger_word |> String.trim() |> String.downcase()

    cond do
      search_key == "" ->
        Logger.info("TagSelector: No trigger word provided")
        {:ok, %{"selected_tags" => default_value}}

      true ->
        # Parse the presets
        tags_dict = parse_presets(presets)

        # Look up the trigger word
        case Map.get(tags_dict, search_key) do
          nil ->
            Logger.info("TagSelector: Trigger '#{trigger_word}' not found. Using default.")
            {:ok, %{"selected_tags" => default_value}}

          result ->
            preview =
              if String.length(result) > 100 do
                String.slice(result, 0, 100) <> "..."
              else
                result
              end

            Logger.info("TagSelector: Trigger '#{trigger_word}' matched: '#{preview}'")
            {:ok, %{"selected_tags" => result}}
        end
    end
  rescue
    e ->
      Logger.error("TagSelector exception: #{inspect(e)}")
      {:error, "Failed to select tags: #{Exception.message(e)}"}
  end

  defp parse_presets(presets) do
    lines = String.split(presets, "\n")

    # Check if we have TOML/INI format (section headers)
    has_sections =
      Enum.any?(lines, fn line ->
        String.match?(line, ~r/^\s*\[.+\]\s*$/)
      end)

    if has_sections do
      parse_toml_format(lines)
    else
      parse_legacy_format(lines)
    end
  end

  defp parse_toml_format(lines) do
    {tags_dict, _current_section} =
      Enum.reduce(lines, {%{}, nil}, fn line, {dict, current_section} ->
        trimmed = String.trim(line)

        cond do
          # Skip empty lines
          trimmed == "" ->
            {dict, current_section}

          # Check for section header [SectionName]
          String.match?(trimmed, ~r/^\[(.+)\]$/) ->
            captures = Regex.run(~r/^\[(.+)\]$/, trimmed)

            case captures do
              [_, section_name] ->
                section_key = section_name |> String.trim() |> String.downcase()
                {dict, section_key}

              _ ->
                {dict, current_section}
            end

          # Content line under a section
          current_section != nil ->
            # Accumulate tags for the section
            updated_dict =
              Map.update(dict, current_section, trimmed, fn existing ->
                existing <> ", " <> trimmed
              end)

            {updated_dict, current_section}

          # Line outside any section, ignore
          true ->
            {dict, current_section}
        end
      end)

    tags_dict
  end

  defp parse_legacy_format(lines) do
    lines
    |> Enum.filter(fn line ->
      trimmed = String.trim(line)
      trimmed != "" && String.contains?(trimmed, ":")
    end)
    |> Enum.reduce(%{}, fn line, dict ->
      case String.split(line, ":", parts: 2) do
        [key, value] ->
          key_normalized = key |> String.trim() |> String.downcase()
          value_trimmed = String.trim(value)
          Map.put(dict, key_normalized, value_trimmed)

        _ ->
          dict
      end
    end)
  end
end
