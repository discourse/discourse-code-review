# frozen_string_literal: true

require 'rails_helper'

describe Enumerators::FlattenMerge do
  it "should merge a set of enumerators" do
    result =
      Enumerators::FlattenMerge
        .new([
          [0],
          [1],
        ]) { |a, b| a < b }
        .to_a

    expect(result).to eq([0, 1])
  end

  it "should merge a set of enumerators" do
    result =
      Enumerators::FlattenMerge
        .new([
          [0, 1],
        ]) { |a, b| a < b }
        .to_a

    expect(result).to eq([0, 1])
  end

  it "should merge a set of enumerators" do
    result =
      Enumerators::FlattenMerge
        .new([
          [6],
          [0, 2, 4],
          [1, 3, 5],
          []
        ]) { |a, b| a < b }
        .to_a

    expect(result).to eq([0, 1, 2, 3, 4, 5, 6])
  end
end
