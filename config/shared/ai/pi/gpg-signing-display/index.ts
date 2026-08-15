// @ts-expect-error Pi provides this package to its extension loader.
import { createBashTool, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import core from "./core.js";

export default function gpgSigningDisplayExtension(pi: ExtensionAPI) {
  core(pi, { createBashTool });
}
