defmodule Dashboard.HH.Client do
  @moduledoc """
  HTTP client for HH.ru using cookie-based authentication.

  This module handles authenticated requests to HH.ru using cookies
  stored in a Netscape-format cookie file.
  """
  use GenServer
  require Logger

  alias Dashboard.HH.CookieParser

  @api_url "https://api.hh.ru"

  defmodule State do
    @moduledoc false
    defstruct [
      :cookies,
      :cookies_file,
      :access_token,
      :last_loaded,
      session_valid: true
    ]
  end

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Makes an authenticated GET request to HH.ru
  """
  def get(path, opts \\ []) do
    GenServer.call(__MODULE__, {:get, path, opts}, 30_000)
  end

  @doc """
  Makes an authenticated POST request to HH.ru
  """
  def post(path, body, opts \\ []) do
    GenServer.call(__MODULE__, {:post, path, body, opts}, 30_000)
  end

  @doc """
  Makes an authenticated PUT request to HH.ru
  """
  def put(path, body, opts \\ []) do
    GenServer.call(__MODULE__, {:put, path, body, opts}, 30_000)
  end

  @doc """
  Gets current session status
  """
  def session_status do
    GenServer.call(__MODULE__, :session_status)
  end

  @doc """
  Reloads cookies from file
  """
  def reload_cookies do
    GenServer.cast(__MODULE__, :reload_cookies)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    access_token =
      Keyword.get(opts, :access_token) ||
        Application.get_env(:dashboard, __MODULE__)[:access_token]

    state =
      if access_token do
        Logger.info("HH Client initialized with OAuth token")

        %State{
          access_token: access_token,
          session_valid: true
        }
      else
        # Fallback to cookies
        cookies_file = Keyword.get(opts, :cookies_file, "hh.ru_cookies.txt")

        case load_cookies(cookies_file) do
          {:ok, cookies} ->
            Logger.info("HH Client initialized with #{map_size(cookies)} cookies")

            %State{
              cookies: cookies,
              cookies_file: cookies_file,
              last_loaded: DateTime.utc_now()
            }

          {:error, reason} ->
            Logger.warning("Failed to load cookies: #{inspect(reason)}")
            Logger.warning("No auth available (no token or cookies) - HH Client will be disabled")
            {:ok, %{session_valid: false}}
        end
      end

    case state do
      %State{} -> {:ok, state}
      error -> error
    end
  end

  @impl true
  def handle_call({:get, path, opts}, _from, state) do
    if not state.session_valid do
      {:reply, {:error, :no_auth}, state}
    else
      url = build_url(path, opts)
      headers = build_headers(state, opts)

      Logger.debug("GET #{url}")

      case Req.get(url, headers: headers) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:reply, {:ok, body}, state}

      {:ok, %{status: 401}} ->
        Logger.warning("Session expired (401)")
        new_state = %{state | session_valid: false}
        {:reply, {:error, :session_expired}, new_state}

      {:ok, %{status: 403}} ->
        Logger.warning("Forbidden (403)")
        {:reply, {:error, :forbidden}, state}

      {:ok, %{status: 429}} ->
        Logger.warning("Rate limited (429)")
        {:reply, {:error, :rate_limited}, state}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Unexpected status #{status}: #{inspect(body)}")
        {:reply, {:error, {:unexpected_status, status}}, state}

      {:error, reason} ->
        Logger.error("Request failed: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
    end
  end

  @impl true
  def handle_call({:post, path, body, opts}, _from, state) do
    if not state.session_valid do
      {:reply, {:error, :no_auth}, state}
    else
      url = build_url(path, opts)
      headers = build_headers(state, opts)

      Logger.debug("POST #{url}")

      case Req.post(url, headers: headers, json: body) do
      {:ok, %{status: status, body: response_body}} when status in 200..299 ->
        {:reply, {:ok, response_body}, state}

      {:ok, %{status: 401}} ->
        Logger.warning("Session expired (401)")
        new_state = %{state | session_valid: false}
        {:reply, {:error, :session_expired}, new_state}

      {:ok, %{status: status, body: response_body}} ->
        Logger.warning("POST failed with status #{status}: #{inspect(response_body)}")
        {:reply, {:error, {:unexpected_status, status, response_body}}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
    end
  end

  @impl true
  def handle_call({:put, path, body, opts}, _from, state) do
    if not state.session_valid do
      {:reply, {:error, :no_auth}, state}
    else
      url = build_url(path, opts)
      headers = build_headers(state, opts)

      Logger.debug("PUT #{url}")

      case Req.put(url, headers: headers, json: body) do
      {:ok, %{status: status, body: response_body}} when status in 200..299 ->
        {:reply, {:ok, response_body}, state}

      {:ok, %{status: 401}} ->
        Logger.warning("Session expired (401)")
        new_state = %{state | session_valid: false}
        {:reply, {:error, :session_expired}, new_state}

      {:ok, %{status: status, body: response_body}} ->
        Logger.warning("PUT failed with status #{status}: #{inspect(response_body)}")
        {:reply, {:error, {:unexpected_status, status, response_body}}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
    end
  end

  @impl true
  def handle_call(:session_status, _from, state) do
    status = %{
      valid: state.session_valid,
      cookies_count: if(state.cookies, do: map_size(state.cookies), else: 0),
      last_loaded: state.last_loaded
    }

    {:reply, status, state}
  end

  @impl true
  def handle_cast(:reload_cookies, state) do
    case load_cookies(state.cookies_file) do
      {:ok, cookies} ->
        Logger.info("Reloaded #{map_size(cookies)} cookies")

        new_state = %{
          state
          | cookies: cookies,
            last_loaded: DateTime.utc_now(),
            session_valid: true
        }

        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to reload cookies: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  # Private Functions

  defp load_cookies(file_path) do
    # Support both absolute and relative paths
    full_path =
      if String.starts_with?(file_path, "/") do
        file_path
      else
        Path.join([File.cwd!(), file_path])
      end

    case File.read(full_path) do
      {:ok, content} ->
        cookies = CookieParser.parse(content)
        {:ok, cookies}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_url(path, opts) do
    base = Keyword.get(opts, :base_url, @api_url)

    path_with_slash =
      if String.starts_with?(path, "/") do
        path
      else
        "/" <> path
      end

    base <> path_with_slash
  end

  # Build headers with OAuth token (preferred)
  defp build_headers(%State{access_token: token} = _state, opts) when not is_nil(token) do
    base_headers = [
      {"Authorization", "Bearer #{token}"},
      {"User-Agent", "Dashboard/1.0 (job-application-assistant)"},
      {"Accept", "application/json"},
      {"Content-Type", "application/json"}
    ]

    custom_headers = Keyword.get(opts, :headers, [])
    base_headers ++ custom_headers
  end

  # Build headers with cookies (fallback)
  defp build_headers(%State{cookies: cookies} = _state, opts) when not is_nil(cookies) do
    cookie_header = cookies_to_header(cookies)

    base_headers = [
      {"User-Agent",
       "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"},
      {"Accept", "application/json"},
      {"Accept-Language", "en-US,en;q=0.9,ru;q=0.8"},
      {"Cookie", cookie_header}
    ]

    custom_headers = Keyword.get(opts, :headers, [])
    base_headers ++ custom_headers
  end

  defp cookies_to_header(cookies) do
    cookies
    |> Enum.map(fn {name, value} -> "#{name}=#{value}" end)
    |> Enum.join("; ")
  end
end
