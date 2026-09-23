// Executable excerpt from pi-web-access 0.31.0 (MIT, Nico Bailon).
import { buildSessionContext } from "@earendil-works/pi-coding-agent";
import { dirname as dirname2, join as join7 } from "node:path";
import { readFileSync as readFileSync42 } from "node:fs";
import { fileURLToPath } from "node:url";
function supportsDynamicTools(pi) {
  if (typeof pi.getAllTools !== "function" || typeof pi.getActiveTools !== "function" || typeof pi.setActiveTools !== "function") return false;
  try {
    const packagePath = join7(dirname2(fileURLToPath(import.meta.resolve("@earendil-works/pi-coding-agent"))), "..", "package.json");
    const [major, minor, patch] = JSON.parse(readFileSync42(packagePath, "utf8")).version.split(".").map(Number);
    return major > 0 || minor > 86 || minor === 86 && patch >= 1;
  } catch {
    return false;
  }
}
export { supportsDynamicTools };
