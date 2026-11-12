import MuteEnhancementsDefaultUsers from "../../../components/mute-enhancements-default-users";
import MuteEnhancementsHideIgnoredTopics from "../../../components/mute-enhancements-hide-ignored-topics";
import MuteEnhancementsHidePreferences from "../../../components/mute-enhancements-hide-preferences";
import MuteEnhancementsMutedTopics from "../../../components/mute-enhancements-muted-topics";

const isPresent = (value) => value !== undefined;

<template>
  <div class="groups-form form-vertical mute-enhancements-user-preferences">
    {{#if (isPresent @controller.model.mute_enhancements_default_users)}}
      <MuteEnhancementsDefaultUsers @group={{@controller.model}} />
    {{/if}}
    {{#if (isPresent @controller.model.mute_enhancements_hidden_preferences)}}
      <MuteEnhancementsHidePreferences @group={{@controller.model}} />
    {{/if}}
    {{#if (isPresent @controller.model.mute_enhancements_muted_topic_ids)}}
      <MuteEnhancementsMutedTopics @group={{@controller.model}} />
    {{/if}}
    {{#if (isPresent @controller.model.mute_enhancements_hide_ignored_topics)}}
      <MuteEnhancementsHideIgnoredTopics @group={{@controller.model}} />
    {{/if}}
  </div>
</template>
