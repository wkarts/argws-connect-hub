# frozen_string_literal: true

class SetHubBrandDefaults < ActiveRecord::Migration[7.0]
  HUB_RED = '#E10600'

  def up
    change_column_default :channel_web_widgets, :widget_color, from: '#1f93ff', to: HUB_RED
    change_column_default :labels, :color, from: '#1f93ff', to: HUB_RED
  end

  def down
    change_column_default :channel_web_widgets, :widget_color, from: HUB_RED, to: '#1f93ff'
    change_column_default :labels, :color, from: HUB_RED, to: '#1f93ff'
  end
end
