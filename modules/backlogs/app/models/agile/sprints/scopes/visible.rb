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
      # A sprint is visible if its project is a sprint source for any project
      # where the user has the :view_sprints permission (accounting for sprint sharing
      # configuration), or if it has work packages in such a project.
      def visible(user = User.current)
        allowed_projects = Project.allowed_to(user, :view_sprints)
        source_project_ids = sprint_source_projects_for(allowed_projects)
        from_wps = WorkPackage.where(project: allowed_projects).where.not(sprint_id: nil)

        where(arel_table[:project_id].in(source_project_ids))
          .or(where(id: from_wps.select(:sprint_id)))
      end

      private

      # Returns an Arel union node of project IDs that are sprint sources for any
      # project in +projects+. Covers three cases:
      #
      # 1. Non-receiving allowed projects (sprint_source = self)
      # 2. The closest share_subprojects ancestor of each receiving allowed project
      # 3. The global sharer for receiving projects that have no share_subprojects ancestor
      def sprint_source_projects_for(projects)
        share_subprojects = Projects::SprintSharing::SHARE_SUBPROJECTS

        receiving_in_allowed = projects.receive_shared_sprints
        receiving_ids_sql = receiving_in_allowed.select(:id).to_sql

        # Case 1: Non-receiving allowed projects (sprint_source = self)
        direct = projects
          .where("settings->>'sprint_sharing' IS DISTINCT FROM ?",
                 Projects::SprintSharing::RECEIVE_SHARED)
          .select(:id)

        # Case 2: Closest share_subprojects ancestor for each receiving project.
        # Project S is a source if there EXISTS a receiving project R in projects
        # such that S is an ancestor of R and no closer share_subprojects ancestor exists.
        closest_ancestors = Project.share_sprints_with_subprojects.where(<<~SQL).select(:id)
          EXISTS (
            SELECT 1 FROM projects receiving
            WHERE receiving.id IN (#{receiving_ids_sql})
              AND projects.lft < receiving.lft
              AND projects.rgt > receiving.rgt
              AND NOT EXISTS (
                SELECT 1 FROM projects closer
                WHERE closer.settings->>'sprint_sharing' = '#{share_subprojects}'
                  AND closer.lft < receiving.lft
                  AND closer.rgt > receiving.rgt
                  AND closer.lft > projects.lft
              )
          )
        SQL

        # Case 3: Global sharer for receiving projects that have no share_subprojects ancestor.
        # The global sharer is wrapped in WHERE IN to avoid a LIMIT clause inside a UNION member.
        global_sharer = Project
          .where(id: Project.global_sprint_sharer_relation)
          .where(<<~SQL).select(:id)
            EXISTS (
              SELECT 1 FROM projects receiving
              WHERE receiving.id IN (#{receiving_ids_sql})
                AND NOT EXISTS (
                  SELECT 1 FROM projects anc
                  WHERE anc.settings->>'sprint_sharing' = '#{share_subprojects}'
                    AND anc.lft < receiving.lft
                    AND anc.rgt > receiving.rgt
                )
            )
          SQL

        Arel::Nodes::Union.new(
          direct.arel,
          Arel::Nodes::Union.new(closest_ancestors.arel, global_sharer.arel)
        )
      end
    end
  end
end
