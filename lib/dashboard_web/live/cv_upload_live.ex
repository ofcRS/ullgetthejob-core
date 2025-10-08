defmodule DashboardWeb.CVUploadLive do
  use DashboardWeb, :live_view
  require Logger

  alias Dashboard.CVs
  alias Dashboard.CVs.Parser

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:uploaded_files, [])
      |> assign(:cv, nil)
      |> assign(:parsing, false)
      |> assign(:parse_error, nil)
      |> allow_upload(:cv_file,
        accept: ~w(.pdf .docx .txt),
        max_entries: 1,
        max_file_size: 10_000_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :cv_file, ref)}
  end

  @impl true
  def handle_event("save", _params, socket) do
    uploaded_files =
      consume_uploaded_entries(socket, :cv_file, fn %{path: path}, entry ->
        filename = entry.client_name
        ext = Path.extname(filename)

        # Generate unique filename
        unique_filename = "#{System.unique_integer([:positive])}#{ext}"
        dest_dir = Path.join([File.cwd!(), "priv", "static", "uploads", "cvs"])
        File.mkdir_p!(dest_dir)

        dest_path = Path.join(dest_dir, unique_filename)
        File.cp!(path, dest_path)

        {:ok, %{path: dest_path, original_name: filename, content_type: entry.client_type}}
      end)

    case uploaded_files do
      [file_info | _] ->
        socket = assign(socket, :parsing, true)
        send(self(), {:parse_cv, file_info})
        {:noreply, socket}

      [] ->
        {:noreply, put_flash(socket, :error, "No file was uploaded")}
    end
  end

  @impl true
  def handle_info({:parse_cv, file_info}, socket) do
    Logger.info("Parsing CV: #{file_info.original_name}")

    case Parser.parse_file(file_info.path) do
      {:ok, parsed_data} ->
        # Create CV record
        cv_attrs = %{
          name: Path.rootname(file_info.original_name),
          file_path: file_info.path,
          original_filename: file_info.original_name,
          content_type: file_info.content_type,
          parsed_data: parsed_data
        }

        case CVs.create_cv(cv_attrs) do
          {:ok, cv} ->
            socket =
              socket
              |> assign(:cv, cv)
              |> assign(:parsing, false)
              |> put_flash(:info, "CV uploaded and parsed successfully!")

            {:noreply, socket}

          {:error, changeset} ->
            Logger.error("Failed to save CV: #{inspect(changeset)}")

            socket =
              socket
              |> assign(:parsing, false)
              |> assign(:parse_error, "Failed to save CV")
              |> put_flash(:error, "Failed to save CV to database")

            {:noreply, socket}
        end

      {:error, reason} ->
        Logger.error("Failed to parse CV: #{inspect(reason)}")

        socket =
          socket
          |> assign(:parsing, false)
          |> assign(:parse_error, "Failed to parse CV: #{inspect(reason)}")
          |> put_flash(:error, "Failed to parse CV file")

        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-4xl mx-auto px-4 py-8">
        <div class="mb-8">
          <h1 class="text-3xl font-bold text-gray-900">Upload Your CV</h1>
          <p class="mt-2 text-gray-600">
            Upload your CV/resume in PDF, DOCX, or TXT format. We'll parse it and extract your information.
          </p>
        </div>

        <%= if @cv do %>
          <div class="bg-green-50 border border-green-200 rounded-lg p-6 mb-6">
            <div class="flex items-start">
              <.icon name="hero-check-circle" class="w-6 h-6 text-green-600 mr-3 mt-0.5" />
              <div class="flex-1">
                <h3 class="text-lg font-semibold text-green-900">CV Uploaded Successfully!</h3>
                <p class="text-green-700 mt-1">{@cv.original_filename}</p>
                <div class="mt-4 flex gap-3">
                  <.link
                    navigate={~p"/cvs/#{@cv.id}"}
                    class="px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 transition"
                  >
                    View CV Details
                  </.link>
                  <.link
                    navigate={~p"/cvs"}
                    class="px-4 py-2 bg-white text-green-600 border border-green-600 rounded-lg hover:bg-green-50 transition"
                  >
                    View All CVs
                  </.link>
                </div>
              </div>
            </div>
          </div>

          <%= if @cv.parsed_data do %>
            <div class="bg-white border border-gray-200 rounded-lg p-6">
              <h3 class="text-lg font-semibold text-gray-900 mb-4">Parsed Information</h3>
              <div class="space-y-4">
                <%= if personal_info = Map.get(@cv.parsed_data, "personal_info") do %>
                  <div>
                    <h4 class="font-medium text-gray-700">Personal Info</h4>
                    <pre class="mt-2 p-3 bg-gray-50 rounded text-sm overflow-x-auto">{Jason.encode!(personal_info, pretty: true)}</pre>
                  </div>
                <% end %>

                <%= if skills = Map.get(@cv.parsed_data, "skills") do %>
                  <div>
                    <h4 class="font-medium text-gray-700">Skills</h4>
                    <div class="mt-2 flex flex-wrap gap-2">
                      <%= for skill <- skills do %>
                        <span class="px-3 py-1 bg-blue-100 text-blue-800 rounded-full text-sm">
                          {skill}
                        </span>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        <% else %>
          <div class="bg-white border-2 border-dashed border-gray-300 rounded-lg p-12">
            <.form for={%{}} phx-submit="save" phx-change="validate" id="upload-form">
              <div class="text-center">
                <.icon name="hero-document-arrow-up" class="w-16 h-16 text-gray-400 mx-auto mb-4" />

                <%= if @parsing do %>
                  <div class="mb-4">
                    <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600 mx-auto">
                    </div>
                    <p class="mt-4 text-gray-600">Parsing your CV with AI...</p>
                  </div>
                <% else %>
                  <div
                    class="mb-4"
                    phx-drop-target={@uploads.cv_file.ref}
                  >
                    <label
                      for={@uploads.cv_file.ref}
                      class="cursor-pointer inline-flex items-center px-6 py-3 bg-blue-600 text-white font-medium rounded-lg hover:bg-blue-700 transition"
                    >
                      <.icon name="hero-document-plus" class="w-5 h-5 mr-2" /> Choose CV File
                    </label>
                    <.live_file_input upload={@uploads.cv_file} class="hidden" />
                    <p class="mt-2 text-sm text-gray-500">or drag and drop</p>
                    <p class="mt-1 text-xs text-gray-400">PDF, DOCX, or TXT up to 10MB</p>
                  </div>

                  <%= for entry <- @uploads.cv_file.entries do %>
                    <div class="mt-4 flex items-center justify-between bg-gray-50 p-4 rounded-lg">
                      <div class="flex items-center gap-3">
                        <.icon name="hero-document" class="w-6 h-6 text-blue-600" />
                        <div class="text-left">
                          <p class="font-medium text-gray-900">{entry.client_name}</p>
                          <p class="text-sm text-gray-500">{format_bytes(entry.client_size)}</p>
                        </div>
                      </div>
                      <button
                        type="button"
                        phx-click="cancel-upload"
                        phx-value-ref={entry.ref}
                        class="text-red-600 hover:text-red-700"
                      >
                        <.icon name="hero-x-mark" class="w-5 h-5" />
                      </button>
                    </div>

                    <%= for err <- upload_errors(@uploads.cv_file, entry) do %>
                      <p class="mt-2 text-sm text-red-600">{error_to_string(err)}</p>
                    <% end %>
                  <% end %>

                  <%= if @uploads.cv_file.entries != [] do %>
                    <button
                      type="submit"
                      class="mt-4 px-6 py-3 bg-green-600 text-white font-medium rounded-lg hover:bg-green-700 transition"
                    >
                      Upload and Parse CV
                    </button>
                  <% end %>
                <% end %>

                <%= if @parse_error do %>
                  <div class="mt-4 p-4 bg-red-50 border border-red-200 rounded-lg">
                    <p class="text-red-800">{@parse_error}</p>
                  </div>
                <% end %>
              </div>
            </.form>
          </div>
        <% end %>

        <div class="mt-6">
          <.link navigate={~p"/cvs"} class="text-blue-600 hover:text-blue-700">
            ← Back to CVs
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp error_to_string(:too_large), do: "File is too large (max 10MB)"
  defp error_to_string(:not_accepted), do: "File type not accepted (PDF, DOCX, or TXT only)"
  defp error_to_string(:too_many_files), do: "Only one file allowed"

  defp format_bytes(bytes) do
    cond do
      bytes >= 1_000_000 -> "#{Float.round(bytes / 1_000_000, 1)} MB"
      bytes >= 1_000 -> "#{Float.round(bytes / 1_000, 1)} KB"
      true -> "#{bytes} bytes"
    end
  end
end
