defmodule DashboardWeb.CVShowLive do
  use DashboardWeb, :live_view

  alias Dashboard.CVs

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    cv = CVs.get_cv!(id)
    {:ok, assign(socket, :cv, cv)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-4xl mx-auto px-4 py-8">
        <div class="mb-6">
          <.link navigate={~p"/cvs"} class="text-blue-600 hover:text-blue-700 mb-4 inline-block">
            ← Back to CVs
          </.link>
        </div>

        <div class="bg-white border border-gray-200 rounded-lg p-8">
          <div class="flex items-start justify-between mb-6">
            <div>
              <h1 class="text-3xl font-bold text-gray-900">{@cv.name}</h1>
              <p class="text-gray-600 mt-2">{@cv.original_filename}</p>
            </div>
            <.link
              navigate={~p"/cvs/#{@cv.id}/edit"}
              class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition"
            >
              Edit for Job
            </.link>
          </div>

          <div class="border-t border-gray-200 pt-6">
            <h2 class="text-xl font-semibold text-gray-900 mb-4">Parsed Information</h2>

            <%= if @cv.parsed_data do %>
              <div class="space-y-6">
                <%= if personal_info = Map.get(@cv.parsed_data, "personal_info") do %>
                  <div>
                    <h3 class="font-medium text-gray-700 mb-2">Personal Information</h3>
                    <div class="bg-gray-50 rounded-lg p-4 space-y-2">
                      <%= for {key, value} <- personal_info do %>
                        <div class="flex">
                          <span class="font-medium text-gray-600 w-32">{key}:</span>
                          <span class="text-gray-900">{value}</span>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>

                <%= if experience = Map.get(@cv.parsed_data, "experience") do %>
                  <div>
                    <h3 class="font-medium text-gray-700 mb-2">Experience</h3>
                    <div class="space-y-4">
                      <%= for exp <- experience do %>
                        <div class="bg-gray-50 rounded-lg p-4">
                          <h4 class="font-semibold text-gray-900">{Map.get(exp, "title", "")}</h4>
                          <p class="text-gray-700">{Map.get(exp, "company", "")}</p>
                          <p class="text-sm text-gray-600">{Map.get(exp, "period", "")}</p>
                          <p class="mt-2 text-gray-800">{Map.get(exp, "description", "")}</p>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>

                <%= if skills = Map.get(@cv.parsed_data, "skills") do %>
                  <div>
                    <h3 class="font-medium text-gray-700 mb-2">Skills</h3>
                    <div class="flex flex-wrap gap-2">
                      <%= for skill <- skills do %>
                        <span class="px-3 py-1 bg-blue-100 text-blue-800 rounded-full text-sm">
                          {skill}
                        </span>
                      <% end %>
                    </div>
                  </div>
                <% end %>

                <%= if projects = Map.get(@cv.parsed_data, "projects") do %>
                  <div>
                    <h3 class="font-medium text-gray-700 mb-2">Projects</h3>
                    <div class="space-y-4">
                      <%= for project <- projects do %>
                        <div class="bg-gray-50 rounded-lg p-4">
                          <h4 class="font-semibold text-gray-900">{Map.get(project, "name", "")}</h4>
                          <p class="text-gray-800">{Map.get(project, "description", "")}</p>
                          <%= if technologies = Map.get(project, "technologies") do %>
                            <div class="mt-2 flex flex-wrap gap-2">
                              <%= for tech <- technologies do %>
                                <span class="px-2 py-1 bg-green-100 text-green-800 rounded text-xs">
                                  {tech}
                                </span>
                              <% end %>
                            </div>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>

                <%= if education = Map.get(@cv.parsed_data, "education") do %>
                  <div>
                    <h3 class="font-medium text-gray-700 mb-2">Education</h3>
                    <div class="space-y-4">
                      <%= for edu <- education do %>
                        <div class="bg-gray-50 rounded-lg p-4">
                          <h4 class="font-semibold text-gray-900">{Map.get(edu, "degree", "")}</h4>
                          <p class="text-gray-700">{Map.get(edu, "institution", "")}</p>
                          <p class="text-sm text-gray-600">{Map.get(edu, "year", "")}</p>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            <% else %>
              <p class="text-gray-600">No parsed data available</p>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
