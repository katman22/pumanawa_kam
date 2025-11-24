# frozen_string_literal: true

class ApplicationService
  def self.call(*args, **kwargs, &block)
    new(*args, **kwargs, &block).call
  end
  def failed(message)
    ServiceResult.new(success: false, value: message)
  end

  def successful(value)
    ServiceResult.new(success: true, value: value)
  end
end
