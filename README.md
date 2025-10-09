# YOU WILL GET THE JOB 🚀

An intelligent job application automation platform built with Phoenix LiveView, designed to streamline your job search on HH.ru with AI-powered CV customization and automated tracking.

## ✨ Features

### 🔍 Smart Job Discovery
- **Real-time job fetching** from HH.ru API with configurable search criteria
- **Live streaming interface** displaying jobs as they're fetched
- **Multi-query search** for comprehensive job coverage
- **Rate limiting** to respect API constraints
- **Duplicate detection** to avoid redundant applications

### 📄 Intelligent CV Management
- **Drag & drop CV upload** supporting PDF, DOCX, and TXT formats
- **AI-powered parsing** to extract structured data (skills, experience, projects)
- **Custom CV versions** tailored to specific job requirements
- **Highlight relevant experience** based on job descriptions using AI
- **Version tracking** for multiple job applications

### 🤖 AI-Powered Customization
- **Job requirement analysis** to understand what employers want
- **Automatic CV highlighting** to emphasize relevant skills and experience
- **Cover letter generation** customized for each job posting
- **OpenRouter integration** supporting GPT-4, Claude, and other models
- **Real-time preview** of customized content

### 📊 Application Tracking
- **Centralized dashboard** for all job applications
- **Status tracking** (pending, submitted, failed)
- **Response monitoring** to track employer feedback
- **Daily application limits** for safe automation
- **Submission history** with detailed logs

## 🛠️ Tech Stack

- **[Phoenix Framework](https://www.phoenixframework.org/)** v1.8 - Modern web framework for Elixir
- **[Phoenix LiveView](https://hexdocs.pm/phoenix_live_view/)** v1.1 - Real-time interactive UI
- **[PostgreSQL](https://www.postgresql.org/)** - Robust database for storing jobs, CVs, and applications
- **[Req](https://hexdocs.pm/req/)** - Modern HTTP client for API interactions
- **[Tailwind CSS](https://tailwindcss.com/)** v4 - Utility-first CSS framework
- **[OpenRouter](https://openrouter.ai/)** - AI model gateway for CV analysis and generation

## 📋 Prerequisites

- Elixir 1.15 or higher
- Erlang/OTP 26 or higher
- PostgreSQL 14 or higher
- Node.js 18+ (for asset compilation)

## 🚀 Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/ullgetthejobs.git
cd ullgetthejobs
```

### 2. Install Dependencies

```bash
mix setup
```

This will:
- Install Elixir dependencies
- Create and migrate the database
- Install and build assets

### 3. Configure Environment

Create a `.env` file in the project root:

```bash
# Database
DATABASE_URL=ecto://postgres:postgres@localhost/dashboard_dev

# OpenRouter AI Configuration
OPENROUTER_API_KEY=your_api_key_here
OPENROUTER_MODEL=openai/gpt-4-turbo

# HH.ru Authentication (optional - for advanced features)
HH_COOKIES_FILE=hh.ru_cookies.txt

# Application Settings
MAX_DAILY_APPLICATIONS=10
```

### 4. Get Your OpenRouter API Key

1. Sign up at [OpenRouter](https://openrouter.ai/)
2. Navigate to API Keys section
3. Create a new API key
4. Add it to your `.env` file

### 5. Start the Server

```bash
mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000) in your browser.

## 📖 Usage Guide

### Uploading Your CV

1. Navigate to `/cvs/upload`
2. Drag & drop your CV (PDF, DOCX, or TXT)
3. Wait for AI to parse and extract structured data
4. Review the parsed information

### Finding Jobs

1. Go to `/jobs`
2. Click "Fetch Now" to retrieve jobs from HH.ru
3. Browse available positions in real-time
4. Select jobs you're interested in using checkboxes

### Customizing Your Application

1. Select one or more jobs and click "Customize CV & Apply"
2. The AI will analyze job requirements
3. Generate customized CV highlighting relevant experience
4. Create a tailored cover letter
5. Review and edit as needed
6. Save your custom application

### Submitting Applications

1. Preview your application at `/applications/new`
2. Review job details, customized CV, and cover letter
3. Make final edits if needed
4. Click "Submit Application"
5. Track status in the Applications dashboard

### Tracking Applications

1. Visit `/applications` to see all submissions
2. Filter by status (pending, submitted, failed)
3. View detailed information about each application
4. Monitor employer responses

## 🏗️ Project Structure

```
ullgetthejobs/
├── lib/
│   ├── dashboard/              # Core business logic
│   │   ├── ai/                 # OpenRouter AI client
│   │   ├── applications/       # Job application management
│   │   ├── cvs/                # CV storage and parsing
│   │   ├── hh/                 # HH.ru API integration
│   │   ├── jobs/               # Job fetching and storage
│   │   ├── cv_editor.ex        # CV customization logic
│   │   └── rate_limiter.ex     # API rate limiting
│   ├── dashboard_web/          # Web interface
│   │   └── live/               # LiveView modules
│   └── dashboard.ex            # Application entry point
├── priv/
│   ├── repo/migrations/        # Database migrations
│   └── static/                 # Static assets
├── assets/                     # Frontend assets
├── test/                       # Test suite
└── config/                     # Configuration files
```

## 🧪 Development

### Run Tests

```bash
mix test
```

### Run Quality Checks

```bash
mix precommit
```

This will:
- Compile with warnings as errors
- Remove unused dependencies
- Format code
- Run full test suite

### Database Commands

```bash
# Create database
mix ecto.create

# Run migrations
mix ecto.migrate

# Reset database
mix ecto.reset

# Rollback last migration
mix ecto.rollback
```

## 🔒 Security & Privacy

- **Cookie files** containing authentication data are gitignored
- **Environment variables** are used for sensitive configuration
- **Uploaded CVs** are stored locally and not committed to version control
- **Rate limiting** prevents API abuse
- **Daily application limits** ensure responsible automation

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Phoenix Framework](https://www.phoenixframework.org/) for the excellent web framework
- [OpenRouter](https://openrouter.ai/) for AI model access
- [HH.ru](https://hh.ru/) for the job search API
- The Elixir community for amazing tools and support

## 📧 Contact

For questions or feedback, please open an issue on GitHub.

---

**Note**: This tool is designed to assist with job applications, not to spam employers. Please use responsibly and in accordance with HH.ru's terms of service.
