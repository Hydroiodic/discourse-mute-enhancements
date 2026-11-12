# frozen_string_literal: true

module Jobs
  # Group mutes follow membership changes as they happen; this catches what the events do not
  # cover, such as members who became staff.
  class MuteEnhancementsReconcileGroupMutes < ::Jobs::Scheduled
    every 1.day

    def execute(_args)
      DiscourseMuteEnhancements::GroupMutes.reconcile_all
    end
  end
end
