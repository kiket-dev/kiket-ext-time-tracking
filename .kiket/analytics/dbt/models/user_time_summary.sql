{{
  config(
    materialized='table'
  )
}}

-- User-level time tracking summary
with user_totals as (
  select
    user_id,
    count(*) as total_entries,
    sum(duration_seconds) as total_seconds,
    sum(duration_hours) as total_hours,
    sum(case when billable then duration_seconds else 0 end) as billable_seconds,
    sum(case when billable then duration_hours else 0 end) as billable_hours,
    min(started_at) as first_entry_at,
    max(ended_at) as last_entry_at,
    count(distinct issue_id) as issues_worked,
    count(distinct date(started_at)) as days_worked
  from {{ source('time_tracking', 'time_entries') }}
  group by 1
),

user_avg as (
  select
    user_id,
    avg(duration_hours) as avg_entry_hours,
    percentile_cont(0.5) within group (order by duration_hours) as median_entry_hours
  from {{ source('time_tracking', 'time_entries') }}
  group by 1
)

select
  t.user_id,
  t.total_entries,
  t.total_seconds,
  t.total_hours,
  t.billable_seconds,
  t.billable_hours,
  t.total_hours - t.billable_hours as non_billable_hours,
  round(100.0 * t.billable_hours / nullif(t.total_hours, 0), 2) as billable_percentage,
  t.first_entry_at,
  t.last_entry_at,
  t.issues_worked,
  t.days_worked,
  round(t.total_hours / nullif(t.days_worked, 0), 2) as avg_hours_per_day,
  a.avg_entry_hours,
  a.median_entry_hours,
  current_timestamp as calculated_at
from user_totals t
left join user_avg a on t.user_id = a.user_id
