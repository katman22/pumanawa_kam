# frozen_string_literal: true

class ServiceResult
  attr_reader :success, :value
  def initialize(success:, value:)
    @success = success
    @value = value
  end

  def success?
    success
  end
  def failure?
    !success
  end

  def to_h
    { success: success, value: value }
  end
end
