# frozen_string_literal: true

require 'rails_helper'

class MockClient
  MockComment = Struct.new(:id)

  attr_reader :comment, :call

  def create_commit_comment(repo, sha, body, path = nil, line = nil, position = nil, options = {})
    raise "already called" if @call
    @call = {
      repo: repo,
      sha: sha,
      body: body,
      path: path,
      line: line,
      position: position,
      options: options
    }
    @comment = MockComment.new('comment id')
    @comment
  end
end

describe DiscourseCodeReview do
  describe '.sync_to_github' do
    context 'when a category, topic and post exist with appropriate custom fields, a reply and another post have been created and sync_to_github is true' do
      fab!(:category) do
        Fabricate(:category).tap do |category|
          category.custom_fields[DiscourseCodeReview::State::GithubRepoCategories::GITHUB_REPO_NAME] = 'some github repo'
          category.save_custom_fields
        end
      end

      fab!(:topic) do
        Fabricate(:topic, category: category).tap do |topic|
          topic.custom_fields[DiscourseCodeReview::COMMIT_HASH] = 'a commit sha'
          topic.save_custom_fields
          DiscourseCodeReview::CommitTopic.create!(topic_id: topic.id, sha: 'a commit sha')
        end
      end

      fab!(:post) do
        Fabricate(:post, topic: topic).tap do |post|
          post.custom_fields[DiscourseCodeReview::GITHUB_ID] = 'an id from github'
          post.save_custom_fields
        end
      end

      fab!(:reply) do
        Fabricate(:post, topic: topic, reply_to_post_number: post.post_number).tap do |reply|
          reply.raw = [
            '# Title',
            '',
            'So much insightful prose',
            '',
            'and another paragraph in [markdown](/path-to-somewhere)',
          ].join("\n")
          reply.save!
        end
      end

      fab!(:another_post) do
        Fabricate(:post, topic: topic).tap do |reply|
          reply.raw = [
            '# Another Title',
            '',
            'So much more insightful prose',
            '',
            'and another paragraph in [markdown](/path-to-somewhere)',
          ].join("\n")
          reply.save!
        end
      end

      before do
        SiteSetting.code_review_sync_to_github = true
      end

      let!(:client) { MockClient.new }

      it "should send the repo name from the category" do
        DiscourseCodeReview.sync_post_to_github(client, reply)

        expect(client.call[:repo]).to eq('some github repo')
      end

      it "should send the sha from the topic" do
        DiscourseCodeReview.sync_post_to_github(client, reply)

        expect(client.call[:sha]).to eq('a commit sha')
      end

      it "should send a comment that ends with the raw post" do
        DiscourseCodeReview.sync_post_to_github(client, reply)

        expect(client.call[:body]).to end_with(reply.raw)
      end

      context "when the post is in response to a particular file" do
        fab!(:comment_path_field) do
          PostCustomField.create!(
            post_id: post.id,
            name: DiscourseCodeReview::COMMENT_PATH,
            value: 'path to comment',
          )
        end

        it "should label the reply as also being in response to that file" do
          DiscourseCodeReview.sync_post_to_github(client, reply)

          expect(reply.custom_fields[DiscourseCodeReview::COMMENT_PATH]).to eq('path to comment')
        end

        it "should not label the other post as also being in response to that file" do
          DiscourseCodeReview.sync_post_to_github(client, another_post)

          expect(reply.custom_fields[DiscourseCodeReview::COMMENT_PATH]).to eq(nil)
        end

        context "when the post is in reponse to a particular position in the file" do
          fab!(:comment_position_field) do
            PostCustomField.create!(
              post_id: post.id,
              name: DiscourseCodeReview::COMMENT_POSITION,
              value: 'comment position',
            )
          end

          it "should label the reply as also having that position" do
            DiscourseCodeReview.sync_post_to_github(client, reply)

            expect(reply.custom_fields[DiscourseCodeReview::COMMENT_POSITION]).to eq('comment position')
          end

          it "should not label the other post as also having that position" do
            DiscourseCodeReview.sync_post_to_github(client, another_post)

            expect(reply.custom_fields[DiscourseCodeReview::COMMENT_POSITION]).to eq(nil)
          end
        end
      end

      context "when reply's user has a name" do
        fab!(:user) do
          reply.user.tap do |user|
            user.name = "Fred"
            user.save!
          end
        end

        it "should send a comment that includes the user's name" do
          DiscourseCodeReview.sync_post_to_github(client, reply)

          expect(client.call[:body]).to include(user.name)
        end
      end

      context "when reply's user doesn't have a name" do
        fab!(:user) do
          reply.user.tap do |user|
            user.name = nil
            user.save!
          end
        end

        it "should send a comment that includes the username" do
          DiscourseCodeReview.sync_post_to_github(client, reply)

          expect(client.call[:body]).to include(user.username)
        end
      end

      context "when reply is a whisper" do
        before { reply.post_type = Post.types[:whisper] }

        it "does not send the reply to github" do
          client.expects(:create_commit_comment).never

          DiscourseCodeReview.sync_post_to_github(client, reply)
        end
      end

      context "when reply is a small action" do
        before { reply.post_type = Post.types[:small_action] }

        it "does not send the reply to github" do
          client.expects(:create_commit_comment).never

          DiscourseCodeReview.sync_post_to_github(client, reply)
        end
      end
    end
  end
end
