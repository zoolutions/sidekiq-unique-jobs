# frozen_string_literal: true

class LandingsController < ApplicationController
  def show
    render_page Views::Landings::Show.new
  end
end
