# frozen_string_literal: true

require 'rails_helper'

module DiscourseCodeReview
  describe State::CommitTopics do
    it "has robust sha detection" do
      text = (<<~STR).strip
        hello abcdf672, a723c123444!
        (abc2345662) {abcd87234} [#1209823bc]
        ,7862abcdf abcdefg722
        abc7827421119a
      STR

      shas = State::CommitTopics.detect_shas(text)

      expect(shas).to eq(%w{
       abcdf672
       a723c123444
       abc2345662
       abcd87234
       1209823bc
       7862abcdf
       abc7827421119a
      })
    end

    it "#auto_link_commits" do
      topic = Fabricate(:topic)
      topic.custom_fields[DiscourseCodeReview::COMMIT_HASH] = "dbbadb5c357bc23daf1fa732f8670e55dc28b7cb"
      topic.save
      CommitTopic.create!(topic_id: topic.id, sha: "dbbadb5c357bc23daf1fa732f8670e55dc28b7cb")
      topic2 = Fabricate(:topic)
      topic2.custom_fields[DiscourseCodeReview::COMMIT_HASH] = "a1db15feadc7951d8a2b4ae63384babd6c568ae0"
      topic2.save
      CommitTopic.create!(topic_id: topic2.id, sha: "a1db15feadc7951d8a2b4ae63384babd6c568ae0")

      result = State::CommitTopics.auto_link_commits("a1db15feadc and another one dbbadb5c357")
      markdown = "[a1db15feadc](#{topic2.url}) and another one [dbbadb5c357](#{topic.url})"
      cooked = PrettyText.cook(markdown)
      expect(result[0]).to eq(markdown)
      expect(result[2].to_html).to eq(cooked)
    end
  end
end
