# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

module Agile::Sprints::Scopes
  module Visible
    extend ActiveSupport::Concern

    class_methods do
      # Returns all sprints the user is allowed to see.
      # A sprint is visible if it can be seen via for_project in any project
      # where the user has the :view_sprints permission (including sprints shared
      # via sprint source configuration or work packages).
      def visible(user = User.current)
        # This currently requires two queries, one for fetching the allowed projects
        # and one for fetching the sprints in those projects.
        # The alternative would be much more complex to implement.
        Project.allowed_to(user, :view_sprints).to_a.inject(none) do |scope, project|
          scope.or(for_project(project))
        end
      end
    end
  end
end
