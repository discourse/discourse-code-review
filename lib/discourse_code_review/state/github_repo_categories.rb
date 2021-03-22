# frozen_string_literal: true

module DiscourseCodeReview::State::GithubRepoCategories
  GITHUB_REPO_ID = "GitHub Repo ID"
  GITHUB_REPO_NAME = "GitHub Repo Name"

  class << self
    def ensure_category(repo_name:, repo_id: nil)
      Category.transaction(requires_new: true) do
        category =
          Category.where(
            id:
              CategoryCustomField
                .select(:category_id)
                .where(name: GITHUB_REPO_NAME, value: repo_name)
          ).first

        if category.present? && category.custom_fields[GITHUB_REPO_ID].blank? && repo_id.present?
          category.custom_fields[GITHUB_REPO_ID] = repo_id
          category.save_custom_fields
        end

        if category.blank? && repo_id.present?
          category =
            Category.where(
              id:
                CategoryCustomField
                  .select(:category_id)
                .where(name: GITHUB_REPO_ID, value: repo_id)
            ).first

          if category.present?
            # update repository name in category custom field
            category.custom_fields[GITHUB_REPO_NAME] = repo_name
            category.save_custom_fields
          end
        end

        if !category
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

          category.custom_fields[GITHUB_REPO_ID] = repo_id if repo_id.present?
          category.custom_fields[GITHUB_REPO_NAME] = repo_name
          category.save_custom_fields
        end

        category
      end
    end

    def each_repo_name(&blk)
      CategoryCustomField
        .where(name: GITHUB_REPO_NAME)
        .pluck(:value)
        .each(&blk)
    end

    def github_repo_category_fields
      CategoryCustomField
        .where(name: GITHUB_REPO_NAME)
        .include(:category)
    end

    def get_repo_name_from_topic(topic)
      topic.category.custom_fields[GITHUB_REPO_NAME]
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
