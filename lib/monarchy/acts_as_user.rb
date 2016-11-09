# frozen_string_literal: true
module Monarchy
  module ActsAsUser
    extend ActiveSupport::Concern

    module ClassMethods
      def acts_as_user
        has_many :members, class_name: "::#{Monarchy.member_class}", dependent: :destroy
        has_many :hierarchies, through: :members, class_name: "::#{Monarchy.hierarchy_class}"

        scope :accessible_for, (lambda do |user|
          where(id: Monarchy.hierarchy_class.accessible_for(user)
                                       .joins(members: [:user]).select(:user_id)).union(where(id: user.id))
        end)

        include Monarchy::ActsAsUser::InstanceMethods
      end
    end

    module InstanceMethods
      def roles_for(resource, inheritance = true)
        Monarchy::Validators.resource(resource, false, false)
        accessible_roles_for(resource, inheritance)
      end

      def member_for(resource)
        Monarchy::Validators.resource(resource)
        resource.hierarchy.members.where(monarchy_members: { user_id: id }).first
      end

      def grant(*role_names, resource)
        ActiveRecord::Base.transaction do
          grant_or_create_member(role_names, resource)
        end
      end

      def revoke_access(resource, hierarchies = nil)
        Monarchy::Validators.resource(resource)
        hierarchies ||= resource.hierarchy.self_and_descendants
        members_for(hierarchies).delete_all
      end

      def revoke_role(role_name, resource)
        revoking_role(role_name, resource)
      end

      def revoke_role!(role_name, resource)
        revoking_role(role_name, resource, Monarchy.configuration.revoke_strategy)
      end

      private

      def accessible_roles_for(resource, inheritnce)
        return Monarchy.role_class.none unless resource.hierarchy
        accessible_roles = if inheritnce
                             resource_and_inheritance_roles(resource)
                           else
                             resource_roles(resource).order('level desc')
                           end

        return accessible_roles if accessible_roles.present?
        inheritnce ? descendant_role(resource) : Monarchy.role_class.none
      end

      def resource_and_inheritance_roles(resource)
        hierarchy_ids = resource.hierarchy.ancestors.select(:id)

        Monarchy.role_class.where(id:
          Monarchy.role_class
            .joins('INNER JOIN monarchy_members_roles ON monarchy_roles.id = monarchy_members_roles.role_id')
            .joins("INNER JOIN (SELECT id, hierarchy_id FROM monarchy_members WHERE user_id = #{id}) as " \
              'monarchy_members ON monarchy_members.id = monarchy_members_roles.member_id')
            .where('monarchy_roles.inherited': 't')
            .where('monarchy_members.hierarchy_id': hierarchy_ids)
            .select('monarchy_roles.inherited_role_id'))
                .union(resource_roles(resource))
      end

      def resource_roles(resource)
        Monarchy.role_class
                .joins('INNER JOIN monarchy_members_roles ON monarchy_roles.id = monarchy_members_roles.role_id')
                .joins('INNER JOIN (SELECT id, hierarchy_id FROM monarchy_members WHERE ' \
                  "hierarchy_id = #{resource.hierarchy.id} AND user_id = #{id}) as monarchy_members ON " \
                  'monarchy_members.id = monarchy_members_roles.member_id')
      end

      def descendant_role(resource)
        descendants = resource.hierarchy.descendants
        children_access = members_for(descendants).present?
        children_access ? Monarchy.role_class.where(id: inherited_default_role) : Monarchy.role_class.none
      end

      def revoking_role(role_name, resource, strategy = nil)
        Monarchy::Validators.resource(resource)
        role = Monarchy::Validators.role_name(role_name)

        member = member_for(resource)
        member_roles = member.try(:members_roles)
        return 0 if member_roles.nil?

        revoking_last_role(role, resource, strategy) if Monarchy::Validators.last_role?(member, role)
        member_roles.where(role: role).delete_all
      end

      def revoking_last_role(role, resource, strategy)
        case strategy
        when :revoke_access
          return revoke_access(resource)
        when :revoke_member
          return member_for(resource).delete
        else
          default_role = Monarchy::Validators.default_role?(resource, role)
          raise Monarchy::Exceptions::RoleNotRevokable if default_role

          grant(resource.class.default_role_name, resource)
        end
      end

      def grant_or_create_member(role_names, resource)
        Monarchy::Validators.resource(resource)
        roles = Monarchy::Validators.role_names(role_names)
        member = member_for(resource)

        if member
          member_roles = roles.map { |role| { member: member, role: role } }
          Monarchy::MembersRole.create(member_roles)
        else
          member = Monarchy.member_class.create(user: self, hierarchy: resource.hierarchy, roles: roles)
        end

        member
      end

      def members_for(hierarchies)
        Monarchy.member_class.where(hierarchy: hierarchies, user_id: id)
      end

      def inherited_default_role
        @inherited_default_role ||= Monarchy.role_class.find_by(name: Monarchy.configuration.inherited_default_role)
      end
    end
  end
end

ActiveRecord::Base.send :include, Monarchy::ActsAsUser
