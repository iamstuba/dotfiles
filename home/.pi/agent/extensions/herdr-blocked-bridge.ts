import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// herdr's own herdr-agent-state.ts owns working and idle. It reports blocked
// only while another extension says so, and nothing in pi says so, so a pane
// waiting on a question reads as working forever. This is the missing half.
export default function (pi: ExtensionAPI) {
  pi.on("ui_prompt_start", (event) => {
    // pi coalesces nested prompts into one span, so starts and ends pair up.
    pi.events.emit("herdr:blocked", { active: true, label: event.title ?? event.kind });
  });

  pi.on("ui_prompt_end", () => {
    pi.events.emit("herdr:blocked", { active: false });
  });
}
