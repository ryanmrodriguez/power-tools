# frozen_string_literal: true

module Consent
  #
  # Defines a CanCan(Can)::Ability class based on Consent::Permissions
  #
  class Ability
    include CanCan::Ability

    #
    # Initialize a Consent::Ability consenting all the given permissions.
    #
    # When super_user is set to true, it grants `:manage :all`, which is understood by
    # CanCan as a keyword to allow everything with no restrictions.
    #
    # If apply_defaults is set to true, Consent::Ability will grant the default views
    # defined in the permissions.
    #
    # I.e.:
    #
    #   Consent.define Project, 'Projects' do
    #     view :department, "User's department only" do |user|
    #       { department_id: user.id }
    #     end
    #     view :self, "User's own projects" do |user|
    #       { user_id: user.id }
    #     end
    #
    #     action :close, views: %i[department self], default_view: :self
    #   end
    #
    #   Consent::Ability.new(user, permissions: user&.permissions,
    #                              super_user: user&.super_user?,
    #                              apply_defaults: user.present?)
    #
    # @param [*] *context the view context, usually the user and some additional information
    # @param [Array<Consent::Permission>] permissions the list of permissions to grant
    # @param [Boolean] super_user whether Consent should grant :manage :all
    # @param [Boolean] apply_defaults whether Consent should grant default views
    #
    def initialize(*context, permissions: nil, super_user: false, apply_defaults: true)
      @context = *context

      apply_defaults! if apply_defaults
      can :manage, :all if super_user

      permissions&.each do |permission|
        consent(**permission.slice(:subject, :action, :view).symbolize_keys)
      end
    end

    def consent!(subject: nil, action: nil, view: nil)
      view = case view
             when Consent::View
               view
             when Symbol
               Consent.find_view(subject, action, view)
             end

      can(
        action, subject,
        view&.conditions(*@context), &view&.object_conditions(*@context)
      )
    end

    def consent(**kwargs)
      consent!(**kwargs)
    rescue Consent::ViewNotFound
      nil
    end

    # Returns a hash where the keys are the given permissions, and the values
    # are either true or false, representing their ability to perform the given
    # permision
    #
    # @param [Array<String>,String,nil] permissions an array of the requested permissions
    # @return [Hash<String,Boolean>] the hash with the results
    def to_h(permissions = nil)
      Array(permissions).reduce({}) do |result, permission|
        result.merge permission => can?(permission)
      end
    end

    # Check if the user has permission to perform a given action on an object.
    #
    #   can? :destroy, @project
    #
    # You can also pass the class instead of an instance (if you don't have one handy).
    #
    #   can? :create, Project
    #
    # You can also check with string form of the permission:
    #
    #   can? "project/create"
    #
    # For more info, check the documentation of [CanCan::Ability]
    def can?(action_or_pair, subject = nil, *args)
      action, subject = extract_action_subject(action_or_pair, subject)
      super action, subject, *args
    end

  private

    def apply_defaults!
      Consent.subjects.each do |subject|
        subject.actions.each do |action|
          next unless action.default_view

          consent(
            subject: subject.key,
            action: action.key,
            view: action.default_view
          )
        end
      end
    end

    def extract_action_subject(action_or_string_pair, subject)
      return action_or_string_pair, subject if subject

      subject_key, _, action_key = action_or_string_pair.rpartition("/")
      [action_key.to_sym, Consent::SubjectCoder.load(subject_key)]
    end
  end
end
