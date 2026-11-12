import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";

function toText(ids) {
  return ids.join("\n");
}

// The ids in the box, as the server reads them, to tell whether it changed.
function normalize(text) {
  return text
    .split(/[\s,]+/)
    .filter(Boolean)
    .join(",");
}

// Group > Manage > Member preferences (admins only): topics muted for the group's members, one
// topic id per line. Saving mutes the added topics for current members.
export default class MuteEnhancementsMutedTopics extends Component {
  @service toasts;

  @tracked text = toText(this.saved);
  @tracked saving = false;

  get saved() {
    return this.args.group.mute_enhancements_muted_topic_ids;
  }

  get dirty() {
    return normalize(this.text) !== this.saved.join(",");
  }

  @action
  onInput(event) {
    this.text = event.target.value;
  }

  @action
  async save() {
    this.saving = true;
    try {
      const result = await ajax(
        `/mute-enhancements/groups/${this.args.group.id}/muted-topics`,
        { type: "PUT", data: { topic_ids: this.text } }
      );
      this.args.group.set(
        "mute_enhancements_muted_topic_ids",
        result.muted_topic_ids
      );
      this.text = toText(result.muted_topic_ids);

      this.toasts.success({
        duration: "short",
        data: {
          message:
            result.applied_user_count > 0
              ? i18n("mute_enhancements.muted_topics.saved_and_applied", {
                  count: result.applied_user_count,
                })
              : i18n("mute_enhancements.muted_topics.saved"),
        },
      });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.saving = false;
    }
  }

  <template>
    <div class="control-group mute-enhancements-muted-topics">
      <label class="control-label" for="mute-enhancements-muted-topics-input">
        {{i18n "mute_enhancements.muted_topics.title"}}
      </label>
      <div class="control-instructions">
        {{i18n "mute_enhancements.muted_topics.description"}}
      </div>
      <textarea
        id="mute-enhancements-muted-topics-input"
        value={{this.text}}
        disabled={{this.saving}}
        {{on "input" this.onInput}}
      ></textarea>
      <div>
        <DButton
          class="btn-default mute-enhancements-save-muted-topics"
          @action={{this.save}}
          @disabled={{if this.dirty this.saving true}}
          @label="mute_enhancements.muted_topics.save"
        />
      </div>
    </div>
  </template>
}
