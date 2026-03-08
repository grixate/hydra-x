defmodule HydraX.Ingest.Parser do
  @moduledoc """
  Parses document files into chunks suitable for memory entry creation.

  Supported formats: `.md`, `.txt`, `.json`, `.pdf`
  """

  @supported_extensions ~w(.md .txt .json .pdf)

  @doc "Returns true if the file extension is supported."
  def supported?(path) do
    Path.extname(path) in @supported_extensions
  end

  @doc """
  Parse a file into a list of content chunks.

  Returns `{:ok, [%{content: string, metadata: map}]}` or `{:error, reason}`.
  """
  def parse(path) do
    ext = Path.extname(path)

    if ext in @supported_extensions do
      case read_content(ext, path) do
        {:ok, content} -> {:ok, do_parse(ext, content, path)}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, {:unsupported_format, ext}}
    end
  end

  # -- Markdown: split by ## headings --

  defp do_parse(".md", content, path) do
    content
    |> String.split(~r/^## /m)
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {"", _idx} ->
        []

      {section, idx} ->
        section = if idx > 0, do: "## " <> section, else: section
        trimmed = String.trim(section)

        if trimmed == "" do
          []
        else
          heading =
            case Regex.run(~r/^##?\s+(.+)$/m, trimmed) do
              [_, title] -> String.trim(title)
              _ -> "Section #{idx + 1}"
            end

          [
            %{
              content: trimmed,
              metadata: %{
                "section" => heading,
                "section_index" => idx,
                "format" => "markdown",
                "content_hash" => content_hash(trimmed),
                "source_file" => Path.basename(path)
              }
            }
          ]
        end
    end)
  end

  # -- Text: split by blank lines --

  defp do_parse(".txt", content, path) do
    content
    |> String.split(~r/\n\s*\n/, trim: true)
    |> Enum.with_index()
    |> Enum.map(fn {paragraph, idx} ->
      trimmed = String.trim(paragraph)

      %{
        content: trimmed,
        metadata: %{
          "section" => "Paragraph #{idx + 1}",
          "section_index" => idx,
          "format" => "text",
          "content_hash" => content_hash(trimmed),
          "source_file" => Path.basename(path)
        }
      }
    end)
    |> Enum.reject(&(&1.content == ""))
  end

  # -- JSON: extract top-level key-value pairs or array items --

  defp do_parse(".json", content, path) do
    case Jason.decode(content) do
      {:ok, data} when is_map(data) ->
        data
        |> Enum.with_index()
        |> Enum.map(fn {{key, value}, idx} ->
          text = "#{key}: #{inspect(value)}"

          %{
            content: text,
            metadata: %{
              "section" => key,
              "section_index" => idx,
              "format" => "json",
              "content_hash" => content_hash(text),
              "source_file" => Path.basename(path)
            }
          }
        end)

      {:ok, data} when is_list(data) ->
        data
        |> Enum.with_index()
        |> Enum.map(fn {item, idx} ->
          text = inspect(item)

          %{
            content: text,
            metadata: %{
              "section" => "Item #{idx + 1}",
              "section_index" => idx,
              "format" => "json",
              "content_hash" => content_hash(text),
              "source_file" => Path.basename(path)
            }
          }
        end)

      {:error, _} ->
        []
    end
  end

  defp do_parse(".pdf", content, path) do
    content
    |> String.split(~r/\n\s*\n/, trim: true)
    |> Enum.with_index()
    |> Enum.map(fn {paragraph, idx} ->
      trimmed = String.trim(paragraph)

      %{
        content: trimmed,
        metadata: %{
          "section" => "PDF segment #{idx + 1}",
          "section_index" => idx,
          "format" => "pdf",
          "content_hash" => content_hash(trimmed),
          "source_file" => Path.basename(path)
        }
      }
    end)
    |> Enum.reject(&(&1.content == ""))
  end

  defp read_content(".pdf", path), do: read_pdf_text(path)
  defp read_content(_ext, path), do: File.read(path)

  defp read_pdf_text(path) do
    case Application.get_env(:hydra_x, :pdf_text_extractor) do
      fun when is_function(fun, 1) ->
        fun.(path)

      _ ->
        with executable when is_binary(executable) <- System.find_executable("pdftotext"),
             {output, 0} <- System.cmd(executable, ["-layout", path, "-"], stderr_to_stdout: true) do
          {:ok, output}
        else
          nil -> {:error, :pdf_extractor_unavailable}
          {output, code} -> {:error, {:pdf_extract_failed, code, output}}
        end
    end
  end

  @doc "Compute SHA-256 hash of content for deduplication."
  def content_hash(content) do
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end
end
