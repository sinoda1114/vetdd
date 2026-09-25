// Validate a JSON document against a draft 2020-12 JSON Schema.
// Usage: node validate-schema.mjs <schema.json> <data.json>
import { readFileSync } from "node:fs";
import Ajv2020 from "ajv/dist/2020.js";

const [schemaPath, dataPath] = process.argv.slice(2);
if (!schemaPath || !dataPath) {
  console.error("usage: validate-schema.mjs <schema.json> <data.json>");
  process.exit(2);
}
const ajv = new Ajv2020({ allErrors: true, strict: true });
const validate = ajv.compile(JSON.parse(readFileSync(schemaPath, "utf8")));
if (validate(JSON.parse(readFileSync(dataPath, "utf8")))) {
  console.log("valid");
} else {
  console.error(JSON.stringify(validate.errors, null, 2));
  process.exit(1);
}
