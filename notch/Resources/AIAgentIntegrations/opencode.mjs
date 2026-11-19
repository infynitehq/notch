import { Plugin } from "@opencode/plugin";
import { startCompanion } from "./opencode-runtime.mjs";

export default Plugin.define({
  id: "notch.agents",
  setup: startCompanion,
});
