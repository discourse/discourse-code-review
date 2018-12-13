class CreateCustomFieldIndexes < ActiveRecord::Migration[5.2]
  def change
    add_index :topic_custom_fields, [:value], unique: true, where: "name = 'commit hash'"
  end
end
