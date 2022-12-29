# frozen_string_literal: true

class AddSkippedCodeReviews < ActiveRecord::Migration[6.0]
  def change
    create_table :skipped_code_reviews do |t|
      t.integer :topic_id, null: false
      t.integer :user_id, null: false
      t.datetime :expires_at, null: false

      t.timestamps null: false
    end

    add_index :skipped_code_reviews, %i[topic_id user_id], unique: true
  end
end
