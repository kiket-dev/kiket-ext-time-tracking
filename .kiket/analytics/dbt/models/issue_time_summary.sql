{{
  config(
    materialized='table'
  )
}}

-- Issue-level time tracking summary
select
  issue_id,
  count(*) as total_entries,
  count(distinct user_id) as contributors,
  sum(duration_seconds) as total_seconds,
  sum(duration_hours) as total_hours,
  sum(case when billable then duration_seconds else 0 end) as billable_seconds,
  sum(case when billable then duration_hours else 0 end) as billable_hours,
  sum(duration_hours) - sum(case when billable then duration_hours else 0 end) as non_billable_hours,
  round(100.0 * sum(case when billable then duration_hours else 0 end) / nullif(sum(duration_hours), 0), 2) as billable_percentage,
  min(started_at) as first_entry_at,
  max(ended_at) as last_entry_at,
  avg(duration_hours) as avg_entry_hours,
  max(duration_hours) as max_entry_hours,
  current_timestamp as calculated_at
from {{ source('time_tracking', 'time_entries') }}
group by 1
