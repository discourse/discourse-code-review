# frozen_string_literal: true

class CreateCodeReviewGithubRepos < ActiveRecord::Migration[6.1]
  def change
    create_table :code_review_github_repos, id: false do |t|
      t.integer :category_id, null: false, primary_key: true
      t.text :name
      t.text :repo_id
      t.timestamps
    end

    add_index :code_review_github_repos, :repo_id, unique: true
    add_index :code_review_github_repos, :name, unique: true

    reversible do |dir|
      dir.up do
        execute <<~SQL
          INSERT INTO code_review_github_repos (category_id, repo_id, name, created_at, updated_at)
          SELECT
            categories.id,
            repo_ids.value,
            names.value,
            least(repo_ids.created_at, names.created_at),
            greatest(repo_ids.updated_at, names.updated_at)
          FROM categories
          LEFT OUTER JOIN
            (
              SELECT *
              FROM category_custom_fields
              WHERE name = 'GitHub Repo Name'
            ) names
          ON names.category_id = categories.id
          LEFT OUTER JOIN
            (
              SELECT *
              FROM category_custom_fields
              WHERE name = 'GitHub Repo ID'
            ) repo_ids
          ON repo_ids.category_id = categories.id
          WHERE repo_ids.value IS NOT NULL
          OR names.value IS NOT NULL
        SQL
      end
    end
  end
end
