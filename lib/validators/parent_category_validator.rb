# frozen_string_literal: true

class ParentCategoryValidator
  def initialize(opts = {})
    @opts = opts
  end

  def valid_value?(val)
    category = Category.find_by(id: val)
    !category || category.height_of_ancestors < SiteSetting.max_category_nesting - 1
  end

  def error_message
    I18n.t("category.errors.depth")
  end
end
