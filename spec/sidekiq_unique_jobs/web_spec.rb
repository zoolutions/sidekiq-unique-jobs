# frozen_string_literal: true

require "sidekiq_unique_jobs/web"
require "rack/test"
require "rack/session"
require "rspec-html-matchers"

RSpec.describe SidekiqUniqueJobs::Web do
  include Rack::Test::Methods
  include RSpecHtmlMatchers

  def app
    @app ||= Rack::Builder.new do
      use Rack::Session::Cookie,
        key: "rack.session",
        domain: "foo.com",
        path: "/",
        expire_after: 2_592_000,
        secret: "change_me" * 10,
        old_secret: "also_change_me" * 10

      run Sidekiq::Web
    end
  end

  before do
    flush_redis
  end

  let(:lock_one)   { SidekiqUniqueJobs::Lock.new(digest_one) }
  let(:lock_two)   { SidekiqUniqueJobs::Lock.new(digest_two) }
  let(:jid_one)    { "jid_one" }
  let(:jid_two)    { "jid_two" }
  let(:digest_one) { "uniquejobs:9e9b5ce5d423d3ea470977004b50ff84" }
  let(:digest_two) { "uniquejobs:24c5b03e2d49d765e5dfb2d7c51c5929" }
  let(:lock_info)  { { "type" => "until_executed" } }
  let(:digests)    { SidekiqUniqueJobs::Digests.new }

  it "registers the locks tab without a trailing slash" do
    expect(Sidekiq::Web.tabs.fetch("Locks")).to eq("locks")
  end

  it "renders the locks navigation without a trailing slash" do
    get "/"

    expect(last_response).to be_ok
    expect(last_response.body).to include('href="/locks"')
    expect(last_response.body).not_to include('href="/locks/"')
  end

  it "can display locks" do
    lock_one.lock(jid_one, lock_info)
    lock_two.lock(jid_two, lock_info)

    get "/locks"

    expect(last_response).to be_ok
    expect(last_response.body).to match("/locks/#{digest_one}")
    expect(last_response.body).to match("/locks/#{digest_two}")
  end

  it "can display single lock" do
    lock_one.lock(jid_one, lock_info)

    get "/locks/#{digest_one}"

    expect(last_response).to be_ok
    expect(last_response.body).to match(digest_one)
  end

  it "can delete a lock" do
    lock_one.lock(jid_one, lock_info)
    lock_two.lock(jid_two, lock_info)

    get "/locks/#{digest_one}/delete"

    if last_response.redirect?
      expect(last_response.status).to eq(302)
      follow_redirect!
    end

    expect(last_request.url).to end_with("/locks")
  end

  it "can unlock a job" do
    lock_one.lock(jid_one, lock_info)
    lock_one.lock(jid_two, lock_info)

    get "/locks/#{digest_one}/jobs/#{jid_one}/delete"

    if last_response.redirect?
      expect(last_response.status).to eq(302)
      follow_redirect!
    end

    expect(lock_one.locked_jids).not_to include(jid_one)
    expect(lock_one.locked_jids).to include(jid_two)
  end

  describe "delete_all" do
    it "deletes all locks" do
      lock_one.lock(jid_one, lock_info)
      lock_two.lock(jid_two, lock_info)

      expect(digests.count).to eq(2)

      get "/locks/delete_all"

      if last_response.redirect?
        expect(last_response.status).to eq(302)
        follow_redirect!
      end

      expect(digests.count).to eq(0)
    end

    it "handles empty state" do
      get "/locks/delete_all"

      follow_redirect! if last_response.redirect?

      expect(last_response).to be_ok
    end
  end
end
