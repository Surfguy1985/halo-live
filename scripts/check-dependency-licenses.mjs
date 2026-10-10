import { readFile } from "node:fs/promises";

const lockfiles = [
  "package-lock.json",
  "enterprise/workflow-publishing/package-lock.json",
];

const reviewedLicenses = new Set([
  "0BSD",
  "Apache-2.0",
  "BSD-2-Clause",
  "BSD-3-Clause",
  "BlueOak-1.0.0",
  "CC-BY-4.0",
  "Hippocratic-2.1",
  "ISC",
  "MIT",
  "MPL-2.0",
  "Unlicense",
]);

let packageCount = 0;
const failures = [];

for (const lockfile of lockfiles) {
  const lock = JSON.parse(await readFile(new URL(`../${lockfile}`, import.meta.url), "utf8"));
  if (lock.lockfileVersion !== 3 || typeof lock.packages !== "object") {
    failures.push(`${lockfile}: expected npm lockfileVersion 3`);
    continue;
  }

  for (const [path, metadata] of Object.entries(lock.packages)) {
    if (!path) continue;
    packageCount += 1;
    if (typeof metadata.license !== "string" || metadata.license.length === 0) {
      failures.push(`${lockfile}:${path}: missing declared license`);
    } else if (!reviewedLicenses.has(metadata.license)) {
      failures.push(`${lockfile}:${path}: unreviewed license ${metadata.license}`);
    }
  }
}

if (failures.length) {
  console.error(failures.join("\n"));
  process.exitCode = 1;
} else {
  console.log(`Dependency license gate passed for ${packageCount} locked packages.`);
}
