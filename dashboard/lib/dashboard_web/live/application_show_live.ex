defmodule DashboardWeb.ApplicationShowLive do
  use DashboardWeb, :live_view

  alias Dashboard.Applications

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    application = Applications.get_application!(id)

    {:ok, assign(socket, :application, application)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-4xl mx-auto px-4 py-8">
        <div class="mb-6">
          <.link navigate={~p"/applications"} class="text-blue-600 hover:text-blue-700">
            ← Back to Applications
          </.link>
        </div>

        <div class="bg-white border border-gray-200 rounded-lg p-8">
          <div class="flex justify-between items-start mb-6">
            <div>
              <h1 class="text-3xl font-bold text-gray-900">Application Details</h1>
              <p class="text-gray-600 mt-2">
                {if @application.job, do: @application.job.title, else: "Job #{@application.job_external_id}"}
              </p>
            </div>
            <span class={[
              "px-4 py-2 text-sm font-semibold rounded-full",
              status_class(@application.status)
            ]}>
              {@application.status}
            </span>
          </div>

          <%= if @application.job do %>
            <div class="mb-6 p-4 bg-gray-50 rounded-lg">
              <h3 class="font-semibold text-gray-900 mb-2">Job Information</h3>
              <div class="space-y-2 text-sm">
                <p><span class="font-medium">Company:</span> {@application.job.company}</p>
                <p><span class="font-medium">Location:</span> {@application.job.area}</p>
                <p><span class="font-medium">Salary:</span> {@application.job.salary}</p>
                <%= if @application.job.url do %>
                  <p>
                    <span class="font-medium">URL:</span>
                    <a href={@application.job.url} target="_blank" class="text-blue-600 hover:underline">
                      View Job Posting
                    </a>
                  </p>
                <% end %>
              </div>
            </div>
          <% end %>

          <%= if @application.cover_letter do %>
            <div class="mb-6">
              <h3 class="font-semibold text-gray-900 mb-2">Cover Letter</h3>
              <div class="p-4 bg-gray-50 rounded-lg whitespace-pre-wrap text-sm">
                {@application.cover_letter}
              </div>
            </div>
          <% end %>

          <div class="grid grid-cols-2 gap-4 mb-6">
            <div>
              <p class="text-sm text-gray-600">Submitted</p>
              <p class="font-medium text-gray-900">
                {if @application.submitted_at, do: format_datetime(@application.submitted_at), else: "Not submitted"}
              </p>
            </div>
            <div>
              <p class="text-sm text-gray-600">Created</p>
              <p class="font-medium text-gray-900">{format_datetime(@application.inserted_at)}</p>
            </div>
          </div>

          <%= if @application.error_message do %>
            <div class="p-4 bg-red-50 border border-red-200 rounded-lg">
              <h3 class="font-semibold text-red-900 mb-2">Error Details</h3>
              <p class="text-red-800 text-sm">{@application.error_message}</p>
            </div>
          <% end %>

          <%= if @application.response_data do %>
            <div class="mt-4">
              <h3 class="font-semibold text-gray-900 mb-2">Response Data</h3>
              <pre class="p-4 bg-gray-50 rounded-lg text-xs overflow-x-auto">{Jason.encode!(@application.response_data, pretty: true)}</pre>
            </div>
          <% end %>
        </div>
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
    Calendar.strftime(datetime, "%B %d, %Y at %H:%M")
  end
end
