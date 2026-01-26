# frozen_string_literal: true

describe DiscourseCodeReview::GithubPRSyncer do
  it "does nothing if the topic is a PM" do
    pm_post = Fabricate(:post, post_number: 2, topic: Fabricate(:private_message_topic))

    syncer = described_class.new(nil, nil)

    expect(syncer.mirror_pr_post(pm_post)).to be_nil
  end
end
