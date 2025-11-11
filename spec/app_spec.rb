# frozen_string_literal: true

require "spec_helper"

RSpec.describe TimeTrackingExtension do
  def app
    TimeTrackingExtension
  end

  describe "GET /health" do
    it "returns healthy status" do
      get "/health"

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json["status"]).to eq("healthy")
      expect(json["service"]).to eq("time-tracking")
      expect(json["version"]).to eq("1.0.0")
      expect(json["active_timers"]).to eq(0)
      expect(json["total_entries"]).to eq(0)
    end
  end

  describe "POST /timer/start" do
    it "starts a timer successfully" do
      post "/timer/start", JSON.generate({
        user_id: "user123",
        issue_id: "issue456",
        description: "Working on feature"
      }), { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json["success"]).to be true
      expect(json["timer"]["user_id"]).to eq("user123")
      expect(json["timer"]["issue_id"]).to eq("issue456")
      expect(json["timer"]["elapsed_seconds"]).to eq(0)
    end

    it "prevents starting multiple timers for same user" do
      # Start first timer
      post "/timer/start", JSON.generate({
        user_id: "user123",
        issue_id: "issue1"
      }), { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok

      # Try to start second timer
      post "/timer/start", JSON.generate({
        user_id: "user123",
        issue_id: "issue2"
      }), { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(400)
      json = JSON.parse(last_response.body)
      expect(json["error"]).to include("already has an active timer")
    end

    it "allows different users to have timers" do
      post "/timer/start", JSON.generate({
        user_id: "user1",
        issue_id: "issue1"
      }), { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok

      post "/timer/start", JSON.generate({
        user_id: "user2",
        issue_id: "issue2"
      }), { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
    end

    it "requires user_id" do
      post "/timer/start", JSON.generate({
        issue_id: "issue1"
      }), { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(400)
      json = JSON.parse(last_response.body)
      expect(json["error"]).to include("user_id")
    end

    it "requires issue_id" do
      post "/timer/start", JSON.generate({
        user_id: "user1"
      }), { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(400)
      json = JSON.parse(last_response.body)
      expect(json["error"]).to include("issue_id")
    end
  end

  describe "POST /timer/stop" do
    it "stops timer and creates entry" do
      # Start timer
      start_time = Time.parse("2025-11-10 10:00:00 UTC")
      Timecop.freeze(start_time) do
        post "/timer/start", JSON.generate({
          user_id: "user123",
          issue_id: "issue456",
          description: "Testing"
        }), { "CONTENT_TYPE" => "application/json" }
      end

      # Stop timer 2 hours later
      stop_time = Time.parse("2025-11-10 12:00:00 UTC")
      Timecop.freeze(stop_time) do
        post "/timer/stop", JSON.generate({
          user_id: "user123"
        }), { "CONTENT_TYPE" => "application/json" }

        expect(last_response).to be_ok
        json = JSON.parse(last_response.body)
        expect(json["success"]).to be true
        expect(json["entry"]["user_id"]).to eq("user123")
        expect(json["entry"]["issue_id"]).to eq("issue456")
        expect(json["entry"]["duration_seconds"]).to eq(7200)  # 2 hours
        expect(json["entry"]["duration_hours"]).to eq(2.0)
        expect(json["entry"]["billable"]).to be true
      end
    end

    it "removes active timer after stopping" do
      # Start timer
      post "/timer/start", JSON.generate({
        user_id: "user123",
        issue_id: "issue456"
      }), { "CONTENT_TYPE" => "application/json" }

      # Stop timer
      post "/timer/stop", JSON.generate({
        user_id: "user123"
      }), { "CONTENT_TYPE" => "application/json" }

      # Check no active timer
      get "/timer/active/user123"
      expect(last_response.status).to eq(404)
    end

    it "returns error if no active timer" do
      post "/timer/stop", JSON.generate({
        user_id: "user123"
      }), { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(400)
      json = JSON.parse(last_response.body)
      expect(json["error"]).to include("No active timer")
    end
  end

  describe "GET /timer/active/:user_id" do
    it "returns active timer with elapsed time" do
      start_time = Time.parse("2025-11-10 10:00:00 UTC")
      Timecop.freeze(start_time) do
        post "/timer/start", JSON.generate({
          user_id: "user123",
          issue_id: "issue456"
        }), { "CONTENT_TYPE" => "application/json" }
      end

      # Check timer 30 minutes later
      check_time = Time.parse("2025-11-10 10:30:00 UTC")
      Timecop.freeze(check_time) do
        get "/timer/active/user123"

        expect(last_response).to be_ok
        json = JSON.parse(last_response.body)
        expect(json["success"]).to be true
        expect(json["timer"]["elapsed_seconds"]).to eq(1800)  # 30 minutes
        expect(json["timer"]["elapsed_hours"]).to eq(0.5)
      end
    end

    it "returns 404 if no active timer" do
      get "/timer/active/user123"

      expect(last_response.status).to eq(404)
      json = JSON.parse(last_response.body)
      expect(json["error"]).to include("No active timer")
    end
  end

  describe "POST /entries" do
    it "creates manual time entry with end time" do
      post "/entries", JSON.generate({
        user_id: "user123",
        issue_id: "issue456",
        started_at: "2025-11-10T10:00:00Z",
        ended_at: "2025-11-10T12:30:00Z",
        description: "Manual entry",
        billable: true
      }), { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(201)
      json = JSON.parse(last_response.body)
      expect(json["success"]).to be true
      expect(json["entry"]["duration_seconds"]).to eq(9000)  # 2.5 hours
      expect(json["entry"]["duration_hours"]).to eq(2.5)
    end

    it "creates entry with duration instead of end time" do
      post "/entries", JSON.generate({
        user_id: "user123",
        issue_id: "issue456",
        started_at: "2025-11-10T10:00:00Z",
        duration_seconds: 3600,  # 1 hour
        description: "1 hour entry"
      }), { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(201)
      json = JSON.parse(last_response.body)
      expect(json["entry"]["duration_hours"]).to eq(1.0)
      expect(json["entry"]["ended_at"]).to eq("2025-11-10T11:00:00Z")
    end

    it "defaults billable to true" do
      post "/entries", JSON.generate({
        user_id: "user123",
        issue_id: "issue456",
        started_at: "2025-11-10T10:00:00Z",
        duration_seconds: 3600
      }), { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(201)
      json = JSON.parse(last_response.body)
      expect(json["entry"]["billable"]).to be true
    end

    it "requires user_id, issue_id, and started_at" do
      post "/entries", JSON.generate({
        duration_seconds: 3600
      }), { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(400)
    end
  end

  describe "PUT /entries/:id" do
    it "updates time entry" do
      # Create entry
      post "/entries", JSON.generate({
        user_id: "user123",
        issue_id: "issue456",
        started_at: "2025-11-10T10:00:00Z",
        duration_seconds: 3600
      }), { "CONTENT_TYPE" => "application/json" }

      entry_id = JSON.parse(last_response.body)["entry"]["id"]

      # Update entry
      put "/entries/#{entry_id}", JSON.generate({
        description: "Updated description",
        billable: false
      }), { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json["entry"]["description"]).to eq("Updated description")
      expect(json["entry"]["billable"]).to be false
    end

    it "recalculates duration when times change" do
      post "/entries", JSON.generate({
        user_id: "user123",
        issue_id: "issue456",
        started_at: "2025-11-10T10:00:00Z",
        duration_seconds: 3600
      }), { "CONTENT_TYPE" => "application/json" }

      entry_id = JSON.parse(last_response.body)["entry"]["id"]

      put "/entries/#{entry_id}", JSON.generate({
        ended_at: "2025-11-10T12:00:00Z"
      }), { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json["entry"]["duration_hours"]).to eq(2.0)
    end
  end

  describe "DELETE /entries/:id" do
    it "deletes time entry" do
      post "/entries", JSON.generate({
        user_id: "user123",
        issue_id: "issue456",
        started_at: "2025-11-10T10:00:00Z",
        duration_seconds: 3600
      }), { "CONTENT_TYPE" => "application/json" }

      entry_id = JSON.parse(last_response.body)["entry"]["id"]

      delete "/entries/#{entry_id}"

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json["success"]).to be true

      # Verify deleted
      get "/entries/#{entry_id}"
      expect(last_response.status).to eq(404)
    end
  end

  describe "GET /entries" do
    before do
      # Create sample entries
      post "/entries", JSON.generate({
        user_id: "user1",
        issue_id: "issue1",
        started_at: "2025-11-10T10:00:00Z",
        duration_seconds: 3600,
        billable: true,
        tags: [ "development" ]
      }), { "CONTENT_TYPE" => "application/json" }

      post "/entries", JSON.generate({
        user_id: "user2",
        issue_id: "issue2",
        started_at: "2025-11-11T10:00:00Z",
        duration_seconds: 7200,
        billable: false,
        tags: [ "meeting" ]
      }), { "CONTENT_TYPE" => "application/json" }
    end

    it "lists all entries" do
      get "/entries"

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json["count"]).to eq(2)
      expect(json["entries"].length).to eq(2)
    end

    it "filters by user_id" do
      get "/entries?user_id=user1"

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json["count"]).to eq(1)
      expect(json["entries"][0]["user_id"]).to eq("user1")
    end

    it "filters by issue_id" do
      get "/entries?issue_id=issue2"

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json["count"]).to eq(1)
      expect(json["entries"][0]["issue_id"]).to eq("issue2")
    end

    it "filters by billable status" do
      get "/entries?billable=false"

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json["count"]).to eq(1)
      expect(json["entries"][0]["billable"]).to be false
    end

    it "filters by tags" do
      get "/entries?tags=development"

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json["count"]).to eq(1)
      expect(json["entries"][0]["tags"]).to include("development")
    end
  end

  describe "GET /reports/summary" do
    before do
      post "/entries", JSON.generate({
        user_id: "user1",
        issue_id: "issue1",
        started_at: "2025-11-10T10:00:00Z",
        duration_seconds: 3600,
        billable: true
      }), { "CONTENT_TYPE" => "application/json" }

      post "/entries", JSON.generate({
        user_id: "user1",
        issue_id: "issue2",
        started_at: "2025-11-10T11:00:00Z",
        duration_seconds: 7200,
        billable: false
      }), { "CONTENT_TYPE" => "application/json" }

      post "/entries", JSON.generate({
        user_id: "user2",
        issue_id: "issue1",
        started_at: "2025-11-10T12:00:00Z",
        duration_seconds: 1800,
        billable: true
      }), { "CONTENT_TYPE" => "application/json" }
    end

    it "generates summary report" do
      get "/reports/summary"

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)

      expect(json["summary"]["total_entries"]).to eq(3)
      expect(json["summary"]["total_hours"]).to eq(3.5)
      expect(json["summary"]["billable_hours"]).to eq(1.5)
      expect(json["summary"]["non_billable_hours"]).to eq(2.0)
    end

    it "groups by user" do
      get "/reports/summary"

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)

      expect(json["summary"]["by_user"]["user1"]["total_hours"]).to eq(3.0)
      expect(json["summary"]["by_user"]["user1"]["entry_count"]).to eq(2)
      expect(json["summary"]["by_user"]["user2"]["total_hours"]).to eq(0.5)
    end

    it "groups by issue" do
      get "/reports/summary"

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)

      expect(json["summary"]["by_issue"]["issue1"]["total_hours"]).to eq(1.5)
      expect(json["summary"]["by_issue"]["issue1"]["entry_count"]).to eq(2)
    end
  end

  describe "GET /export/csv" do
    before do
      post "/entries", JSON.generate({
        user_id: "user1",
        issue_id: "issue1",
        started_at: "2025-11-10T10:00:00Z",
        duration_seconds: 3600,
        description: "Test work",
        billable: true
      }), { "CONTENT_TYPE" => "application/json" }
    end

    it "exports entries as CSV" do
      get "/export/csv"

      expect(last_response).to be_ok
      expect(last_response.headers["Content-Type"]).to eq("text/csv")
      expect(last_response.headers["Content-Disposition"]).to include("attachment")

      csv = last_response.body
      expect(csv).to include("User ID,Issue ID")
      expect(csv).to include("user1,issue1")
    end
  end

  describe "POST /webhooks/issue.transitioned" do
    it "auto-stops timers when issue is closed" do
      # Start timer
      post "/timer/start", JSON.generate({
        user_id: "user123",
        issue_id: "issue456"
      }), { "CONTENT_TYPE" => "application/json" }

      # Trigger webhook
      post "/webhooks/issue.transitioned", JSON.generate({
        issue: { id: "issue456" },
        transition: { from: "in_progress", to: "closed" }
      }), { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json["stopped_timers"]).to eq(1)

      # Verify timer was stopped
      get "/timer/active/user123"
      expect(last_response.status).to eq(404)

      # Verify entry was created
      get "/entries"
      json = JSON.parse(last_response.body)
      expect(json["count"]).to eq(1)
      expect(json["entries"][0]["tags"]).to include("auto-stopped")
    end

    it "does nothing for other transitions" do
      post "/timer/start", JSON.generate({
        user_id: "user123",
        issue_id: "issue456"
      }), { "CONTENT_TYPE" => "application/json" }

      post "/webhooks/issue.transitioned", JSON.generate({
        issue: { id: "issue456" },
        transition: { from: "open", to: "in_progress" }
      }), { "CONTENT_TYPE" => "application/json" }

      expect(last_response).to be_ok

      # Timer should still be active
      get "/timer/active/user123"
      expect(last_response).to be_ok
    end
  end
end
