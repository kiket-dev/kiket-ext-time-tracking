# kiket-ext-time-tracking

Time Tracking Extension for Kiket - Track time spent on issues with active timers, manual entries, and comprehensive reporting.

## Features

- **Active Timers**: Start/stop timers on issues with automatic duration calculation
- **Manual Time Entries**: Log time with flexible duration or time range input
- **Automatic Timer Stopping**: Auto-stop active timers when issues are closed
- **Comprehensive Filtering**: Filter entries by user, issue, date range, billable status, and tags
- **Summary Reports**: Aggregated time reports grouped by user and issue
- **CSV Export**: Export time entries with full filtering support
- **Analytics Integration**: dbt models for time analysis and dashboards
- **Command Palette Integration**: Quick access to timer and reporting functions
- **Billable Time Tracking**: Mark entries as billable or non-billable

## Installation

### Prerequisites

- Ruby 3.4+
- Bundler
- Access to Kiket custom_data module

### Setup

```bash
cd extensions/time-tracking
bundle install
```

### Environment Variables

Create a `.env` file:

```bash
RACK_ENV=development
PORT=9393
```

### Running Locally

```bash
bundle exec puma -C puma.rb
```

The extension will be available at `http://localhost:9393`.

## API Endpoints

### Health Check

**GET /health**

Returns extension health status.

```json
{
  "status": "ok",
  "extension": "time-tracking",
  "version": "1.0.0"
}
```

### Timer Management

**POST /timer/start**

Start tracking time on an issue.

Request:
```json
{
  "user_id": "user-123",
  "issue_id": "ISSUE-456",
  "description": "Working on authentication feature",
  "tags": ["development", "backend"]
}
```

Response:
```json
{
  "status": "started",
  "timer": {
    "id": 1,
    "user_id": "user-123",
    "issue_id": "ISSUE-456",
    "started_at": "2025-11-10T14:30:00Z",
    "description": "Working on authentication feature",
    "tags": ["development", "backend"]
  }
}
```

**POST /timer/stop**

Stop active timer and create time entry.

Request:
```json
{
  "user_id": "user-123",
  "description": "Updated description",
  "billable": true
}
```

Response:
```json
{
  "status": "stopped",
  "entry": {
    "id": 1,
    "user_id": "user-123",
    "issue_id": "ISSUE-456",
    "started_at": "2025-11-10T14:30:00Z",
    "ended_at": "2025-11-10T16:30:00Z",
    "duration_seconds": 7200,
    "duration_hours": 2.0,
    "description": "Updated description",
    "billable": true,
    "tags": ["development", "backend"]
  }
}
```

**GET /timer/active/:user_id**

Get active timer with elapsed time.

Response:
```json
{
  "timer": {
    "id": 1,
    "user_id": "user-123",
    "issue_id": "ISSUE-456",
    "started_at": "2025-11-10T14:30:00Z",
    "description": "Working on authentication feature",
    "tags": ["development", "backend"],
    "elapsed_seconds": 3600,
    "elapsed_hours": 1.0
  }
}
```

### Manual Time Entries

**POST /entries**

Create a manual time entry.

Request (with end time):
```json
{
  "user_id": "user-123",
  "issue_id": "ISSUE-456",
  "started_at": "2025-11-10T09:00:00Z",
  "ended_at": "2025-11-10T11:30:00Z",
  "description": "Code review",
  "billable": true,
  "tags": ["review"]
}
```

Request (with duration):
```json
{
  "user_id": "user-123",
  "issue_id": "ISSUE-456",
  "started_at": "2025-11-10T09:00:00Z",
  "duration_seconds": 9000,
  "description": "Code review",
  "billable": true,
  "tags": ["review"]
}
```

**PUT /entries/:id**

Update a time entry.

Request:
```json
{
  "description": "Updated code review",
  "billable": false,
  "tags": ["review", "urgent"]
}
```

**DELETE /entries/:id**

