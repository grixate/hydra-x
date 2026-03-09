defmodule HydraX.Security.LoginThrottle do
  @moduledoc false

  @table :login_rate_limit
  @default_max_attempts 5
  @default_window_seconds 60

  def max_attempts do
    Application.get_env(:hydra_x, :operator_login_max_attempts, @default_max_attempts)
  end

  def window_seconds do
    Application.get_env(:hydra_x, :operator_login_window_seconds, @default_window_seconds)
  end

  def rate_limited?(ip) do
    ensure_table()
    sweep_expired_entries()
    now = System.system_time(:second)
    window = window_seconds()

    case :ets.lookup(@table, ip) do
      [{^ip, attempts, window_start}] ->
        now - window_start < window and attempts >= max_attempts()

      _ ->
        false
    end
  end

  def record_attempt(ip) do
    ensure_table()
    now = System.system_time(:second)
    window = window_seconds()

    case :ets.lookup(@table, ip) do
      [{^ip, attempts, window_start}] ->
        if now - window_start < window do
          :ets.insert(@table, {ip, attempts + 1, window_start})
        else
          :ets.insert(@table, {ip, 1, now})
        end

      _ ->
        :ets.insert(@table, {ip, 1, now})
    end
  end

  def clear_attempts(ip) do
    ensure_table()
    :ets.delete(@table, ip)
  end

  def current_attempts(ip) do
    ensure_table()

    case :ets.lookup(@table, ip) do
      [{^ip, attempts, _window_start}] -> attempts
      _ -> 0
    end
  end

  def state(ip) do
    ensure_table()
    sweep_expired_entries()
    now = System.system_time(:second)

    case :ets.lookup(@table, ip) do
      [{^ip, attempts, window_start}] ->
        remaining = max(window_seconds() - (now - window_start), 0)

        %{
          ip: ip,
          attempts: attempts,
          max_attempts: max_attempts(),
          window_seconds: window_seconds(),
          rate_limited?: attempts >= max_attempts() and remaining > 0,
          retry_after_seconds: if(attempts >= max_attempts(), do: remaining, else: 0)
        }

      _ ->
        %{
          ip: ip,
          attempts: 0,
          max_attempts: max_attempts(),
          window_seconds: window_seconds(),
          rate_limited?: false,
          retry_after_seconds: 0
        }
    end
  end

  def summary do
    ensure_table()
    sweep_expired_entries()

    rows = :ets.tab2list(@table)

    %{
      max_attempts: max_attempts(),
      window_seconds: window_seconds(),
      tracked_ips: length(rows),
      blocked_ips:
        Enum.count(rows, fn {_ip, attempts, _window_start} ->
          attempts >= max_attempts()
        end)
    }
  end

  def reset! do
    ensure_table()
    :ets.delete_all_objects(@table)
    :ok
  end

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table])
    end
  end

  defp sweep_expired_entries do
    now = System.system_time(:second)

    :ets.tab2list(@table)
    |> Enum.each(fn {ip, _attempts, window_start} ->
      if now - window_start >= window_seconds() do
        :ets.delete(@table, ip)
      end
    end)
  end
end
