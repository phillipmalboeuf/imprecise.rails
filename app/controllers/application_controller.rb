# typed: true
# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  MAX_MONTHLY_TOKENS = 10_000
end
