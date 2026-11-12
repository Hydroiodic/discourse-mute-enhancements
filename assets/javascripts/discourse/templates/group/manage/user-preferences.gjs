import MuteEnhancementsDefaultUsers from "../../../components/mute-enhancements-default-users";
import MuteEnhancementsHidePreferences from "../../../components/mute-enhancements-hide-preferences";

const isPresent = (value) => value !== undefined;

<template>
  <div class="groups-form form-vertical mute-enhancements-user-preferences">
    {{#if (isPresent @controller.model.mute_enhancements_default_users)}}
      <MuteEnhancementsDefaultUsers @group={{@controller.model}} />
    {{/if}}
    {{#if (isPresent @controller.model.mute_enhancements_hidden_preferences)}}
      <MuteEnhancementsHidePreferences @group={{@controller.model}} />
    {{/if}}
  </div>
</template>