Delete a time entry.

Response:
```json
{
  "status": "deleted"
}
```

**GET /entries**

List time entries with filtering.

Query parameters:
- `user_id`: Filter by user
- `issue_id`: Filter by issue
- `start_date`: Filter entries after this date (ISO 8601)
- `end_date`: Filter entries before this date (ISO 8601)
- `billable`: Filter by billable status (true/false)
- `tags`: Filter by tags (comma-separated)

Example:
```
GET /entries?user_id=user-123&billable=true&start_date=2025-11-01&end_date=2025-11-30
```

### Reports and Export

**GET /reports/summary**

Generate summary report with totals and grouping.

Query parameters: Same as `/entries`

Response:
```json
{
  "total_entries": 45,
  "total_hours": 87.5,
  "billable_hours": 72.0,
  "non_billable_hours": 15.5,
  "billable_percentage": 82.29,
  "by_user": {
    "user-123": {
      "total_hours": 45.0,
      "billable_hours": 40.0,
      "entry_count": 20
    }
  },
  "by_issue": {
    "ISSUE-456": {
      "total_hours": 12.5,
      "billable_hours": 12.5,
      "entry_count": 5
    }
  }
}
```

**GET /export/csv**

Export time entries as CSV.

Query parameters: Same as `/entries`

Response: CSV file with columns:
- ID, User ID, Issue ID, Started At, Ended At, Duration (seconds), Duration (hours), Description, Tags, Billable, Created At, Updated At

### Webhooks

**POST /webhooks/issue.transitioned**

Automatically handles issue transitions. When an issue is closed, all active timers for that issue are stopped and tagged with "auto-stopped".

Request:
```json
{
  "issue_id": "ISSUE-456",
  "from_status": "In Progress",
  "to_status": "Closed"
}
```

## Custom Data Schema

The extension uses two custom data tables:

### time_entries

Stores completed time entries.

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| user_id | string | User identifier |
| issue_id | string | Issue identifier |
| started_at | timestamp | When time tracking started |
| ended_at | timestamp | When time tracking ended |
| duration_seconds | integer | Duration in seconds |
| duration_hours | decimal(10,2) | Duration in hours |
| description | text | Entry description |
| tags | json | Array of tags |
| billable | boolean | Whether time is billable (default: true) |
| created_at | timestamp | Record creation time |
| updated_at | timestamp | Record update time |

Indexes:
- `idx_time_entries_user_started` on (user_id, started_at)
- `idx_time_entries_issue_started` on (issue_id, started_at)
- `idx_time_entries_billable` on (billable)

### active_timers

Stores currently running timers.

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| user_id | string | User identifier (unique) |
| issue_id | string | Issue identifier |
| started_at | timestamp | When timer started |
| description | text | Timer description |
| tags | json | Array of tags |
| created_at | timestamp | Record creation time |

Unique constraint on `user_id` (one active timer per user).

## Analytics Models

The extension provides three dbt models for analytics:

### time_entries_daily

Incremental model aggregating time entries by day.

```sql
select
  date(started_at) as entry_date,
  user_id,
  issue_id,
  sum(duration_seconds) as total_seconds,
  sum(duration_hours) as total_hours,
  sum(case when billable then duration_hours else 0 end) as billable_hours,
  count(*) as entry_count,
  array_agg(distinct tag) as all_tags
from time_entries
group by 1, 2, 3
```

### user_time_summary

Summary statistics per user.

Metrics:
- Total entries and hours
- Billable vs non-billable breakdown
- Billable percentage
- Issues worked on
- Days worked
- Average hours per day
- Median entry duration

### issue_time_summary

Summary statistics per issue.

Metrics:
- Total contributors
- Total hours and entries
- Billable percentage
- Earliest and latest entries
- Average entry duration

### Dashboard

The `time_tracking_overview` dashboard provides:
- Summary metrics (total hours, billable hours, active timers)
- Time trends chart (daily hours over time)
- Top contributors bar chart
- Top issues by time bar chart
- Recent entries table

