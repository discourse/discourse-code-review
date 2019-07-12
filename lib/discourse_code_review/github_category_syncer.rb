# frozen_string_literal: true

module DiscourseCodeReview
  module GithubCategorySyncer
    GithubRepoName = "GitHub Repo Name"

    class << self
      def ensure_category(repo_name:)
        Category.transaction(requires_new: true) do
          category =
            Category.where(
              id:
                CategoryCustomField
                  .select(:category_id)
                  .where(name: GithubRepoName, value: repo_name)
            ).first

          if category.nil?
            short_name = find_category_name(repo_name.split("/", 2).last)

            category =
              Category.create!(
                name: short_name,
                user: Discourse.system_user
              )

            category.custom_fields[GithubRepoName] = repo_name
            category.save_custom_fields
          end

          category
        end
      end

      def each_repo_name(&blk)
        CategoryCustomField
          .where(name: GithubRepoName)
          .pluck(:value)
          .each(&blk)
      end

      def github_repo_category_fields
        CategoryCustomField
          .where(name: GithubRepoName)
          .include(:category)
      end

      def get_repo_name_from_topic(topic)
        topic.category.custom_fields[GithubRepoName]
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
