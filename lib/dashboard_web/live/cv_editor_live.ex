defmodule DashboardWeb.CVEditorLive do
  use DashboardWeb, :live_view
  require Logger

  alias Dashboard.CVs
  alias Dashboard.Jobs
  alias Dashboard.CVEditor

  @impl true
  def mount(%{"id" => cv_id} = params, _session, socket) do
    cv = CVs.get_cv!(cv_id)
    job_id = Map.get(params, "job_id")

    socket =
      socket
      |> assign(:cv, cv)
      |> assign(:job, nil)
      |> assign(:job_requirements, nil)
      |> assign(:ai_suggestions, nil)
      |> assign(:customized_data, cv.parsed_data)
      |> assign(:cover_letter, "")
      |> assign(:loading, false)
      |> assign(:error, nil)

    socket =
      if job_id do
        load_job_and_analyze(socket, job_id)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("analyze_job", %{"job_id" => job_id}, socket) do
    {:noreply, load_job_and_analyze(socket, job_id)}
  end

  @impl true
  def handle_event("generate_suggestions", _params, socket) do
    socket = assign(socket, :loading, true)
    send(self(), :generate_suggestions)
    {:noreply, socket}
  end

  @impl true
  def handle_event("generate_cover_letter", _params, socket) do
    socket = assign(socket, :loading, true)
    send(self(), :generate_cover_letter)
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_cover_letter", %{"cover_letter" => cover_letter}, socket) do
    {:noreply, assign(socket, :cover_letter, cover_letter)}
  end

  @impl true
  def handle_event("save_custom_cv", _params, socket) do
    if socket.assigns.job do
      attrs = %{
        cv_id: socket.assigns.cv.id,
        job_id: socket.assigns.job.id,
        job_title: socket.assigns.job.title,
        customized_data: socket.assigns.customized_data,
        cover_letter: socket.assigns.cover_letter,
        ai_suggestions: socket.assigns.ai_suggestions
      }

      case Dashboard.Repo.insert(
             %Dashboard.CVs.CustomCV{}
             |> Dashboard.CVs.CustomCV.changeset(attrs)
           ) do
        {:ok, custom_cv} ->
          socket =
            socket
            |> put_flash(:info, "Custom CV saved successfully!")
            |> push_navigate(to: ~p"/applications/new?custom_cv_id=#{custom_cv.id}")

          {:noreply, socket}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to save custom CV")}
      end
    else
      {:noreply, put_flash(socket, :error, "Please select a job first")}
    end
  end

  @impl true
  def handle_info(:generate_suggestions, socket) do
    case CVEditor.suggest_highlights(
           socket.assigns.cv.parsed_data,
           socket.assigns.job_requirements
         ) do
      {:ok, suggestions} ->
        # Merge suggestions into customized data
        customized_data = merge_suggestions(socket.assigns.cv.parsed_data, suggestions)

        socket =
          socket
          |> assign(:ai_suggestions, suggestions)
          |> assign(:customized_data, customized_data)
          |> assign(:loading, false)
          |> put_flash(:info, "AI suggestions generated!")

        {:noreply, socket}

      {:error, reason} ->
        Logger.error("Failed to generate suggestions: #{inspect(reason)}")

        socket =
          socket
          |> assign(:loading, false)
          |> assign(:error, "Failed to generate AI suggestions")
          |> put_flash(:error, "Failed to generate suggestions")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:generate_cover_letter, socket) do
    case CVEditor.generate_cover_letter(socket.assigns.cv.parsed_data, socket.assigns.job) do
      {:ok, cover_letter} ->
        socket =
          socket
          |> assign(:cover_letter, cover_letter)
          |> assign(:loading, false)
          |> put_flash(:info, "Cover letter generated!")

        {:noreply, socket}

      {:error, reason} ->
        Logger.error("Failed to generate cover letter: #{inspect(reason)}")

        socket =
          socket
          |> assign(:loading, false)
          |> put_flash(:error, "Failed to generate cover letter")

        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-screen-2xl mx-auto px-4 py-8">
        <div class="mb-6">
          <.link navigate={~p"/cvs/#{@cv.id}"} class="text-blue-600 hover:text-blue-700">
            ← Back to CV
          </.link>
        </div>

        <div class="mb-8">
          <h1 class="text-3xl font-bold text-gray-900">Customize CV for Job</h1>
          <p class="mt-2 text-gray-600">Use AI to tailor your CV for specific job requirements</p>
        </div>

        <%= if @job do %>
          <div class="bg-blue-50 border border-blue-200 rounded-lg p-6 mb-6">
            <h3 class="font-semibold text-blue-900 mb-2">Selected Job</h3>
            <p class="text-lg text-blue-800">{@job.title}</p>
            <p class="text-blue-700">{@job.company} · {@job.area}</p>
          </div>
        <% end %>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <%!-- Original CV --%>
          <div class="bg-white border border-gray-200 rounded-lg p-6">
            <h2 class="text-xl font-semibold text-gray-900 mb-4">Original CV</h2>
            <div class="space-y-4 max-h-[600px] overflow-y-auto">
              {render_cv_data(@cv.parsed_data)}
            </div>
          </div>

          <%!-- AI Suggestions & Customized CV --%>
          <div class="bg-white border border-gray-200 rounded-lg p-6">
            <div class="flex justify-between items-center mb-4">
              <h2 class="text-xl font-semibold text-gray-900">Customized CV</h2>
              <%= if @job && @job_requirements do %>
                <button
                  phx-click="generate_suggestions"
                  disabled={@loading}
                  class={[
                    "px-4 py-2 rounded-lg font-medium transition",
                    if(@loading,
                      do: "bg-gray-300 text-gray-500 cursor-not-allowed",
                      else: "bg-purple-600 text-white hover:bg-purple-700"
                    )
                  ]}
                >
                  <%= if @loading do %>
                    Generating...
                  <% else %>
                    <.icon name="hero-sparkles" class="w-4 h-4 inline mr-1" /> Generate AI Suggestions
                  <% end %>
                </button>
              <% end %>
            </div>

            <%= if @ai_suggestions do %>
              <div class="mb-4 p-4 bg-purple-50 border border-purple-200 rounded-lg">
                <p class="text-sm text-purple-900 font-medium mb-2">AI Recommendations Applied:</p>
                <ul class="text-sm text-purple-800 space-y-1">
                  <%= if recommended_skills = Map.get(@ai_suggestions, "recommended_skills") do %>
                    <li>✓ Highlighted {length(recommended_skills)} relevant skills</li>
                  <% end %>
                  <%= if recommended_exp = Map.get(@ai_suggestions, "recommended_experiences") do %>
                    <li>✓ Prioritized {length(recommended_exp)} relevant experiences</li>
                  <% end %>
                </ul>
              </div>
            <% end %>

            <div class="space-y-4 max-h-[600px] overflow-y-auto">
              {render_cv_data(@customized_data, @ai_suggestions)}
            </div>
          </div>
        </div>

        <%!-- Cover Letter Section --%>
        <div class="mt-6 bg-white border border-gray-200 rounded-lg p-6">
          <div class="flex justify-between items-center mb-4">
            <h2 class="text-xl font-semibold text-gray-900">Cover Letter</h2>
            <%= if @job do %>
              <button
                phx-click="generate_cover_letter"
                disabled={@loading}
                class={[
                  "px-4 py-2 rounded-lg font-medium transition",
                  if(@loading,
                    do: "bg-gray-300 text-gray-500 cursor-not-allowed",
                    else: "bg-blue-600 text-white hover:bg-blue-700"
                  )
                ]}
              >
                <%= if @loading do %>
                  Generating...
                <% else %>
                  <.icon name="hero-sparkles" class="w-4 h-4 inline mr-1" /> Generate Cover Letter
                <% end %>
              </button>
            <% end %>
          </div>

          <textarea
            name="cover_letter"
            phx-change="update_cover_letter"
            rows="12"
            class="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
            placeholder="Cover letter will appear here after generation, or write your own..."
          >{@cover_letter}</textarea>
        </div>

        <%!-- Action Buttons --%>
        <div class="mt-6 flex gap-4">
          <button
            phx-click="save_custom_cv"
            disabled={@loading || !@job}
            class={[
              "px-6 py-3 rounded-lg font-medium transition",
              if(@loading || !@job,
                do: "bg-gray-300 text-gray-500 cursor-not-allowed",
                else: "bg-green-600 text-white hover:bg-green-700"
              )
            ]}
          >
            Save & Preview Application
          </button>
          <.link
            navigate={~p"/cvs/#{@cv.id}"}
            class="px-6 py-3 bg-gray-200 text-gray-700 rounded-lg hover:bg-gray-300 transition font-medium"
          >
            Cancel
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp render_cv_data(nil), do: Phoenix.HTML.raw("No data available")

  defp render_cv_data(data, suggestions \\ nil) do
    assigns = %{data: data, suggestions: suggestions}

    ~H"""
    <div class="space-y-4">
      <%= if skills = Map.get(@data, "skills") do %>
        <div>
          <h4 class="font-medium text-gray-700 mb-2">Skills</h4>
          <div class="flex flex-wrap gap-2">
            <%= for skill <- skills do %>
              <span class={[
                "px-3 py-1 rounded-full text-sm",
                if(is_recommended_skill?(skill, @suggestions),
                  do: "bg-purple-100 text-purple-800 ring-2 ring-purple-400",
                  else: "bg-blue-100 text-blue-800"
                )
              ]}>
                {skill}
              </span>
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if experience = Map.get(@data, "experience") do %>
        <div>
          <h4 class="font-medium text-gray-700 mb-2">Experience</h4>
          <div class="space-y-3">
            <%= for exp <- experience do %>
              <div class={[
                "p-3 rounded-lg",
                if(Map.get(exp, "highlighted"),
                  do: "bg-purple-50 border-2 border-purple-300",
                  else: "bg-gray-50 border border-gray-200"
                )
              ]}>
                <div class="flex justify-between items-start">
                  <div>
                    <h5 class="font-semibold text-gray-900">{Map.get(exp, "title", "")}</h5>
                    <p class="text-gray-700">{Map.get(exp, "company", "")}</p>
                    <p class="text-sm text-gray-600">{Map.get(exp, "period", "")}</p>
                  </div>
                  <%= if score = Map.get(exp, "relevance_score") do %>
                    <span class="px-2 py-1 bg-purple-200 text-purple-900 rounded text-xs font-medium">
                      {round(score * 100)}% match
                    </span>
                  <% end %>
                </div>
                <p class="mt-2 text-gray-800 text-sm">{Map.get(exp, "description", "")}</p>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp is_recommended_skill?(_skill, nil), do: false

  defp is_recommended_skill?(skill, suggestions) do
    recommended = Map.get(suggestions, "recommended_skills", [])
    String.downcase(skill) in Enum.map(recommended, &String.downcase/1)
  end

  defp load_job_and_analyze(socket, job_id) do
    case Jobs.get_job_by_external_id(job_id) do
      nil ->
        put_flash(socket, :error, "Job not found")

      job ->
        socket = assign(socket, :job, job)

        # Analyze job requirements
        socket = assign(socket, :loading, true)

        case CVEditor.analyze_job_requirements(build_job_desc(job)) do
          {:ok, requirements} ->
            socket
            |> assign(:job_requirements, requirements)
            |> assign(:loading, false)
            |> put_flash(:info, "Job requirements analyzed successfully!")

          {:error, reason} ->
            Logger.error("Failed to analyze job: #{inspect(reason)}")

            socket
            |> assign(:loading, false)
            |> put_flash(:error, "Failed to analyze job requirements")
        end
    end
  end

  defp build_job_desc(job) do
    """
    Job Title: #{job.title}
    Company: #{job.company || "Not specified"}
    Location: #{job.area || "Not specified"}
    Salary: #{job.salary || "Not specified"}
    """
  end

  defp merge_suggestions(cv_data, _suggestions) do
    # Implement the same logic as CVEditor.merge_suggestions
    cv_data
  end
end
