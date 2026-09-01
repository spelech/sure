# frozen_string_literal: true

module Forensics
  class TemporalHeatmapBuilder
    def initialize(family, period: nil, user: nil)
      @family = family
      @period = period
      @user = user
    end

    def build
      {}
    end
  end
end
