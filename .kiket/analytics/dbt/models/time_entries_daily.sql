{{
  config(
    materialized='incremental',
    unique_key='day_user_issue',
    on_schema_change='append_new_columns'
  )
}}

-- Daily aggregation of time entries by user and issue
with daily_entries as (
  select
    date(started_at) as entry_date,
    user_id,
    issue_id,
    sum(duration_seconds) as total_seconds,
    sum(duration_hours) as total_hours,
    sum(case when billable then duration_seconds else 0 end) as billable_seconds,
    sum(case when billable then duration_hours else 0 end) as billable_hours,
    count(*) as entry_count,
    min(started_at) as first_entry_at,
    max(ended_at) as last_entry_at,
    array_agg(distinct tag) as all_tags
  from {{ source('time_tracking', 'time_entries') }},
       unnest(coalesce(tags, array[]::text[])) as tag

  {% if is_incremental() %}
    where started_at >= (select max(entry_date) from {{ this }})
  {% endif %}

  group by 1, 2, 3
)

select
  md5(entry_date::text || user_id || issue_id) as day_user_issue,
  entry_date,
  user_id,
  issue_id,
  total_seconds,
  total_hours,
  billable_seconds,
  billable_hours,
  total_hours - billable_hours as non_billable_hours,
  entry_count,
  first_entry_at,
  last_entry_at,
  all_tags,
  current_timestamp as calculated_at
from daily_entries
