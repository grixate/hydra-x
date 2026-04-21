defmodule HydraX.Product.Workspace.Backend do
  @moduledoc """
  Behaviour implemented by workspace execution backends. Currently `Host`
  (direct filesystem + System.cmd). A future `Docker` backend will mount the
  workspace into a long-running container.

  All `relative_path` arguments are interpreted relative to the workspace's
  filesystem root. Implementations MUST guard against path traversal — see
  `HydraX.Product.Workspace.Backend.Host.safe_join/2`.

  All `command` arguments to `exec/4` are `[binary, ...args]` lists. The
  command name is matched against the allowlist; arguments are passed verbatim
  with no shell interpolation.
  """

  alias HydraX.Product.Workspace

  @type relative_path :: String.t()
  @type exec_opts :: [
          {:env, [{String.t(), String.t()}]}
          | {:timeout_ms, pos_integer()}
          | {:stdin, String.t()}
        ]
  @type exec_result :: %{stdout: String.t(), stderr: String.t(), exit_code: integer()}
  @type entry :: %{name: String.t(), type: :file | :dir | :other, size: non_neg_integer()}
  @type reason :: atom() | {atom(), term()} | String.t()

  @callback ensure_root(Workspace.t()) :: :ok | {:error, reason()}
  @callback destroy(Workspace.t()) :: :ok | {:error, reason()}
  @callback read_file(Workspace.t(), relative_path()) :: {:ok, binary()} | {:error, reason()}
  @callback write_file(Workspace.t(), relative_path(), binary()) :: :ok | {:error, reason()}
  @callback list_dir(Workspace.t(), relative_path()) :: {:ok, [entry()]} | {:error, reason()}
  @callback exec(Workspace.t(), [String.t()], exec_opts()) ::
              {:ok, exec_result()} | {:error, reason()}

  @doc "Returns the configured backend implementation for the given workspace."
  def for_workspace(%Workspace{sandbox_mode: "host"}), do: __MODULE__.Host
  def for_workspace(%Workspace{sandbox_mode: "docker"}), do: __MODULE__.Docker

  def for_workspace(%Workspace{sandbox_mode: mode}),
    do: raise("unknown sandbox_mode: #{inspect(mode)}")
end
