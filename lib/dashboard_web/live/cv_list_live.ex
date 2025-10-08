defmodule DashboardWeb.CVListLive do
  use DashboardWeb, :live_view

  alias Dashboard.CVs

  @impl true
  def mount(_params, _session, socket) do
    cvs = CVs.list_cvs()
    {:ok, assign(socket, :cvs, cvs)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    cv = CVs.get_cv!(id)
    {:ok, _} = CVs.delete_cv(cv)

    cvs = CVs.list_cvs()

    socket =
      socket
      |> assign(:cvs, cvs)
      |> put_flash(:info, "CV deleted successfully")

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-6xl mx-auto px-4 py-8">
        <div class="flex justify-between items-center mb-8">
          <div>
            <h1 class="text-3xl font-bold text-gray-900">My CVs</h1>
            <p class="mt-2 text-gray-600">Manage your uploaded resumes and CVs</p>
          </div>
          <.link
            navigate={~p"/cvs/upload"}
            class="px-6 py-3 bg-blue-600 text-white font-medium rounded-lg hover:bg-blue-700 transition"
          >
            <.icon name="hero-plus" class="w-5 h-5 inline mr-2" /> Upload New CV
          </.link>
        </div>

        <%= if @cvs == [] do %>
          <div class="bg-white border-2 border-dashed border-gray-300 rounded-lg p-12 text-center">
            <.icon name="hero-document" class="w-16 h-16 text-gray-400 mx-auto mb-4" />
            <h3 class="text-lg font-medium text-gray-900 mb-2">No CVs yet</h3>
            <p class="text-gray-600 mb-6">Upload your first CV to get started</p>
            <.link
              navigate={~p"/cvs/upload"}
              class="inline-flex items-center px-6 py-3 bg-blue-600 text-white font-medium rounded-lg hover:bg-blue-700 transition"
            >
              <.icon name="hero-plus" class="w-5 h-5 mr-2" /> Upload CV
            </.link>
          </div>
        <% else %>
          <div class="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
            <%= for cv <- @cvs do %>
              <div class="bg-white border border-gray-200 rounded-lg p-6 hover:shadow-lg transition">
                <div class="flex items-start justify-between mb-4">
                  <div class="flex items-center gap-3">
                    <.icon name="hero-document-text" class="w-8 h-8 text-blue-600" />
                    <div>
                      <h3 class="font-semibold text-gray-900">{cv.name}</h3>
                      <p class="text-sm text-gray-500">{cv.original_filename}</p>
                    </div>
                  </div>
                </div>

                <div class="text-sm text-gray-600 mb-4">
                  <p>Uploaded: {format_date(cv.inserted_at)}</p>
                </div>

                <div class="flex gap-2">
                  <.link
                    navigate={~p"/cvs/#{cv.id}"}
                    class="flex-1 px-4 py-2 bg-blue-600 text-white text-center rounded-lg hover:bg-blue-700 transition text-sm font-medium"
                  >
                    View Details
                  </.link>
                  <button
                    phx-click="delete"
                    phx-value-id={cv.id}
                    data-confirm="Are you sure you want to delete this CV?"
                    class="px-4 py-2 bg-red-100 text-red-700 rounded-lg hover:bg-red-200 transition text-sm font-medium"
                  >
                    <.icon name="hero-trash" class="w-4 h-4" />
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%B %d, %Y")
  end
end
