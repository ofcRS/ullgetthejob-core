defmodule DashboardWeb.ApplicationPreviewLive do
  use DashboardWeb, :live_view
  require Logger

  alias Dashboard.Jobs
  alias Dashboard.Applications
  alias Dashboard.Applications.Applicator

  @impl true
  def mount(params, _session, socket) do
    custom_cv_id = Map.get(params, "custom_cv_id")
    job_id = Map.get(params, "job_id")

    socket =
      socket
      |> assign(:custom_cv, nil)
      |> assign(:job, nil)
      |> assign(:cover_letter, "")
      |> assign(:submitting, false)
      |> assign(:error, nil)

    socket =
      cond do
        custom_cv_id ->
          load_custom_cv(socket, custom_cv_id)

        job_id ->
          load_job(socket, job_id)

        true ->
          put_flash(socket, :error, "Missing custom_cv_id or job_id parameter")
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("update_cover_letter", %{"cover_letter" => cover_letter}, socket) do
    {:noreply, assign(socket, :cover_letter, cover_letter)}
  end

  @impl true
  def handle_event("submit_application", _params, socket) do
    socket = assign(socket, :submitting, true)
    send(self(), :submit_application)
    {:noreply, socket}
  end

  @impl true
  def handle_info(:submit_application, socket) do
    custom_cv = socket.assigns.custom_cv
    job = socket.assigns.job
    cover_letter = socket.assigns.cover_letter

    # Create application record
    application_attrs = %{
      job_id: job.id,
      custom_cv_id: if(custom_cv, do: custom_cv.id),
      job_external_id: job.external_id,
      cover_letter: cover_letter,
      status: "pending"
    }

    case Applications.create_application(application_attrs) do
      {:ok, application} ->
        # Submit to HH.ru
        case Applicator.submit_application(application) do
          {:ok, _response} ->
            socket =
              socket
              |> assign(:submitting, false)
              |> put_flash(:info, "Application submitted successfully!")
              |> push_navigate(to: ~p"/applications/#{application.id}")

            {:noreply, socket}

          {:error, reason} ->
            # Update application with error
            Applications.update_application(application, %{
              status: "failed",
              error_message: inspect(reason)
            })

            socket =
              socket
              |> assign(:submitting, false)
              |> assign(:error, "Failed to submit application: #{inspect(reason)}")
              |> put_flash(:error, "Failed to submit application")

            {:noreply, socket}
        end

      {:error, _changeset} ->
        socket =
          socket
          |> assign(:submitting, false)
          |> put_flash(:error, "Failed to create application record")

        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-5xl mx-auto px-4 py-8">
        <div class="mb-8">
          <h1 class="text-3xl font-bold text-gray-900">Application Preview</h1>
          <p class="mt-2 text-gray-600">Review your application before submission</p>
        </div>

        <%= if @job do %>
          <%!-- Job Information --%>
          <div class="bg-white border border-gray-200 rounded-lg p-6 mb-6">
            <h2 class="text-xl font-semibold text-gray-900 mb-4">Job Details</h2>
            <div class="space-y-2">
              <p class="text-lg font-medium text-gray-900">{@job.title}</p>
              <p class="text-gray-700">{@job.company}</p>
              <p class="text-gray-600">{@job.area} · {@job.salary}</p>
              <%= if @job.url do %>
                <a href={@job.url} target="_blank" class="text-blue-600 hover:underline text-sm">
                  View Original Posting →
                </a>
              <% end %>
            </div>
          </div>

          <%!-- CV Preview --%>
          <%= if @custom_cv do %>
            <div class="bg-white border border-gray-200 rounded-lg p-6 mb-6">
              <h2 class="text-xl font-semibold text-gray-900 mb-4">Your Customized CV</h2>
              <%= if @custom_cv.customized_data do %>
                <div class="space-y-4">
                  {render_cv_preview(@custom_cv.customized_data)}
                </div>
              <% else %>
                <p class="text-gray-600">No CV data available</p>
              <% end %>
            </div>
          <% end %>

          <%!-- Cover Letter --%>
          <div class="bg-white border border-gray-200 rounded-lg p-6 mb-6">
            <h2 class="text-xl font-semibold text-gray-900 mb-4">Cover Letter</h2>
            <textarea
              name="cover_letter"
              phx-change="update_cover_letter"
              rows="12"
              class="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
              placeholder="Enter your cover letter here..."
            >{@cover_letter || (@custom_cv && @custom_cv.cover_letter) || ""}</textarea>
            <p class="mt-2 text-sm text-gray-500">
              You can edit the cover letter before submitting
            </p>
          </div>

          <%!-- Submission Checklist --%>
          <div class="bg-blue-50 border border-blue-200 rounded-lg p-6 mb-6">
            <h3 class="font-semibold text-blue-900 mb-3">Before You Submit</h3>
            <ul class="space-y-2 text-sm text-blue-800">
              <li class="flex items-start">
                <.icon name="hero-check-circle" class="w-5 h-5 mr-2 flex-shrink-0" />
                <span>Review your CV and ensure all information is accurate</span>
              </li>
              <li class="flex items-start">
                <.icon name="hero-check-circle" class="w-5 h-5 mr-2 flex-shrink-0" />
                <span>Proofread your cover letter for any typos or errors</span>
              </li>
              <li class="flex items-start">
                <.icon name="hero-check-circle" class="w-5 h-5 mr-2 flex-shrink-0" />
                <span>Verify the job details match your expectations</span>
              </li>
            </ul>
          </div>

          <%= if @error do %>
            <div class="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg">
              <p class="text-red-800">{@error}</p>
            </div>
          <% end %>

          <%!-- Action Buttons --%>
          <div class="flex gap-4">
            <button
              phx-click="submit_application"
              disabled={@submitting}
              class={[
                "flex-1 px-6 py-3 rounded-lg font-medium transition",
                if(@submitting,
                  do: "bg-gray-300 text-gray-500 cursor-not-allowed",
                  else: "bg-green-600 text-white hover:bg-green-700"
                )
              ]}
            >
              <%= if @submitting do %>
                <span class="flex items-center justify-center">
                  <div class="animate-spin rounded-full h-5 w-5 border-b-2 border-white mr-2"></div>
                  Submitting...
                </span>
              <% else %>
                <.icon name="hero-paper-airplane" class="w-5 h-5 inline mr-2" /> Submit Application
              <% end %>
            </button>
            <.link
              navigate={~p"/applications"}
              class="px-6 py-3 bg-gray-200 text-gray-700 rounded-lg hover:bg-gray-300 transition font-medium"
            >
              Cancel
            </.link>
          </div>
        <% else %>
          <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-6">
            <p class="text-yellow-800">No job information available. Please select a job first.</p>
            <.link navigate={~p"/jobs"} class="mt-4 inline-block text-blue-600 hover:underline">
              Browse Jobs →
            </.link>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp render_cv_preview(nil), do: Phoenix.HTML.raw("No CV data available")

  defp render_cv_preview(data) do
    assigns = %{data: data}

    ~H"""
    <div class="space-y-4">
      <%= if personal_info = Map.get(@data, "personal_info") do %>
        <div>
          <h4 class="font-medium text-gray-700 mb-2">Contact Information</h4>
          <div class="text-sm text-gray-600 space-y-1">
            <%= for {key, value} <- personal_info do %>
              <p><span class="font-medium">{key}:</span> {value}</p>
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if skills = Map.get(@data, "skills") do %>
        <div>
          <h4 class="font-medium text-gray-700 mb-2">Skills</h4>
          <div class="flex flex-wrap gap-2">
            <%= for skill <- Enum.take(skills, 10) do %>
              <span class="px-3 py-1 bg-blue-100 text-blue-800 rounded-full text-sm">{skill}</span>
            <% end %>
            <%= if length(skills) > 10 do %>
              <span class="px-3 py-1 bg-gray-100 text-gray-600 rounded-full text-sm">
                +{length(skills) - 10} more
              </span>
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if experience = Map.get(@data, "experience") do %>
        <div>
          <h4 class="font-medium text-gray-700 mb-2">Experience ({length(experience)} positions)</h4>
          <div class="text-sm text-gray-600">
            <%= for exp <- Enum.take(experience, 3) do %>
              <p class="mb-1">
                <span class="font-medium">{Map.get(exp, "title", "")}</span>
                at {Map.get(exp, "company", "")}
              </p>
            <% end %>
            <%= if length(experience) > 3 do %>
              <p class="text-gray-500">... and {length(experience) - 3} more</p>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp load_custom_cv(socket, custom_cv_id) do
    case Dashboard.CVEditor.get_custom_cv(custom_cv_id) do
      {:ok, custom_cv} ->
        socket
        |> assign(:custom_cv, custom_cv)
        |> assign(:job, custom_cv.job)
        |> assign(:cover_letter, custom_cv.cover_letter || "")

      {:error, _} ->
        put_flash(socket, :error, "Custom CV not found")
    end
  end

  defp load_job(socket, job_id) do
    case Jobs.get_job_by_external_id(job_id) do
      nil ->
        put_flash(socket, :error, "Job not found")

      job ->
        assign(socket, :job, job)
    end
  end
end