## Command Palette

The extension contributes the following commands to Kiket's command palette (⌘K / Ctrl+K):

- **Start Time Timer**: Start tracking time on the current issue
- **Stop Timer**: Stop your active timer
- **View Time Report**: View time tracking summary
- **Export Time Entries**: Export time entries as CSV
- **Log Time Manually**: Create a manual time entry

## Usage Examples

### Starting a Timer

```bash
curl -X POST http://localhost:9393/timer/start \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "john.doe",
    "issue_id": "PROJ-123",
    "description": "Implementing user authentication",
    "tags": ["development", "security"]
  }'
```

### Stopping a Timer

```bash
curl -X POST http://localhost:9393/timer/stop \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "john.doe",
    "billable": true
  }'
```

### Creating Manual Entry

```bash
curl -X POST http://localhost:9393/entries \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "john.doe",
    "issue_id": "PROJ-123",
    "started_at": "2025-11-10T09:00:00Z",
    "duration_seconds": 7200,
    "description": "Morning code review session",
    "billable": true,
    "tags": ["review"]
  }'
```

### Getting Summary Report

```bash
curl "http://localhost:9393/reports/summary?user_id=john.doe&start_date=2025-11-01&end_date=2025-11-30"
```

### Exporting to CSV

```bash
curl "http://localhost:9393/export/csv?user_id=john.doe&billable=true" \
  -o time_entries.csv
```

## Development

### Running Tests

```bash
bundle exec rspec
```

Test coverage includes:
- Timer start/stop operations
- Manual entry creation and updates
- Filtering and queries
- Summary report generation
- CSV export
- Webhook handling
- Error cases and validation

### Linting

```bash
bundle exec rubocop
```

Auto-fix:
```bash
bundle exec rubocop -a
```

### Docker

Build:
```bash
docker build -t kiket-ext-time-tracking .
```

Run:
```bash
docker run -p 9393:9393 -e RACK_ENV=production kiket-ext-time-tracking
```

## Deployment

The extension includes a GitHub Actions workflow for automatic deployment to Google Cloud Run.

Deployment triggers:
- Push to `main` branch
- Git tags matching `v*`

Required GitHub secrets:
- `GCP_WORKLOAD_IDENTITY_PROVIDER`
- `GCP_SERVICE_ACCOUNT`

## Best Practices

1. **Timer Management**
   - Stop timers at end of day to ensure accurate tracking
   - Use descriptive descriptions for better reporting
   - Tag entries consistently for easier filtering

2. **Manual Entries**
   - Use `duration_seconds` for quick entries
   - Use `started_at` and `ended_at` for precise time ranges
   - Always provide meaningful descriptions

3. **Billable Time**
   - Mark non-billable time explicitly
   - Use consistent tagging for billable work types
   - Review billable percentage regularly

4. **Reporting**
   - Use date filters for period-based reports
   - Export to CSV for detailed analysis
   - Leverage analytics dashboard for trends

## Permissions

The extension uses role-based access control:

- **user**: Can read/write/delete own time entries
- **manager**: Can read/write all time entries
- **admin**: Full access to all data

## Troubleshooting

### Timer won't start

- Check if user already has an active timer
- Ensure `user_id` and `issue_id` are provided
- Verify the user has permission to create entries

### Timer not auto-stopping

- Check webhook is configured for `issue.transitioned` event
- Verify webhook payload includes `issue_id` and `to_status`
- Check application logs for webhook processing errors

### Missing entries in reports

- Verify date filters are correct (ISO 8601 format)
- Check if entries were created with different user_id
- Ensure entries have valid timestamps

### CSV export fails

- Check if query parameters are valid
- Verify sufficient permissions for filtered data
- Ensure there are entries matching the filters

## Support

For issues and questions, please refer to the main Kiket documentation or open an issue in the repository.

## License

Part of the Kiket platform.