# AI-Powered Job Application System

This document describes the comprehensive AI features implemented in the Phoenix core backend.

## Overview

The system implements six major AI components that work together to optimize job applications:

1. **AI-Powered Job Matching Engine** - Multi-factor scoring for job-user compatibility
2. **Predictive Success Models** - ML-based success probability prediction with continuous learning
3. **Intelligent Application Orchestrator** - Timing optimization and strategy generation
4. **Smart Rate Limit Optimizer** - Dynamic rate allocation based on success patterns
5. **Company Research Automation** - Automated intelligence gathering on employers
6. **Real-Time AI Analytics Engine** - Performance monitoring and insights

## Architecture

```
Core.AI (Main API)
├── Matching.Engine          - Job matching with multi-factor scoring
│   ├── Scorer               - Scoring algorithms
│   └── FeatureExtractor     - Feature extraction from jobs/CVs
├── Prediction.Engine        - Success prediction
│   ├── Features             - Prediction feature extraction
│   └── TimingOptimizer      - Optimal timing computation
├── Learning.FeedbackCollector - Continuous learning system
├── RateLimit.Optimizer      - Intelligent rate limiting
├── Company.ResearchEngine   - Automated company research
├── Analytics                - Real-time analytics and tracking
└── Orchestrator             - Main coordination layer
```

## Features

### 1. AI-Powered Job Matching Engine

Multi-dimensional scoring that evaluates:

- **Skills Match** (30% weight) - Semantic matching of required/preferred skills
- **Experience Match** (25% weight) - Years of experience and seniority alignment
- **Salary Match** (15% weight) - Compensation expectations vs offering
- **Location Match** (10% weight) - Geographic and remote work preferences
- **Company Culture** (10% weight) - Values and culture alignment
- **Career Growth** (5% weight) - Growth opportunities and trajectory
- **Benefits** (5% weight) - Benefits and perks matching

**Key Features:**
- Semantic skill matching with synonym awareness
- Confidence levels for each dimension
- Detailed recommendations and concerns
- Missing skills identification
- Caching for performance (24-hour TTL)

**Usage:**
```elixir
{:ok, score} = Core.AI.compute_match(job, user_id)
# score.overall_score: 0.0-1.0
# score.matching_skills: ["python", "react", ...]
# score.missing_skills: ["kubernetes", ...]
# score.recommendations: "Consider highlighting..."
```

### 2. Predictive Success Models

ML-based prediction system that forecasts:

- **Success Probability** - Overall likelihood of positive outcome
- **Response Probability** - Chance of hearing back
- **Interview Probability** - Likelihood of interview invitation
- **Offer Probability** - Chance of receiving offer
- **Response Time** - Expected time to hear back
- **Optimal Application Time** - Best time to apply

**Factors Considered:**
- User profile strength (completeness, experience, skills)
- Job-user match quality
- Application timing and freshness
- Market demand and competition
- Company responsiveness patterns
- Historical success rates

**Continuous Learning:**
- Records actual outcomes vs predictions
- Computes accuracy metrics (MAE, RMSE, F1)
- Collects feedback for model improvement
- Triggers retraining when threshold reached

**Usage:**
```elixir
{:ok, prediction} = Core.AI.predict_success(job, user_id)
# prediction.success_probability: 0.0-1.0
# prediction.optimal_application_time: DateTime
# prediction.recommendations: "Wait for optimal timing..."

# Record outcome for learning
Core.AI.record_outcome(prediction.id, "interview", 48)
```

### 3. Intelligent Application Orchestrator

Main coordination layer that:

- Combines all AI features for comprehensive analysis
- Prioritizes jobs based on multiple factors
- Generates application strategies (aggressive/balanced/conservative)
- Optimizes timing across multiple applications
- Provides actionable recommendations

**Orchestration Process:**
1. Fetch and analyze available jobs
2. Compute match scores for all jobs
3. Generate success predictions
4. Apply intelligent filtering
5. Research companies in batch
6. Generate prioritized recommendations
7. Create application strategy

**Usage:**
```elixir
{:ok, result} = Core.AI.orchestrate_applications(user_id, jobs)
# result.recommended_jobs: Top-ranked jobs with full analysis
# result.strategy: Application strategy (type, daily rate, rationale)
# result.rate_strategy: Rate limit optimization plan
```

### 4. Smart Rate Limit Optimizer

Dynamically optimizes rate limit allocation:

- **User-Specific Rates** - Adapts to individual success patterns
- **Priority-Based Allocation** - Reserves tokens for high-probability jobs
- **Strategy Selection** - Aggressive/Balanced/Conservative approaches
- **Batch Size Optimization** - Recommends optimal application batch sizes
- **Performance Adaptation** - Adjusts rates based on recent outcomes

**Decision Logic:**
- High success rate (>60%) + quality jobs → Aggressive (up to 200/day)
- Low success rate (<30%) → Conservative (selective, ~20/day)
- Moderate performance → Balanced (optimize quality)

**Usage:**
```elixir
{:ok, decision} = Core.AI.should_allow_application?(user_id, job)
# {:allow, priority} - Go ahead with given priority
# {:defer, reason} - Wait for better timing
# {:reject, reason} - Skip this application

{:ok, batch} = Core.AI.recommend_batch_size(user_id, jobs)
# batch.recommended_batch_size: 5-20
# batch.rationale: "Conservative due to low success rate"
```

### 5. Company Research Automation

Automatically gathers and analyzes company data:

**Data Collected:**
- Company basics (industry, size, description)
- Culture keywords and values
- Technology stack
- Benefits and perks
- Hiring trends and velocity
- Reputation and responsiveness scores
- Recent news and updates

