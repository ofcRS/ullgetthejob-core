defmodule DashboardWeb.ApplicationsLive do
  use DashboardWeb, :live_view

  alias Dashboard.Applications

  @impl true
  def mount(_params, _session, socket) do
    applications = Applications.list_applications()
    stats = Applications.get_statistics()

    socket =
      socket
      |> assign(:applications, applications)
      |> assign(:stats, stats)
      |> assign(:filter, "all")

    {:ok, socket}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    filters = if status == "all", do: %{}, else: %{status: status}
    applications = Applications.list_applications(filters)

    socket =
      socket
      |> assign(:applications, applications)
      |> assign(:filter, status)

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    application = Applications.get_application!(id)
    {:ok, _} = Applications.delete_application(application)

    applications = Applications.list_applications()
    stats = Applications.get_statistics()

    socket =
      socket
      |> assign(:applications, applications)
      |> assign(:stats, stats)
      |> put_flash(:info, "Application deleted successfully")

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-screen-2xl mx-auto px-4 py-8">
        <div class="flex justify-between items-center mb-8">
          <div>
            <h1 class="text-3xl font-bold text-gray-900">My Applications</h1>
            <p class="mt-2 text-gray-600">Track your job application submissions</p>
          </div>
          <.link
            navigate={~p"/jobs"}
            class="px-6 py-3 bg-blue-600 text-white font-medium rounded-lg hover:bg-blue-700 transition"
          >
            <.icon name="hero-plus" class="w-5 h-5 inline mr-2" /> New Application
          </.link>
        </div>

        <%!-- Statistics Cards --%>
        <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
          <div class="bg-white border border-gray-200 rounded-lg p-6">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm text-gray-600">Total</p>
                <p class="text-2xl font-bold text-gray-900">{@stats.total}</p>
              </div>
              <.icon name="hero-document-text" class="w-8 h-8 text-blue-600" />
            </div>
          </div>

          <div class="bg-white border border-gray-200 rounded-lg p-6">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm text-gray-600">Pending</p>
                <p class="text-2xl font-bold text-yellow-600">{@stats.pending}</p>
              </div>
              <.icon name="hero-clock" class="w-8 h-8 text-yellow-600" />
            </div>
          </div>

          <div class="bg-white border border-gray-200 rounded-lg p-6">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm text-gray-600">Submitted</p>
                <p class="text-2xl font-bold text-green-600">{@stats.submitted}</p>
              </div>
              <.icon name="hero-check-circle" class="w-8 h-8 text-green-600" />
            </div>
          </div>

          <div class="bg-white border border-gray-200 rounded-lg p-6">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm text-gray-600">Today</p>
                <p class="text-2xl font-bold text-purple-600">{@stats.today}</p>
              </div>
              <.icon name="hero-calendar" class="w-8 h-8 text-purple-600" />
            </div>
          </div>
        </div>

        <%!-- Filters --%>
        <div class="mb-6 flex gap-2">
          <button
            phx-click="filter"
            phx-value-status="all"
            class={[
              "px-4 py-2 rounded-lg font-medium transition",
              if(@filter == "all",
                do: "bg-blue-600 text-white",
                else: "bg-gray-200 text-gray-700 hover:bg-gray-300"
              )
            ]}
          >
            All
          </button>
          <button
            phx-click="filter"
            phx-value-status="pending"
            class={[
              "px-4 py-2 rounded-lg font-medium transition",
              if(@filter == "pending",
                do: "bg-yellow-600 text-white",
                else: "bg-gray-200 text-gray-700 hover:bg-gray-300"
              )
            ]}
          >
            Pending
          </button>
          <button
            phx-click="filter"
            phx-value-status="submitted"
            class={[
              "px-4 py-2 rounded-lg font-medium transition",
              if(@filter == "submitted",
                do: "bg-green-600 text-white",
                else: "bg-gray-200 text-gray-700 hover:bg-gray-300"
              )
            ]}
          >
            Submitted
          </button>
          <button
            phx-click="filter"
            phx-value-status="failed"
            class={[
              "px-4 py-2 rounded-lg font-medium transition",
              if(@filter == "failed",
                do: "bg-red-600 text-white",
                else: "bg-gray-200 text-gray-700 hover:bg-gray-300"
              )
            ]}
          >
            Failed
          </button>
        </div>

        <%!-- Applications List --%>
        <%= if @applications == [] do %>
          <div class="bg-white border-2 border-dashed border-gray-300 rounded-lg p-12 text-center">
            <.icon name="hero-document-check" class="w-16 h-16 text-gray-400 mx-auto mb-4" />
            <h3 class="text-lg font-medium text-gray-900 mb-2">No applications yet</h3>
            <p class="text-gray-600 mb-6">Start applying to jobs to see them here</p>
            <.link
              navigate={~p"/jobs"}
              class="inline-flex items-center px-6 py-3 bg-blue-600 text-white font-medium rounded-lg hover:bg-blue-700 transition"
            >
              <.icon name="hero-magnifying-glass" class="w-5 h-5 mr-2" /> Browse Jobs
            </.link>
          </div>
        <% else %>
          <div class="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Job
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Status
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Submitted
                  </th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for app <- @applications do %>
                  <tr class="hover:bg-gray-50">
                    <td class="px-6 py-4">
                      <div>
                        <p class="text-sm font-medium text-gray-900">
                          {if app.job, do: app.job.title, else: "Job #{app.job_external_id}"}
                        </p>
                        <%= if app.job do %>
                          <p class="text-sm text-gray-500">{app.job.company} · {app.job.area}</p>
                        <% end %>
                      </div>
                    </td>
                    <td class="px-6 py-4">
                      <span class={[
                        "px-3 py-1 inline-flex text-xs leading-5 font-semibold rounded-full",
                        status_class(app.status)
                      ]}>
                        {app.status}
                      </span>
                    </td>
                    <td class="px-6 py-4 text-sm text-gray-500">
                      {if app.submitted_at,
                        do: format_datetime(app.submitted_at),
                        else: "Not submitted"}
                    </td>
                    <td class="px-6 py-4 text-right text-sm font-medium">
                      <div class="flex justify-end gap-2">
                        <.link
                          navigate={~p"/applications/#{app.id}"}
                          class="text-blue-600 hover:text-blue-900"
                        >
                          View
                        </.link>
                        <button
                          phx-click="delete"
                          phx-value-id={app.id}
                          data-confirm="Are you sure?"
                          class="text-red-600 hover:text-red-900"
                        >
                          Delete
                        </button>
                      </div>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp status_class("pending"), do: "bg-yellow-100 text-yellow-800"
  defp status_class("submitted"), do: "bg-green-100 text-green-800"
  defp status_class("failed"), do: "bg-red-100 text-red-800"
  defp status_class("error"), do: "bg-red-100 text-red-800"
  defp status_class(_), do: "bg-gray-100 text-gray-800"

  defp format_datetime(nil), do: ""

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end
end
