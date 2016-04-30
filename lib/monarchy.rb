# frozen_string_literal: true
require 'closure_tree'
require 'configurations'

require 'monarchy/acts_as_hierarchy'
require 'monarchy/acts_as_resource'
require 'monarchy/acts_as_user'
require 'monarchy/membership'
require 'app/models/hierarchy'

module Monarchy
  include Configurations

  not_configured do |prop|
    raise NoMethodError, "#{prop} must be configured"
  end
end
