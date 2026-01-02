# Getting Started with Time Tracking

Track time spent on issues with automatic timers, manual entries, and reporting.

## Features

- Start/stop timers on issues
- Manual time entry
- Time reports by user, project, or date range
- Integration with billing systems
- Export to CSV/PDF

## Step 1: Enable Time Tracking

1. Go to **Project Settings → Extensions → Time Tracking**
2. Enable time tracking for the project
3. Configure settings:
   - **Require time entries**: Mandate logging before closing issues
   - **Auto-start timer**: Start timer when issue moves to "In Progress"
   - **Rounding**: Round to nearest 15/30/60 minutes

## Step 2: Track Time

### Using Timers
1. Open an issue
2. Click **Start Timer** in the sidebar
3. Work on the issue
4. Click **Stop Timer** when done

### Manual Entry
1. Open an issue
2. Click **Log Time**
3. Enter hours/minutes and description
4. Submit

## Step 3: Automate Time Tracking

```yaml
automations:
  - name: auto_start_timer
    trigger:
      event: issue.transitioned
      conditions:
        - field: transition.to
          operator: eq
          value: "in_progress"
    actions:
      - extension: dev.kiket.ext.time-tracking
        command: time.startTimer
        params:
          issue_id: "{{ issue.id }}"
          user_id: "{{ user.id }}"

  - name: auto_stop_timer
    trigger:
      event: issue.transitioned
      conditions:
        - field: transition.to
          operator: in
          value: ["review", "done"]
    actions:
      - extension: dev.kiket.ext.time-tracking
        command: time.stopTimer
        params:
          issue_id: "{{ issue.id }}"
```

## Reports

Access time reports via **Project → Reports → Time Tracking**:
- Time by user
- Time by issue type
- Time by date range
- Billable vs non-billable hours
