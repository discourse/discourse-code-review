# frozen_string_literal: true

class CreateCodeReviewCommitTopics < ActiveRecord::Migration[6.1]
  def change
    create_table :code_review_commit_topics, id: false do |t|
      t.integer :topic_id, null: false, primary_key: true
      t.text :sha, null: false
      t.timestamps
    end

    add_index :code_review_commit_topics, :sha, unique: true

    reversible do |dir|
      dir.up do
        execute <<~SQL
          INSERT INTO code_review_commit_topics (topic_id, sha, created_at, updated_at)
          SELECT
            topics.id,
            github_hashes.value,
            github_hashes.created_at,
            github_hashes.updated_at
          FROM
            (
              SELECT *
              FROM topic_custom_fields
              WHERE name = 'commit hash'
            ) github_hashes
          INNER JOIN topics
          ON github_hashes.topic_id = topics.id
        SQL
      end
    end
  end
end
