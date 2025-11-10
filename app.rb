# frozen_string_literal: true

require "sinatra/base"
require "json"
require "chronic"
require "logger"
require "csv"

# Time Tracking Extension
# Manages time entries, timers, and reporting for issues
class TimeTrackingExtension < Sinatra::Base
  # Custom error classes
  class ValidationError < StandardError; end
  class NotFoundError < StandardError; end
  class TimerError < StandardError; end

  configure do
    set :logging, true
    set :logger, Logger.new($stdout)

    # In-memory storage for time entries (production should use custom_data tables)
    set :time_entries, []

    # Active timers (user_id => timer data)
    set :active_timers, {}

    # Timer start counter for ID generation
    set :entry_counter, 0
  end

  # Health check endpoint
  get "/health" do
    content_type :json
    {
      status: "healthy",
      service: "time-tracking",
      version: "1.0.0",
      timestamp: Time.now.utc.iso8601,
      active_timers: settings.active_timers.count,
      total_entries: settings.time_entries.count
    }.to_json
  end

  # Start a timer
  post "/timer/start" do
    content_type :json

    begin
      request_body = JSON.parse(request.body.read, symbolize_names: true)

      validate_timer_start!(request_body)

      user_id = request_body[:user_id]
      issue_id = request_body[:issue_id]

      # Check if user already has an active timer
      if settings.active_timers[user_id]
        raise TimerError, "User already has an active timer. Stop it first."
      end

      # Create timer
      timer = {
        user_id: user_id,
        issue_id: issue_id,
        started_at: Time.now.utc,
        description: request_body[:description],
        tags: request_body[:tags] || []
      }

      settings.active_timers[user_id] = timer

      status 200
      {
        success: true,
        timer: timer.merge(
          started_at: timer[:started_at].iso8601,
          elapsed_seconds: 0
        )
      }.to_json

    rescue JSON::ParserError => e
      logger.error "Invalid JSON: #{e.message}"
      status 400
      { success: false, error: "Invalid JSON in request body" }.to_json

    rescue ValidationError, TimerError => e
      logger.error "Error: #{e.message}"
      status 400
      { success: false, error: e.message }.to_json

    rescue StandardError => e
      logger.error "Unexpected error: #{e.message}"
      logger.error e.backtrace.join("\n")
      status 500
      { success: false, error: "Internal server error" }.to_json
    end
  end

  # Stop a timer and create time entry
  post "/timer/stop" do
    content_type :json

    begin
      request_body = JSON.parse(request.body.read, symbolize_names: true)

      user_id = request_body[:user_id]
      raise ValidationError, "user_id is required" unless user_id

      timer = settings.active_timers[user_id]
      raise NotFoundError, "No active timer for user" unless timer

      # Calculate duration
      ended_at = Time.now.utc
      duration_seconds = (ended_at - timer[:started_at]).to_i

      # Create time entry
      settings.entry_counter += 1
      entry = {
        id: settings.entry_counter,
        user_id: timer[:user_id],
        issue_id: timer[:issue_id],
        started_at: timer[:started_at],
        ended_at: ended_at,
        duration_seconds: duration_seconds,
        duration_hours: (duration_seconds / 3600.0).round(2),
        description: timer[:description],
        tags: timer[:tags],
        billable: request_body[:billable] != false,  # Default to billable
        created_at: Time.now.utc
      }

      settings.time_entries << entry

      # Remove active timer
      settings.active_timers.delete(user_id)

      status 200
      {
        success: true,
        entry: serialize_entry(entry)
      }.to_json

    rescue JSON::ParserError, ValidationError, NotFoundError => e
      status 400
      { success: false, error: e.message }.to_json

    rescue StandardError => e
      logger.error "Unexpected error: #{e.message}"
      status 500
      { success: false, error: "Internal server error" }.to_json
    end
  end

  # Get active timer for user
  get "/timer/active/:user_id" do
    content_type :json

    user_id = params[:user_id]
    timer = settings.active_timers[user_id]

    if timer
      elapsed_seconds = (Time.now.utc - timer[:started_at]).to_i

      status 200
      {
        success: true,
        timer: timer.merge(
          started_at: timer[:started_at].iso8601,
          elapsed_seconds: elapsed_seconds,
          elapsed_hours: (elapsed_seconds / 3600.0).round(2)
        )
      }.to_json
    else
      status 404
      { success: false, error: "No active timer for user" }.to_json
    end
  end

  # Create manual time entry
  post "/entries" do
    content_type :json

    begin
      request_body = JSON.parse(request.body.read, symbolize_names: true)

      validate_entry_create!(request_body)

      # Parse dates
      started_at = parse_datetime(request_body[:started_at])
      ended_at = parse_datetime(request_body[:ended_at]) if request_body[:ended_at]

      # Calculate duration
      if ended_at
        duration_seconds = (ended_at - started_at).to_i
      elsif request_body[:duration_seconds]
        duration_seconds = request_body[:duration_seconds].to_i
        ended_at = started_at + duration_seconds
      else
        raise ValidationError, "Either ended_at or duration_seconds is required"
      end

      # Create entry
      settings.entry_counter += 1
      entry = {
        id: settings.entry_counter,
        user_id: request_body[:user_id],
        issue_id: request_body[:issue_id],
        started_at: started_at,
        ended_at: ended_at,
        duration_seconds: duration_seconds,
        duration_hours: (duration_seconds / 3600.0).round(2),
        description: request_body[:description],
        tags: request_body[:tags] || [],
        billable: request_body[:billable] != false,
        created_at: Time.now.utc
      }

      settings.time_entries << entry

      status 201
      {
        success: true,
        entry: serialize_entry(entry)
      }.to_json

    rescue JSON::ParserError, ValidationError => e
      status 400
      { success: false, error: e.message }.to_json

    rescue StandardError => e
      logger.error "Unexpected error: #{e.message}"
      status 500
      { success: false, error: "Internal server error" }.to_json
    end
  end

  # Update time entry
  put "/entries/:id" do
    content_type :json

    begin
      entry_id = params[:id].to_i
      request_body = JSON.parse(request.body.read, symbolize_names: true)

      entry = settings.time_entries.find { |e| e[:id] == entry_id }
      raise NotFoundError, "Time entry not found" unless entry

      # Update fields
      if request_body[:started_at]
        entry[:started_at] = parse_datetime(request_body[:started_at])
      end

      if request_body[:ended_at]
        entry[:ended_at] = parse_datetime(request_body[:ended_at])
      end

      if request_body[:duration_seconds]
        entry[:duration_seconds] = request_body[:duration_seconds].to_i
        entry[:ended_at] = entry[:started_at] + entry[:duration_seconds]
      end

      # Recalculate duration if times changed
      if entry[:started_at] && entry[:ended_at]
        entry[:duration_seconds] = (entry[:ended_at] - entry[:started_at]).to_i
        entry[:duration_hours] = (entry[:duration_seconds] / 3600.0).round(2)
      end

      entry[:description] = request_body[:description] if request_body.key?(:description)
      entry[:tags] = request_body[:tags] if request_body.key?(:tags)
      entry[:billable] = request_body[:billable] if request_body.key?(:billable)

      status 200
      {
        success: true,
        entry: serialize_entry(entry)
      }.to_json

    rescue JSON::ParserError, NotFoundError, ValidationError => e
      status 400
      { success: false, error: e.message }.to_json

    rescue StandardError => e
      logger.error "Unexpected error: #{e.message}"
      status 500
      { success: false, error: "Internal server error" }.to_json
    end
  end

  # Delete time entry
  delete "/entries/:id" do
    content_type :json

    entry_id = params[:id].to_i
    entry = settings.time_entries.find { |e| e[:id] == entry_id }

    if entry
      settings.time_entries.delete(entry)

      status 200
      {
        success: true,
        message: "Time entry deleted"
      }.to_json
    else
      status 404
      { success: false, error: "Time entry not found" }.to_json
    end
  end

  # List time entries with filtering
  get "/entries" do
    content_type :json

    entries = settings.time_entries

    # Filter by user
    if params[:user_id]
      entries = entries.select { |e| e[:user_id] == params[:user_id] }
    end

    # Filter by issue
    if params[:issue_id]
      entries = entries.select { |e| e[:issue_id] == params[:issue_id] }
    end

    # Filter by date range
    if params[:start_date]
      start_date = parse_datetime(params[:start_date])
      entries = entries.select { |e| e[:started_at] >= start_date }
    end

    if params[:end_date]
      end_date = parse_datetime(params[:end_date])
      entries = entries.select { |e| e[:started_at] <= end_date }
    end

    # Filter by billable status
    if params[:billable]
      billable = params[:billable] == "true"
      entries = entries.select { |e| e[:billable] == billable }
    end

    # Filter by tags
    if params[:tags]
      tags = params[:tags].split(",")
      entries = entries.select { |e| (e[:tags] & tags).any? }
    end

    # Sort
    entries = entries.sort_by { |e| e[:started_at] }.reverse

    status 200
    {
      success: true,
      count: entries.count,
      entries: entries.map { |e| serialize_entry(e) }
    }.to_json
  end

  # Get time entry by ID
  get "/entries/:id" do
    content_type :json

    entry_id = params[:id].to_i
    entry = settings.time_entries.find { |e| e[:id] == entry_id }

    if entry
      status 200
      {
        success: true,
        entry: serialize_entry(entry)
      }.to_json
    else
      status 404
      { success: false, error: "Time entry not found" }.to_json
    end
  end

  # Get summary report
  get "/reports/summary" do
    content_type :json

    entries = settings.time_entries

    # Apply filters
    if params[:user_id]
      entries = entries.select { |e| e[:user_id] == params[:user_id] }
    end

    if params[:issue_id]
      entries = entries.select { |e| e[:issue_id] == params[:issue_id] }
    end

    if params[:start_date]
      start_date = parse_datetime(params[:start_date])
      entries = entries.select { |e| e[:started_at] >= start_date }
    end

    if params[:end_date]
      end_date = parse_datetime(params[:end_date])
      entries = entries.select { |e| e[:started_at] <= end_date }
    end

    # Calculate totals
    total_seconds = entries.sum { |e| e[:duration_seconds] }
    total_hours = (total_seconds / 3600.0).round(2)

    billable_entries = entries.select { |e| e[:billable] }
    billable_seconds = billable_entries.sum { |e| e[:duration_seconds] }
    billable_hours = (billable_seconds / 3600.0).round(2)

    # Group by user
    by_user = entries.group_by { |e| e[:user_id] }.transform_values do |user_entries|
      {
        total_seconds: user_entries.sum { |e| e[:duration_seconds] },
        total_hours: (user_entries.sum { |e| e[:duration_seconds] } / 3600.0).round(2),
        entry_count: user_entries.count
      }
    end

    # Group by issue
    by_issue = entries.group_by { |e| e[:issue_id] }.transform_values do |issue_entries|
      {
        total_seconds: issue_entries.sum { |e| e[:duration_seconds] },
        total_hours: (issue_entries.sum { |e| e[:duration_seconds] } / 3600.0).round(2),
        entry_count: issue_entries.count
      }
    end

    status 200
    {
      success: true,
      summary: {
        total_entries: entries.count,
        total_seconds: total_seconds,
        total_hours: total_hours,
        billable_entries: billable_entries.count,
        billable_seconds: billable_seconds,
        billable_hours: billable_hours,
        non_billable_hours: (total_hours - billable_hours).round(2),
        by_user: by_user,
        by_issue: by_issue
      }
    }.to_json
  end

  # Export time entries as CSV
  get "/export/csv" do
    content_type "text/csv"
    attachment "time_entries.csv"

    entries = settings.time_entries

    # Apply same filters as list endpoint
    if params[:user_id]
      entries = entries.select { |e| e[:user_id] == params[:user_id] }
    end

    if params[:issue_id]
      entries = entries.select { |e| e[:issue_id] == params[:issue_id] }
    end

    if params[:start_date]
      start_date = parse_datetime(params[:start_date])
      entries = entries.select { |e| e[:started_at] >= start_date }
    end

    if params[:end_date]
      end_date = parse_datetime(params[:end_date])
      entries = entries.select { |e| e[:started_at] <= end_date }
    end

    # Generate CSV
    CSV.generate do |csv|
      csv << ["ID", "User ID", "Issue ID", "Started At", "Ended At", "Duration (hours)", "Description", "Tags", "Billable", "Created At"]

      entries.each do |entry|
        csv << [
          entry[:id],
          entry[:user_id],
          entry[:issue_id],
          entry[:started_at].iso8601,
          entry[:ended_at].iso8601,
          entry[:duration_hours],
          entry[:description],
          entry[:tags].join(", "),
          entry[:billable],
          entry[:created_at].iso8601
        ]
      end
    end
  end

  # Webhook handler for issue transitions
  post "/webhooks/issue.transitioned" do
    content_type :json

    begin
      request_body = JSON.parse(request.body.read, symbolize_names: true)

      # Auto-stop timers when issue is closed
      if request_body[:transition][:to] == "closed" || request_body[:transition][:to] == "done"
        issue_id = request_body[:issue][:id]

        # Find any active timers for this issue
        stopped_timers = []
        settings.active_timers.each do |user_id, timer|
          if timer[:issue_id] == issue_id
            # Auto-stop the timer
            ended_at = Time.now.utc
            duration_seconds = (ended_at - timer[:started_at]).to_i

            settings.entry_counter += 1
            entry = {
              id: settings.entry_counter,
              user_id: timer[:user_id],
              issue_id: timer[:issue_id],
              started_at: timer[:started_at],
              ended_at: ended_at,
              duration_seconds: duration_seconds,
              duration_hours: (duration_seconds / 3600.0).round(2),
              description: timer[:description] || "Auto-stopped on issue closure",
              tags: (timer[:tags] || []) + ["auto-stopped"],
              billable: true,
              created_at: Time.now.utc
            }

            settings.time_entries << entry
            settings.active_timers.delete(user_id)
            stopped_timers << user_id
          end
        end

        status 200
        {
          success: true,
          stopped_timers: stopped_timers.count,
          message: "Stopped #{stopped_timers.count} active timer(s)"
        }.to_json
      else
        status 200
        { success: true, message: "No action taken" }.to_json
      end

    rescue JSON::ParserError => e
      status 400
      { success: false, error: "Invalid JSON" }.to_json

    rescue StandardError => e
      logger.error "Webhook error: #{e.message}"
      status 500
      { success: false, error: "Internal server error" }.to_json
    end
  end

  private

  def validate_timer_start!(body)
    raise ValidationError, "user_id is required" unless body[:user_id]
    raise ValidationError, "issue_id is required" unless body[:issue_id]
  end

  def validate_entry_create!(body)
    raise ValidationError, "user_id is required" unless body[:user_id]
    raise ValidationError, "issue_id is required" unless body[:issue_id]
    raise ValidationError, "started_at is required" unless body[:started_at]
  end

  def parse_datetime(value)
    return value if value.is_a?(Time)

    # Try ISO 8601 format first
    Time.parse(value)
  rescue ArgumentError
    # Try natural language parsing
    result = Chronic.parse(value)
    raise ValidationError, "Invalid date/time format: #{value}" unless result

    result
  end

  def serialize_entry(entry)
    entry.merge(
      started_at: entry[:started_at].iso8601,
      ended_at: entry[:ended_at].iso8601,
      created_at: entry[:created_at].iso8601
    )
  end
end