**Analysis:**
- Reputation scoring (0.0-1.0)
- Employee satisfaction estimates
- Growth trajectory classification
- Hiring velocity trends
- Salary range analysis
- Competitive positioning

**Caching:**
- 7-day cache validity
- Automatic staleness detection
- Batch refresh capabilities

**Usage:**
```elixir
{:ok, research} = Core.AI.research_company("Yandex")
# research.reputation_score: 0.0-1.0
# research.tech_stack: ["python", "go", "kubernetes", ...]
# research.culture_keywords: ["innovation", "growth", ...]
# research.hiring_trends: %{velocity: 2.5, trend: "growing"}
```

### 6. Real-Time AI Analytics Engine

Comprehensive analytics and monitoring:

**Event Tracking:**
- All AI operations tracked with timestamps
- Model performance metrics
- User behavior patterns
- System health indicators

**Metrics Provided:**
- Real-time system metrics
- Time-series data for charting
- User-specific analytics
- Model performance by version
- Error rates and trends

**Dashboards:**
- Active users and engagement
- Model accuracy trends
- Processing time distributions
- Success rate correlations

**Usage:**
```elixir
# Track custom events
Core.AI.track_event("job_match_computed", %{
  user_id: 1,
  job_id: 123,
  overall_score: 0.85
})

# Get real-time metrics
{:ok, metrics} = Core.AI.get_realtime_metrics(time_window_minutes: 60)
# metrics.total_events: 1523
# metrics.avg_processing_time: 145ms
# metrics.model_performance: %{avg_accuracy: 0.83}

# User analytics
{:ok, analytics} = Core.AI.get_user_analytics(user_id)
```

## API Endpoints

### Main Orchestration

**POST /api/ai/orchestrate**
```json
{
  "user_id": 123,
  "job_ids": [1, 2, 3],
  "options": {
    "min_match_score": 0.5,
    "min_success_probability": 0.4,
    "max_results": 20
  }
}
```

**POST /api/ai/evaluate-job**
```json
{
  "user_id": 123,
  "job_id": 456
}
```

### Job Matching

**POST /api/ai/match**
```json
{
  "user_id": 123,
  "job_id": 456
}
```

### Success Prediction

**POST /api/ai/predict**
```json
{
  "user_id": 123,
  "job_id": 456
}
```

**POST /api/ai/record-outcome**
```json
{
  "application_id": 789,
  "outcome": "interview",
  "response_time_hours": 48
}
```

### Company Research

**POST /api/ai/research-company**
```json
{
  "company_name": "Yandex"
}
```

### Analytics

**GET /api/ai/analytics/realtime?time_window=60**

**GET /api/ai/analytics/user/:user_id?days_back=30**

**GET /api/ai/health**

## Database Schema

### ai_job_matching_scores
- Multi-factor scores (skill, experience, salary, location, culture, growth, benefits)
- Matching/missing skills
- Recommendations and concerns
- Confidence levels
- Performance tracking

### application_predictions
- Success/response/interview/offer probabilities
- Timing predictions and optimal application time
- Factor breakdowns
- Actual outcomes for learning
- Accuracy tracking

### company_research
- Company profile and basics
- Culture, tech stack, benefits
- Reputation and satisfaction scores
- Hiring trends and market position
- Cache management

### ai_analytics_events
- Event tracking with categories
- Model performance metrics
- Time-series support
- User activity tracking

### learning_feedback
- Prediction vs actual outcomes
- Feature vectors and importance
- Model performance metrics
- Training data collection

## Performance

**Computation Times:**
- Job matching: ~100-200ms per job
- Success prediction: ~150-300ms per job
- Company research: ~500ms-2s (cached: <10ms)
- Full orchestration (20 jobs): ~3-5s

**Optimizations:**
- Async/concurrent processing (10 workers)
- 24-hour caching for match scores
- 7-day caching for company research
- Batch operations for efficiency
- Database indexes on key fields

## Continuous Learning

The system learns from real outcomes:

1. **Feedback Collection** - Actual outcomes recorded
2. **Accuracy Computation** - Prediction errors calculated
3. **Performance Metrics** - MAE, RMSE, Precision, Recall, F1
4. **Feature Analysis** - Feature importance tracking
5. **Model Improvement** - Retraining triggered at thresholds

**Learning Metrics:**
- Prediction accuracy over time
- Feature importance weights
- Model version performance comparison
- Error distribution analysis

## Configuration

Key configuration points:

```elixir
# Match score weights
@score_weights %{
  skill_match: 0.30,
  experience_match: 0.25,
  salary_match: 0.15,
  location_match: 0.10,
  company_culture: 0.10,
  career_growth: 0.05,
  benefits: 0.05
}

# Rate limits
@default_daily_limit 200  # HH.ru platform limit
@min_success_probability 0.4

# Cache durations
match_scores: 24 hours
company_research: 7 days
```

## Future Enhancements

Potential improvements:

1. **Advanced NLP** - Better semantic understanding with embeddings
2. **Deep Learning Models** - Neural networks for predictions
3. **A/B Testing** - Compare model versions
4. **External Data Sources** - Glassdoor, LinkedIn integration
5. **Personalization** - User-specific model training
6. **Multi-language Support** - Better handling of Russian content
7. **Real-time Model Updates** - Online learning
8. **Explainable AI** - Better transparency in recommendations

## Testing

Run tests:
```bash
mix test test/core/ai/
```

## Monitoring

Monitor AI system health:
- Check `/api/ai/health` endpoint
- Review real-time metrics dashboard
- Monitor model performance trends
- Track error rates and latencies

## License

Part of the UllGetTheJob core backend system.
