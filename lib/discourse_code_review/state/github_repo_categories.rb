# frozen_string_literal: true

module DiscourseCodeReview
  module State::GithubRepoCategories
    GITHUB_REPO_ID = "GitHub Repo ID"
    GITHUB_REPO_NAME = "GitHub Repo Name"

    class << self
      def ensure_category(repo_name:, repo_id: nil)
        ActiveRecord::Base.transaction(requires_new: true) do
          repo_category =
            GithubRepoCategory
              .find_by(repo_id: repo_id)

          repo_category ||=
            GithubRepoCategory
              .find_by(name: repo_name)

          category = repo_category&.category

          if !category && repo_id.present?
            # create new category
            short_name = find_category_name(repo_name.split("/", 2).last)

            category = Category.new(
              name: short_name,
              user: Discourse.system_user,
              description: I18n.t('discourse_code_review.category_description', repo_name: repo_name)
            )

            if SiteSetting.code_review_default_parent_category.present?
              category.parent_category_id = SiteSetting.code_review_default_parent_category.to_i
            end

            category.save!

            if SiteSetting.code_review_default_mute_new_categories
              existing_category_ids = Category.where(id: SiteSetting.default_categories_muted.split("|")).pluck(:id)
              SiteSetting.default_categories_muted = (existing_category_ids << category.id).join("|")
            end
          end

          if category
            repo_category ||= GithubRepoCategory.new
            repo_category.category_id = category.id
            repo_category.repo_id = repo_id
            repo_category.name = repo_name
            repo_category.save! if repo_category.changed?

            category.custom_fields[GITHUB_REPO_ID] = repo_id
            category.custom_fields[GITHUB_REPO_NAME] = repo_name
            category.save_custom_fields
          end

          category
        end
      end

      def each_repo_name(&blk)
        GithubRepoCategory
          .pluck(:name)
          .each(&blk)
      end

      def get_repo_name_from_topic(topic)
        GithubRepoCategory
          .where(category_id: topic.category_id)
          .first
          &.name
      end

      private

      def find_category_name(name)
        if Category.where(name: name).exists?
          name += SecureRandom.hex
        else
          name
        end
      end
    end
  end
end
